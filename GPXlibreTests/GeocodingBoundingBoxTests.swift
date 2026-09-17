import XCTest
@testable import GPXlibre

/// Spec "region-download-by-place" (it21) — décodage du champ `boundingbox` de Nominatim
/// (`[minLat, maxLat, minLon, maxLon]`, en chaînes), testé sans réseau ni JSON brut.
final class GeocodingBoundingBoxTests: XCTestCase {
    func testValidFourElementArrayParsesCorrectly() {
        let box = GeocodingBoundingBox(nominatimStrings: ["41.3", "51.1", "-5.2", "9.6"])

        XCTAssertEqual(box?.minLat, 41.3)
        XCTAssertEqual(box?.maxLat, 51.1)
        XCTAssertEqual(box?.minLon, -5.2)
        XCTAssertEqual(box?.maxLon, 9.6)
    }

    func testNilArrayProducesNil() {
        XCTAssertNil(GeocodingBoundingBox(nominatimStrings: nil))
    }

    func testWrongElementCountProducesNil() {
        XCTAssertNil(GeocodingBoundingBox(nominatimStrings: ["41.3", "51.1", "-5.2"]))
    }

    func testNonNumericElementProducesNil() {
        XCTAssertNil(GeocodingBoundingBox(nominatimStrings: ["41.3", "pas-un-nombre", "-5.2", "9.6"]))
    }
}
