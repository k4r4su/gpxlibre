import Foundation

enum OfflineTileEstimateResult {
    case empty
    case tooLarge
    case estimate(PrecacheEstimate)
}

/// Factorise le patron "compter avant d'énumérer" (fix "region-picker-huge-bbox-crash", it16) —
/// extrait de `RegionDownloadView.updateEstimate()` pour être réutilisé tel quel par
/// `PlaceRegionPickerView` (spec "region-download-by-place", it21) : une bbox "Pays" peut être
/// tout aussi grande qu'un pincement manuel jusqu'au zoom monde, même protection nécessaire.
enum OfflineTileEstimator {
    static func estimate(
        minLat: Double, maxLat: Double, minLon: Double, maxLon: Double,
        minZoom: Int, maxZoom: Int, source: TileSource
    ) -> OfflineTileEstimateResult {
        guard maxZoom >= minZoom else { return .empty }

        var projectedTileCount = 0
        for zoom in minZoom...maxZoom {
            projectedTileCount += TileCoordinate.tileCount(minLat: minLat, maxLat: maxLat, minLon: minLon, maxLon: maxLon, zoom: zoom, source: source)
            if projectedTileCount > OfflineConstants.regionTileCountHardCap {
                return .tooLarge
            }
        }

        var tileSet = Set<TileCoordinate>()
        for zoom in minZoom...maxZoom {
            let tiles = TileCoordinate.tiles(minLat: minLat, maxLat: maxLat, minLon: minLon, maxLon: maxLon, zoom: zoom, source: source)
            tileSet.formUnion(tiles)
        }
        return .estimate(PrecacheEstimate(tiles: Array(tileSet)))
    }
}
