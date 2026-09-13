import Foundation
import CoreLocation

/// Analyse une trace GPX une seule fois au chargement pour produire les checkpoints
/// du roadbook (changements de cap). Ne modifie jamais la trace elle-même.
enum RoadbookAnalyzer {

    static func buildCheckpoints(for track: GPXTrack, turnThresholdDegrees: Double, turnMergeMinDistanceMeters: Double = RideConstants.turnMergeMinDistanceMetersDefault) -> [Checkpoint] {
        let points = track.points
        guard points.count > 2 else { return [] }

        var raw: [(coordinate: CLLocationCoordinate2D, angle: Double, direction: TurnDirection, pointIndex: Int)] = []

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

            raw.append((points[i].coordinate, absDelta, direction, i))
        }

        return mergeNearby(raw, minDistanceMeters: turnMergeMinDistanceMeters)
    }

    /// Inflexions pour la bannière latérale (spec "lateral-cap-banner-countdown", it12) —
    /// DISTINCT de `buildCheckpoints` ci-dessus : au lieu d'un seuil ponctuel (angle
    /// avant/après un point, lissé sur ±`bearingLookaroundMeters`), on somme le cap SIGNÉ de
    /// segment en segment sur une fenêtre glissante de `windowMeters` à partir de chaque point.
    /// Un virage "dur" progressif (aucun point isolé au-delà du seuil ponctuel, mais qui tourne
    /// net sur 100-150 m) déclenche donc ici alors qu'il ne générerait AUCUN checkpoint — c'est
    /// précisément le cas que `buildCheckpoints` ne couvre pas. Une vraie "split" nette continue
    /// de déclencher aussi (tout l'angle tombe dans un petit sous-segment de la fenêtre).
    /// N'affecte JAMAIS `checkpoints`/le roadbook (flash/voix/haptique) : liste strictement
    /// séparée, consommée uniquement par la bannière.
    static func buildInflectionPoints(
        for track: GPXTrack,
        thresholdDegrees: Double,
        windowMeters: Double,
        mergeMinDistanceMeters: Double
    ) -> [Checkpoint] {
        let points = track.points
        guard points.count > 2, windowMeters > 0 else { return [] }

        var segmentBearings: [Double] = []
        segmentBearings.reserveCapacity(points.count - 1)
        for i in 0..<(points.count - 1) {
            segmentBearings.append(bearing(from: points[i].coordinate, to: points[i + 1].coordinate))
        }

        var raw: [(coordinate: CLLocationCoordinate2D, angle: Double, direction: TurnDirection, pointIndex: Int)] = []

        for i in 0..<segmentBearings.count {
            var cumulativeDistance: Double = 0
            var cumulativeTurn: Double = 0
            var j = i
            while j < segmentBearings.count, cumulativeDistance < windowMeters {
                if j > i {
                    cumulativeTurn += signedAngleDifference(from: segmentBearings[j - 1], to: segmentBearings[j])
                }
                cumulativeDistance += distanceMeters(points[j].coordinate, points[j + 1].coordinate)
                j += 1
            }

            let absTurn = abs(cumulativeTurn)
            guard absTurn >= thresholdDegrees else { continue }

            let direction: TurnDirection
            if absTurn >= RideConstants.uTurnThresholdDegrees {
                direction = .uTurn
            } else if cumulativeTurn > 0 {
                direction = .right
            } else {
                direction = .left
            }

            raw.append((points[i].coordinate, absTurn, direction, i))
        }

        return mergeNearby(raw, minDistanceMeters: mergeMinDistanceMeters)
    }

    /// Fusionne les points de virage trop rapprochés (même épingle détectée sur plusieurs
    /// points consécutifs de la trace, ou piste qui zigzague) en gardant celui à l'angle le
    /// plus marqué — le total affiché (X/Y) reflète donc toujours la liste FUSIONNÉE, jamais
    /// le nombre brut de candidats détectés.
    private static func mergeNearby(
        _ raw: [(coordinate: CLLocationCoordinate2D, angle: Double, direction: TurnDirection, pointIndex: Int)],
        minDistanceMeters: Double
    ) -> [Checkpoint] {
        var merged: [(coordinate: CLLocationCoordinate2D, angle: Double, direction: TurnDirection, pointIndex: Int)] = []

        for candidate in raw {
            if let lastIndex = merged.indices.last,
               distanceMeters(merged[lastIndex].coordinate, candidate.coordinate) < minDistanceMeters {
                if candidate.angle > merged[lastIndex].angle {
                    merged[lastIndex] = candidate
                }
            } else {
                merged.append(candidate)
            }
        }

        return merged.enumerated().map { index, item in
            Checkpoint(coordinate: item.coordinate, turnAngleDegrees: item.angle, direction: item.direction, sequenceIndex: index + 1, sourcePointIndex: item.pointIndex)
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
