import Foundation
import CoreLocation

/// Analyse une trace GPX une seule fois au chargement pour produire les événements du roadbook
/// (changements de cap). Ne modifie jamais la trace elle-même.
///
/// Roadbook rebuilt from scratch (spec "roadbook-angle-buckets-replay", it14, Bloc 4) —
/// REMPLACE les deux anciens détecteurs séparés (`buildCheckpoints` : seuil ponctuel ±20 m ;
/// `buildInflectionPoints` : fenêtre glissante forward-only 150 m, un seul seuil 40°) par UN
/// SEUL algorithme, source unique pour la bannière latérale ET les épingles carte : mesure la
/// tangente sur une fenêtre AVANT/APRÈS chaque point (±40-80 m, configurable), classée en 5
/// paliers (segmentation type Waze/MUTCD). "Aujourd'hui aucun déclenchement réel en roulage"
/// (retour terrain) — fondations propres plutôt qu'un correctif de plus sur l'ancien système.
enum RoadbookAnalyzer {

    /// - Parameters:
    ///   - windowBeforeMeters/windowAfterMeters : ROADBOOK_WINDOW_BEFORE_M/AFTER_M — distance
    ///     sur laquelle le cap entrant/sortant de chaque point est mesuré.
    ///   - lightThresholdDegrees...uTurnThresholdDegrees : paliers croissants (light < marked
    ///     < hard < uTurn) — un angle sous `lightThresholdDegrees` ne produit AUCUN événement.
    /// - Parameter mapMatchedManeuvers : manœuvres de changement de direction RETENUES (déjà
    ///   filtrées route-aware, voir `ValhallaManeuverType.roadbookTier`) issues du map matching
    ///   Valhalla (spec "valhalla-map-matching-direction-change", it20 ; filtrage type, it24
    ///   point 1) — `[]` par défaut (comportement STRICTEMENT identique à avant it20, non-
    ///   régression). Fusionnées dans la MÊME liste que les événements géométriques ci-dessous
    ///   (invariant it14 "source unique pour épingles carte ET bannière latérale" : un seul
    ///   `[Checkpoint]`, jamais deux listes parallèles) — une manœuvre ignorée si elle tombe à
    ///   moins de `mergeMinDistanceMeters` d'un événement géométrique déjà détecté (pas de
    ///   doublon), sinon ajoutée avec le `tier`/la `direction` dérivés de
    ///   `ValhallaManeuverType.roadbookTier`/`roadbookDirection` (it24, point 2 — remplace
    ///   l'ancien `tier: .lightDirectionChange` fixe et la direction dérivée de l'angle
    ///   géométrique bruité au point).
    static func buildRoadbookEvents(
        for track: GPXTrack,
        windowBeforeMeters: Double,
        windowAfterMeters: Double,
        lightThresholdDegrees: Double,
        markedThresholdDegrees: Double,
        hardThresholdDegrees: Double,
        uTurnThresholdDegrees: Double,
        mergeMinDistanceMeters: Double,
        mapMatchedManeuvers: [MapMatchedManeuver] = []
    ) -> [Checkpoint] {
        let points = track.points
        guard points.count > 2, windowBeforeMeters > 0, windowAfterMeters > 0 else { return [] }

        // Cap par segment (bearing ET longueur), même patron que buildInflectionPoints (it12) —
        // généralisé ici aux DEUX sens (avant ET après chaque point, pas seulement en avant).
        var segmentBearings: [Double] = []
        var segmentLengths: [Double] = []
        segmentBearings.reserveCapacity(points.count - 1)
        segmentLengths.reserveCapacity(points.count - 1)
        for i in 0..<(points.count - 1) {
            segmentBearings.append(bearing(from: points[i].coordinate, to: points[i + 1].coordinate))
            segmentLengths.append(distanceMeters(points[i].coordinate, points[i + 1].coordinate))
        }

        var raw: [(coordinate: CLLocationCoordinate2D, angle: Double, direction: TurnDirection, tier: RoadbookTier, pointIndex: Int)] = []

        for i in 1..<(points.count - 1) {
            guard let windowed = windowedTurn(
                at: i,
                segmentBearings: segmentBearings,
                segmentLengths: segmentLengths,
                windowBeforeMeters: windowBeforeMeters,
                windowAfterMeters: windowAfterMeters
            ) else { continue }
            guard windowed.absAngle >= lightThresholdDegrees else { continue }

            let tier: RoadbookTier
            if windowed.absAngle >= uTurnThresholdDegrees {
                tier = .uTurn
            } else if windowed.absAngle >= hardThresholdDegrees {
                tier = .hard
            } else if windowed.absAngle >= markedThresholdDegrees {
                tier = .marked
            } else {
                tier = .light
            }

            let direction: TurnDirection = tier == .uTurn ? .uTurn : (windowed.signedAngle > 0 ? .right : .left)

            raw.append((points[i].coordinate, windowed.absAngle, direction, tier, i))
        }

        let geometricEvents = mergeNearby(raw, minDistanceMeters: mergeMinDistanceMeters)
        guard !mapMatchedManeuvers.isEmpty else { return geometricEvents }

        return mergingMapMatchedDirectionChanges(
            mapMatchedManeuvers,
            into: geometricEvents,
            points: points,
            segmentBearings: segmentBearings,
            segmentLengths: segmentLengths,
            windowBeforeMeters: windowBeforeMeters,
            windowAfterMeters: windowAfterMeters,
            mergeMinDistanceMeters: mergeMinDistanceMeters
        )
    }

