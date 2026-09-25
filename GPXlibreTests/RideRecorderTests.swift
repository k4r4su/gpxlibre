import XCTest
import CoreLocation
@testable import GPXlibre

/// It30 — enregistrement de la sortie : service applicatif indépendant des écrans, actif en
/// arrière-plan seulement pendant un enregistrement démarré par l'utilisateur, persisté point par
/// point. Source GPS factice ; journal, secours et réglages dans des emplacements dédiés (jamais
/// les vraies données de l'app). Reprend les tests du secours "Sorties non enregistrées" (it19),
/// qui vivaient dans `RideSessionManagerUnsavedRideTests` avant le déplacement du code.
@MainActor
final class RideRecorderTests: XCTestCase {
    /// GPS factice : enregistre les demandes, émet des positions à la demande.
    final class FakeSource: RecordingLocationSource {
        var onLocation: ((CLLocation) -> Void)?
        var onAuthorizationChange: ((CLAuthorizationStatus) -> Void)?
        var authorizationStatus: CLAuthorizationStatus
        private(set) var isUpdatingInBackground = false
        private(set) var startCount = 0
        private(set) var stopCount = 0
        private(set) var authorizationRequests = 0

        init(authorization: CLAuthorizationStatus = .authorizedWhenInUse) {
            authorizationStatus = authorization
        }

        func requestAuthorization() { authorizationRequests += 1 }
        func startBackgroundUpdates() { startCount += 1; isUpdatingInBackground = true }
        func stopUpdates() { stopCount += 1; isUpdatingInBackground = false }

        func emit(_ location: CLLocation) { onLocation?(location) }
        func grant(_ status: CLAuthorizationStatus) {
            authorizationStatus = status
            onAuthorizationChange?(status)
        }
    }

    private var directory: URL!
    private var suiteName: String!

