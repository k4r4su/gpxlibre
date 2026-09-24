import XCTest
import CoreLocation
@testable import GPXlibre

/// Spec "valhalla-map-matching-direction-change" (it20, "cache local... pour éviter de refaire
/// l'appel réseau à chaque chargement") ; format enrichi type/roundabout_exit_count en it24
/// (point 1/2) ; clé par SENS de parcours en it26 (fix "mapmatch-cache-direction-aware") —
/// chaque test utilise un dossier temporaire dédié (jamais le vrai
/// `Documents/RoadbookMapMatchCache` de l'app), même patron que `UnsavedRideStoreTests`.
@MainActor
final class RoadbookMapMatchCacheTests: XCTestCase {
    private var tempDirectory: URL!

    override func setUp() {
        super.setUp()
        tempDirectory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: tempDirectory)
        super.tearDown()
    }

    private func makeCache() -> RoadbookMapMatchCache {
        RoadbookMapMatchCache(directoryOverride: tempDirectory)
    }

    private func makeTrack(id: UUID = UUID()) -> GPXTrack {
        GPXTrack(
            id: id, name: "Test", fileName: "t.gpx", importDate: Date(),
            points: [
                GPXPoint(latitude: 45.000, longitude: 5.000),
                GPXPoint(latitude: 45.001, longitude: 5.000),
                GPXPoint(latitude: 45.002, longitude: 5.001),
            ],
            waypoints: []
        )
    }

    func testManeuversReturnsNilForAnUnknownTrack() {
        XCTAssertNil(makeCache().maneuvers(for: makeTrack()))
    }

    func testStoreThenManeuversRoundTrips() {
        let cache = makeCache()
        let track = makeTrack()
        let maneuvers = [
            MapMatchedManeuver(coordinate: CLLocationCoordinate2D(latitude: 45.1, longitude: 5.2), type: .right, roundaboutExitCount: nil),
            MapMatchedManeuver(coordinate: CLLocationCoordinate2D(latitude: 45.2, longitude: 5.3), type: .roundaboutExit, roundaboutExitCount: 2),
        ]

        cache.store(traversalKey: track.traversalKey, maneuvers: maneuvers)

        let result = cache.maneuvers(for: track)
        XCTAssertEqual(result?.count, 2)
        XCTAssertEqual(result?[0].coordinate.latitude ?? -1, 45.1, accuracy: 0.0000001)
        XCTAssertEqual(result?[1].coordinate.longitude ?? -1, 5.3, accuracy: 0.0000001)
        XCTAssertEqual(result?[0].type, .right)
        XCTAssertEqual(result?[1].type, .roundaboutExit)
        XCTAssertEqual(result?[1].roundaboutExitCount, 2)
    }

    func testStoringAgainForTheSameTrackReplacesRatherThanDuplicates() {
        let cache = makeCache()
        let track = makeTrack()

        cache.store(traversalKey: track.traversalKey, maneuvers: [MapMatchedManeuver(coordinate: CLLocationCoordinate2D(latitude: 1, longitude: 1), type: .right, roundaboutExitCount: nil)])
        cache.store(traversalKey: track.traversalKey, maneuvers: [
            MapMatchedManeuver(coordinate: CLLocationCoordinate2D(latitude: 2, longitude: 2), type: .left, roundaboutExitCount: nil),
            MapMatchedManeuver(coordinate: CLLocationCoordinate2D(latitude: 3, longitude: 3), type: .left, roundaboutExitCount: nil),
        ])

        XCTAssertEqual(cache.maneuvers(for: track)?.count, 2)
    }

    /// Cœur du besoin terrain : une nouvelle instance (nouveau lancement de l'app) doit
    /// retrouver ce qu'une instance précédente a écrit sur le MÊME dossier.
    func testANewInstancePicksUpEntriesWrittenByAPreviousInstanceOnTheSameDirectory() {
        let track = makeTrack()
        let cache1 = makeCache()
        cache1.store(traversalKey: track.traversalKey, maneuvers: [MapMatchedManeuver(coordinate: CLLocationCoordinate2D(latitude: 45.5, longitude: 5.5), type: .right, roundaboutExitCount: nil)])

        let cache2 = makeCache()

        XCTAssertEqual(cache2.maneuvers(for: track)?.count, 1)
    }

    /// Fix "mapmatch-cache-direction-aware" : un résultat map-matché dans le sens A→B (types
    /// gauche/droite, rang de sortie de rond-point propres à CE sens) ne doit JAMAIS être servi
    /// tel quel pour la même trace parcourue en sens inverse — `reordered(using:)` préserve
    /// `id`, seule `traversalKey` distingue les deux.
    func testAResultStoredForOneDirectionIsNotServedForTheReversedDirection() {
        let cache = makeCache()
        let forward = makeTrack()
        let reversed = forward.reordered(using: TrackRideSettings(isReversed: true))
        XCTAssertEqual(forward.id, reversed.id)

        cache.store(traversalKey: forward.traversalKey, maneuvers: [MapMatchedManeuver(coordinate: CLLocationCoordinate2D(latitude: 45.001, longitude: 5.0), type: .right, roundaboutExitCount: nil)])

        XCTAssertNotNil(cache.maneuvers(for: forward))
        XCTAssertNil(cache.maneuvers(for: reversed), "le sens inverse doit déclencher son propre map matching, jamais réutiliser les types du sens A→B")
    }

    /// Sur une boucle, le premier point est au même endroit dans les deux sens — la clé doit
    /// quand même distinguer les deux sens (elle inclut le DEUXIÈME point).
    func testTraversalKeyDistinguishesBothDirectionsOfALoop() {
        let loop = GPXTrack(
            id: UUID(), name: "Boucle", fileName: "b.gpx", importDate: Date(),
            points: [
                GPXPoint(latitude: 45.000, longitude: 5.000),
                GPXPoint(latitude: 45.001, longitude: 5.000),
                GPXPoint(latitude: 45.001, longitude: 5.001),
                GPXPoint(latitude: 45.000, longitude: 5.000),
            ],
            waypoints: []
        )
        let reversed = loop.reordered(using: TrackRideSettings(isReversed: true))

        XCTAssertNotEqual(loop.traversalKey, reversed.traversalKey)
    }

    /// Dégradation propre documentée : un ancien fichier `index.json` (format it20 `coordinates`
    /// seul, OU format it24 indexé par `trackID`) échoue à décoder — jamais un crash, juste un
    /// cache VIDE, le prochain accès se comporte comme si rien n'avait jamais été mis en cache.
    func testAnOldFormatIndexFileIsIgnoredRatherThanCrashing() throws {
        let track = makeTrack()
        try FileManager.default.createDirectory(at: tempDirectory, withIntermediateDirectories: true)
        let legacyJSON = """
        [{"trackID":"\(track.id.uuidString)","maneuvers":[{"coordinate":{"latitude":45.1,"longitude":5.2},"maneuverTypeRawValue":10}]}]
        """
        try legacyJSON.data(using: .utf8)!.write(to: tempDirectory.appendingPathComponent("index.json"))

        let cache = makeCache()

        XCTAssertNil(cache.maneuvers(for: track))
    }
}
