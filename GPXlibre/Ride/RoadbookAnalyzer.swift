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

        let cumulativeDistances = TrackProjector.cumulativeDistances(for: points)
        let thresholds = TierThresholds(light: lightThresholdDegrees, marked: markedThresholdDegrees, hard: hardThresholdDegrees, veryHard: veryHardThresholdDegrees)

        // Fix "roadbook-turn-angle-from-heading-chords" : changement de cap RÉEL en chaque
        // sommet (voir `headingChange`), candidats au-delà du seuil minimal, puis regroupés.
        var candidates: [(pointIndex: Int, angle: Double)] = []
        for i in 1..<(points.count - 1) {
            guard let angle = headingChange(
                atCumulativeDistance: cumulativeDistances[i],
                points: points,
                cumulativeDistances: cumulativeDistances,
                windowBeforeMeters: windowBeforeMeters,
                windowAfterMeters: windowAfterMeters
            ), abs(angle) >= lightThresholdDegrees else { continue }
            candidates.append((i, angle))
        }

        var raw: [(coordinate: CLLocationCoordinate2D, angle: Double, direction: TurnDirection, tier: RoadbookTier, pointIndex: Int)] = []
        for candidate in clustered(candidates, points: points, cumulativeDistances: cumulativeDistances, windowBeforeMeters: windowBeforeMeters, windowAfterMeters: windowAfterMeters, minimumTurnDegrees: lightThresholdDegrees) {
            let i = candidate.pointIndex
            let absAngle = abs(candidate.angle)

            // Fix "roadbook-no-false-uturn" (it26 point 2) : le demi-tour n'est plus un palier
            // d'angle (≥ 135° avant, ce qui classait toute épingle en demi-tour) — il faut que la
            // trace reparte réellement sur SON PROPRE tracé. Au départ/à l'arrivée, c'est une
            // manœuvre de stationnement : ignorée.
            let reversesOnSamePath = absAngle >= NavigationConstants.roadbookUTurnMinDegrees
                && returnsOnSamePath(at: i, points: points, cumulativeDistances: cumulativeDistances, probeMeters: min(windowBeforeMeters, windowAfterMeters))
            if reversesOnSamePath, isNearTrackEndpoint(cumulativeDistances[i], cumulativeDistances: cumulativeDistances) { continue }

            let tier = reversesOnSamePath ? .uTurn : thresholds.tier(forAbsoluteAngle: absAngle)
            let direction: TurnDirection = tier == .uTurn ? .uTurn : (candidate.angle > 0 ? .right : .left)
            raw.append((points[i].coordinate, absAngle, direction, tier, i))
        }

        let geometricEvents = mergeNearby(raw, minDistanceMeters: mergeMinDistanceMeters, cumulativeDistances: cumulativeDistances)
        guard !mapMatchedManeuvers.isEmpty else { return geometricEvents }

        return mergingMapMatchedDirectionChanges(
            mapMatchedManeuvers,
            into: geometricEvents,
            points: points,
            cumulativeDistances: cumulativeDistances,
            thresholds: thresholds,
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
        thresholds: TierThresholds,
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

            // Fix "roadbook-turn-angle-from-heading-chords" : angle, sens ET libellé d'une
            // manœuvre Valhalla viennent de la géométrie de la TRACE SUIVIE au vrai carrefour,
            // jamais de la seule catégorie Valhalla (qui décrit la manœuvre sur SA route
            // recalée, et gardait des carrefours où la trace va tout droit).
            let turn = headingChange(
                atCumulativeDistance: exactCumulative,
                points: points,
                cumulativeDistances: cumulativeDistances,
                windowBeforeMeters: windowBeforeMeters,
                windowAfterMeters: windowAfterMeters
            ) ?? 0
            var direction = maneuver.type.roadbookDirection
            switch tier {
            case .roundabout, .fork, .merge:
                // Gardés tels quels, pictogrammes dédiés : sortie de rond-point, vraie fourche, et
                // bretelle/sortie (choisir une branche, même à faible angle, EST une décision).
                break
            case .uTurn:
                // Fix "roadbook-no-false-uturn" (it26 point 2) : au départ/à l'arrivée, manœuvre de
                // stationnement — ignoré. Ailleurs, demi-tour seulement sur la même rue ; sinon
                // virage très serré, du côté indiqué par Valhalla.
                guard !isNearTrackEndpoint(exactCumulative, cumulativeDistances: cumulativeDistances) else { continue }
                if !maneuver.isSameRoadUTurn {
                    tier = .veryHard
                    direction = maneuver.type == .uturnLeft ? .left : .right
                }
            default:
                // Virage : gardé si la trace tourne vraiment (seuil minimal), OU si la route suivie
                // change de nom avec un changement de cap sensible — "Changement de direction".
                // Croisement de chemin/sentier où la trace garde son cap ET sa route : supprimé.
                let isRealTurn = abs(turn) >= thresholds.light
                let isRoadChange = maneuver.changesRoadName && abs(turn) >= NavigationConstants.roadbookRoadChangeMinTurnDegrees
                guard isRealTurn || isRoadChange else { continue }
                tier = isRealTurn ? thresholds.tier(forAbsoluteAngle: abs(turn)) : .lightDirectionChange
                direction = turn > 0 ? .right : .left
            }

            // Point GPX le plus proche SUR LE SEGMENT projeté — ne sert plus qu'au cap sortant
            // (`RoadbookExtractor`) et à l'angle affiché, jamais à la position/distance.
            let segmentStart = projection.nearestSegmentIndex
            let segmentEnd = min(segmentStart + 1, points.count - 1)
            let pointIndex = exactCumulative - cumulativeDistances[segmentStart] <= cumulativeDistances[segmentEnd] - exactCumulative
                ? segmentStart
                : segmentEnd

            combined.append(Checkpoint(
                coordinate: maneuver.coordinate,
                turnAngleDegrees: abs(turn),
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

    /// Paliers d'angle — SEUL endroit où un angle devient un libellé (fix "roadbook-turn-angle-
    /// from-heading-chords") : un angle sous `light` n'est jamais un virage.
    struct TierThresholds {
        let light: Double
        let marked: Double
        let hard: Double
        let veryHard: Double

        func tier(forAbsoluteAngle angle: Double) -> RoadbookTier {
            if angle >= veryHard { return .veryHard }
            if angle >= hard { return .hard }
            if angle >= marked { return .marked }
            return .light
        }
    }

    /// Changement de cap signé (droite > 0) à la distance cumulée `c` : cap MOYEN des
    /// `windowBeforeMeters` précédents (corde position(c − avant) → position(c)) comparé au cap
    /// moyen des `windowAfterMeters` suivants — positions INTERPOLÉES sur la trace suivie.
    ///
    /// Fix "roadbook-turn-angle-from-heading-chords" — retour terrain : "Virage fort" là où la trace
    /// continue tout droit. Remplace l'ancienne SOMME des écarts de cap segment par segment, qui
    /// cumulait deux défauts : (1) la fenêtre comptait en segments ENTIERS (au moins deux de chaque
    /// côté), donc sur une trace peu dense "±60 m" couvrait plusieurs centaines de mètres et
    /// additionnait des courbes sans rapport ; (2) un segment de longueur nulle (point GPX
    /// dupliqué) a un cap fictif de 0°, qui injectait deux faux virages de ±90°. Cas réel : un
    /// point dupliqué juste après un vrai virage à gauche produisait un "Virage fort" fantôme
    /// 240 m plus loin sur une ligne droite. Une corde ne voit que le déplacement NET : ni
    /// doublon, ni gigue GPS, ni zigzag ne créent de virage. `nil` si la trace ne s'étend pas
    /// d'au moins la moitié de la fenêtre de chaque côté.
    static func headingChange(
        atCumulativeDistance c: Double,
        points: [GPXPoint],
        cumulativeDistances: [Double],
        windowBeforeMeters: Double,
        windowAfterMeters: Double
    ) -> Double? {
        headingChange(from: c, to: c, points: points, cumulativeDistances: cumulativeDistances, windowBeforeMeters: windowBeforeMeters, windowAfterMeters: windowAfterMeters)
    }

    /// Même mesure entre un cap d'APPROCHE (corde qui se termine à `start`) et un cap de SORTIE
    /// (corde qui commence à `end`) — virage net d'une portion de trace [start, end] (grappe de
    /// sommets rapprochés, ex. les deux coins d'une épingle).
    private static func headingChange(
        from start: Double,
        to end: Double,
        points: [GPXPoint],
        cumulativeDistances: [Double],
        windowBeforeMeters: Double,
        windowAfterMeters: Double
    ) -> Double? {
        guard let total = cumulativeDistances.last else { return nil }
        let approachStart = max(start - windowBeforeMeters, 0)
        let exitEnd = min(end + windowAfterMeters, total)
        guard start - approachStart >= windowBeforeMeters / 2, exitEnd - end >= windowAfterMeters / 2,
              let a = TrackProjector.interpolatedCoordinate(atCumulativeDistance: approachStart, points: points, cumulativeDistances: cumulativeDistances),
              let s = TrackProjector.interpolatedCoordinate(atCumulativeDistance: start, points: points, cumulativeDistances: cumulativeDistances),
              let e = TrackProjector.interpolatedCoordinate(atCumulativeDistance: end, points: points, cumulativeDistances: cumulativeDistances),
              let b = TrackProjector.interpolatedCoordinate(atCumulativeDistance: exitEnd, points: points, cumulativeDistances: cumulativeDistances)
        else { return nil }
        return signedAngleDifference(from: bearing(from: a, to: s), to: bearing(from: e, to: b))
    }

    /// Cap absolu (0-360°) à suivre APRÈS la distance cumulée `c` — cap moyen des
    /// `windowAfterMeters` suivants (jamais le seul segment suivant, qui peut mesurer 0 m et
    /// afficher un cap fictif de 0°). Repli sur le cap d'arrivée en toute fin de trace.
    static func outgoingHeading(
        atCumulativeDistance c: Double,
        points: [GPXPoint],
        cumulativeDistances: [Double],
        windowAfterMeters: Double
    ) -> Double {
        guard let total = cumulativeDistances.last, total > 0,
              let m = TrackProjector.interpolatedCoordinate(atCumulativeDistance: c, points: points, cumulativeDistances: cumulativeDistances)
        else { return 0 }
        let heading: Double
        if total - c >= 1, let b = TrackProjector.interpolatedCoordinate(atCumulativeDistance: min(c + windowAfterMeters, total), points: points, cumulativeDistances: cumulativeDistances) {
            heading = bearing(from: m, to: b)
        } else if let a = TrackProjector.interpolatedCoordinate(atCumulativeDistance: max(c - windowAfterMeters, 0), points: points, cumulativeDistances: cumulativeDistances) {
            heading = bearing(from: a, to: m)
        } else {
            return 0
        }
        return (heading + 360).truncatingRemainder(dividingBy: 360)
    }

    /// Regroupe les candidats consécutifs à `roadbookTurnClusterMeters` ou moins les uns des autres
    /// (le même virage vu depuis plusieurs sommets, ou deux coins rapprochés d'une épingle) : UN
    /// événement par grappe, placé au sommet le plus marqué dans le sens du virage NET de la
    /// grappe (de la fenêtre avant son premier sommet à la fenêtre après son dernier), et portant
    /// ce virage net — deux coins à 90° espacés de 40 m forment une épingle à 180°, pas un
    /// "virage fort". Virage net sous le seuil minimal : aller-retour parasite (zigzag d'un
    /// artefact de tracé/matching), ignoré.
    private static func clustered(
        _ candidates: [(pointIndex: Int, angle: Double)],
        points: [GPXPoint],
        cumulativeDistances: [Double],
        windowBeforeMeters: Double,
        windowAfterMeters: Double,
        minimumTurnDegrees: Double
    ) -> [(pointIndex: Int, angle: Double)] {
        var groups: [[(pointIndex: Int, angle: Double)]] = []
        for candidate in candidates {
            if let last = groups.last?.last,
               cumulativeDistances[candidate.pointIndex] - cumulativeDistances[last.pointIndex] <= NavigationConstants.roadbookTurnClusterMeters {
                groups[groups.count - 1].append(candidate)
            } else {
                groups.append([candidate])
            }
        }

        return groups.compactMap { group in
            guard group.count > 1, let first = group.first, let last = group.last else { return group.first }
            // Changement de cap net : approche du premier sommet → sortie du dernier.
            let net = headingChange(
                from: cumulativeDistances[first.pointIndex],
                to: cumulativeDistances[last.pointIndex],
                points: points,
                cumulativeDistances: cumulativeDistances,
                windowBeforeMeters: windowBeforeMeters,
                windowAfterMeters: windowAfterMeters
            ) ?? group.map(\.angle).reduce(0, +)
            guard abs(net) >= minimumTurnDegrees else { return nil }
            if let apex = group.filter({ ($0.angle > 0) == (net > 0) }).max(by: { abs($0.angle) < abs($1.angle) }) {
                return (apex.pointIndex, net)
            }
            // Aucun sommet dans le sens du virage net : la grappe a tourné de PLUS de 180° (boucle,
            // bretelle d'échangeur) et la différence de caps s'est "enroulée" (210° à droite se
            // lit −150°). Virage réel = 360° − |net|, dans le sens de ses sommets.
            guard let apex = group.max(by: { abs($0.angle) < abs($1.angle) }) else { return nil }
            return (apex.pointIndex, (apex.angle > 0 ? 1 : -1) * (360 - abs(net)))
        }
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
