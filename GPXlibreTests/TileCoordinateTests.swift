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
}
