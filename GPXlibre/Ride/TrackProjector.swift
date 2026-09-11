import Foundation
import CoreLocation

/// Projette une position GPS sur la trace (distance perpendiculaire + position curviligne),
/// et retrouve un point de ralliement plus loin sur la trace. Ne modifie jamais la trace :
/// sert uniquement à mesurer l'écart et proposer un point de retour.
enum TrackProjector {

    struct Projection {
        let nearestSegmentIndex: Int
        let distanceToTrackMeters: Double
        let cumulativeDistanceMeters: Double
    }

    /// Distances cumulées depuis le départ, un élément par point de la trace.
    static func cumulativeDistances(for points: [GPXPoint]) -> [Double] {
        guard !points.isEmpty else { return [] }
        var result = [Double](repeating: 0, count: points.count)
        for i in 1..<points.count {
            result[i] = result[i - 1] + RoadbookAnalyzer.distanceMeters(points[i - 1].coordinate, points[i].coordinate)
        }
        return result
    }

    static func project(
        _ coordinate: CLLocationCoordinate2D,
        onto points: [GPXPoint],
        cumulativeDistances: [Double]
    ) -> Projection? {
        guard points.count > 1, points.count == cumulativeDistances.count else { return nil }

        var bestIndex = 0
        var bestDistance = Double.greatestFiniteMagnitude
        var bestCumulative: Double = 0

        for i in 0..<(points.count - 1) {
            let a = points[i].coordinate
            let b = points[i + 1].coordinate
            let (distance, t) = distanceFromPointToSegment(coordinate, a, b)
            if distance < bestDistance {
                bestDistance = distance
                bestIndex = i
                let segmentLength = cumulativeDistances[i + 1] - cumulativeDistances[i]
                bestCumulative = cumulativeDistances[i] + segmentLength * t
            }
        }

        return Projection(nearestSegmentIndex: bestIndex, distanceToTrackMeters: bestDistance, cumulativeDistanceMeters: bestCumulative)
    }

    /// Premier point de la trace situé au-delà de `afterCumulativeDistance` dans la fenêtre
    /// [min, max] donnée (essais par pas de `stepMeters`), utilisé comme candidat de ralliement
    /// après une zone bloquée.
    static func rejoinCandidates(
        in points: [GPXPoint],
        cumulativeDistances: [Double],
        afterCumulativeDistance: Double,
        minAhead: Double,
        maxAhead: Double,
        step: Double
    ) -> [CLLocationCoordinate2D] {
        guard !points.isEmpty else { return [] }
        var candidates: [CLLocationCoordinate2D] = []
        var target = afterCumulativeDistance + minAhead
        let ceiling = afterCumulativeDistance + maxAhead

        while target <= ceiling {
            if let coordinate = coordinate(in: points, cumulativeDistances: cumulativeDistances, atCumulativeDistance: target) {
                candidates.append(coordinate)
            }
            target += step
        }
        return candidates
    }

    static func coordinate(
        in points: [GPXPoint],
        cumulativeDistances: [Double],
        atCumulativeDistance target: Double
    ) -> CLLocationCoordinate2D? {
        guard let last = cumulativeDistances.last else { return nil }
        if target >= last { return points.last?.coordinate }

        guard let index = cumulativeDistances.firstIndex(where: { $0 >= target }) else { return points.last?.coordinate }
        return points[index].coordinate
    }

    /// Distance (m) point → segment, et position relative `t` (0 = début du segment, 1 = fin),
    /// via une projection locale équirectangulaire (précise pour des segments courts).
    private static func distanceFromPointToSegment(
        _ p: CLLocationCoordinate2D,
        _ a: CLLocationCoordinate2D,
        _ b: CLLocationCoordinate2D
    ) -> (distance: Double, t: Double) {
        let metersPerDegreeLat = 111_320.0
        let metersPerDegreeLon = 111_320.0 * cos(a.latitude * .pi / 180)

        func toXY(_ c: CLLocationCoordinate2D) -> (Double, Double) {
            ((c.longitude - a.longitude) * metersPerDegreeLon, (c.latitude - a.latitude) * metersPerDegreeLat)
        }

        let (px, py) = toXY(p)
        let (bx, by) = toXY(b)
        let abLenSq = bx * bx + by * by
        let t = abLenSq > 0 ? max(0, min(1, (px * bx + py * by) / abLenSq)) : 0
        let closestX = bx * t
        let closestY = by * t
        let dx = px - closestX
        let dy = py - closestY
        return (sqrt(dx * dx + dy * dy), t)
    }
}
