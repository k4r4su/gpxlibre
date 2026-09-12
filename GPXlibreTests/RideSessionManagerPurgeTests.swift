import XCTest
import CoreLocation
@testable import GPXlibre

/// Purge explicite au `stop()` (fix "single-source-active-track", Bloc 1, itération 10) —
/// vérifie qu'aucun état (checkpoints, progression, détour) ne survit à la fin d'une session,
/// condition nécessaire pour que "supprimer la trace ACTIVE → Ride vide propre" (spec it10)
/// soit garanti par construction plutôt que par la chance d'un futur `start()`.
@MainActor
final class RideSessionManagerPurgeTests: XCTestCase {
    private func makeSession(defaultsSuiteName: String) -> RideSessionManager {
        let defaults = UserDefaults(suiteName: defaultsSuiteName)!
        return RideSessionManager(
            settings: RideSettingsStore(defaults: defaults),
            networkMonitor: NetworkMonitor(),
            modeStore: RideModeStore(),
            sharedBlockages: SharedBlockageSyncCoordinator(defaults: defaults)
        )
    }

    /// Virage net à 90° (est puis nord) pour garantir au moins un checkpoint détecté —
    /// une ligne droite ne produirait aucun virage à purger, rendant le test sans objet.
    private func makeTrack() -> GPXTrack {
        GPXTrack(
            id: UUID(),
            name: "T",
            fileName: "t.gpx",
            importDate: Date(),
            points: [
                GPXPoint(latitude: 45.0, longitude: 5.0),
                GPXPoint(latitude: 45.0, longitude: 5.01),
                GPXPoint(latitude: 45.0, longitude: 5.02),
                GPXPoint(latitude: 45.01, longitude: 5.02),
                GPXPoint(latitude: 45.02, longitude: 5.02),
            ],
            waypoints: []
        )
    }

    func testStopPurgesCheckpointsAndProgression() {
        let suite = "RideSessionManagerPurgeTests.\(UUID().uuidString)"
        defer { UserDefaults(suiteName: suite)?.removePersistentDomain(forName: suite) }
        let session = makeSession(defaultsSuiteName: suite)
        let track = makeTrack()

        session.start(track: track)
        XCTAssertFalse(session.checkpoints.isEmpty, "précondition : une trace avec virages doit produire des checkpoints")

        session.stop()

        XCTAssertTrue(session.checkpoints.isEmpty, "stop() doit purger les checkpoints")
        XCTAssertEqual(session.currentCheckpointIndex, 0)
        XCTAssertNil(session.detourRoute)
        XCTAssertNil(session.goToGuidance)
        XCTAssertFalse(session.isActive)
    }
}
