import XCTest
import CoreLocation
@testable import GPXlibre

/// Spec "manual-point-guidance-exclusivity" (it22) — "un seul guidage actif à la fois" : test
/// unitaire de transition `GuidanceTarget` (trace → point manuel → retour trace), et vérifie
/// que le guidage de reprise de trace (`resumeGuidance`) et un guidage manuel (`navRoute`/
/// `goToGuidance`) ne sont JAMAIS actifs simultanément.
@MainActor
final class GuidanceTargetTests: XCTestCase {
    private final class FakeNavRoutingProvider: NavRoutingProvider {
        func route(from origin: CLLocationCoordinate2D, to destination: CLLocationCoordinate2D, destinationLabel: String, configuration: ValhallaConfiguration) async throws -> ValhallaNavRoute {
            ValhallaNavRoute(coordinates: [origin, destination], maneuvers: [], totalDistanceMeters: 1000, totalDurationSeconds: 60, destinationLabel: destinationLabel)
        }
    }

    private func makeSession() -> RideSessionManager {
        let suite = "GuidanceTargetTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        let settings = RideSettingsStore(defaults: defaults)
        settings.valhallaEnabled = true
        settings.valhallaEndpointURLString = "https://valhalla.example.com"
        let session = RideSessionManager(
            settings: settings,
            networkMonitor: NetworkMonitor(),
            modeStore: RideModeStore(),
            sharedBlockages: SharedBlockageSyncCoordinator(defaults: defaults)
        )
        session.navRoutingProvider = FakeNavRoutingProvider()
        return session
    }

    private func location(_ coordinate: CLLocationCoordinate2D) -> CLLocation {
        CLLocation(coordinate: coordinate, altitude: 0, horizontalAccuracy: 5, verticalAccuracy: 5, timestamp: Date())
    }

    private func track() -> GPXTrack {
        GPXTrack(
            id: UUID(), name: "Test", fileName: "test.gpx", importDate: Date(),
            points: [
                GPXPoint(latitude: 45.0, longitude: 5.0),
                GPXPoint(latitude: 45.01, longitude: 5.0),
                GPXPoint(latitude: 45.02, longitude: 5.0),
            ],
            waypoints: []
        )
    }

    func testGuidanceTargetIsTraceByDefaultWhenATrackIsLoaded() {
        let session = makeSession()
        session.start(track: track())

        XCTAssertEqual(session.guidanceTarget, .trace)
    }

    func testGuidanceTargetIsNoneWithoutATrackAndWithoutAnyGuidance() {
        let session = makeSession()
        session.start(track: nil)

        XCTAssertEqual(session.guidanceTarget, .none)
    }

    /// Cœur du test attendu par la spec : trace → point manuel → retour trace.
    func testTransitionFromTraceToManualPointAndBackToTrace() async {
        let session = makeSession()
        let loadedTrack = track()
        session.start(track: loadedTrack)
        session.handle(location: location(loadedTrack.points[0].coordinate))
        XCTAssertEqual(session.guidanceTarget, .trace, "précondition : trace chargée, aucun guidage manuel")

        let manualDestination = CLLocationCoordinate2D(latitude: 45.05, longitude: 5.05)
        session.startNav(to: manualDestination, label: "Point manuel")
        await session.navRoutingTask?.value

        XCTAssertEqual(session.guidanceTarget, .manualPoint(manualDestination), "un point manuel actif doit devenir la cible de guidage")

        session.returnToTraceGuidance()

        XCTAssertEqual(session.guidanceTarget, .trace, "revenir à la trace doit annuler le point manuel et réactiver le guidage trace")
    }

    /// "un seul guidage actif à la fois" : démarrer un guidage manuel doit mettre en pause
    /// (annuler) un guidage de reprise de trace déjà en cours.
    func testStartingAManualPointGuidanceCancelsAnActiveResumeGuidance() {
        let session = makeSession()
        let loadedTrack = track()
        session.start(track: loadedTrack)
        session.handle(location: location(loadedTrack.points[0].coordinate))

        session.requestResume(pinCoordinate: loadedTrack.points[1].coordinate, pinCumulativeDistanceMeters: 100)
        XCTAssertNotNil(session.resumeGuidance, "précondition : un guidage de reprise de trace est actif")

        session.startGoTo(to: CLLocationCoordinate2D(latitude: 45.05, longitude: 5.05), label: "Point manuel", profile: .offroad)

        XCTAssertNil(session.resumeGuidance, "démarrer un guidage manuel doit mettre en pause la reprise de trace")
        session.goToTask?.cancel()
    }

    /// Jamais les deux en même temps, dans l'autre sens aussi : `requestResume` (déclenché par
    /// un tap sur la trace) alors qu'un guidage manuel riche est actif doit être précédé d'un
    /// `returnToTraceGuidance()` côté appelant (RideView.handleTrackTap) — vérifié ici au niveau
    /// de l'invariant que cette méthode garantit : `resumeGuidance` et `navRoute` ne sont jamais
    /// tous les deux non-nil simultanément après un cycle complet.
    func testResumeGuidanceAndManualNavRouteAreNeverBothActiveAfterAFullCycle() async {
        let session = makeSession()
        let loadedTrack = track()
        session.start(track: loadedTrack)
        session.handle(location: location(loadedTrack.points[0].coordinate))

        session.startNav(to: CLLocationCoordinate2D(latitude: 45.05, longitude: 5.05), label: "Point manuel")
        await session.navRoutingTask?.value
        XCTAssertNotNil(session.navRoute)
        XCTAssertNil(session.resumeGuidance, "le guidage riche ne doit jamais coexister avec un guidage de reprise de trace")

        session.returnToTraceGuidance()
        session.requestResume(pinCoordinate: loadedTrack.points[1].coordinate, pinCumulativeDistanceMeters: 100)

        XCTAssertNotNil(session.resumeGuidance)
        XCTAssertNil(session.navRoute, "la reprise de trace ne doit jamais coexister avec un guidage riche")
    }
}
