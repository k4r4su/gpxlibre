import XCTest
import CoreLocation
@testable import GPXlibre

/// Spec "nav-classic-rebuild" (it21) — "Test de progression : position avançant le long de la
/// polyline → manœuvre affichée passe correctement à la suivante au bon end_shape_index,
/// countdown décroît correctement." Provider Valhalla FACTICE (`session.navRoutingProvider`,
/// voir RideSessionManager) — jamais de vrai réseau ici.
@MainActor
final class NavProgressTests: XCTestCase {
    private final class FakeNavRoutingProvider: NavRoutingProvider {
        let routeToReturn: ValhallaNavRoute
        private(set) var callCount = 0

        init(routeToReturn: ValhallaNavRoute) {
            self.routeToReturn = routeToReturn
        }

        func route(from origin: CLLocationCoordinate2D, to destination: CLLocationCoordinate2D, destinationLabel: String, configuration: ValhallaConfiguration) async throws -> ValhallaNavRoute {
            callCount += 1
            return routeToReturn
        }
    }

    /// Trace synthétique rectiligne puis un virage net — 3 manœuvres : départ (point 0), virage
    /// à droite (point 4), arrivée (point 6). ~111 m entre points consécutifs (0.001° de
    /// latitude/longitude), largement au-delà de `NavConstants.maneuverPassedRadiusMeters` (25 m)
    /// pour une détection de franchissement sans ambiguïté.
    private let routeCoordinates: [CLLocationCoordinate2D] = [
        CLLocationCoordinate2D(latitude: 45.000, longitude: 5.000),
        CLLocationCoordinate2D(latitude: 45.001, longitude: 5.000),
        CLLocationCoordinate2D(latitude: 45.002, longitude: 5.000),
        CLLocationCoordinate2D(latitude: 45.003, longitude: 5.000),
        CLLocationCoordinate2D(latitude: 45.004, longitude: 5.000),
        CLLocationCoordinate2D(latitude: 45.004, longitude: 5.001),
        CLLocationCoordinate2D(latitude: 45.004, longitude: 5.002),
    ]

    private func maneuver(type: ValhallaManeuverType, beginShapeIndex: Int, endShapeIndex: Int, instruction: String) -> ValhallaNavManeuver {
        ValhallaNavManeuver(
            type: type,
            instruction: instruction,
            verbalTransitionAlertInstruction: "Alerte : \(instruction)",
            verbalPreTransitionInstruction: "Bientôt : \(instruction)",
            verbalPostTransitionInstruction: "Fait : \(instruction)",
            streetNames: ["Rue de Test"],
            lengthMeters: 400,
            timeSeconds: 30,
            beginShapeIndex: beginShapeIndex,
            endShapeIndex: endShapeIndex,
            isMultiCue: false,
            roundaboutExitCount: nil,
            sign: nil
        )
    }

    private func makeRoute() -> ValhallaNavRoute {
        ValhallaNavRoute(
            coordinates: routeCoordinates,
            maneuvers: [
                maneuver(type: .start, beginShapeIndex: 0, endShapeIndex: 4, instruction: "Démarrez"),
                maneuver(type: .right, beginShapeIndex: 4, endShapeIndex: 6, instruction: "Tournez à droite"),
                maneuver(type: .destination, beginShapeIndex: 6, endShapeIndex: 6, instruction: "Vous êtes arrivé"),
            ],
            totalDistanceMeters: 666,
            totalDurationSeconds: 90,
            destinationLabel: "Destination test"
        )
    }

