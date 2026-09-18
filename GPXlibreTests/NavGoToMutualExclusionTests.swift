import XCTest
import CoreLocation
@testable import GPXlibre

/// Fix "nav-goto-mutual-exclusion" (it21, retour terrain : "je vois pas de diff" en testant le
/// repli sans Valhalla juste après un guidage riche) — `startNav`/`startGoTo` doivent s'exclure
/// mutuellement : sélectionner une nouvelle destination via "Aller à" ne doit jamais laisser
/// l'ANCIEN guidage (l'autre genre) actif en même temps que le nouveau. Vérifié au niveau
/// SYNCHRONE (`stopGoTo()`/`stopNav()` s'exécutent avant même le lancement de la tâche réseau
/// de l'autre) — jamais de vrai réseau ici, `startGoTo` lance un vrai appel OSRM/Valhalla que ce
/// fichier n'a pas besoin d'attendre pour vérifier l'exclusion mutuelle elle-même.
@MainActor
final class NavGoToMutualExclusionTests: XCTestCase {
    private final class FakeNavRoutingProvider: NavRoutingProvider {
        func route(from origin: CLLocationCoordinate2D, to destination: CLLocationCoordinate2D, destinationLabel: String, configuration: ValhallaConfiguration) async throws -> ValhallaNavRoute {
            ValhallaNavRoute(
                coordinates: [origin, destination],
                maneuvers: [],
                totalDistanceMeters: 1000,
                totalDurationSeconds: 60,
                destinationLabel: destinationLabel
            )
        }
    }

    private func makeSession() -> RideSessionManager {
        let suite = "NavGoToMutualExclusionTests.\(UUID().uuidString)"
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

    /// `startGoTo` lance un vrai appel réseau (OSRM/Valhalla) en tâche de fond — non mocké ici,
    /// annulé en fin de test pour ne rien laisser tourner. Ce qui est vérifié est SYNCHRONE :
    /// `stopNav()` s'exécute avant même que cette tâche ne démarre.
    func testStartingSimpleGoToClearsAnyActiveRichNavGuidanceImmediately() async {
        let session = makeSession()
        session.start(track: nil)
        session.handle(location: location(CLLocationCoordinate2D(latitude: 45.0, longitude: 5.0)))

        session.startNav(to: CLLocationCoordinate2D(latitude: 45.01, longitude: 5.0), label: "Riche")
        await session.navRoutingTask?.value
        XCTAssertNotNil(session.navRoute, "précondition : un guidage riche est actif")

        session.startGoTo(to: CLLocationCoordinate2D(latitude: 45.02, longitude: 5.0), label: "Simple", profile: .offroad)

        XCTAssertNil(session.navRoute, "démarrer un guidage simple doit effacer immédiatement l'ancien guidage riche, avant même la résolution réseau du nouveau")

        session.goToTask?.cancel()
    }

    /// Symétrique : `startNav` doit effacer immédiatement un guidage simple en cours, avant
    /// même de lancer son propre calcul d'itinéraire (mocké ici, `FakeNavRoutingProvider`).
    func testStartingRichNavClearsAnyActiveSimpleGoToRequestImmediately() async {
        let session = makeSession()
        session.start(track: nil)
        session.handle(location: location(CLLocationCoordinate2D(latitude: 45.0, longitude: 5.0)))

        session.startGoTo(to: CLLocationCoordinate2D(latitude: 45.01, longitude: 5.0), label: "Simple", profile: .offroad)
        XCTAssertTrue(session.isRequestingGoTo, "précondition : une requête de guidage simple est en cours")

        session.startNav(to: CLLocationCoordinate2D(latitude: 45.02, longitude: 5.0), label: "Riche")

        XCTAssertFalse(session.isRequestingGoTo, "démarrer un guidage riche doit annuler la requête de guidage simple en cours")
        XCTAssertNil(session.goToGuidance)

        await session.navRoutingTask?.value
        XCTAssertNotNil(session.navRoute)
    }
}
