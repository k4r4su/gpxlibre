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

    // MARK: - boundingBox(around:radiusMeters:) — spec "region-download-by-place" (it21),
    // réutilisé pour le rayon région/ville autour d'un lieu géocodé (déjà utilisé depuis it17
    // pour le corridor de trace, jamais testé directement jusqu'ici).

    /// 1° de latitude ≈ 111.32 km partout sur Terre (contrairement à la longitude, qui varie
    /// avec cos(latitude)) — un rayon de 111 320 m doit donc produire un delta lat ≈ 1°.
    func testBoundingBoxAroundProducesRoughlyOneDegreeLatitudeDeltaFor111KmRadius() {
        let coordinate = CLLocationCoordinate2D(latitude: 45.0, longitude: 5.0)
        let box = TileCoordinate.boundingBox(around: coordinate, radiusMeters: 111_320)

        XCTAssertEqual(box.maxLat - box.minLat, 2.0, accuracy: 0.01, "±1° de chaque côté")
        XCTAssertEqual(box.minLat, coordinate.latitude - 1, accuracy: 0.01)
        XCTAssertEqual(box.maxLat, coordinate.latitude + 1, accuracy: 0.01)
    }

    /// À 60° de latitude, cos(60°) = 0.5 — le même rayon en mètres doit donc produire un delta
    /// de LONGITUDE environ deux fois plus grand qu'à l'équateur (les degrés de longitude sont
    /// deux fois plus "serrés" en distance à cette latitude).
    func testBoundingBoxAroundWidensLongitudeDeltaAtHigherLatitude() {
        let equator = TileCoordinate.boundingBox(around: CLLocationCoordinate2D(latitude: 0, longitude: 5.0), radiusMeters: 50_000)
        let sixtyNorth = TileCoordinate.boundingBox(around: CLLocationCoordinate2D(latitude: 60, longitude: 5.0), radiusMeters: 50_000)

        let equatorLonDelta = equator.maxLon - equator.minLon
        let sixtyLonDelta = sixtyNorth.maxLon - sixtyNorth.minLon
        XCTAssertEqual(sixtyLonDelta, equatorLonDelta * 2, accuracy: 0.01)
    }

    func testBoundingBoxAroundIsCenteredOnTheOriginalCoordinate() {
        let coordinate = CLLocationCoordinate2D(latitude: 45.0, longitude: 5.0)
        let box = TileCoordinate.boundingBox(around: coordinate, radiusMeters: 20_000)

        XCTAssertEqual((box.minLat + box.maxLat) / 2, coordinate.latitude, accuracy: 0.0001)
        XCTAssertEqual((box.minLon + box.maxLon) / 2, coordinate.longitude, accuracy: 0.0001)
    }
}
