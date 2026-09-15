import XCTest
import CoreLocation
@testable import GPXlibre

/// Spec it19 (P0 "prévisualisation de trace A→B") : cadrage caméra de la fiche trace avec une
/// marge GÉOGRAPHIQUE (~2 km réels, `TrackFicheMapView.cameraGeographicMarginMeters`), pas un
/// padding écran qui varierait avec le zoom/la taille d'écran. Logique pure extraite pour être
/// testable sans instancier de vrai `MLNMapView`.
final class TrackFicheCameraFitTests: XCTestCase {
    private typealias Coordinator = TrackFicheMapView.Coordinator

    func testBoundingBoxOfEmptyCoordinatesIsNil() {
        XCTAssertNil(Coordinator.boundingBox(of: []))
    }

    func testBoundingBoxMatchesMinMaxOfAllCoordinates() {
        let coordinates = [
            CLLocationCoordinate2D(latitude: 45.0, longitude: 5.0),
            CLLocationCoordinate2D(latitude: 45.2, longitude: 4.8),
            CLLocationCoordinate2D(latitude: 44.9, longitude: 5.3),
        ]

        let bounds = Coordinator.boundingBox(of: coordinates)

        XCTAssertEqual(bounds?.minLat, 44.9)
        XCTAssertEqual(bounds?.maxLat, 45.2)
        XCTAssertEqual(bounds?.minLon, 4.8)
        XCTAssertEqual(bounds?.maxLon, 5.3)
    }

    /// ~2 km ajoutés de CHAQUE côté (haut/bas/gauche/droite) — 2000 m / 111 320 m par degré de
    /// latitude ≈ 0.01796°, tolérance large (calcul volontairement approximatif, cadrage
    /// caméra, jamais du routing).
    func testExpandedBoundsAddsApproximatelyTwoKilometersOnEachSide() {
        let raw = (minLat: 45.0, maxLat: 45.1, minLon: 5.0, maxLon: 5.1)

        let expanded = Coordinator.expandedBounds(raw, byMeters: 2000)

        let expectedLatMargin = 2000.0 / 111_320.0
        XCTAssertEqual(expanded.minLat, raw.minLat - expectedLatMargin, accuracy: 0.0001)
        XCTAssertEqual(expanded.maxLat, raw.maxLat + expectedLatMargin, accuracy: 0.0001)
        XCTAssertLessThan(expanded.minLat, raw.minLat)
        XCTAssertGreaterThan(expanded.maxLat, raw.maxLat)
        XCTAssertLessThan(expanded.minLon, raw.minLon)
        XCTAssertGreaterThan(expanded.maxLon, raw.maxLon)
    }

    /// La marge en LONGITUDE doit être plus grande à haute latitude (les degrés de longitude
    /// couvrent moins de distance réelle près des pôles, `cos(latitude)` au dénominateur) — un
    /// même nombre de mètres réels doit donc correspondre à PLUS de degrés de longitude à 60°N
    /// qu'à l'équateur.
    func testExpandedBoundsLongitudeMarginGrowsWithLatitude() {
        let nearEquator = (minLat: 0.0, maxLat: 0.1, minLon: 0.0, maxLon: 0.1)
        let highLatitude = (minLat: 60.0, maxLat: 60.1, minLon: 0.0, maxLon: 0.1)

        let expandedEquator = Coordinator.expandedBounds(nearEquator, byMeters: 2000)
        let expandedHighLat = Coordinator.expandedBounds(highLatitude, byMeters: 2000)

        let lonMarginEquator = nearEquator.minLon - expandedEquator.minLon
        let lonMarginHighLat = highLatitude.minLon - expandedHighLat.minLon
        XCTAssertGreaterThan(lonMarginHighLat, lonMarginEquator)
    }

    func testZeroMarginReturnsBoundsUnchanged() {
        let raw = (minLat: 45.0, maxLat: 45.1, minLon: 5.0, maxLon: 5.1)

        let expanded = Coordinator.expandedBounds(raw, byMeters: 0)

        XCTAssertEqual(expanded.minLat, raw.minLat, accuracy: 1e-9)
        XCTAssertEqual(expanded.maxLat, raw.maxLat, accuracy: 1e-9)
        XCTAssertEqual(expanded.minLon, raw.minLon, accuracy: 1e-9)
        XCTAssertEqual(expanded.maxLon, raw.maxLon, accuracy: 1e-9)
    }
}
