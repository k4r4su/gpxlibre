import XCTest
import CoreLocation
@testable import GPXlibre

/// Bouton toggle Pause/Play/Stop (spec "guidance-toggle-stop-pause-play", it15, Bloc 3) —
/// vérifie que `pauseGuidance()` (tap court) et `stopGuidance()` (menu contextuel "Arrêter le
/// guidage") mènent au MÊME état `isGuidanceStopped`, et que `resumeGuidanceAfterStop()` lève
/// cet état dans les deux cas — seule la présentation (haptique/toast, non testable ici) diffère
/// entre les deux, jamais la sémantique.
@MainActor
final class GuidanceToggleTests: XCTestCase {
    private func makeSession(defaultsSuiteName: String) -> RideSessionManager {
        let defaults = UserDefaults(suiteName: defaultsSuiteName)!
        return RideSessionManager(
            settings: RideSettingsStore(defaults: defaults),
            networkMonitor: NetworkMonitor(),
            modeStore: RideModeStore(),
            sharedBlockages: SharedBlockageSyncCoordinator(defaults: defaults)
        )
    }

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

    func testPauseGuidanceSetsIsGuidanceStoppedSameAsStop() {
        let suite = "GuidanceToggleTests.\(UUID().uuidString)"
        defer { UserDefaults(suiteName: suite)?.removePersistentDomain(forName: suite) }
        let session = makeSession(defaultsSuiteName: suite)
        session.start(track: makeTrack())
        XCTAssertFalse(session.isGuidanceStopped)

        session.pauseGuidance()

        XCTAssertTrue(session.isGuidanceStopped, "pauseGuidance() doit produire le même état isGuidanceStopped que stopGuidance()")
    }

    func testResumeGuidanceAfterStopClearsStateSetByPause() {
        let suite = "GuidanceToggleTests.\(UUID().uuidString)"
        defer { UserDefaults(suiteName: suite)?.removePersistentDomain(forName: suite) }
        let session = makeSession(defaultsSuiteName: suite)
        session.start(track: makeTrack())
        session.pauseGuidance()
        XCTAssertTrue(session.isGuidanceStopped)

        session.resumeGuidanceAfterStop()

        XCTAssertFalse(session.isGuidanceStopped, "la reprise doit fonctionner identiquement, que l'arrêt vienne de pauseGuidance() ou stopGuidance()")
    }

    func testStopGuidanceStillSetsIsGuidanceStopped() {
        let suite = "GuidanceToggleTests.\(UUID().uuidString)"
        defer { UserDefaults(suiteName: suite)?.removePersistentDomain(forName: suite) }
        let session = makeSession(defaultsSuiteName: suite)
        session.start(track: makeTrack())

        session.stopGuidance()

        XCTAssertTrue(session.isGuidanceStopped, "stopGuidance() (menu contextuel, ex-bouton Stop it14) doit rester fonctionnel à l'identique")
    }
}
