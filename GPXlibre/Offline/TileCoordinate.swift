import Foundation
import CoreLocation

struct TileCoordinate: Hashable {
    let z: Int
    let x: Int
    let y: Int
    /// Jamais partagée entre deux sources différentes dans le cache (voir TileSource).
    let source: TileSource

    init(z: Int, x: Int, y: Int, source: TileSource = .osmStandard) {
        self.z = z
        self.x = x
        self.y = y
        self.source = source
    }

    var path: String { "\(z)/\(x)/\(y)" }

    static func covering(latitude: Double, longitude: Double, zoom: Int, source: TileSource = .osmStandard) -> TileCoordinate {
        let n = pow(2.0, Double(zoom))
        let x = Int(((longitude + 180) / 360) * n)
        let latRad = latitude * .pi / 180
        let y = Int((1 - log(tan(latRad) + 1 / cos(latRad)) / .pi) / 2 * n)
        return TileCoordinate(z: zoom, x: max(0, min(Int(n) - 1, x)), y: max(0, min(Int(n) - 1, y)), source: source)
    }

    /// Boîte englobante lat/lon (degrés) d'un point élargi d'un rayon en mètres — utile pour
    /// couvrir un corridor de largeur donnée autour d'un point de la trace.
    static func boundingBox(around coordinate: CLLocationCoordinate2D, radiusMeters: Double) -> (minLat: Double, maxLat: Double, minLon: Double, maxLon: Double) {
        let metersPerDegreeLat = 111_320.0
        let metersPerDegreeLon = 111_320.0 * max(cos(coordinate.latitude * .pi / 180), 0.01)
        let dLat = radiusMeters / metersPerDegreeLat
        let dLon = radiusMeters / metersPerDegreeLon
        return (coordinate.latitude - dLat, coordinate.latitude + dLat, coordinate.longitude - dLon, coordinate.longitude + dLon)
    }

    /// Toutes les tuiles couvrant une boîte englobante lat/lon, à un niveau de zoom donné.
    static func tiles(minLat: Double, maxLat: Double, minLon: Double, maxLon: Double, zoom: Int, source: TileSource = .osmStandard) -> [TileCoordinate] {
        let topLeft = covering(latitude: maxLat, longitude: minLon, zoom: zoom, source: source)
        let bottomRight = covering(latitude: minLat, longitude: maxLon, zoom: zoom, source: source)
        var result: [TileCoordinate] = []
        guard topLeft.x <= bottomRight.x, topLeft.y <= bottomRight.y else { return result }
        for x in topLeft.x...bottomRight.x {
            for y in topLeft.y...bottomRight.y {
                result.append(TileCoordinate(z: zoom, x: x, y: y, source: source))
            }
        }
        return result
    }

    /// Compte O(1) (fix "region-picker-huge-bbox-crash") — À APPELER avant `tiles(...)` pour
    /// vérifier `OfflineConstants.regionTileCountHardCap` sans jamais matérialiser la liste
    /// complète : une zone "monde" au zoom 16 représente des milliards d'éléments, largement
    /// de quoi geler le thread principal si on la construit avant de la compter.
    static func tileCount(minLat: Double, maxLat: Double, minLon: Double, maxLon: Double, zoom: Int, source: TileSource = .osmStandard) -> Int {
        let topLeft = covering(latitude: maxLat, longitude: minLon, zoom: zoom, source: source)
        let bottomRight = covering(latitude: minLat, longitude: maxLon, zoom: zoom, source: source)
        guard topLeft.x <= bottomRight.x, topLeft.y <= bottomRight.y else { return 0 }
        return (bottomRight.x - topLeft.x + 1) * (bottomRight.y - topLeft.y + 1)
    }
}
