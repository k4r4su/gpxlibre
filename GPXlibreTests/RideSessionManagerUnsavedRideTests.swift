import XCTest
import CoreLocation
@testable import GPXlibre

/// Spec "unsaved-ride-recovery" (it19) — vérifie que RideSessionManager écrit bien un
/// checkpoint de secours à la bonne cadence pendant l'enregistrement, SANS jamais toucher au
/// vrai `Documents/UnsavedRides` de l'app : `session.unsavedRideStore` est remplacé par une
/// instance pointant vers un dossier temporaire dédié avant tout `handle(location:)` (voir
/// RideSessionManager.unsavedRideStore, `internal` uniquement pour permettre ce remplacement).
@MainActor
final class RideSessionManagerUnsavedRideTests: XCTestCase {
    private var tempDirectory: URL!

    override func setUp() {
        super.setUp()
        tempDirectory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: tempDirectory)
        super.tearDown()
    }

    private func makeSession(defaultsSuiteName: String) -> RideSessionManager {
        let defaults = UserDefaults(suiteName: defaultsSuiteName)!
        let session = RideSessionManager(
            settings: RideSettingsStore(defaults: defaults),
            networkMonitor: NetworkMonitor(),
            modeStore: RideModeStore(),
            sharedBlockages: SharedBlockageSyncCoordinator(defaults: defaults)
        )
        session.unsavedRideStore = UnsavedRideStore(directoryOverride: tempDirectory)
        return session
    }

    private func location(_ coordinate: CLLocationCoordinate2D, at date: Date) -> CLLocation {
        CLLocation(coordinate: coordinate, altitude: 0, horizontalAccuracy: 5, verticalAccuracy: 5, timestamp: date)
    }

    /// Preset "précis" par défaut (5 s / 15 m) — fixs espacés de 6 s pour garantir que CHAQUE
    /// fix est bien enregistré par `recordRideTrack` (pas de seuil raté par accident).
    func testCheckspointIsWrittenEveryNRecordedPoints() {
        let suite = "RideSessionManagerUnsavedRideTests.\(UUID().uuidString)"
        defer { UserDefaults(suiteName: suite)?.removePersistentDomain(forName: suite) }
        let session = makeSession(defaultsSuiteName: suite)
        session.start(track: nil)
        let t0 = Date()
        let coordinate = CLLocationCoordinate2D(latitude: 45.0, longitude: 5.0)

        for i in 0..<(RideConstants.unsavedRideCheckpointEveryNPoints - 1) {
            session.handle(location: location(coordinate, at: t0.addingTimeInterval(Double(i) * 6)))
        }
        XCTAssertTrue(session.unsavedRideStore.rides.isEmpty, "pas encore de checkpoint avant le Nᵉ point")

        session.handle(location: location(coordinate, at: t0.addingTimeInterval(Double(RideConstants.unsavedRideCheckpointEveryNPoints - 1) * 6)))

        XCTAssertEqual(session.unsavedRideStore.rides.count, 1)
        XCTAssertEqual(session.unsavedRideStore.rides.first?.pointCount, RideConstants.unsavedRideCheckpointEveryNPoints)
    }

    func testDiscardUnsavedRideCheckpointRemovesTheSafetyNet() {
        let suite = "RideSessionManagerUnsavedRideTests.\(UUID().uuidString)"
        defer { UserDefaults(suiteName: suite)?.removePersistentDomain(forName: suite) }
        let session = makeSession(defaultsSuiteName: suite)
        session.start(track: nil)
        let t0 = Date()
        let coordinate = CLLocationCoordinate2D(latitude: 45.0, longitude: 5.0)

        for i in 0..<RideConstants.unsavedRideCheckpointEveryNPoints {
            session.handle(location: location(coordinate, at: t0.addingTimeInterval(Double(i) * 6)))
        }
        XCTAssertEqual(session.unsavedRideStore.rides.count, 1, "précondition : un checkpoint doit avoir été écrit")

        session.discardUnsavedRideCheckpoint()

        XCTAssertTrue(session.unsavedRideStore.rides.isEmpty, "une sortie proprement enregistrée ne doit plus avoir de filet de secours")
    }
}
