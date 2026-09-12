import XCTest
import CoreLocation
@testable import GPXlibre

/// State machine "Reprendre la trace ici" (feat "resume-at-point", Bloc 3, itération 10) —
/// teste la logique de resync/hystérésis directement sur RideSessionManager, sans réseau
/// réel (DetourRoutingService, testé implicitement ailleurs, n'est jamais sollicité ici :
/// networkMonitor démarre non-reachable en environnement de test, ce qui pousse
/// requestResume vers le mode dégradé, exactement le chemin qu'on veut vérifier).
@MainActor
final class ResumeGuidanceTests: XCTestCase {
    private func makeSession(defaultsSuiteName: String) -> RideSessionManager {
        let defaults = UserDefaults(suiteName: defaultsSuiteName)!
        return RideSessionManager(
            settings: RideSettingsStore(defaults: defaults),
            networkMonitor: NetworkMonitor(),
            modeStore: RideModeStore(),
            sharedBlockages: SharedBlockageSyncCoordinator(defaults: defaults)
        )
    }

    /// Trace rectiligne simple, plusieurs centaines de mètres — suffisant pour projeter des
    /// positions dessus sans se soucier des checkpoints (aucun virage franc ici).
    private func makeTrack() -> GPXTrack {
        GPXTrack(
            id: UUID(),
            name: "T",
            fileName: "t.gpx",
            importDate: Date(),
            points: (0...20).map { GPXPoint(latitude: 45.0 + Double($0) * 0.001, longitude: 5.0) },
            waypoints: []
        )
    }

    private func location(_ coordinate: CLLocationCoordinate2D) -> CLLocation {
        CLLocation(coordinate: coordinate, altitude: 0, horizontalAccuracy: 5, verticalAccuracy: 5, timestamp: Date())
    }

    func testRequestResumeStartsInPreviewingPhaseWithoutTouchingCheckpoints() {
        let suite = "ResumeGuidanceTests.\(UUID().uuidString)"
        defer { UserDefaults(suiteName: suite)?.removePersistentDomain(forName: suite) }
        let session = makeSession(defaultsSuiteName: suite)
        let track = makeTrack()
        session.start(track: track)
        let checkpointsBefore = session.checkpoints
        let indexBefore = session.currentCheckpointIndex

        session.requestResume(pinCoordinate: track.points[10].coordinate, pinCumulativeDistanceMeters: 1000)

        XCTAssertEqual(session.resumeGuidance?.phase, .previewing)
        XCTAssertEqual(session.checkpoints.count, checkpointsBefore.count, "previewing ne doit jamais toucher les checkpoints")
        XCTAssertEqual(session.currentCheckpointIndex, indexBefore)
    }

    /// Le pin et l'état "previewing" apparaissent immédiatement, AVANT toute réponse réseau
    /// (l'appel OSRM est asynchrone) — le mode dégradé (pas de tracé, juste le pin) est donc
    /// garanti tant que rien n'a répondu, que ce soit par absence de réseau ou le temps d'un
    /// aller-retour. Le vrai test "sans réseau" (NetworkMonitor forcé à false) demanderait
    /// d'injecter une abstraction de la réachabilité — non fait ici, pas de moyen fiable de
    /// forcer l'état réseau du simulateur dans ce test ; noté en TODO.md.
    func testRequestResumeStartsUnroutedBeforeAnyNetworkResponse() {
        let suite = "ResumeGuidanceTests.\(UUID().uuidString)"
        defer { UserDefaults(suiteName: suite)?.removePersistentDomain(forName: suite) }
        let session = makeSession(defaultsSuiteName: suite)
        let track = makeTrack()
        session.start(track: track)
        session.handle(location: location(track.points[0].coordinate))

        session.requestResume(pinCoordinate: track.points[10].coordinate, pinCumulativeDistanceMeters: 1000)

        XCTAssertEqual(session.resumeGuidance?.phase, .previewing)
        XCTAssertFalse(session.resumeGuidance?.isRouted ?? true)
        XCTAssertEqual(session.resumeGuidance?.routeCoordinates.isEmpty, true)
        XCTAssertEqual(session.resumeGuidance?.pinCoordinate.latitude, track.points[10].coordinate.latitude)
    }

    /// Jonction atteinte (< 30 m du pin) en phase active → resync + guidage effacé, jamais
    /// de retour en arrière (réutilise resyncCheckpointIndex, déjà garanti par it8).
    func testConfirmThenReachingPinResyncsAndClearsGuidance() {
        let suite = "ResumeGuidanceTests.\(UUID().uuidString)"
        defer { UserDefaults(suiteName: suite)?.removePersistentDomain(forName: suite) }
        let session = makeSession(defaultsSuiteName: suite)
        let track = makeTrack()
        session.start(track: track)
        let pin = track.points[10].coordinate
        session.requestResume(pinCoordinate: pin, pinCumulativeDistanceMeters: 1000)
        session.confirmResume()
        XCTAssertEqual(session.resumeGuidance?.phase, .active)

        session.handle(location: location(pin))

        XCTAssertNil(session.resumeGuidance, "la jonction atteinte doit effacer le guidage")
    }

    /// Hystérésis silencieuse (spec Bloc 3) : retour naturel sur la trace AVANT le pin, en
    /// phase active — pas de confirmation demandée, juste la reprise.
    func testConfirmThenNaturalReturnToTrackBeforePinResyncsSilently() {
        let suite = "ResumeGuidanceTests.\(UUID().uuidString)"
        defer { UserDefaults(suiteName: suite)?.removePersistentDomain(forName: suite) }
        let session = makeSession(defaultsSuiteName: suite)
        let track = makeTrack()
        session.start(track: track)
        // Pin loin devant (point 19) ; le rider retombe naturellement sur la trace bien avant.
        session.requestResume(pinCoordinate: track.points[19].coordinate, pinCumulativeDistanceMeters: 1900)
        session.confirmResume()

        session.handle(location: location(track.points[5].coordinate))

        XCTAssertNil(session.resumeGuidance, "un retour naturel sur la trace avant le pin doit aussi effacer le guidage")
    }

    func testCancelResumeAtAnyPhaseLeavesCleanState() {
        let suite = "ResumeGuidanceTests.\(UUID().uuidString)"
        defer { UserDefaults(suiteName: suite)?.removePersistentDomain(forName: suite) }
        let session = makeSession(defaultsSuiteName: suite)
        let track = makeTrack()
        session.start(track: track)
        let checkpointsBefore = session.checkpoints
        session.requestResume(pinCoordinate: track.points[10].coordinate, pinCumulativeDistanceMeters: 1000)
        session.confirmResume()

        session.cancelResume()

        XCTAssertNil(session.resumeGuidance)
        XCTAssertFalse(session.isRequestingResume)
        XCTAssertNil(session.resumeRoutingError)
        XCTAssertEqual(session.checkpoints.count, checkpointsBefore.count, "annuler ne doit jamais altérer track/checkpoints")
    }
}