    /// Fusionne les points de map matching dans la liste géométrique déjà produite, DANS
    /// L'ORDRE de progression le long de la trace (`sourcePointIndex`), quelle que soit la
    /// source — la bannière latérale/la liste roadbook lisent cette liste séquentiellement, un
    /// événement mal ordonné y apparaîtrait au mauvais moment du trajet.
    private static func mergingMapMatchedDirectionChanges(
        _ matchedManeuvers: [MapMatchedManeuver],
        into geometricEvents: [Checkpoint],
        points: [GPXPoint],
        segmentBearings: [Double],
        segmentLengths: [Double],
        windowBeforeMeters: Double,
        windowAfterMeters: Double,
        mergeMinDistanceMeters: Double
    ) -> [Checkpoint] {
        var combined = geometricEvents

        for maneuver in matchedManeuvers {
            // Filtrage route-aware déjà appliqué en amont (voir `ValhallaMapMatchingService.
            // intermediateManeuvers`) — `roadbookTier` ne peut plus être `nil` ici, mais on reste
            // défensif plutôt que de force-unwrap une donnée qui a transité par un cache disque
            // (voir `RoadbookMapMatchCache`, format qui peut évoluer).
            guard let tier = maneuver.type.roadbookTier else { continue }
            guard !combined.contains(where: { distanceMeters($0.coordinate, maneuver.coordinate) < mergeMinDistanceMeters }) else { continue }
            guard let pointIndex = nearestPointIndex(to: maneuver.coordinate, in: points) else { continue }

            let windowed = windowedTurn(
                at: pointIndex,
                segmentBearings: segmentBearings,
                segmentLengths: segmentLengths,
                windowBeforeMeters: windowBeforeMeters,
                windowAfterMeters: windowAfterMeters
            )

            combined.append(Checkpoint(
                coordinate: points[pointIndex].coordinate,
                turnAngleDegrees: windowed?.absAngle ?? 0,
                direction: maneuver.type.roadbookDirection,
                tier: tier,
                sequenceIndex: 0, // renuméroté ci-dessous une fois l'ordre final connu
                sourcePointIndex: pointIndex,
                roundaboutExitCount: maneuver.roundaboutExitCount
            ))
        }

        return combined
            .sorted { $0.sourcePointIndex < $1.sourcePointIndex }
            .enumerated()
            .map { index, checkpoint in
                Checkpoint(
                    coordinate: checkpoint.coordinate,
                    turnAngleDegrees: checkpoint.turnAngleDegrees,
                    direction: checkpoint.direction,
                    tier: checkpoint.tier,
                    sequenceIndex: index + 1,
                    sourcePointIndex: checkpoint.sourcePointIndex,
                    roundaboutExitCount: checkpoint.roundaboutExitCount
                )
            }
    }

