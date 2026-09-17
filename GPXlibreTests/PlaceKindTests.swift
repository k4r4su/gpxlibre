import XCTest
@testable import GPXlibre

/// Spec "region-download-by-place" (it21) : "Pays → pays entier ; Région → région + 50 km ;
/// Ville → ville + 100 km" — vérifie que chaque cas porte exactement le comportement demandé.
final class PlaceKindTests: XCTestCase {
    func testCountryHasNoDefaultRadiusSinceItUsesTheRealExtent() {
        XCTAssertNil(PlaceKind.country.defaultRadiusKm)
    }

    func testRegionDefaultRadiusIs50Km() {
        XCTAssertEqual(PlaceKind.region.defaultRadiusKm, 50)
    }

    func testCityDefaultRadiusIs100Km() {
        XCTAssertEqual(PlaceKind.city.defaultRadiusKm, 100)
    }

    func testNominatimFeatureTypesMatchTheThreeExpectedValues() {
        XCTAssertEqual(PlaceKind.country.nominatimFeatureType, "country")
        XCTAssertEqual(PlaceKind.region.nominatimFeatureType, "state")
        XCTAssertEqual(PlaceKind.city.nominatimFeatureType, "city")
    }
}
