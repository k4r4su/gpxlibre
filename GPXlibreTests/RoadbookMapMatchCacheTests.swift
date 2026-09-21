import XCTest
import CoreLocation
@testable import GPXlibre

/// Spec "valhalla-map-matching-direction-change" (it20, "cache local... pour éviter de refaire
/// l'appel réseau à chaque chargement") ; format enrichi type/roundabout_exit_count en it24
/// (point 1/2) — chaque test utilise un dossier temporaire dédié (jamais le vrai
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

    func testManeuversReturnsNilForAnUnknownTrack() {
        XCTAssertNil(makeCache().maneuvers(for: UUID()))
    }

    func testStoreThenManeuversRoundTrips() {
        let cache = makeCache()
        let trackID = UUID()
        let maneuvers = [
            MapMatchedManeuver(coordinate: CLLocationCoordinate2D(latitude: 45.1, longitude: 5.2), type: .right, roundaboutExitCount: nil),
            MapMatchedManeuver(coordinate: CLLocationCoordinate2D(latitude: 45.2, longitude: 5.3), type: .roundaboutExit, roundaboutExitCount: 2),
        ]

        cache.store(trackID: trackID, maneuvers: maneuvers)

        let result = cache.maneuvers(for: trackID)
        XCTAssertEqual(result?.count, 2)
        XCTAssertEqual(result?[0].coordinate.latitude ?? -1, 45.1, accuracy: 0.0000001)
        XCTAssertEqual(result?[1].coordinate.longitude ?? -1, 5.3, accuracy: 0.0000001)
        XCTAssertEqual(result?[0].type, .right)
        XCTAssertEqual(result?[1].type, .roundaboutExit)
        XCTAssertEqual(result?[1].roundaboutExitCount, 2)
    }

    func testStoringAgainForTheSameTrackReplacesRatherThanDuplicates() {
        let cache = makeCache()
        let trackID = UUID()

        cache.store(trackID: trackID, maneuvers: [MapMatchedManeuver(coordinate: CLLocationCoordinate2D(latitude: 1, longitude: 1), type: .right, roundaboutExitCount: nil)])
        cache.store(trackID: trackID, maneuvers: [
            MapMatchedManeuver(coordinate: CLLocationCoordinate2D(latitude: 2, longitude: 2), type: .left, roundaboutExitCount: nil),
            MapMatchedManeuver(coordinate: CLLocationCoordinate2D(latitude: 3, longitude: 3), type: .left, roundaboutExitCount: nil),
        ])

        XCTAssertEqual(cache.maneuvers(for: trackID)?.count, 2)
    }

    /// Cœur du besoin terrain : une nouvelle instance (nouveau lancement de l'app) doit
    /// retrouver ce qu'une instance précédente a écrit sur le MÊME dossier.
    func testANewInstancePicksUpEntriesWrittenByAPreviousInstanceOnTheSameDirectory() {
        let trackID = UUID()
        let cache1 = makeCache()
        cache1.store(trackID: trackID, maneuvers: [MapMatchedManeuver(coordinate: CLLocationCoordinate2D(latitude: 45.5, longitude: 5.5), type: .right, roundaboutExitCount: nil)])

        let cache2 = makeCache()

        XCTAssertEqual(cache2.maneuvers(for: trackID)?.count, 1)
    }

    /// Dégradation propre documentée (spec it24) : un ancien fichier `index.json` (format it20,
    /// `coordinates` seul, sans `type`) échoue à décoder — jamais un crash, juste un cache VIDE,
    /// le prochain accès se comporte comme si rien n'avait jamais été mis en cache.
    func testAnOldFormatIndexFileIsIgnoredRatherThanCrashing() throws {
        let trackID = UUID()
        try FileManager.default.createDirectory(at: tempDirectory, withIntermediateDirectories: true)
        let legacyJSON = """
        [{"trackID":"\(trackID.uuidString)","coordinates":[{"latitude":45.1,"longitude":5.2}]}]
        """
        try legacyJSON.data(using: .utf8)!.write(to: tempDirectory.appendingPathComponent("index.json"))

        let cache = makeCache()

        XCTAssertNil(cache.maneuvers(for: trackID))
    }
}
