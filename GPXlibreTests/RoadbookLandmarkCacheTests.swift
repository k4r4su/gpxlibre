import XCTest
import CoreLocation
@testable import GPXlibre

/// `directoryOverride` (même patron que `RoadbookMapMatchCache`/`UnsavedRideStore`) — jamais le
/// vrai `Documents/` pendant un test.
@MainActor
final class RoadbookLandmarkCacheTests: XCTestCase {
    private var tempDirectory: URL!
    private var cache: RoadbookLandmarkCache!

    override func setUp() {
        super.setUp()
        tempDirectory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        cache = RoadbookLandmarkCache(directoryOverride: tempDirectory)
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: tempDirectory)
        super.tearDown()
    }

    private let coordinate = CLLocationCoordinate2D(latitude: 45.18800, longitude: 5.72400)

    /// Distinction cœur du fix : un point jamais interrogé (`.notCached`) est DIFFÉRENT d'un
    /// point interrogé sans résultat (`.cached(nil)`) — sans cette distinction, un point sans
    /// repère serait réinterrogé à chaque ouverture de l'écran.
    func testUnqueriedCoordinateReturnsNotCached() {
        XCTAssertEqual(cache.lookup(for: coordinate), .notCached)
    }

    func testStoringAFoundLabelIsRetrievable() {
        cache.store(label: "Rond-point", for: coordinate)
        XCTAssertEqual(cache.lookup(for: coordinate), .cached("Rond-point"))
    }

    func testStoringANegativeResultIsRetrievableAsCachedNil() {
        cache.store(label: nil, for: coordinate)
        XCTAssertEqual(cache.lookup(for: coordinate), .cached(nil))
    }

    func testPersistsAcrossInstancesUsingTheSameDirectory() {
        cache.store(label: "Église", for: coordinate)
        let reloaded = RoadbookLandmarkCache(directoryOverride: tempDirectory)
        XCTAssertEqual(reloaded.lookup(for: coordinate), .cached("Église"))
    }

    func testDifferentCoordinatesAreIsolated() {
        let other = CLLocationCoordinate2D(latitude: 46.0, longitude: 6.0)
        cache.store(label: "Rond-point", for: coordinate)
        XCTAssertEqual(cache.lookup(for: other), .notCached)
    }
}