    private func makeSession() -> RideSessionManager {
        let suite = "NavProgressTests.\(UUID().uuidString)"
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

    private func location(_ coordinate: CLLocationCoordinate2D, at date: Date = Date()) -> CLLocation {
        CLLocation(coordinate: coordinate, altitude: 0, horizontalAccuracy: 5, verticalAccuracy: 5, timestamp: date)
    }

    func testManeuverAdvancesToTheNextOneOncePassedAndCountdownDecreases() async {
        let session = makeSession()
        let provider = FakeNavRoutingProvider(routeToReturn: makeRoute())
        session.navRoutingProvider = provider

        session.start(track: nil)
        // `requestNavRoute()` a besoin de `currentLocation` comme origine — établi par un
        // premier `handle(location:)`, comme le ferait un vrai fix GPS avant que le rider ne
        // choisisse une destination.
        session.handle(location: location(routeCoordinates[0]))
        session.startNav(to: routeCoordinates.last!, label: "Destination test")
        await session.navRoutingTask?.value

        XCTAssertEqual(provider.callCount, 1)
        XCTAssertEqual(session.currentManeuverIndex, 0)
        XCTAssertEqual(session.currentManeuver?.instruction, "Démarrez")

        // La manœuvre 0 ("Démarrez") a pour coordonnée le point de DÉPART lui-même
        // (begin_shape_index 0) — distance ~0 dès le premier fix, donc franchie IMMÉDIATEMENT :
        // comportement attendu d'un vrai GPS, "Démarrez" ne reste jamais affiché une fois qu'on
        // a ne serait-ce que légèrement bougé. Passe directement à la manœuvre 1 (le vrai
        // virage, begin_shape_index 4).
        session.handle(location: location(routeCoordinates[0]))
        XCTAssertEqual(session.currentManeuverIndex, 1, "manœuvre de départ (distance ~0) franchie dès le premier fix")
        XCTAssertEqual(session.currentManeuver?.instruction, "Tournez à droite")

        // Loin de la manœuvre 1 (point 4, ~333 m depuis le point 1) : countdown proche de cette
        // distance, pas de franchissement.
        session.handle(location: location(routeCoordinates[1]))
        XCTAssertEqual(session.currentManeuverIndex, 1, "toujours en approche du virage")
        let farDistance = session.distanceToCurrentManeuverMeters
        XCTAssertNotNil(farDistance)

        // Se rapproche (point 3, ~111 m du virage) : countdown doit décroître.
        session.handle(location: location(routeCoordinates[3]))
        let closerDistance = session.distanceToCurrentManeuverMeters
        XCTAssertNotNil(closerDistance)
        XCTAssertLessThan(closerDistance ?? .infinity, farDistance ?? 0, "le countdown doit décroître à mesure qu'on approche")

        // Atteint le point du virage (index 4) : franchissement, passe à la manœuvre 2
        // (arrivée, begin_shape_index 6).
        session.handle(location: location(routeCoordinates[4]))
        XCTAssertEqual(session.currentManeuverIndex, 2, "manœuvre 1 franchie (< 25 m), doit passer à la suivante")
        XCTAssertEqual(session.currentManeuver?.instruction, "Vous êtes arrivé")

        // Atteint le point d'arrivée lui-même : la dernière manœuvre est également franchie,
        // plus aucune manœuvre "courante" à afficher (arrivée effective).
        session.handle(location: location(routeCoordinates[6]))
        XCTAssertEqual(session.currentManeuverIndex, 3)
        XCTAssertNil(session.currentManeuver)
    }

    func testNextManeuverAndMultiCueDrivesTheSecondaryBanner() async {
        let session = makeSession()
        let multiCueManeuver = ValhallaNavManeuver(
            type: .right,
            instruction: "Tournez à droite",
            verbalTransitionAlertInstruction: nil,
            verbalPreTransitionInstruction: nil,
            verbalPostTransitionInstruction: nil,
            streetNames: [],
            lengthMeters: 50,
            timeSeconds: 5,
            beginShapeIndex: 4,
            endShapeIndex: 5,
            isMultiCue: true,
            roundaboutExitCount: nil,
            sign: nil
        )
        let route = ValhallaNavRoute(
            coordinates: routeCoordinates,
            maneuvers: [
                maneuver(type: .start, beginShapeIndex: 0, endShapeIndex: 4, instruction: "Démarrez"),
                multiCueManeuver,
                maneuver(type: .left, beginShapeIndex: 5, endShapeIndex: 6, instruction: "Puis tournez à gauche"),
            ],
            totalDistanceMeters: 500,
            totalDurationSeconds: 60,
            destinationLabel: "Destination test"
        )
        let provider = FakeNavRoutingProvider(routeToReturn: route)
        session.navRoutingProvider = provider

        session.start(track: nil)
        session.handle(location: location(routeCoordinates[0]))
        session.startNav(to: routeCoordinates.last!, label: "Destination test")
        await session.navRoutingTask?.value

        // Premier fix après le calcul, au point de départ lui-même (distance ~0) : franchit
        // immédiatement la manœuvre 0 ("Démarrez"), passe à la manœuvre 1 (multi-cue).
        session.handle(location: location(routeCoordinates[0]))
        XCTAssertEqual(session.currentManeuverIndex, 1)
        XCTAssertEqual(session.currentManeuver?.isMultiCue, true)
        XCTAssertEqual(session.nextManeuver?.instruction, "Puis tournez à gauche")
    }
}
