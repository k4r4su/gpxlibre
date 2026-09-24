import XCTest
import CoreLocation
@testable import GPXlibre

/// Spec "valhalla-map-matching-direction-change" (it20) — vérifie le DÉCLENCHEMENT du map
/// matching par `RideSessionManager` (une fois par trace, cache disque, dégradation propre) via
/// un `MapMatchingProvider` FACTICE (`session.mapMatchingProvider`, voir RideSessionManager) —
/// jamais de vrai réseau Valhalla dans ce fichier.
@MainActor
final class RideSessionManagerMapMatchingTests: XCTestCase {
    private var tempDirectory: URL!

    override func setUp() {
        super.setUp()
        tempDirectory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: tempDirectory)
        super.tearDown()
    }

    private final class FakeMapMatchingProvider: MapMatchingProvider {
        let maneuversToReturn: [MapMatchedManeuver]
        private(set) var callCount = 0

        /// `type: .right` par défaut — une vraie décision de conduite (`roadbookTier` non `nil`,
        /// voir it24 point 1), pour ne pas avoir à répéter ce détail dans chaque test qui ne
        /// s'intéresse qu'au déclenchement/cache, pas au filtrage type.
        init(coordinatesToReturn: [CLLocationCoordinate2D], type: ValhallaManeuverType = .right) {
            maneuversToReturn = coordinatesToReturn.map { MapMatchedManeuver(coordinate: $0, type: type, roundaboutExitCount: nil) }
        }

        func matchRoute(coordinates: [CLLocationCoordinate2D], configuration: ValhallaConfiguration) async throws -> [MapMatchedManeuver] {
            callCount += 1
            return maneuversToReturn
        }
    }

    private func makeSession(valhallaEnabled: Bool) -> RideSessionManager {
        let suite = "RideSessionManagerMapMatchingTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        let settings = RideSettingsStore(defaults: defaults)
        settings.valhallaEnabled = valhallaEnabled
        settings.valhallaEndpointURLString = valhallaEnabled ? "https://valhalla.example.com" : ""
        let session = RideSessionManager(
            settings: settings,
            networkMonitor: NetworkMonitor(),
            modeStore: RideModeStore(),
            sharedBlockages: SharedBlockageSyncCoordinator(defaults: defaults)
        )
        session.mapMatchCache = RoadbookMapMatchCache(directoryOverride: tempDirectory)
        return session
    }

    private func track(id: UUID = UUID()) -> GPXTrack {
        GPXTrack(
            id: id,
            name: "Test",
            fileName: "test.gpx",
            importDate: Date(),
            points: [
                GPXPoint(latitude: 45.0, longitude: 5.0),
                GPXPoint(latitude: 45.01, longitude: 5.0),
                GPXPoint(latitude: 45.02, longitude: 5.0),
            ],
            waypoints: []
        )
    }

    func testMapMatchingProviderIsNeverCalledWhenValhallaIsDisabled() async {
        let session = makeSession(valhallaEnabled: false)
        let provider = FakeMapMatchingProvider(coordinatesToReturn: [CLLocationCoordinate2D(latitude: 45.01, longitude: 5.0)])
        session.mapMatchingProvider = provider

        session.start(track: track())
        await session.mapMatchingTask?.value

        XCTAssertEqual(provider.callCount, 0)
        XCTAssertTrue(session.mapMatchedDirectionChangePoints.isEmpty)
    }

    func testMapMatchingProviderIsCalledOnceWhenValhallaEnabledAndResultIsCached() async {
        let session = makeSession(valhallaEnabled: true)
        let matchedTrack = track()
        let expectedCoordinate = matchedTrack.points[1].coordinate
        let provider = FakeMapMatchingProvider(coordinatesToReturn: [expectedCoordinate])
        session.mapMatchingProvider = provider

        session.start(track: matchedTrack)
        await session.mapMatchingTask?.value

        XCTAssertEqual(provider.callCount, 1)
        XCTAssertEqual(session.mapMatchedDirectionChangePoints.count, 1)
        XCTAssertEqual(session.mapMatchCache.maneuvers(for: matchedTrack)?.count, 1, "le résultat doit être écrit dans le cache disque")
    }

    /// Fix "mapmatch-cache-direction-aware" : inverser le sens de parcours (Réglages de trace →
    /// retour sur Ride, donc `switchMode` avec la MÊME `id` mais les points réordonnés) doit
    /// relancer le map matching — les types gauche/droite/rang de sortie de rond-point du sens
    /// A→B sont faux dans le sens B→A. Avant ce fix, le garde `mapMatchedTrackID == track.id`
    /// court-circuitait tout, et les manœuvres A→B restaient appliquées en B→A.
    func testReversingTheDirectionOfTheSameTrackRetriggersMapMatching() async {
        let session = makeSession(valhallaEnabled: true)
        let forward = track()
        let reversed = forward.reordered(using: TrackRideSettings(isReversed: true))
        let provider = FakeMapMatchingProvider(coordinatesToReturn: [forward.points[1].coordinate])
        session.mapMatchingProvider = provider

        session.start(track: forward)
        await session.mapMatchingTask?.value
        XCTAssertEqual(provider.callCount, 1)

        session.switchMode(track: reversed)
        await session.mapMatchingTask?.value

        XCTAssertEqual(provider.callCount, 2, "sens inversé : nouveau map matching, jamais les types du sens A→B")
        XCTAssertNotNil(session.mapMatchCache.maneuvers(for: forward))
        XCTAssertNotNil(session.mapMatchCache.maneuvers(for: reversed))
    }

    /// Retour d'onglet (Ride→Biblio→Ride) : `switchMode` est appelé pour la MÊME trace, le map
    /// matching ne doit PAS repartir en réseau une seconde fois.
    func testMapMatchingIsNotRetriggeredOnSwitchModeForTheSameTrack() async {
        let session = makeSession(valhallaEnabled: true)
        let sharedTrack = track()
        let provider = FakeMapMatchingProvider(coordinatesToReturn: [sharedTrack.points[1].coordinate])
        session.mapMatchingProvider = provider

        session.start(track: sharedTrack)
        await session.mapMatchingTask?.value
        XCTAssertEqual(provider.callCount, 1)

        session.switchMode(track: sharedTrack)
        await session.mapMatchingTask?.value

        XCTAssertEqual(provider.callCount, 1, "même trace : aucun nouvel appel réseau")
    }

    /// Le cache est tenu par TRACE et SENS (`traversalKey`), pas par session — une nouvelle session pointant vers le
    /// même dossier de cache (équivalent à un relancement de l'app) ne doit pas ré-appeler le
    /// réseau pour une trace déjà mise en cache.
    func testASecondSessionReusesTheDiskCacheInsteadOfCallingTheProviderAgain() async {
        let sharedTrack = track()

        let session1 = makeSession(valhallaEnabled: true)
        let provider1 = FakeMapMatchingProvider(coordinatesToReturn: [sharedTrack.points[1].coordinate])
        session1.mapMatchingProvider = provider1
        session1.start(track: sharedTrack)
        await session1.mapMatchingTask?.value
        XCTAssertEqual(provider1.callCount, 1)

        let session2 = makeSession(valhallaEnabled: true) // mapMatchCache pointe vers le MÊME tempDirectory
        let provider2 = FakeMapMatchingProvider(coordinatesToReturn: [])
        session2.mapMatchingProvider = provider2
        session2.start(track: sharedTrack)

        // Cache-hit : aucune Task créée du tout (voir triggerMapMatchingIfNeeded), donc rien à
        // attendre — la valeur est déjà disponible synchronement à la sortie de `start`.
        XCTAssertNil(session2.mapMatchingTask)
        XCTAssertEqual(provider2.callCount, 0, "le cache disque doit éviter un nouvel appel réseau")
        XCTAssertEqual(session2.mapMatchedDirectionChangePoints.count, 1)
    }

    /// Dégradation propre : le résultat du map matching finit bien par apparaître dans les
    /// checkpoints affichés (roadbook), une fois la tâche de fond terminée — pas seulement dans
    /// `mapMatchedDirectionChangePoints` en interne.
    func testMapMatchingResultEventuallyAppearsInCheckpoints() async {
        let session = makeSession(valhallaEnabled: true)
        // Trace avec un léger virage (20°, sous le seuil light 30° par défaut) au point du
        // milieu — invisible géométriquement seul.
        let lightTurnTrack = GPXTrack(
            id: UUID(),
            name: "Léger virage",
            fileName: "leger.gpx",
            importDate: Date(),
            points: [
                GPXPoint(latitude: 45.0, longitude: 5.0),
                GPXPoint(latitude: 45.001, longitude: 5.0),
                GPXPoint(latitude: 45.002, longitude: 5.0002),
            ],
            waypoints: []
        )
        let provider = FakeMapMatchingProvider(coordinatesToReturn: [lightTurnTrack.points[1].coordinate])
        session.mapMatchingProvider = provider

        session.start(track: lightTurnTrack)
        XCTAssertTrue(session.checkpoints.isEmpty, "avant la fin de la tâche de fond, rien de nouveau")

        await session.mapMatchingTask?.value

        XCTAssertTrue(session.checkpoints.contains { $0.tier == .lightDirectionChange })
    }
}
