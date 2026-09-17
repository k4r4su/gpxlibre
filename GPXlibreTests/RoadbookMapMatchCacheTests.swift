import XCTest
import CoreLocation
@testable import GPXlibre

/// Spec "valhalla-map-matching-direction-change" (it20, "cache local... pour éviter de refaire
/// l'appel réseau à chaque chargement") — chaque test utilise un dossier temporaire dédié
/// (jamais le vrai `Documents/RoadbookMapMatchCache` de l'app), même patron que
/// `UnsavedRideStoreTests`.
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

    func testCoordinatesReturnsNilForAnUnknownTrack() {
        XCTAssertNil(makeCache().coordinates(for: UUID()))
    }

    func testStoreThenCoordinatesRoundTrips() {
        let cache = makeCache()
        let trackID = UUID()
        let coordinates = [
            CLLocationCoordinate2D(latitude: 45.1, longitude: 5.2),
            CLLocationCoordinate2D(latitude: 45.2, longitude: 5.3),
        ]

        cache.store(trackID: trackID, coordinates: coordinates)

        let result = cache.coordinates(for: trackID)
        XCTAssertEqual(result?.count, 2)
        XCTAssertEqual(result?[0].latitude ?? -1, 45.1, accuracy: 0.0000001)
        XCTAssertEqual(result?[1].longitude ?? -1, 5.3, accuracy: 0.0000001)
    }

    func testStoringAgainForTheSameTrackReplacesRatherThanDuplicates() {
        let cache = makeCache()
        let trackID = UUID()

        cache.store(trackID: trackID, coordinates: [CLLocationCoordinate2D(latitude: 1, longitude: 1)])
        cache.store(trackID: trackID, coordinates: [CLLocationCoordinate2D(latitude: 2, longitude: 2), CLLocationCoordinate2D(latitude: 3, longitude: 3)])

        XCTAssertEqual(cache.coordinates(for: trackID)?.count, 2)
    }

    /// Cœur du besoin terrain : une nouvelle instance (nouveau lancement de l'app) doit
    /// retrouver ce qu'une instance précédente a écrit sur le MÊME dossier.
    func testANewInstancePicksUpEntriesWrittenByAPreviousInstanceOnTheSameDirectory() {
        let trackID = UUID()
        let cache1 = makeCache()
        cache1.store(trackID: trackID, coordinates: [CLLocationCoordinate2D(latitude: 45.5, longitude: 5.5)])

        let cache2 = makeCache()

        XCTAssertEqual(cache2.coordinates(for: trackID)?.count, 1)
    }
}
