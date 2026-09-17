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
        XCTAssertNil(session.detourRoute)
        XCTAssertNil(session.goToGuidance)
        XCTAssertFalse(session.isActive)
    }

    /// Fix "ride-restarts-from-zero-on-tab-return" (it19, retour terrain : "si je switch
    /// d'onglet et reviens sur Ride, ça repart de zéro") — RideView.onAppear appelait
    /// inconditionnellement `start(track:)`, y compris sur un simple retour d'onglet (TabView
    /// appelle onAppear à chaque changement de visibilité, pas juste au montage initial),
    /// remettant les stats de la sortie à zéro à chaque aller-retour. `switchMode(track:)`
    /// existe précisément pour ce cas et doit préserver les stats — `start(track:)`, lui, doit
    /// vraiment repartir de zéro (c'est la garantie qui rend le fix RideView correct : basculer
    /// sur switchMode() pour tout retour ne doit rien casser du "vrai nouveau départ").
    func testSwitchModePreservesRideStatsButStartResetsThem() {
        let suite = "RideSessionManagerPurgeTests.\(UUID().uuidString)"
        defer { UserDefaults(suiteName: suite)?.removePersistentDomain(forName: suite) }
        let session = makeSession(defaultsSuiteName: suite)
        let track = makeTrack()
        session.start(track: track)

        let fastLocation = CLLocation(
            coordinate: track.points[0].coordinate, altitude: 0, horizontalAccuracy: 5, verticalAccuracy: 5,
            course: 0, speed: 20 / 3.6, timestamp: Date()
        )
        session.handle(location: fastLocation)
        XCTAssertGreaterThan(session.maxSpeedKmh, 0, "précondition : une vitesse doit avoir été enregistrée")

        session.switchMode(track: track)
        XCTAssertGreaterThan(session.maxSpeedKmh, 0, "switchMode (retour d'onglet) ne doit JAMAIS remettre les stats de la sortie à zéro")

        session.start(track: track)
        XCTAssertEqual(session.maxSpeedKmh, 0, "start() (vrai nouveau départ) doit repartir de zéro")
    }
}