    /// Angle de virage sur fenêtre AVANT/APRÈS le point `i` (extrait de `buildRoadbookEvents`
    /// pour être réutilisé par la fusion map matching ci-dessus, SANS dupliquer la logique de
    /// fenêtrage) — somme pas-à-pas des deltas de cap segment par segment (pas une simple
    /// différence corde à corde, voir commentaire historique ci-dessous).
    private static func windowedTurn(
        at i: Int,
        segmentBearings: [Double],
        segmentLengths: [Double],
        windowBeforeMeters: Double,
        windowAfterMeters: Double
    ) -> (absAngle: Double, signedAngle: Double)? {
        guard i > 0, i < segmentBearings.count else { return nil }

        // Segment le plus ANCIEN considéré : recule depuis i-1 (le segment qui MÈNE à `i`,
        // toujours inclus) tant que windowBeforeMeters n'est pas couvert.
        var startSeg = i - 1
        var distBefore: Double = 0
        while startSeg > 0, distBefore < windowBeforeMeters {
            distBefore += segmentLengths[startSeg - 1]
            startSeg -= 1
        }
        // Segment le plus AVANCÉ considéré : avance depuis i (le segment qui PART de `i`,
        // toujours inclus) tant que windowAfterMeters n'est pas couvert.
        var endSeg = i
        var distAfter: Double = 0
        while endSeg < segmentBearings.count - 1, distAfter < windowAfterMeters {
            distAfter += segmentLengths[endSeg]
            endSeg += 1
        }
        guard endSeg > startSeg else { return nil }

        // Somme des deltas segment à segment de startSeg à endSeg (PAS une simple différence
        // d'angle entre les deux bornes — un virage > 180° sur la fenêtre serait alors mal
        // reconstruit ; la somme pas-à-pas, chacun normalisé dans (-180,180], reste correcte
        // même au-delà).
        var totalTurn: Double = 0
        for m in startSeg..<endSeg {
            totalTurn += signedAngleDifference(from: segmentBearings[m], to: segmentBearings[m + 1])
        }
        return (abs(totalTurn), totalTurn)
    }

    /// Point de la trace le plus proche à VOL D'OISEAU (parcours linéaire, trace de taille
    /// raisonnable pour un roadbook — pas besoin d'index spatial) — retrouve l'index d'origine
    /// (`sourcePointIndex`) d'une coordonnée de map matching, qui ne coïncide pas forcément
    /// EXACTEMENT avec un point de `points` (coordonnées Valhalla arrondies au 1e6).
    private static func nearestPointIndex(to coordinate: CLLocationCoordinate2D, in points: [GPXPoint]) -> Int? {
        guard !points.isEmpty else { return nil }
        var bestIndex = 0
        var bestDistance = Double.greatestFiniteMagnitude
        for (index, point) in points.enumerated() {
            let distance = distanceMeters(coordinate, point.coordinate)
            if distance < bestDistance {
                bestDistance = distance
                bestIndex = index
            }
        }
        return bestIndex
    }

    /// Fusionne les points de virage trop rapprochés (même épingle détectée sur plusieurs
    /// points consécutifs de la trace, ou piste qui zigzague) en gardant celui à l'angle le
    /// plus marqué — le total affiché (X/Y) reflète donc toujours la liste FUSIONNÉE, jamais
    /// le nombre brut de candidats détectés.
    private static func mergeNearby(
        _ raw: [(coordinate: CLLocationCoordinate2D, angle: Double, direction: TurnDirection, tier: RoadbookTier, pointIndex: Int)],
        minDistanceMeters: Double
    ) -> [Checkpoint] {
        var merged: [(coordinate: CLLocationCoordinate2D, angle: Double, direction: TurnDirection, tier: RoadbookTier, pointIndex: Int)] = []

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
            Checkpoint(coordinate: item.coordinate, turnAngleDegrees: item.angle, direction: item.direction, tier: item.tier, sequenceIndex: index + 1, sourcePointIndex: item.pointIndex)
        }
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
