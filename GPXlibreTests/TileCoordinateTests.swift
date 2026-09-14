import XCTest
import CoreLocation
@testable import GPXlibre

/// Fix "region-picker-huge-bbox-crash" (bug terrain, it16) — `RegionPickerMapView` démarrait
/// sans caméra initiale, et un premier `visibleCoordinateBounds` proche du "monde" faisait
/// énumérer des milliards de tuiles synchroniquement sur le thread principal (watchdog kill
/// après ~10 s). `TileCoordinate.tileCount` doit rester en O(1) (jamais matérialiser la liste)
/// pour que `RegionDownloadView.updateEstimate()` puisse comparer au plafond AVANT d'énumérer.
final class TileCoordinateTests: XCTestCase {
    func testTileCountMatchesActualTilesCountForASmallArea() {
        let count = TileCoordinate.tileCount(minLat: 45.0, maxLat: 45.05, minLon: 5.0, maxLon: 5.05, zoom: 12)
        let tiles = TileCoordinate.tiles(minLat: 45.0, maxLat: 45.05, minLon: 5.0, maxLon: 5.05, zoom: 12)

        XCTAssertEqual(count, tiles.count, "le compte O(1) doit être exact, pas une approximation")
    }

    /// Ne DOIT JAMAIS appeler `tiles(...)` sur ce cas — c'est justement ce qui gelait le thread
    /// principal. `tileCount` doit rester instantané même pour une zone quasi mondiale.
    func testTileCountForNearWorldBoundsAtDeepZoomExceedsHardCapWithoutHanging() {
        let count = TileCoordinate.tileCount(minLat: -85, maxLat: 85, minLon: -179, maxLon: 179, zoom: OfflineConstants.regionMaxZoomSliderValue)

        XCTAssertGreaterThan(count, OfflineConstants.regionTileCountHardCap, "une zone quasi mondiale au zoom max doit dépasser le plafond — sinon le garde-fou ne se déclencherait jamais")
    }

    func testTileCountIsZeroForInvertedOrDegenerateBounds() {
        let count = TileCoordinate.tileCount(minLat: 45.0, maxLat: 44.0, minLon: 5.0, maxLon: 4.0, zoom: 12)

        XCTAssertEqual(count, 0)
    }

    // MARK: - northWestCorner (spec "offline-zones-outline", it17, Bloc 1)

    /// Round-trip avec `covering` : le coin NO de la tuile qui couvre un point doit être au
    /// nord-ouest (ou exactement sur) ce point, jamais au-delà.
    func testNorthWestCornerIsConsistentWithCovering() {
        let coordinate = CLLocationCoordinate2D(latitude: 45.5, longitude: 5.5)
        let tile = TileCoordinate.covering(latitude: coordinate.latitude, longitude: coordinate.longitude, zoom: 10)
        let corner = TileCoordinate.northWestCorner(z: tile.z, x: tile.x, y: tile.y)

        XCTAssertLessThanOrEqual(corner.longitude, coordinate.longitude)
        XCTAssertGreaterThanOrEqual(corner.latitude, coordinate.latitude)
    }

    func testNorthWestCornerOfTile000IsTopLeftOfTheWorld() {
        let corner = TileCoordinate.northWestCorner(z: 0, x: 0, y: 0)
        XCTAssertEqual(corner.longitude, -180, accuracy: 0.001)
        XCTAssertEqual(corner.latitude, 85.05, accuracy: 0.01, "limite de Mercator standard (~85.0511°)")
    }
}
