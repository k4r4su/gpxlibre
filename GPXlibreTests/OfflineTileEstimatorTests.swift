import XCTest
@testable import GPXlibre

/// Spec "region-download-by-place" (it21) — `OfflineTileEstimator` factorise le patron "compter
/// avant d'énumérer" (fix "region-picker-huge-bbox-crash", it16) pour être réutilisé par
/// `PlaceRegionPickerView` en plus de `RegionDownloadView`.
final class OfflineTileEstimatorTests: XCTestCase {
    func testEmptyWhenMaxZoomIsBelowMinZoom() {
        let result = OfflineTileEstimator.estimate(
            minLat: 45.0, maxLat: 45.1, minLon: 5.0, maxLon: 5.1,
            minZoom: 14, maxZoom: 12, source: .osmStandard
        )

        guard case .empty = result else { return XCTFail("attendu .empty, obtenu \(result)") }
    }

    /// Ne DOIT JAMAIS matérialiser la liste de tuiles pour ce cas — c'est justement ce qui
    /// gelait le thread principal (fix it16). Mêmes bornes que `TileCoordinateTests`.
    func testTooLargeForNearWorldBoundsWithoutHanging() {
        let result = OfflineTileEstimator.estimate(
            minLat: -85, maxLat: 85, minLon: -179, maxLon: 179,
            minZoom: OfflineConstants.regionMinZoomSliderValue, maxZoom: OfflineConstants.regionMaxZoomSliderValue,
            source: .osmStandard
        )

        guard case .tooLarge = result else { return XCTFail("attendu .tooLarge, obtenu \(result)") }
    }

    func testSmallAreaProducesANonEmptyEstimate() {
        let result = OfflineTileEstimator.estimate(
            minLat: 45.0, maxLat: 45.05, minLon: 5.0, maxLon: 5.05,
            minZoom: 12, maxZoom: 13, source: .osmStandard
        )

        guard case .estimate(let estimate) = result else { return XCTFail("attendu .estimate, obtenu \(result)") }
        XCTAssertGreaterThan(estimate.tileCount, 0)
    }
}