    override func setUp() {
        super.setUp()
        directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        suiteName = "RideRecorderTests.\(UUID().uuidString)"
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: directory)
        UserDefaults(suiteName: suiteName)?.removePersistentDomain(forName: suiteName)
        super.tearDown()
    }

    private func makeRecorder(source: FakeSource) -> RideRecorder {
        let settings = RideSettingsStore(defaults: UserDefaults(suiteName: suiteName)!)
        return RideRecorder(
            settings: settings,
            source: source,
            journal: RideRecordingJournal(directoryOverride: directory.appendingPathComponent("journal", isDirectory: true)),
            unsavedRideStore: UnsavedRideStore(directoryOverride: directory.appendingPathComponent("unsaved", isDirectory: true))
        )
    }

    private let t0 = Date(timeIntervalSince1970: 1_800_000_000)

    /// Position `index` d'un trajet vers le nord, un fix toutes les 6 s (preset "précis" 5 s/15 m :
    /// chaque fix est enregistré).
    private func fix(_ index: Int) -> CLLocation {
        CLLocation(coordinate: CLLocationCoordinate2D(latitude: 47.5 + Double(index) * 0.0003, longitude: 7.3), altitude: 300, horizontalAccuracy: 5, verticalAccuracy: 5, timestamp: t0.addingTimeInterval(Double(index) * 6))
    }

    // MARK: - Démarrage explicite, arrière-plan, arrêt propre

    func testNothingRecordsWithoutAnExplicitStart() {
        let source = FakeSource()
        let recorder = makeRecorder(source: source)

        source.emit(fix(0))
        source.emit(fix(1))

        XCTAssertEqual(recorder.state, .idle)
        XCTAssertEqual(recorder.pointCount, 0)
        XCTAssertEqual(source.startCount, 0, "aucun GPS démarré au lancement")
        XCTAssertFalse(source.isUpdatingInBackground, "aucune capture permanente en arrière-plan")
    }

    /// Changer d'onglet ou passer l'app en arrière-plan ne touche PAS ce service (il ne dépend
    /// d'aucune vue) : les points continuent d'arriver et d'être enregistrés sans trou.
    func testRecordingIsContinuousAndOnlyStopsOnUserAction() {
        let source = FakeSource()
        let recorder = makeRecorder(source: source)

        XCTAssertEqual(recorder.start(), .started)
        XCTAssertTrue(source.isUpdatingInBackground, "GPS actif en arrière-plan pendant l'enregistrement")
        for i in 0..<30 { source.emit(fix(i)) } // 3 minutes, quel que soit l'écran affiché
        XCTAssertEqual(recorder.pointCount, 30)
        let gaps = zip(recorder.points, recorder.points.dropFirst()).compactMap { pair -> TimeInterval? in
            guard let a = pair.0.time, let b = pair.1.time else { return nil }
            return b.timeIntervalSince(a)
        }
        XCTAssertEqual(gaps.max() ?? 0, 6, accuracy: 0.001, "aucun trou")

        recorder.pause()
        XCTAssertFalse(source.isUpdatingInBackground, "pause : GPS et arrière-plan coupés")
        source.emit(fix(30))
        XCTAssertEqual(recorder.pointCount, 30, "rien en pause")

        XCTAssertEqual(recorder.resume(), .started)
        source.emit(fix(31))
        XCTAssertEqual(recorder.pointCount, 31)

        recorder.finish()
        XCTAssertEqual(recorder.state, .idle)
        XCTAssertEqual(recorder.pointCount, 0)
        XCTAssertFalse(source.isUpdatingInBackground, "fin : plus rien ne tourne")
        source.emit(fix(32))
        XCTAssertEqual(recorder.pointCount, 0)
    }

    func testDensityPresetStillThrottlesPoints() {
        let source = FakeSource()
        let recorder = makeRecorder(source: source)
        recorder.start()
        let base = fix(0)
        source.emit(base)
        // 1 s plus tard, 2 m plus loin : sous les deux seuils (5 s / 15 m).
        source.emit(CLLocation(coordinate: CLLocationCoordinate2D(latitude: base.coordinate.latitude + 0.00002, longitude: 7.3), altitude: 300, horizontalAccuracy: 5, verticalAccuracy: 5, timestamp: t0.addingTimeInterval(1)))
        XCTAssertEqual(recorder.pointCount, 1)
    }

    // MARK: - Persistance point par point

    /// Chaque point est sur disque dès qu'il est enregistré : après un arrêt forcé de l'app, une
    /// nouvelle instance retrouve TOUS les points, en pause (jamais de reprise automatique).
    func testEveryPointSurvivesAnAppKillAndIsRestoredPaused() {
        let source = FakeSource()
        let recorder = makeRecorder(source: source)
        recorder.start()
        for i in 0..<7 { source.emit(fix(i)) }
        let sessionID = recorder.sessionID

        // "Kill" : l'instance disparaît sans rien terminer ; relance de l'app.
        let relaunchedSource = FakeSource()
        let relaunched = makeRecorder(source: relaunchedSource)

        XCTAssertEqual(relaunched.pointCount, 7)
        XCTAssertEqual(relaunched.points.map(\.latitude), recorder.points.map(\.latitude))
        XCTAssertEqual(relaunched.sessionID, sessionID)
        XCTAssertEqual(relaunched.state, .paused)
        XCTAssertTrue(relaunched.wasRestoredAfterInterruption)
        XCTAssertEqual(relaunchedSource.startCount, 0, "pas de reprise automatique")

        relaunched.resume()
        relaunchedSource.emit(fix(7))
        XCTAssertEqual(relaunched.pointCount, 8, "la sortie continue dans la même session")
    }

    func testFinishingClearsTheJournal() {
        let source = FakeSource()
        let recorder = makeRecorder(source: source)
        recorder.start()
        for i in 0..<3 { source.emit(fix(i)) }
        recorder.finish()

        XCTAssertEqual(makeRecorder(source: FakeSource()).pointCount, 0, "rien à restaurer après une fin propre")
    }

    // MARK: - Secours "Sorties non enregistrées" (it19, inchangé)

    func testUnsavedRideCheckpointIsWrittenEveryNPointsAndDiscardedOnFinish() {
        let source = FakeSource()
        let recorder = makeRecorder(source: source)
        recorder.start()
        for i in 0..<(RideConstants.unsavedRideCheckpointEveryNPoints - 1) { source.emit(fix(i)) }
        XCTAssertTrue(recorder.unsavedRideStore.rides.isEmpty)

        source.emit(fix(RideConstants.unsavedRideCheckpointEveryNPoints - 1))
        XCTAssertEqual(recorder.unsavedRideStore.rides.first?.pointCount, RideConstants.unsavedRideCheckpointEveryNPoints)

        recorder.finish()
        XCTAssertTrue(recorder.unsavedRideStore.rides.isEmpty, "sortie terminée : plus de secours")
    }

    // MARK: - Autorisation

    func testFirstStartAsksForLocationThenStartsOnceGranted() {
        let source = FakeSource(authorization: .notDetermined)
        let recorder = makeRecorder(source: source)

        XCTAssertEqual(recorder.start(), .awaitingAuthorization)
        XCTAssertEqual(source.authorizationRequests, 1)
        XCTAssertEqual(recorder.state, .idle)

        source.grant(.authorizedWhenInUse)
        XCTAssertEqual(recorder.state, .recording, "\"Lorsque l'app est active\" suffit")
        XCTAssertTrue(source.isUpdatingInBackground)
    }

    /// Refusée : pas de crash, rien ne démarre, message explicite.
    func testDeniedLocationNeverStartsAndIsExplained() {
        let source = FakeSource(authorization: .denied)
        let recorder = makeRecorder(source: source)

        XCTAssertEqual(recorder.start(), .denied)
        XCTAssertEqual(recorder.state, .idle)
        XCTAssertFalse(source.isUpdatingInBackground)
        XCTAssertFalse(recorder.canRecordInBackground)
        XCTAssertTrue(RideRecordingStatusText.text(state: .idle, authorization: .denied, wasRestored: false)?.contains("Localisation refusée") ?? false)
    }

    /// Autorisation retirée PENDANT l'enregistrement (Réglages) : pause propre, points conservés.
    func testAuthorizationRevokedDuringRecordingPausesCleanly() {
        let source = FakeSource()
        let recorder = makeRecorder(source: source)
        recorder.start()
        for i in 0..<3 { source.emit(fix(i)) }

        source.grant(.denied)

        XCTAssertEqual(recorder.state, .paused)
        XCTAssertEqual(recorder.pointCount, 3)
        XCTAssertFalse(source.isUpdatingInBackground)
    }

    func testWhenInUseIsEnoughForBackgroundRecording() {
        let recorder = makeRecorder(source: FakeSource(authorization: .authorizedWhenInUse))
        XCTAssertTrue(recorder.canRecordInBackground)
    }

    // MARK: - Configuration réelle

    /// Le mode arrière-plan "location" est déclaré (sans lui, `allowsBackgroundLocationUpdates`
    /// ferait planter l'app), et le message d'autorisation parle de l'enregistrement.
    func testInfoPlistDeclaresBackgroundLocation() throws {
        let modes = try XCTUnwrap(Bundle.main.object(forInfoDictionaryKey: "UIBackgroundModes") as? [String])
        XCTAssertTrue(modes.contains("location"))
        let usage = try XCTUnwrap(Bundle.main.object(forInfoDictionaryKey: "NSLocationWhenInUseUsageDescription") as? String)
        XCTAssertTrue(usage.contains("enregistre"))
    }

    func testRecordingControlLabels() {
        XCTAssertEqual(RideRecordingControl.label(state: .idle, pointCount: 0), "Enregistrer")
        XCTAssertEqual(RideRecordingControl.label(state: .recording, pointCount: 42), "REC · 42 pts")
        XCTAssertEqual(RideRecordingControl.label(state: .paused, pointCount: 42), "Pause · 42 pts")
    }
}
