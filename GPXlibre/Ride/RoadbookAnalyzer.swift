import Foundation
import CoreLocation

/// Analyse une trace GPX une seule fois au chargement pour produire les checkpoints
/// du roadbook (changements de cap). Ne modifie jamais la trace elle-même.
enum RoadbookAnalyzer {

    static func buildCheckpoints(for track: GPXTrack, turnThresholdDegrees: Double) -> [Checkpoint] {
        let points = track.points
        guard points.count > 2 else { return [] }

        var raw: [(coordinate: CLLocationCoordinate2D, angle: Double, direction: TurnDirection)] = []

        for i in 1..<(points.count - 1) {
            guard let beforeCoord = coordinate(in: points, aroundIndex: i, stepBack: true),
                  let afterCoord = coordinate(in: points, aroundIndex: i, stepBack: false) else { continue }

            let incomingBearing = bearing(from: beforeCoord, to: points[i].coordinate)
            let outgoingBearing = bearing(from: points[i].coordinate, to: afterCoord)
            let delta = signedAngleDifference(from: incomingBearing, to: outgoingBearing)
            let absDelta = abs(delta)

            guard absDelta >= turnThresholdDegrees else { continue }

            let direction: TurnDirection
            if absDelta >= RideConstants.uTurnThresholdDegrees {
                direction = .uTurn
            } else if delta > 0 {
                direction = .right
            } else {
                direction = .left
            }

            raw.append((points[i].coordinate, absDelta, direction))
        }

        return mergeNearby(raw)
    }

    /// Fusionne les points de virage trop rapprochés (même épingle détectée sur plusieurs
    /// points consécutifs de la trace) en gardant celui à l'angle le plus marqué.
    private static func mergeNearby(
        _ raw: [(coordinate: CLLocationCoordinate2D, angle: Double, direction: TurnDirection)]
    ) -> [Checkpoint] {
        var merged: [(coordinate: CLLocationCoordinate2D, angle: Double, direction: TurnDirection)] = []

        for candidate in raw {
            if let lastIndex = merged.indices.last,
               distanceMeters(merged[lastIndex].coordinate, candidate.coordinate) < RideConstants.checkpointPassedRadiusMeters {
                if candidate.angle > merged[lastIndex].angle {
                    merged[lastIndex] = candidate
                }
            } else {
                merged.append(candidate)
            }
        }

        return merged.enumerated().map { index, item in
            Checkpoint(coordinate: item.coordinate, turnAngleDegrees: item.angle, direction: item.direction, sequenceIndex: index + 1)
        }
    }

    /// Point situé à ~`RideConstants.bearingLookaroundMeters` avant/après `aroundIndex`,
    /// pour lisser le calcul de cap et éviter le bruit des points GPX rapprochés.
    private static func coordinate(in points: [GPXPoint], aroundIndex: Int, stepBack: Bool) -> CLLocationCoordinate2D? {
        let origin = points[aroundIndex].coordinate
        var cumulative: Double = 0
        var i = aroundIndex

        while stepBack ? i > 0 : i < points.count - 1 {
            let next = stepBack ? i - 1 : i + 1
            cumulative += distanceMeters(points[i].coordinate, points[next].coordinate)
            i = next
            if cumulative >= RideConstants.bearingLookaroundMeters {
                return points[i].coordinate
            }
        }

        let fallback = points[i].coordinate
        return distanceMeters(origin, fallback) > 0 ? fallback : nil
    }

    static func distanceMeters(_ a: CLLocationCoordinate2D, _ b: CLLocationCoordinate2D) -> Double {
        CLLocation(latitude: a.latitude, longitude: a.longitude)
            .distance(from: CLLocation(latitude: b.latitude, longitude: b.longitude))
    }

    static func bearing(from: CLLocationCoordinate2D, to: CLLocationCoordinate2D) -> Double {
        let lat1 = from.latitude * .pi / 180
        let lat2 = to.latitude * .pi / 180
        let deltaLon = (to.longitude - from.longitude) * .pi / 180

        let y = sin(deltaLon) * cos(lat2)
        let x = cos(lat1) * sin(lat2) - sin(lat1) * cos(lat2) * cos(deltaLon)
        let radians = atan2(y, x)
        return (radians * 180 / .pi).truncatingRemainder(dividingBy: 360)
    }

    /// Différence signée entre deux caps, normalisée dans (-180, 180].
    /// Positif = virage à droite, négatif = virage à gauche.
    static func signedAngleDifference(from: Double, to: Double) -> Double {
        var diff = (to - from).truncatingRemainder(dividingBy: 360)
        if diff > 180 { diff -= 360 }
        if diff < -180 { diff += 360 }
        return diff
    }
}
