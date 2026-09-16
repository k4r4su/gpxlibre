import XCTest
import CoreLocation
@testable import GPXlibre

/// Spec "valhalla-client-toggle" (it19) : `ValhallaRoutingService.decodePolyline6` doit décoder
/// au facteur de PRÉCISION 6 (1e6), pas 5 (Google Maps/OSRM standard) — l'erreur la plus
/// probable sur ce genre de décodeur. Vérifié ici par ROUND-TRIP (encode localement avec
/// l'algorithme inverse bien connu, puis décode avec le code de production) : si le décodeur
/// utilisait le mauvais facteur, les coordonnées reviendraient fausses d'un facteur 10, ce que
/// la comparaison avec tolérance serrée détecte directement — pas besoin d'un vecteur de test
/// externe pour vérifier cette propriété.
final class ValhallaPolylineTests: XCTestCase {
    private func encodePolyline6(_ coordinates: [CLLocationCoordinate2D]) -> String {
        var output = ""
        var previousLatitude = 0
        var previousLongitude = 0
        for coordinate in coordinates {
            let latitude = Int((coordinate.latitude * 1e6).rounded())
            let longitude = Int((coordinate.longitude * 1e6).rounded())
            output += encodeValue(latitude - previousLatitude)
            output += encodeValue(longitude - previousLongitude)
            previousLatitude = latitude
            previousLongitude = longitude
        }
        return output
    }

    private func encodeValue(_ value: Int) -> String {
        var shifted = value << 1
        if value < 0 { shifted = ~shifted }
        var output = ""
        while shifted >= 0x20 {
            output.unicodeScalars.append(UnicodeScalar(UInt8((0x20 | (shifted & 0x1f)) + 63)))
            shifted >>= 5
        }
        output.unicodeScalars.append(UnicodeScalar(UInt8(shifted + 63)))
        return output
    }

    func testRoundTripPreservesCoordinatesAtPrecision6() {
        let original = [
            CLLocationCoordinate2D(latitude: 45.188410, longitude: 5.724522),
            CLLocationCoordinate2D(latitude: 45.188932, longitude: 5.725103),
            CLLocationCoordinate2D(latitude: 45.190005, longitude: 5.726811),
            CLLocationCoordinate2D(latitude: 45.150000, longitude: 5.700000),
        ]
        let encoded = encodePolyline6(original)

        let decoded = ValhallaRoutingService.decodePolyline6(encoded)

        XCTAssertEqual(decoded.count, original.count)
        for (expected, actual) in zip(original, decoded) {
            XCTAssertEqual(actual.latitude, expected.latitude, accuracy: 0.0000001)
            XCTAssertEqual(actual.longitude, expected.longitude, accuracy: 0.0000001)
        }
    }

    func testRoundTripHandlesNegativeCoordinates() {
        let original = [
            CLLocationCoordinate2D(latitude: -33.865143, longitude: -70.649513),
            CLLocationCoordinate2D(latitude: -33.860000, longitude: -70.640000),
        ]
        let encoded = encodePolyline6(original)

        let decoded = ValhallaRoutingService.decodePolyline6(encoded)

        XCTAssertEqual(decoded.count, original.count)
        for (expected, actual) in zip(original, decoded) {
            XCTAssertEqual(actual.latitude, expected.latitude, accuracy: 0.0000001)
            XCTAssertEqual(actual.longitude, expected.longitude, accuracy: 0.0000001)
        }
    }

    func testEmptyStringDecodesToEmptyArray() {
        XCTAssertTrue(ValhallaRoutingService.decodePolyline6("").isEmpty)
    }

    func testSinglePointRoundTrip() {
        let original = [CLLocationCoordinate2D(latitude: 45.0, longitude: 5.0)]
        let encoded = encodePolyline6(original)

        let decoded = ValhallaRoutingService.decodePolyline6(encoded)

        XCTAssertEqual(decoded.count, 1)
        XCTAssertEqual(decoded[0].latitude, 45.0, accuracy: 0.0000001)
        XCTAssertEqual(decoded[0].longitude, 5.0, accuracy: 0.0000001)
    }
}
