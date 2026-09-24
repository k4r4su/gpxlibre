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
    ///   - lightThresholdDegrees...veryHardThresholdDegrees : paliers croissants (light < marked
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
        veryHardThresholdDegrees: Double,
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
        let cumulativeDistances = TrackProjector.cumulativeDistances(for: points)

        for i in 1..<(points.count - 1) {
            guard let windowed = windowedTurn(
                at: i,
                segmentBearings: segmentBearings,
                segmentLengths: segmentLengths,
                windowBeforeMeters: windowBeforeMeters,
                windowAfterMeters: windowAfterMeters
            ) else { continue }
            guard windowed.absAngle >= lightThresholdDegrees else { continue }

            // Fix "roadbook-no-false-uturn" (it26 point 2) : le demi-tour n'est plus un palier
            // d'angle (≥ 135° avant, ce qui classait toute épingle en demi-tour) — il faut que la
            // trace reparte réellement sur SON PROPRE tracé. Au départ/à l'arrivée, c'est une
            // manœuvre de stationnement : ignorée.
            let reversesOnSamePath = windowed.absAngle >= NavigationConstants.roadbookUTurnMinDegrees
                && returnsOnSamePath(at: i, points: points, cumulativeDistances: cumulativeDistances, probeMeters: min(windowBeforeMeters, windowAfterMeters))
            if reversesOnSamePath, isNearTrackEndpoint(cumulativeDistances[i], cumulativeDistances: cumulativeDistances) { continue }

            let tier: RoadbookTier
            if reversesOnSamePath {
                tier = .uTurn
            } else if windowed.absAngle >= veryHardThresholdDegrees {
                tier = .veryHard
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

        let geometricEvents = mergeNearby(raw, minDistanceMeters: mergeMinDistanceMeters, cumulativeDistances: cumulativeDistances)
        guard !mapMatchedManeuvers.isEmpty else { return geometricEvents }

        return mergingMapMatchedDirectionChanges(
            mapMatchedManeuvers,
            into: geometricEvents,
            points: points,
            cumulativeDistances: cumulativeDistances,
            segmentBearings: segmentBearings,
            segmentLengths: segmentLengths,
            windowBeforeMeters: windowBeforeMeters,
            windowAfterMeters: windowAfterMeters,
            mergeMinDistanceMeters: mergeMinDistanceMeters
        )
    }

    /// Fusionne les points de map matching dans la liste géométrique déjà produite, DANS
    /// L'ORDRE de progression le long de la trace (distance cumulée exacte), quelle que soit la
    /// source — la bannière latérale/la liste roadbook lisent cette liste séquentiellement, un
    /// événement mal ordonné y apparaîtrait au mauvais moment du trajet.
    ///
    /// Fix "roadbook-maneuver-position-from-route" (it26 point 1, retour terrain : "certains
    /// changements de direction sont annoncés avec un décalage par rapport au vrai carrefour").
    /// `maneuver.coordinate` est déjà le VRAI carrefour (`shape[begin_shape_index]` de la
    /// géométrie recalée par Valhalla, voir `ValhallaMapMatchingService`) — la précision était
    /// perdue ICI : l'ancien `nearestPointIndex` le remplaçait par le point GPX le plus proche à
    /// vol d'oiseau (coordonnée ET distance cumulée), soit un décalage jusqu'à l'espacement des
    /// points GPX (15 m en préset "précis", 120 m en "ultra léger", davantage sur une trace
    /// planifiée peu dense). Désormais projeté sur son segment de trace (`TrackProjector.project`,
    /// distance cumulée INTERPOLÉE) — la trace GPX reste la référence de progression (Trace
    /// sacrée), seule la POSITION du virage vient de la route réelle.
    ///
    /// Choix du PASSAGE de trace : voir `placement(of:...)` — une trace qui repasse près d'un
    /// carrefour (boucle, aller-retour) ne fait plus retomber une manœuvre tardive sur le premier
    /// passage (l'ancienne recherche globale les y plaçait toutes, puis la seconde disparaissait
    /// comme "doublon").
    private static func mergingMapMatchedDirectionChanges(
        _ matchedManeuvers: [MapMatchedManeuver],
        into geometricEvents: [Checkpoint],
        points: [GPXPoint],
        cumulativeDistances: [Double],
        segmentBearings: [Double],
        segmentLengths: [Double],
        windowBeforeMeters: Double,
        windowAfterMeters: Double,
        mergeMinDistanceMeters: Double
    ) -> [Checkpoint] {
        var combined = geometricEvents
        var previousMatchedCumulative: Double?

        for maneuver in matchedManeuvers {
            // Filtrage route-aware déjà appliqué en amont (voir `ValhallaMapMatchingService.
            // intermediateManeuvers`) — `roadbookTier` ne peut plus être `nil` ici, mais on reste
            // défensif plutôt que de force-unwrap une donnée qui a transité par un cache disque
            // (voir `RoadbookMapMatchCache`, format qui peut évoluer).
            guard var tier = maneuver.type.roadbookTier else { continue }
            guard let projection = placement(
                of: maneuver,
                points: points,
                cumulativeDistances: cumulativeDistances,
                previousMatchedCumulative: previousMatchedCumulative,
                mergeMinDistanceMeters: mergeMinDistanceMeters
            ) else { continue }
            previousMatchedCumulative = projection.cumulativeDistanceMeters

            // Doublon mesuré LE LONG DE LA TRACE (plus à vol d'oiseau) : sur un aller-retour, le
            // même carrefour repassé au retour n'est pas un doublon de l'aller.
            let exactCumulative = projection.cumulativeDistanceMeters
            guard !combined.contains(where: { abs(($0.cumulativeDistanceMeters(using: cumulativeDistances) ?? .infinity) - exactCumulative) < mergeMinDistanceMeters }) else { continue }

            // Fix "roadbook-no-false-uturn" (it26 point 2) : un demi-tour Valhalla au départ/à
            // l'arrivée est une manœuvre de stationnement (le seul du cache réel du propriétaire
            // était à 20 m du départ) — ignoré. Ailleurs, demi-tour seulement si la rue d'après
            // est celle d'avant ; sinon virage très serré, du côté indiqué par Valhalla.
            var direction = maneuver.type.roadbookDirection
            if tier == .uTurn {
                guard !isNearTrackEndpoint(exactCumulative, cumulativeDistances: cumulativeDistances) else { continue }
                if !maneuver.isSameRoadUTurn {
                    tier = .veryHard
                    direction = maneuver.type == .uturnLeft ? .left : .right
                }
            }

            // Point GPX le plus proche SUR LE SEGMENT projeté — ne sert plus qu'au cap sortant
            // (`RoadbookExtractor`) et à l'angle affiché, jamais à la position/distance.
            let segmentStart = projection.nearestSegmentIndex
            let segmentEnd = min(segmentStart + 1, points.count - 1)
            let pointIndex = exactCumulative - cumulativeDistances[segmentStart] <= cumulativeDistances[segmentEnd] - exactCumulative
                ? segmentStart
                : segmentEnd

            let windowed = windowedTurn(
                at: pointIndex,
                segmentBearings: segmentBearings,
                segmentLengths: segmentLengths,
                windowBeforeMeters: windowBeforeMeters,
                windowAfterMeters: windowAfterMeters
            )

            combined.append(Checkpoint(
                coordinate: maneuver.coordinate,
                turnAngleDegrees: windowed?.absAngle ?? 0,
                direction: direction,
                tier: tier,
                sequenceIndex: 0, // renuméroté ci-dessous une fois l'ordre final connu
                sourcePointIndex: pointIndex,
                roundaboutExitCount: maneuver.roundaboutExitCount,
                trackCumulativeDistanceMeters: exactCumulative
            ))
        }

        return combined
            .sorted { ($0.cumulativeDistanceMeters(using: cumulativeDistances) ?? 0) < ($1.cumulativeDistanceMeters(using: cumulativeDistances) ?? 0) }
            .enumerated()
            .map { index, checkpoint in
                Checkpoint(
                    coordinate: checkpoint.coordinate,
                    turnAngleDegrees: checkpoint.turnAngleDegrees,
                    direction: checkpoint.direction,
                    tier: checkpoint.tier,
                    sequenceIndex: index + 1,
                    sourcePointIndex: checkpoint.sourcePointIndex,
                    roundaboutExitCount: checkpoint.roundaboutExitCount,
                    trackCumulativeDistanceMeters: checkpoint.trackCumulativeDistanceMeters
                )
            }
    }

    /// Position d'une manœuvre Valhalla sur la trace : parmi les PASSAGES de la trace à moins de
    /// `roadbookMapMatchMaxOffTrackMeters` du carrefour (aucun = carrefour hors du parcours,
    /// ignoré), celui qui correspond à la progression de la manœuvre le long de la route recalée
    /// (`routeProgressFraction` × longueur de trace) — la géométrie seule ne peut pas départager
    /// deux passages au même carrefour (boucle qui le traverse tout droit puis y tourne plus
    /// tard, aller-retour par la même route).
    ///
    /// Repli sans cette progression (fixture de test) : le premier passage plausible AU-DELÀ de
    /// la manœuvre précédente (ordre du trajet), en sautant celui qui retomberait sur elle
    /// (doublon) si un passage ultérieur est aussi proche du carrefour
    /// (`roadbookMapMatchRepassToleranceMeters`).
    private static func placement(
        of maneuver: MapMatchedManeuver,
        points: [GPXPoint],
        cumulativeDistances: [Double],
        previousMatchedCumulative: Double?,
        mergeMinDistanceMeters: Double
    ) -> TrackProjector.Projection? {
        let maxOffTrack = NavigationConstants.roadbookMapMatchMaxOffTrackMeters

        if let fraction = maneuver.routeProgressFraction, let totalMeters = cumulativeDistances.last, totalMeters > 0 {
            let expectedCumulative = fraction * totalMeters
            return TrackProjector.passes(of: maneuver.coordinate, onto: points, cumulativeDistances: cumulativeDistances, maxDistanceMeters: maxOffTrack)
                .min { abs($0.cumulativeDistanceMeters - expectedCumulative) < abs($1.cumulativeDistanceMeters - expectedCumulative) }
        }

        let candidates = TrackProjector.passes(
            of: maneuver.coordinate,
            onto: points,
            cumulativeDistances: cumulativeDistances,
            maxDistanceMeters: maxOffTrack,
            minimumCumulativeDistanceMeters: previousMatchedCumulative ?? 0
        )
        guard let bestDistance = candidates.map(\.distanceToTrackMeters).min() else { return nil }
        let plausible = candidates.filter { $0.distanceToTrackMeters <= bestDistance + NavigationConstants.roadbookMapMatchRepassToleranceMeters }
        if let previousMatchedCumulative, plausible.count > 1,
           plausible[0].cumulativeDistanceMeters - previousMatchedCumulative < mergeMinDistanceMeters {
            return plausible[1]
        }
        return plausible.first
    }

    /// Vrai demi-tour géométrique : le point situé `probeMeters` APRÈS le virage passe à moins de
    /// `roadbookUTurnSamePathMaxMeters` du tracé des `probeMeters` PRÉCÉDENTS — la trace repart
    /// sur la même route. Une épingle/un lacet repart sur une AUTRE branche, plusieurs dizaines de
    /// mètres plus loin, quel que soit son angle cumulé. Positions interpolées (jamais le point
    /// GPX suivant, qui peut être à 300 m sur une trace peu dense). Pas assez de trace avant/après
    /// pour vérifier : jamais un demi-tour.
    private static func returnsOnSamePath(at i: Int, points: [GPXPoint], cumulativeDistances: [Double], probeMeters: Double) -> Bool {
        let c = cumulativeDistances[i]
        guard let probe = TrackProjector.interpolatedCoordinate(atCumulativeDistance: c + probeMeters, points: points, cumulativeDistances: cumulativeDistances),
              let approachStart = TrackProjector.interpolatedCoordinate(atCumulativeDistance: c - probeMeters, points: points, cumulativeDistances: cumulativeDistances)
        else { return false }

        var approach = [GPXPoint(latitude: approachStart.latitude, longitude: approachStart.longitude)]
        for k in 0...i where cumulativeDistances[k] > c - probeMeters {
            approach.append(points[k])
        }
        guard approach.count > 1,
              let projection = TrackProjector.project(probe, onto: approach, cumulativeDistances: TrackProjector.cumulativeDistances(for: approach))
        else { return false }
        return projection.distanceToTrackMeters <= NavigationConstants.roadbookUTurnSamePathMaxMeters
    }

    /// Premiers/derniers `roadbookUTurnEndpointGuardMeters` de la trace — zone où un demi-tour
    /// est une manœuvre de stationnement, pas une instruction de parcours.
    private static func isNearTrackEndpoint(_ cumulative: Double, cumulativeDistances: [Double]) -> Bool {
        let total = cumulativeDistances.last ?? 0
        let guardMeters = NavigationConstants.roadbookUTurnEndpointGuardMeters
        return cumulative < guardMeters || cumulative > total - guardMeters
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

    /// Fusionne les points de virage trop rapprochés (même épingle détectée sur plusieurs
    /// points consécutifs de la trace, ou piste qui zigzague) en gardant celui à l'angle le
    /// plus marqué — le total affiché (X/Y) reflète donc toujours la liste FUSIONNÉE, jamais
    /// le nombre brut de candidats détectés.
    private static func mergeNearby(
        _ raw: [(coordinate: CLLocationCoordinate2D, angle: Double, direction: TurnDirection, tier: RoadbookTier, pointIndex: Int)],
        minDistanceMeters: Double,
        cumulativeDistances: [Double]
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
            Checkpoint(
                coordinate: item.coordinate,
                turnAngleDegrees: item.angle,
                direction: item.direction,
                tier: item.tier,
                sequenceIndex: index + 1,
                sourcePointIndex: item.pointIndex,
                trackCumulativeDistanceMeters: cumulativeDistances[item.pointIndex]
            )
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
