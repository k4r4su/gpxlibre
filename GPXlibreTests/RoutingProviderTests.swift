import XCTest
import CoreLocation
@testable import GPXlibre

/// Spec "valhalla-live-routing" (it20) — providers FACTICES, jamais de vrai réseau (ni OSRM, ni
/// Valhalla) : vérifie uniquement la logique de résolution/repli en chaîne, pas un moteur réel.
private struct FakeAlwaysSucceedsProvider: RoutingProvider {
    let kind: RoutingActivityProvider
    let coordinates: [CLLocationCoordinate2D]

    init(kind: RoutingActivityProvider = .osrm, coordinates: [CLLocationCoordinate2D]) {
        self.kind = kind
        self.coordinates = coordinates
    }

    func route(from origin: CLLocationCoordinate2D, to destination: CLLocationCoordinate2D, profile: DetourProfile) async throws -> [CLLocationCoordinate2D] {
        coordinates
    }
}

private struct FakeAlwaysFailsProvider: RoutingProvider {
    let kind: RoutingActivityProvider = .valhalla
    struct Failure: Error {}
    func route(from origin: CLLocationCoordinate2D, to destination: CLLocationCoordinate2D, profile: DetourProfile) async throws -> [CLLocationCoordinate2D] {
        throw Failure()
    }
}

final class RoutingProviderTests: XCTestCase {
    private let origin = CLLocationCoordinate2D(latitude: 45.0, longitude: 5.0)
    private let destination = CLLocationCoordinate2D(latitude: 45.1, longitude: 5.1)

    // MARK: - RoutingProviderResolver (pur, sans réseau)

    func testResolverReturnsOnlyOSRMWhenValhallaDisabled() {
        let providers = RoutingProviderResolver.orderedProviders(valhallaEnabled: false, configuration: nil)

        XCTAssertEqual(providers.count, 1)
        XCTAssertTrue(providers[0] is OSRMRoutingProvider)
    }

    func testResolverReturnsOnlyOSRMWhenEnabledButNoConfiguration() {
        // Toggle activé sans endpoint saisi (chaîne vide côté RideSessionManager.
        // currentValhallaConfiguration) — équivalent à "pas de configuration" pour le resolver.
        let providers = RoutingProviderResolver.orderedProviders(valhallaEnabled: true, configuration: nil)

        XCTAssertEqual(providers.count, 1)
        XCTAssertTrue(providers[0] is OSRMRoutingProvider)
    }

    func testResolverPutsValhallaFirstThenOSRMAsFallbackWhenEnabledAndConfigured() {
        let configuration = ValhallaConfiguration(endpointURLString: "https://valhalla.example.com", username: "", password: "")

        let providers = RoutingProviderResolver.orderedProviders(valhallaEnabled: true, configuration: configuration)

        XCTAssertEqual(providers.count, 2)
        XCTAssertTrue(providers[0] is ValhallaProvider)
        XCTAssertTrue(providers[1] is OSRMRoutingProvider, "OSRM doit rester le dernier maillon même quand Valhalla est actif")
    }

    // MARK: - DetourRoutingService.route(...providers:) — chaîne de repli, providers injectés

    func testChainReturnsFirstProviderResultWhenItSucceeds() async throws {
        let expected = [origin, destination]
        let providers: [RoutingProvider] = [FakeAlwaysSucceedsProvider(coordinates: expected), FakeAlwaysFailsProvider()]

        let result = try await DetourRoutingService.route(from: origin, to: destination, profile: .route, providers: providers)

        XCTAssertEqual(result.count, expected.count)
    }

    func testChainFallsBackToNextProviderWithoutPropagatingTheFirstErrorWhenItFails() async throws {
        let fallbackCoordinates = [origin, destination]
        let providers: [RoutingProvider] = [FakeAlwaysFailsProvider(), FakeAlwaysSucceedsProvider(coordinates: fallbackCoordinates)]

        // Ne doit PAS throw : le repli vers le second provider doit être silencieux, exactement
        // comme "toggle ON + erreur réseau simulée → repli OSRM sans exception propagée".
        let result = try await DetourRoutingService.route(from: origin, to: destination, profile: .route, providers: providers)

        XCTAssertEqual(result.count, fallbackCoordinates.count)
    }

    func testChainThrowsOnlyWhenEveryProviderFails() async {
        let providers: [RoutingProvider] = [FakeAlwaysFailsProvider(), FakeAlwaysFailsProvider()]

        do {
            _ = try await DetourRoutingService.route(from: origin, to: destination, profile: .route, providers: providers)
            XCTFail("tous les providers échouent, une erreur doit être propagée")
        } catch {
            // Attendu.
        }
    }

    // MARK: - RoutingActivityMonitor (spec "routing-active-service-indicator", it24, point 0)
    // Instance FRAÎCHE à chaque test (jamais `.shared`) — jamais d'état partagé entre tests.

    func testChainRecordsValhallaOnDirectSuccess() async throws {
        let monitor = await RoutingActivityMonitor()
        let providers: [RoutingProvider] = [FakeAlwaysSucceedsProvider(kind: .valhalla, coordinates: [origin, destination])]

        _ = try await DetourRoutingService.route(from: origin, to: destination, profile: .route, providers: providers, activityMonitor: monitor)

        let lastEvent = await monitor.lastEvent
        XCTAssertEqual(lastEvent?.provider, .valhalla)
    }

    /// Cœur du retour terrain : "mock Valhalla en échec → bascule affichée sur OSRM".
    func testChainRecordsOSRMWhenValhallaFailsAndOSRMFallsBackSuccessfully() async throws {
        let monitor = await RoutingActivityMonitor()
        let providers: [RoutingProvider] = [FakeAlwaysFailsProvider(), FakeAlwaysSucceedsProvider(kind: .osrm, coordinates: [origin, destination])]

        _ = try await DetourRoutingService.route(from: origin, to: destination, profile: .route, providers: providers, activityMonitor: monitor)

        let lastEvent = await monitor.lastEvent
        XCTAssertEqual(lastEvent?.provider, .osrm, "Valhalla en échec doit basculer l'indicateur sur OSRM (repli)")
    }

    func testChainNeverRecordsAnythingWhenEveryProviderFails() async {
        let monitor = await RoutingActivityMonitor()
        let providers: [RoutingProvider] = [FakeAlwaysFailsProvider(), FakeAlwaysFailsProvider()]

        _ = try? await DetourRoutingService.route(from: origin, to: destination, profile: .route, providers: providers, activityMonitor: monitor)

        let lastEvent = await monitor.lastEvent
        XCTAssertNil(lastEvent, "aucun service n'a RÉELLEMENT répondu — l'indicateur ne doit jamais afficher un succès qui n'a pas eu lieu")
    }
}
