import Foundation

struct PrecacheEstimate {
    let tiles: [TileCoordinate]
    var tileCount: Int { tiles.count }
    var estimatedBytes: Int64 { Int64(tiles.count) * OfflineConstants.averageTileSizeBytes }
    var estimatedSeconds: Double { Double(estimatedBytes) / OfflineConstants.assumedDownloadThroughputBytesPerSecond }

    var formattedSize: String {
        ByteCountFormatter.string(fromByteCount: estimatedBytes, countStyle: .file)
    }

    var formattedDuration: String {
        let minutes = Int((estimatedSeconds / 60).rounded(.up))
        return minutes <= 1 ? String(localized: "< 1 min", bundle: .appLanguage) : String(localized: "~\(minutes) min", bundle: .appLanguage)
    }
}

/// Calcule le corridor de tuiles (±1 km, zoom 10-15) autour d'une trace, échantillonnée
/// pour rester rapide même sur une trace de 250 km.
enum CorridorPrecacheEstimator {
    /// `source` = thème carte actif au moment du pré-cache (#10) — le corridor DOIT suivre
    /// le thème actif, y compris Relief (OpenTopoMap), pas seulement OSM standard.
    static func estimate(for track: GPXTrack, source: TileSource = .osmStandard) -> PrecacheEstimate {
        var tileSet = Set<TileCoordinate>()
        let points = sampledPoints(of: track)
        let maxZoom = min(OfflineConstants.corridorMaxZoom, source.maxZoomLevel)

        for point in points {
            let box = TileCoordinate.boundingBox(around: point.coordinate, radiusMeters: OfflineConstants.corridorHalfWidthMeters)
            for zoom in OfflineConstants.corridorMinZoom...maxZoom {
                let tiles = TileCoordinate.tiles(minLat: box.minLat, maxLat: box.maxLat, minLon: box.minLon, maxLon: box.maxLon, zoom: zoom, source: source)
                tileSet.formUnion(tiles)
            }
        }
        return PrecacheEstimate(tiles: Array(tileSet))
    }

    private static func sampledPoints(of track: GPXTrack) -> [GPXPoint] {
        guard track.points.count > 1 else { return track.points }
        var result: [GPXPoint] = [track.points[0]]
        var accumulated: Double = 0
        for i in 1..<track.points.count {
            accumulated += RoadbookAnalyzer.distanceMeters(track.points[i - 1].coordinate, track.points[i].coordinate)
            if accumulated >= OfflineConstants.corridorSampleStepMeters {
                result.append(track.points[i])
                accumulated = 0
            }
        }
        if let last = track.points.last, result.last?.id != last.id {
            result.append(last)
        }
        return result
    }
}
