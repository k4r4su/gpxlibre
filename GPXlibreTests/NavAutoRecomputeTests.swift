import XCTest
import CoreLocation
@testable import GPXlibre

/// Spec "nav-classic-rebuild" (it21) — "Test de recalcul : écart significatif de la polyline →
/// nouveau /route demandé, sans boucle de recalcul infinie." Provider Valhalla FACTICE
/// (`session.navRoutingProvider`) — jamais de vrai réseau ici.
@MainActor
final class NavAutoRecomputeTests: XCTestCase {
    /// Réussit une seule fois (calcul initial), échoue ensuite — simule un serveur Valhalla
    /// devenu injoignable EN COURS de guidage, le cas où l'absence de cooldown redéclencherait
    /// un appel réseau à CHAQUE fix hors-trace (plusieurs fois par seconde en pratique).
    private final class FakeSucceedsOnceThenFailsProvider: NavRoutingProvider {
        struct Failure: Error {}
        let routeToReturn: ValhallaNavRoute
        private(set) var callCount = 0

        init(routeToReturn: ValhallaNavRoute) {
            self.routeToReturn = routeToReturn
        }

        func route(from origin: CLLocationCoordinate2D, to destination: CLLocationCoordinate2D, destinationLabel: String, configuration: ValhallaConfiguration) async throws -> ValhallaNavRoute {
            callCount += 1
            guard callCount == 1 else { throw Failure() }
            return routeToReturn
        }
    }

    private let routeCoordinates: [CLLocationCoordinate2D] = [
        CLLocationCoordinate2D(latitude: 45.000, longitude: 5.000),
        CLLocationCoordinate2D(latitude: 45.001, longitude: 5.000),
        CLLocationCoordinate2D(latitude: 45.002, longitude: 5.000),
        CLLocationCoordinate2D(latitude: 45.003, longitude: 5.000),
        CLLocationCoordinate2D(latitude: 45.004, longitude: 5.000),
    ]

    private func makeRoute() -> ValhallaNavRoute {
        ValhallaNavRoute(
            coordinates: routeCoordinates,
            maneuvers: [
                ValhallaNavManeuver(
                    type: .destination, instruction: "Vous êtes arrivé", verbalTransitionAlertInstruction: nil,
                    verbalPreTransitionInstruction: nil, verbalPostTransitionInstruction: nil, streetNames: [],
                    lengthMeters: 0, timeSeconds: 0, beginShapeIndex: 4, endShapeIndex: 4, isMultiCue: false,
                    roundaboutExitCount: nil, sign: nil
                ),
            ],
            totalDistanceMeters: 444,
            totalDurationSeconds: 60,
            destinationLabel: "Destination test"
        )
    }

    private func makeSession() -> RideSessionManager {
        let suite = "NavAutoRecomputeTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        let settings = RideSettingsStore(defaults: defaults)
        settings.valhallaEnabled = true
        settings.valhallaEndpointURLString = "https://valhalla.example.com"
        return RideSessionManager(
            settings: settings,
            networkMonitor: NetworkMonitor(),
            modeStore: RideModeStore(),
            sharedBlockages: SharedBlockageSyncCoordinator(defaults: defaults)
        )
    }

    private func location(_ coordinate: CLLocationCoordinate2D, at date: Date) -> CLLocation {
        CLLocation(coordinate: coordinate, altitude: 0, horizontalAccuracy: 5, verticalAccuracy: 5, timestamp: date)
    }

    private func offsetEast(_ coordinate: CLLocationCoordinate2D, meters: Double) -> CLLocationCoordinate2D {
        let metersPerDegreeLongitude = 111_320 * cos(coordinate.latitude * .pi / 180)
        return CLLocationCoordinate2D(latitude: coordinate.latitude, longitude: coordinate.longitude + meters / metersPerDegreeLongitude)
    }

