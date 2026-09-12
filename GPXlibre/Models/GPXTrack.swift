import Foundation
import CoreLocation

struct GPXTrack: Identifiable, Codable, Hashable {
    let id: UUID
    var name: String
    let fileName: String
    let importDate: Date
    let points: [GPXPoint]
    let waypoints: [GPXPoint]

    var pointCount: Int { points.count }

    var totalDistanceMeters: Double {
        guard points.count > 1 else { return 0 }
        var total: CLLocationDistance = 0
        for i in 1..<points.count {
            let a = CLLocation(latitude: points[i - 1].latitude, longitude: points[i - 1].longitude)
            let b = CLLocation(latitude: points[i].latitude, longitude: points[i].longitude)
            total += a.distance(from: b)
        }
        return total
    }

    var totalDistanceKm: Double { totalDistanceMeters / 1000 }

    var elevationGainMeters: Double {
        guard points.count > 1 else { return 0 }
        var gain: Double = 0
        for i in 1..<points.count {
            guard let e0 = points[i - 1].elevation, let e1 = points[i].elevation else { continue }
            let delta = e1 - e0
            if delta > 0 { gain += delta }
        }
        return gain
    }

    var boundingRegion: (center: CLLocationCoordinate2D, span: (latDelta: Double, lonDelta: Double))? {
        guard !points.isEmpty else { return nil }
        let lats = points.map(\.latitude)
        let lons = points.map(\.longitude)
        guard let minLat = lats.min(), let maxLat = lats.max(),
              let minLon = lons.min(), let maxLon = lons.max() else { return nil }
        let center = CLLocationCoordinate2D(latitude: (minLat + maxLat) / 2, longitude: (minLon + maxLon) / 2)
        let latDelta = max((maxLat - minLat) * 1.3, 0.01)
        let lonDelta = max((maxLon - minLon) * 1.3, 0.01)
        return (center, (latDelta, lonDelta))
    }

    /// Boucle détectée (spec "per-track-settings") : premier et dernier point à moins de
    /// 200 m — dans ce cas, le sens par défaut reste l'ordre du fichier (indiqué dans l'UI),
    /// jamais deviné autrement.
    var isLoop: Bool {
        guard let first = points.first, let last = points.last, points.count > 2 else { return false }
        return RoadbookAnalyzer.distanceMeters(first.coordinate, last.coordinate) < 200
    }

    /// Trace effective (spec "per-track-settings") : sens A→B/B→A + départ personnalisé,
    /// appliqués UNE fois ici — n'écrit JAMAIS le fichier GPX source, tout le reste du code
    /// (roadbook, projection, stats, rendu) continue de lire `points` normalement sans savoir
    /// qu'un réordonnancement a eu lieu.
    func reordered(using settings: TrackRideSettings) -> GPXTrack {
        guard settings.isReversed || settings.customStartPointIndex != nil else { return self }
        var reordered = settings.isReversed ? points.reversed().map { $0 } : points
        if let startIndex = settings.customStartPointIndex, reordered.indices.contains(startIndex), startIndex > 0 {
            reordered = Array(reordered[startIndex...] + reordered[..<startIndex])
        }
        return GPXTrack(id: id, name: name, fileName: fileName, importDate: importDate, points: reordered, waypoints: waypoints)
    }
}
