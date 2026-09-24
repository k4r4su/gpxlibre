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

    /// Tous les PASSAGES de la trace à moins de `maxDistanceMeters` de `coordinate`, dans l'ordre
    /// du trajet — un passage = une suite de segments consécutifs tous à portée, représentée par
    /// sa meilleure projection. Une boucle ou un aller-retour qui repasse au même carrefour en
    /// produit plusieurs ; une trace qui ne l'approche qu'une fois, un seul.
    static func passes(
        of coordinate: CLLocationCoordinate2D,
        onto points: [GPXPoint],
        cumulativeDistances: [Double],
        maxDistanceMeters: Double,
        minimumCumulativeDistanceMeters: Double = 0
    ) -> [Projection] {
        guard points.count > 1, points.count == cumulativeDistances.count else { return [] }

        var result: [Projection] = []
        var currentPassBest: Projection?

        for i in 0..<(points.count - 1) {
            guard cumulativeDistances[i + 1] >= minimumCumulativeDistanceMeters else { continue }
            let segmentLength = cumulativeDistances[i + 1] - cumulativeDistances[i]
            let minT = segmentLength > 0 ? max((minimumCumulativeDistanceMeters - cumulativeDistances[i]) / segmentLength, 0) : 0
            let (distance, t) = distanceFromPointToSegment(coordinate, points[i].coordinate, points[i + 1].coordinate, minT: minT)

            guard distance <= maxDistanceMeters else {
                if let best = currentPassBest { result.append(best) }
                currentPassBest = nil
                continue
            }
            let candidate = Projection(nearestSegmentIndex: i, distanceToTrackMeters: distance, cumulativeDistanceMeters: cumulativeDistances[i] + segmentLength * t)
            if distance < (currentPassBest?.distanceToTrackMeters ?? .greatestFiniteMagnitude) {
                currentPassBest = candidate
            }
        }
        if let best = currentPassBest { result.append(best) }
        return result
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

    /// Point de reprise de la trace le plus proche à VOL D'OISEAU de `coordinate` — parcourt
    /// TOUS les points de la trace, sans se limiter au "point suivant" dans l'ordre
    /// chronologique (spec "rejoin-nearest-by-air", it19, bug terrain : sortie de trace où le
    /// point suivant logique était à 15 km par la route alors qu'un autre point de la trace,
    /// plus loin dans son ordre — typiquement une boucle qui repasse près de la position
    /// actuelle — n'était qu'à 2 km à vol d'oiseau). Le routage vers le point choisi reste
    /// EXACTEMENT le mécanisme existant (réseau routier via DetourRoutingService, voir
    /// `RideSessionManager.requestResume`) — cette fonction ne fait QUE choisir la cible, elle
    /// ne route jamais elle-même.
    static func nearestPointByAirDistance(
        to coordinate: CLLocationCoordinate2D,
        in points: [GPXPoint],
        cumulativeDistances: [Double]
    ) -> (coordinate: CLLocationCoordinate2D, cumulativeDistanceMeters: Double)? {
        guard !points.isEmpty, points.count == cumulativeDistances.count else { return nil }

        var bestIndex = 0
        var bestDistance = Double.greatestFiniteMagnitude
        for (index, point) in points.enumerated() {
            let distance = RoadbookAnalyzer.distanceMeters(coordinate, point.coordinate)
            if distance < bestDistance {
                bestDistance = distance
                bestIndex = index
            }
        }
        return (points[bestIndex].coordinate, cumulativeDistances[bestIndex])
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
    /// via une projection locale équirectangulaire (précise pour des segments courts). `minT`
    /// restreint le segment à [minT, 1] — la distance étant convexe en `t`, borner l'optimum
    /// non contraint donne directement l'optimum contraint.
    private static func distanceFromPointToSegment(
        _ p: CLLocationCoordinate2D,
        _ a: CLLocationCoordinate2D,
        _ b: CLLocationCoordinate2D,
        minT: Double = 0
    ) -> (distance: Double, t: Double) {
        let metersPerDegreeLat = 111_320.0
        let metersPerDegreeLon = 111_320.0 * cos(a.latitude * .pi / 180)

        func toXY(_ c: CLLocationCoordinate2D) -> (Double, Double) {
            ((c.longitude - a.longitude) * metersPerDegreeLon, (c.latitude - a.latitude) * metersPerDegreeLat)
        }

        let (px, py) = toXY(p)
        let (bx, by) = toXY(b)
        let abLenSq = bx * bx + by * by
        let t = abLenSq > 0 ? max(min(max(minT, 0), 1), min(1, (px * bx + py * by) / abLenSq)) : 0
        let closestX = bx * t
        let closestY = by * t
        let dx = px - closestX
        let dy = py - closestY
        return (sqrt(dx * dx + dy * dy), t)
    }
}