    /// Cœur du test attendu par la spec : un écart soutenu déclenche bien UN recalcul — puis,
    /// si ce recalcul échoue et que le rider reste hors-route, le COOLDOWN
    /// (`NavConstants.navRecomputeCooldownSeconds`) empêche un nouvel appel réseau à chaque fix
    /// suivant tant qu'il n'est pas écoulé — sans lui, `navOffRouteSinceDate` (jamais remis à
    /// zéro sur un ÉCHEC, contrairement à un succès) laisserait `elapsed >= offRouteToleranceSeconds`
    /// vrai en continu, redéclenchant un appel à CHAQUE fix suivant.
    func testSustainedDivergenceTriggersOneRecomputeThenCooldownPreventsImmediateRetriesAfterAFailure() async {
        let session = makeSession()
        let provider = FakeSucceedsOnceThenFailsProvider(routeToReturn: makeRoute())
        session.navRoutingProvider = provider
        let t0 = Date()

        session.start(track: nil)
        session.handle(location: location(routeCoordinates[0], at: t0))
        session.startNav(to: routeCoordinates.last!, label: "Destination test")
        await session.navRoutingTask?.value
        XCTAssertEqual(provider.callCount, 1, "calcul initial")

        // Bornes exprimées à partir des constantes réelles (jamais des littéraux codés en dur)
        // — reste correct si `NavConstants.offRouteToleranceSeconds`/`navRecomputeCooldownSeconds`
        // sont retouchées plus tard (fix "nav-recompute-faster" les a déjà réduites une fois).
        let tolerance = NavConstants.offRouteToleranceSeconds
        let cooldown = NavConstants.navRecomputeCooldownSeconds

        let offRoute = offsetEast(routeCoordinates[2], meters: 200)
        // Sous le seuil de durée : pas encore de recalcul.
        session.handle(location: location(offRoute, at: t0.addingTimeInterval(1)))
        XCTAssertEqual(provider.callCount, 1, "écart tout juste détecté, pas encore soutenu assez longtemps")

        // Écart soutenu au-delà de la tolérance : un recalcul est demandé (celui-ci échoue, voir
        // le provider).
        session.handle(location: location(offRoute, at: t0.addingTimeInterval(tolerance + 1)))
        await session.navRoutingTask?.value
        XCTAssertEqual(provider.callCount, 2, "écart soutenu au-delà de la tolérance : un recalcul doit être demandé")
        XCTAssertNotNil(session.navRoutingError)

        // Toujours hors-trace, dans la fenêtre de cooldown (depuis CE recalcul, à t0+tolerance+1)
        // : ne doit PAS redéclencher à chaque fix suivant, même répété plusieurs fois.
        let recomputeDate = tolerance + 1
        session.handle(location: location(offRoute, at: t0.addingTimeInterval(recomputeDate + cooldown * 0.3)))
        await session.navRoutingTask?.value
        session.handle(location: location(offRoute, at: t0.addingTimeInterval(recomputeDate + cooldown * 0.6)))
        await session.navRoutingTask?.value
        session.handle(location: location(offRoute, at: t0.addingTimeInterval(recomputeDate + cooldown - 1)))
        await session.navRoutingTask?.value
        XCTAssertEqual(provider.callCount, 2, "cooldown actif : aucun nouvel appel réseau tant qu'il n'est pas écoulé, malgré l'échec précédent")

        // Cooldown écoulé (depuis le recalcul de t0+tolerance+1) ET toujours hors-trace : un
        // nouvel essai est permis — le rider reste hors-route, ce n'est pas une boucle
        // ininterrompue mais un nouvel essai périodique borné.
        session.handle(location: location(offRoute, at: t0.addingTimeInterval(recomputeDate + cooldown + 1)))
        await session.navRoutingTask?.value
        XCTAssertEqual(provider.callCount, 3, "le cooldown expiré autorise un nouvel essai")
    }

    /// Retour à la trace AVANT que la durée soutenue ne soit atteinte : le minuteur doit se
    /// réinitialiser, jamais de recalcul (même contrat que le mécanisme équivalent côté Trace,
    /// `AutoRecomputeTests.testReturningBelowThresholdResetsTheTimer`).
    func testReturningBelowThresholdBeforeSustainedDurationResetsTheTimer() async {
        let session = makeSession()
        let provider = FakeSucceedsOnceThenFailsProvider(routeToReturn: makeRoute())
        session.navRoutingProvider = provider
        let t0 = Date()

        session.start(track: nil)
        session.handle(location: location(routeCoordinates[0], at: t0))
        session.startNav(to: routeCoordinates.last!, label: "Destination test")
        await session.navRoutingTask?.value
        XCTAssertEqual(provider.callCount, 1)

        let tolerance = NavConstants.offRouteToleranceSeconds
        let returnDate = 20.0

        let offRoute = offsetEast(routeCoordinates[2], meters: 200)
        session.handle(location: location(offRoute, at: t0.addingTimeInterval(1)))
        // Revenu proche de la trace avant la tolérance — minuteur remis à zéro.
        session.handle(location: location(routeCoordinates[2], at: t0.addingTimeInterval(10)))
        session.handle(location: location(offRoute, at: t0.addingTimeInterval(returnDate)))
        // Juste SOUS la tolérance depuis CE retour (t0+returnDate) : sans le reset, l'écart
        // serait soutenu depuis t0+1 (largement au-delà de la tolérance) et aurait déjà
        // déclenché un recalcul ; avec le reset, la tolérance n'est pas encore écoulée depuis
        // t0+returnDate — pas encore de recalcul.
        session.handle(location: location(offRoute, at: t0.addingTimeInterval(returnDate + tolerance - 1)))
        await session.navRoutingTask?.value
        XCTAssertEqual(provider.callCount, 1, "sous la tolérance depuis le dernier retour sur trace : le minuteur a bien été remis à zéro")

        // Poursuite au-delà de la tolérance depuis CE MÊME retour : le recalcul finit par se
        // déclencher normalement, le minuteur n'est pas resté bloqué.
        session.handle(location: location(offRoute, at: t0.addingTimeInterval(returnDate + tolerance + 1)))
        await session.navRoutingTask?.value
        XCTAssertEqual(provider.callCount, 2, "tolérance dépassée depuis le dernier retour sur trace : le recalcul doit maintenant se déclencher")
    }
}
