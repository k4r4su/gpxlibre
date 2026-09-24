import XCTest
import CoreLocation
@testable import GPXlibre

/// Spec "valhalla-map-matching-direction-change" (it20) — vérifie la fusion des points de map
/// matching Valhalla dans `RoadbookAnalyzer.buildRoadbookEvents`, avec des coordonnées MOCKÉES
/// (jamais de vrai réseau ici — voir `ValhallaMapMatchingServiceTests` pour le décodage HTTP,
/// `RideSessionManagerMapMatchingTests` pour le déclenchement/cache).
final class RoadbookMapMatchingTests: XCTestCase {
    /// Déplace un point d'un cap/distance donné (formule de destination great-circle) — même
    /// helper que `RoadbookInflectionTests`.
    private func destination(from coordinate: CLLocationCoordinate2D, bearingDegrees: Double, distanceMeters: Double) -> CLLocationCoordinate2D {
        let earthRadius = 6_371_000.0
        let bearing = bearingDegrees * .pi / 180
        let lat1 = coordinate.latitude * .pi / 180
        let lon1 = coordinate.longitude * .pi / 180
        let angularDistance = distanceMeters / earthRadius

        let lat2 = asin(sin(lat1) * cos(angularDistance) + cos(lat1) * sin(angularDistance) * cos(bearing))
        let lon2 = lon1 + atan2(sin(bearing) * sin(angularDistance) * cos(lat1), cos(angularDistance) - sin(lat1) * sin(lat2))
        return CLLocationCoordinate2D(latitude: lat2 * 180 / .pi, longitude: lon2 * 180 / .pi)
    }

    private func curvingTrack(segmentCount: Int, segmentLengthMeters: Double, segmentTurnDegrees: Double) -> GPXTrack {
        var points = [GPXPoint(latitude: 45.0, longitude: 5.0)]
        var bearing = 0.0
        var coordinate = points[0].coordinate
        for _ in 0..<segmentCount {
            coordinate = destination(from: coordinate, bearingDegrees: bearing, distanceMeters: segmentLengthMeters)
            points.append(GPXPoint(latitude: coordinate.latitude, longitude: coordinate.longitude))
            bearing += segmentTurnDegrees
        }
        return GPXTrack(id: UUID(), name: "Test", fileName: "test.gpx", importDate: Date(), points: points, waypoints: [])
    }

    /// Trace avec des tours VARIABLES par segment (contrairement à `curvingTrack`, incrément
    /// fixe) — nécessaire pour placer plusieurs sommets distincts à des angles différents.
    private func track(segments: [(length: Double, turnAfter: Double)]) -> GPXTrack {
        var points = [GPXPoint(latitude: 45.0, longitude: 5.0)]
        var bearing = 0.0
        var coordinate = points[0].coordinate
        for segment in segments {
            coordinate = destination(from: coordinate, bearingDegrees: bearing, distanceMeters: segment.length)
            points.append(GPXPoint(latitude: coordinate.latitude, longitude: coordinate.longitude))
            bearing += segment.turnAfter
        }
        return GPXTrack(id: UUID(), name: "Ordre", fileName: "ordre.gpx", importDate: Date(), points: points, waypoints: [])
    }

    /// `type: .stayRight` par défaut — une fourche, TOUJOURS conservée quel que soit l'angle de la
    /// trace (depuis "roadbook-turn-angle-from-heading-chords", un simple virage Valhalla n'est
    /// gardé que si la trace tourne vraiment) : suffisant pour les tests de position/fusion ci-dessous, qui
    /// ne s'intéressent pas au choix de palier lui-même (voir `ValhallaMapMatchingServiceTests`/
    /// `testMapMatchedManeuverTypeDrivesTheAssignedTier` pour ça).
    private func events(for track: GPXTrack, mapMatched: [CLLocationCoordinate2D] = [], type: ValhallaManeuverType = .stayRight, mergeMinDistanceMeters: Double = 150) -> [Checkpoint] {
        RoadbookAnalyzer.buildRoadbookEvents(
            for: track,
            windowBeforeMeters: NavigationConstants.roadbookWindowBeforeMetersDefault,
            windowAfterMeters: NavigationConstants.roadbookWindowAfterMetersDefault,
            lightThresholdDegrees: NavigationConstants.roadbookLightThresholdDegreesDefault,
            markedThresholdDegrees: NavigationConstants.roadbookMarkedThresholdDegreesDefault,
            hardThresholdDegrees: NavigationConstants.roadbookHardThresholdDegreesDefault,
            veryHardThresholdDegrees: NavigationConstants.roadbookVeryHardThresholdDegreesDefault,
            mergeMinDistanceMeters: mergeMinDistanceMeters,
            mapMatchedManeuvers: mapMatched.map { MapMatchedManeuver(coordinate: $0, type: type, roundaboutExitCount: nil) }
        )
    }

    /// Non-régression EXPLICITE (spec) : sans coordonnées de map matching (défaut `[]`), le
    /// comportement doit rester STRICTEMENT identique à avant it20 — même appel SANS le nouveau
    /// paramètre du tout (valeur par défaut), pas juste `[]` passé explicitement.
    func testOmittingMapMatchedParameterLeavesGeometricEventsUnchanged() {
        let track = curvingTrack(segmentCount: 10, segmentLengthMeters: 20, segmentTurnDegrees: 8)
        let withoutParam = RoadbookAnalyzer.buildRoadbookEvents(
            for: track,
            windowBeforeMeters: NavigationConstants.roadbookWindowBeforeMetersDefault,
            windowAfterMeters: NavigationConstants.roadbookWindowAfterMetersDefault,
            lightThresholdDegrees: NavigationConstants.roadbookLightThresholdDegreesDefault,
            markedThresholdDegrees: NavigationConstants.roadbookMarkedThresholdDegreesDefault,
            hardThresholdDegrees: NavigationConstants.roadbookHardThresholdDegreesDefault,
            veryHardThresholdDegrees: NavigationConstants.roadbookVeryHardThresholdDegreesDefault,
            mergeMinDistanceMeters: 150
        )
        let withEmptyParam = events(for: track, mapMatched: [])

        XCTAssertEqual(withoutParam.count, withEmptyParam.count)
        XCTAssertEqual(withoutParam.map(\.tier), withEmptyParam.map(\.tier))
    }

    /// Règle produit (fix "roadbook-turn-angle-from-heading-chords") : un virage Valhalla là où la
    /// TRACE ne tourne que de 20° (sous le seuil minimal) n'est pas un checkpoint — Valhalla décrit
    /// la manœuvre sur SA route recalée, pas le changement de cap réel du pilote. (Remplace le test
    /// it20 "virage < 30° avec changement de segment → événement", voir le cas "changement de nom
    /// de route" pour ce qui reste gardé sous le seuil.)
    func testAValhallaTurnWhereTheTraceBarelyTurnsIsNotACheckpoint() {
        let track = curvingTrack(segmentCount: 2, segmentLengthMeters: 100, segmentTurnDegrees: 20)
        XCTAssertTrue(events(for: track).isEmpty, "précondition : rien géométriquement")

        XCTAssertTrue(events(for: track, mapMatched: [track.points[1].coordinate], type: .right).isEmpty)
        XCTAssertTrue(events(for: track, mapMatched: [track.points[1].coordinate], type: .slightRight).isEmpty)
    }

    /// Second test attendu par la spec : "virage < 30° SANS changement de segment → rien" — un
    /// virage léger qui n'est PAS accompagné d'un point de map matching à proximité ne produit
    /// toujours rien (comportement géométrique seul, inchangé).
    func testBelowLightThresholdWithoutAnyNearbyMapMatchedCoordinateProducesNothing() {
        let track = curvingTrack(segmentCount: 2, segmentLengthMeters: 100, segmentTurnDegrees: 20)
        // Coordonnée de map matching TRÈS loin de ce virage précis (mais toujours sur Terre) —
        // ne doit pas être confondue avec le virage à `track.points[1]`.
        let unrelatedCoordinate = CLLocationCoordinate2D(latitude: 48.85, longitude: 2.35)

        let result = events(for: track, mapMatched: [unrelatedCoordinate])

        // Avant it26, la coordonnée était ramenée sur le point GPX le plus proche (sans seuil) et
        // produisait quand même un événement. Depuis "roadbook-maneuver-position-from-route", la
        // position affichée est celle du VRAI carrefour Valhalla : un carrefour à des centaines
        // de km (au-delà de `roadbookMapMatchMaxOffTrackMeters`) n'est pas sur le parcours de
        // cette trace, jamais un virage à annoncer.
        XCTAssertTrue(result.isEmpty)
    }

    // MARK: - Position exacte du carrefour (fix "roadbook-maneuver-position-from-route", it26 point 1)

    /// Test demandé par la fiche it26 : une manœuvre au MILIEU d'un segment GPX long doit obtenir
    /// la distance cumulée du vrai carrefour (interpolée), jamais celle du point GPX voisin.
    /// Trace droite peu dense (points à 0/500/1000 m), carrefour Valhalla à 300 m, 5 m à côté de
    /// la trace (géométrie recalée sur la route réelle) — l'ancien `nearestPointIndex` le plaçait
    /// sur le point à 500 m, soit 200 m de décalage dans l'annonce.
    func testManeuverInTheMiddleOfALongGPXSegmentGetsTheInterpolatedCumulativeDistanceOfTheRealJunction() {
        let track = track(segments: [(500, 0), (500, 0)])
        let junction = destination(from: destination(from: track.points[0].coordinate, bearingDegrees: 0, distanceMeters: 300), bearingDegrees: 90, distanceMeters: 5)

        let result = events(for: track, mapMatched: [junction])

        XCTAssertEqual(result.count, 1)
        let cumulative = result.first?.trackCumulativeDistanceMeters ?? -1
        XCTAssertEqual(cumulative, 300, accuracy: 1, "distance cumulée du vrai carrefour, pas celle du point GPX voisin (500 m)")
        XCTAssertEqual(result.first?.coordinate.latitude ?? 0, junction.latitude, accuracy: 1e-9, "coordonnée affichée = carrefour réel Valhalla")
        XCTAssertEqual(result.first?.coordinate.longitude ?? 0, junction.longitude, accuracy: 1e-9)
    }

    /// Même vérification au niveau de ce que le Road Book affiche réellement
    /// (`RoadbookExtractor`), et du maintien 10-20 m après le virage (`RoadbookLiveProgress`,
    /// fix "roadbook-live-progress-hold") qui doit se caler sur la position CORRIGÉE.
    func testRoadbookManeuverAndLiveHoldAreBasedOnTheCorrectedJunctionPosition() {
        let track = track(segments: [(500, 0), (500, 0)])
        let junction = destination(from: track.points[0].coordinate, bearingDegrees: 0, distanceMeters: 300)
        let maneuvers = RoadbookExtractor.maneuvers(
            for: track,
            windowBeforeMeters: NavigationConstants.roadbookWindowBeforeMetersDefault,
            windowAfterMeters: NavigationConstants.roadbookWindowAfterMetersDefault,
            lightThresholdDegrees: NavigationConstants.roadbookLightThresholdDegreesDefault,
            markedThresholdDegrees: NavigationConstants.roadbookMarkedThresholdDegreesDefault,
            hardThresholdDegrees: NavigationConstants.roadbookHardThresholdDegreesDefault,
            veryHardThresholdDegrees: NavigationConstants.roadbookVeryHardThresholdDegreesDefault,
            mergeMinDistanceMeters: 150,
            mapMatchedManeuvers: [MapMatchedManeuver(coordinate: junction, type: .stayRight, roundaboutExitCount: nil)]
        )
        XCTAssertEqual(maneuvers.count, 1)
        XCTAssertEqual(maneuvers[0].cumulativeDistanceMeters, 300, accuracy: 1)
        XCTAssertEqual(maneuvers[0].partialDistanceMeters, 300, accuracy: 1)

        let cumulativeDistances = TrackProjector.cumulativeDistances(for: track.points)
        let tenMetersBefore = destination(from: track.points[0].coordinate, bearingDegrees: 0, distanceMeters: 290)
        let tenMetersAfter = destination(from: track.points[0].coordinate, bearingDegrees: 0, distanceMeters: 310)
        let beyondHold = destination(from: track.points[0].coordinate, bearingDegrees: 0, distanceMeters: 300 + RoadBookConstants.liveManeuverHoldAfterMeters + 5)

        func live(at coordinate: CLLocationCoordinate2D) -> (index: Int, distanceRemainingMeters: Double)? {
            guard let projection = TrackProjector.project(coordinate, onto: track.points, cumulativeDistances: cumulativeDistances) else { return nil }
            return RoadbookLiveProgress.nextManeuver(maneuvers: maneuvers, currentCumulativeDistanceMeters: projection.cumulativeDistanceMeters)
        }

        XCTAssertEqual(live(at: tenMetersBefore)?.distanceRemainingMeters ?? -1, 10, accuracy: 1, "compte à rebours calé sur le vrai carrefour (300 m), pas sur le point GPX à 500 m")
        XCTAssertEqual(live(at: tenMetersAfter)?.index, 0, "maintenu juste après le vrai carrefour")
        XCTAssertEqual(live(at: tenMetersAfter)?.distanceRemainingMeters ?? -1, 0, accuracy: 0.01)
        XCTAssertNil(live(at: beyondHold), "maintien terminé au-delà de la fenêtre, comptée depuis le vrai carrefour")
    }

    private func buildEvents(_ track: GPXTrack, maneuvers: [MapMatchedManeuver]) -> [Checkpoint] {
        RoadbookAnalyzer.buildRoadbookEvents(
            for: track,
            windowBeforeMeters: NavigationConstants.roadbookWindowBeforeMetersDefault,
            windowAfterMeters: NavigationConstants.roadbookWindowAfterMetersDefault,
            lightThresholdDegrees: NavigationConstants.roadbookLightThresholdDegreesDefault,
            markedThresholdDegrees: NavigationConstants.roadbookMarkedThresholdDegreesDefault,
            hardThresholdDegrees: NavigationConstants.roadbookHardThresholdDegreesDefault,
            veryHardThresholdDegrees: NavigationConstants.roadbookVeryHardThresholdDegreesDefault,
            mergeMinDistanceMeters: 150,
            mapMatchedManeuvers: maneuvers
        )
    }

    /// 500 m vers le nord (points tous les 100 m), demi-tour, 500 m retour vers le sud par la
    /// même route — carrefour à 200 m, 5 m à côté : aussi proche de l'aller (200 m) que du retour
    /// (800 m). Hors de portée (`mergeMinDistanceMeters`) du demi-tour géométrique détecté vers
    /// 400 m, pour que seul le choix du passage soit testé ici.
    private func outAndBack() -> (track: GPXTrack, junction: CLLocationCoordinate2D, outbound: Double, back: Double) {
        let track = track(segments: [(100, 0), (100, 0), (100, 0), (100, 0), (100, 180), (100, 0), (100, 0), (100, 0), (100, 0), (100, 0)])
        let junction = destination(from: destination(from: track.points[0].coordinate, bearingDegrees: 0, distanceMeters: 200), bearingDegrees: 90, distanceMeters: 5)
        let cumulative = TrackProjector.cumulativeDistances(for: track.points)
        return (track, junction, cumulative[2], cumulative[8])
    }

    /// Aller-retour par la MÊME route, avec la progression le long de la route recalée que
    /// fournit Valhalla (cas réel) : chaque manœuvre tombe sur SON passage — avant it26, la
    /// recherche globale plaçait celle du retour sur l'aller, où elle disparaissait comme doublon.
    func testOnAnOutAndBackEachManeuverIsPlacedOnItsOwnPassUsingTheValhallaRouteProgress() {
        let (track, junction, outbound, back) = outAndBack()
        let total = TrackProjector.cumulativeDistances(for: track.points).last ?? 1
        let result = buildEvents(track, maneuvers: [
            MapMatchedManeuver(coordinate: junction, type: .stayRight, roundaboutExitCount: nil, routeProgressFraction: outbound / total),
            MapMatchedManeuver(coordinate: junction, type: .stayLeft, roundaboutExitCount: nil, routeProgressFraction: back / total),
        ])
        let matched = result.filter { $0.tier == .fork }

        XCTAssertEqual(matched.count, 2, "un événement à l'aller, un au retour — jamais fusionnés en un seul")
        XCTAssertEqual(matched.first?.trackCumulativeDistanceMeters ?? -1, outbound, accuracy: 1)
        XCTAssertEqual(matched.first?.direction, .right)
        XCTAssertEqual(matched.last?.trackCumulativeDistanceMeters ?? -1, back, accuracy: 1)
        XCTAssertEqual(matched.last?.direction, .left)
    }

    /// Boucle qui traverse le MÊME carrefour deux fois — tout droit au km 0,2, puis en y
    /// revenant au km 1,4. La manœuvre Valhalla appartient au second passage : la géométrie seule
    /// la placerait au premier (le plus tôt), là où le pilote va tout droit — seule la
    /// progression le long de la route recalée départage les deux.
    func testOnALoopThroughTheSameJunctionTwiceTheRouteProgressPicksTheRightPass() {
        // Nord 400 m (carrefour X à 200 m), est 400 m, sud 200 m, ouest 400 m (retour sur X au
        // km 1,4), ouest encore 400 m.
        let loop = track(segments: [(200, 0), (200, 90), (400, 90), (200, 90), (200, 0), (200, 0), (400, 0)])
        let junctionX = loop.points[1].coordinate
        let cumulative = TrackProjector.cumulativeDistances(for: loop.points)
        let secondPass = cumulative[6]
        XCTAssertLessThan(RoadbookAnalyzer.distanceMeters(loop.points[6].coordinate, junctionX), 1, "précondition : la boucle repasse bien sur X")

        let result = buildEvents(loop, maneuvers: [
            MapMatchedManeuver(coordinate: junctionX, type: .stayRight, roundaboutExitCount: nil, routeProgressFraction: secondPass / (cumulative.last ?? 1)),
        ])
        let matched = result.filter { $0.tier == .fork }

        XCTAssertEqual(matched.count, 1)
        XCTAssertEqual(matched.first?.trackCumulativeDistanceMeters ?? -1, secondPass, accuracy: 2, "second passage (km 1,4), pas le premier (km 0,2) où le pilote va tout droit")
    }

    /// Repli SANS progression Valhalla (fixture/format ancien) : projection monotone dans l'ordre
    /// des manœuvres — l'aller-retour reste correctement réparti, même quand l'arrondi flottant
    /// rend le retour marginalement plus proche du carrefour que l'aller.
    func testOnAnOutAndBackWithoutRouteProgressTheMonotonicFallbackStillSplitsBothPasses() {
        let (track, junction, outbound, back) = outAndBack()
        let result = buildEvents(track, maneuvers: [
            MapMatchedManeuver(coordinate: junction, type: .stayRight, roundaboutExitCount: nil),
            MapMatchedManeuver(coordinate: junction, type: .stayLeft, roundaboutExitCount: nil),
        ])
        let matched = result.filter { $0.tier == .fork }

        XCTAssertEqual(matched.count, 2, "un événement à l'aller, un au retour — jamais fusionnés en un seul")
        XCTAssertEqual(matched.first?.trackCumulativeDistanceMeters ?? -1, outbound, accuracy: 1)
        XCTAssertEqual(matched.first?.direction, .right)
        XCTAssertEqual(matched.last?.trackCumulativeDistanceMeters ?? -1, back, accuracy: 1)
        XCTAssertEqual(matched.last?.direction, .left)
    }

    /// Garde-fou symétrique : deux VRAIS carrefours à 100 m l'un de l'autre sur une route
    /// parcourue une seule fois — le second (plus proche que `mergeMinDistanceMeters`) reste
    /// écarté comme avant, jamais repoussé plus loin sur la trace à une position fausse.
    func testASecondCloseJunctionOnASingleRoadIsNeverPushedFurtherAlongTheTrack() {
        let track = track(segments: [(500, 0), (500, 0)])
        let first = destination(from: track.points[0].coordinate, bearingDegrees: 0, distanceMeters: 300)
        let second = destination(from: track.points[0].coordinate, bearingDegrees: 0, distanceMeters: 400)

        let result = events(for: track, mapMatched: [first, second])

        XCTAssertEqual(result.count, 1)
        XCTAssertEqual(result.first?.trackCumulativeDistanceMeters ?? -1, 300, accuracy: 1)
    }

    /// Deux carrefours éloignés sur le MÊME segment GPX (trace planifiée peu dense) partagent le
    /// même point GPX voisin — ils doivent quand même rester deux événements distincts, avec des
    /// identités distinctes (l'id dérivait du seul `sourcePointIndex` avant it26 : collision).
    func testTwoJunctionsOnTheSameSparseSegmentStayDistinctEvents() {
        let track = track(segments: [(2000, 0), (2000, 0)])
        let first = destination(from: track.points[0].coordinate, bearingDegrees: 0, distanceMeters: 1500)
        let second = destination(from: track.points[0].coordinate, bearingDegrees: 0, distanceMeters: 1800)

        let result = events(for: track, mapMatched: [first, second])

        XCTAssertEqual(result.count, 2)
        XCTAssertEqual(result[0].sourcePointIndex, result[1].sourcePointIndex, "précondition : même point GPX voisin")
        XCTAssertNotEqual(result[0].id, result[1].id)
        XCTAssertNotEqual(result[0], result[1])
    }

    /// "pas de sur-détection" : un point de map matching qui coïncide avec un virage géométrique
    /// DÉJÀ détecté (au-delà du seuil) ne doit jamais produire de doublon.
    func testMapMatchedCoordinateAtAnExistingGeometricEventProducesNoDuplicate() {
        let track = curvingTrack(segmentCount: 2, segmentLengthMeters: 100, segmentTurnDegrees: 60)
        let geometricOnly = events(for: track)
        XCTAssertEqual(geometricOnly.count, 1, "précondition : un virage marqué (60°) déjà détecté géométriquement")

        let matchedCoordinate = track.points[1].coordinate
        let result = events(for: track, mapMatched: [matchedCoordinate])

        XCTAssertEqual(result.count, 1, "le point de map matching coïncide avec un événement déjà détecté, pas de doublon")
        XCTAssertEqual(result.first?.tier, .marked, "l'événement géométrique existant garde son palier, jamais écrasé par .lightDirectionChange")
    }

    /// Invariant it14 "source unique" : les événements fusionnés restent ordonnés par
    /// PROGRESSION le long de la trace (sourcePointIndex), pas par ordre d'insertion — le code
    /// ajoute TOUJOURS les événements géométriques avant ceux du map matching (voir
    /// `buildRoadbookEvents`), donc un point de map matching plus TÔT sur le trajet qu'un virage
    /// géométrique doit quand même ressortir EN PREMIER une fois trié.
    func testMergedEventsStayOrderedByProgressionAlongTheTrack() {
        // Un seul virage géométrique réel (60°, au point 4) — segments assez longs (≥ fenêtre
        // 60 m par défaut) et un seul changement de cap dans toute la trace pour une mesure
        // propre (voir RoadbookInflectionTests, même contrainte). Le point de map matching est
        // placé BIEN AVANT (point 1, sur la portion droite), pour vérifier le tri plutôt que de
        // coïncider avec l'ordre d'insertion par accident.
        let track = track(segments: [(100, 0), (100, 0), (100, 0), (100, 60), (100, 0)])
        let geometricOnly = events(for: track)
        // L'ancienne somme d'écarts de cap sur segments entiers plaçait ce virage au point 3 (un
        // sommet trop tôt) ; le cap moyen par cordes (fix "roadbook-turn-angle-from-heading-
        // chords") le place au vrai sommet, point 4.
        XCTAssertEqual(geometricOnly.count, 1, "précondition : un seul virage marqué (60°) retenu après fusion")
        XCTAssertEqual(geometricOnly.first?.sourcePointIndex, 4)

        let matchedCoordinate = track.points[1].coordinate
        let result = events(for: track, mapMatched: [matchedCoordinate])

        XCTAssertEqual(result.count, 2, "1 virage marqué géométrique + 1 léger changement de direction map matché")
        XCTAssertEqual(result.map(\.sequenceIndex), [1, 2], "numérotation continue dans l'ordre de progression")
        XCTAssertEqual(result.map(\.tier), [.fork, .marked], "le point de map matching (point 1) précède le virage géométrique (point 4) le long de la trace, malgré un ordre d'insertion inverse dans le code")
    }

    // MARK: - Palier/direction pilotés par le type Valhalla (spec "roadbook-route-aware-maneuvers", it24, point 2)

    func testRoundaboutManeuverProducesRoundaboutTierWithItsExitCount() {
        let track = curvingTrack(segmentCount: 2, segmentLengthMeters: 100, segmentTurnDegrees: 20)
        let maneuver = MapMatchedManeuver(coordinate: track.points[1].coordinate, type: .roundaboutExit, roundaboutExitCount: 3)

        let result = RoadbookAnalyzer.buildRoadbookEvents(
            for: track,
            windowBeforeMeters: NavigationConstants.roadbookWindowBeforeMetersDefault,
            windowAfterMeters: NavigationConstants.roadbookWindowAfterMetersDefault,
            lightThresholdDegrees: NavigationConstants.roadbookLightThresholdDegreesDefault,
            markedThresholdDegrees: NavigationConstants.roadbookMarkedThresholdDegreesDefault,
            hardThresholdDegrees: NavigationConstants.roadbookHardThresholdDegreesDefault,
            veryHardThresholdDegrees: NavigationConstants.roadbookVeryHardThresholdDegreesDefault,
            mergeMinDistanceMeters: 150,
            mapMatchedManeuvers: [maneuver]
        )

        XCTAssertEqual(result.count, 1)
        XCTAssertEqual(result.first?.tier, .roundabout)
        XCTAssertEqual(result.first?.roundaboutExitCount, 3)
    }

    func testForkManeuverProducesForkTier() {
        let track = curvingTrack(segmentCount: 2, segmentLengthMeters: 100, segmentTurnDegrees: 20)
        let result = events(for: track, mapMatched: [track.points[1].coordinate], type: .stayRight)

        XCTAssertEqual(result.first?.tier, .fork)
        XCTAssertEqual(result.first?.direction, .right)
    }

    func testMergeManeuverProducesMergeTier() {
        let track = curvingTrack(segmentCount: 2, segmentLengthMeters: 100, segmentTurnDegrees: 20)
        let result = events(for: track, mapMatched: [track.points[1].coordinate], type: .rampRight)

        XCTAssertEqual(result.first?.tier, .merge)
    }

    // MARK: - Demi-tour Valhalla (fix "roadbook-no-false-uturn", it26 point 2)

    private func valhallaUTurn(_ type: ValhallaManeuverType, sameRoad: Bool, atMeters: Double = 500) -> [Checkpoint] {
        let straight = track(segments: [(500, 0), (500, 0)])
        let coordinate = destination(from: straight.points[0].coordinate, bearingDegrees: 0, distanceMeters: atMeters)
        return buildEvents(straight, maneuvers: [MapMatchedManeuver(coordinate: coordinate, type: type, roundaboutExitCount: nil, streetNamesBefore: ["D 83"], streetNamesAfter: sameRoad ? ["D 83"] : ["Rue du Moulin"])])
    }

    /// Test demandé par la fiche it26 : demi-tour SEULEMENT pour un type Valhalla demi-tour SUR
    /// LA MÊME ROUTE (même nom de rue avant/après, voir `ValhallaMapMatchingService`).
    func testValhallaUTurnOnTheSameRoadIsAUTurn() {
        let result = valhallaUTurn(.uturnLeft, sameRoad: true)
        XCTAssertEqual(result.first?.tier, .uTurn)
        XCTAssertEqual(result.first?.direction, .uTurn)
    }

    /// Type demi-tour Valhalla sans même route confirmée (rue différente, ou sans nom) : virage
    /// très serré, du côté indiqué par le type — jamais un demi-tour.
    func testValhallaUTurnNotConfirmedOnTheSameRoadIsAVeryTightTurnOnItsSide() {
        let left = valhallaUTurn(.uturnLeft, sameRoad: false)
        XCTAssertEqual(left.first?.tier, .veryHard)
        XCTAssertEqual(left.first?.direction, .left)

        let right = valhallaUTurn(.uturnRight, sameRoad: false)
        XCTAssertEqual(right.first?.tier, .veryHard)
        XCTAssertEqual(right.first?.direction, .right)
    }

    /// Seul demi-tour Valhalla du cache réel du propriétaire : à 20 m du départ (sortie de
    /// stationnement) — ignoré, même confirmé sur la même route.
    func testValhallaUTurnRightAfterTheStartIsIgnoredAsAParkingManeuver() {
        XCTAssertTrue(valhallaUTurn(.uturnRight, sameRoad: true, atMeters: 20).isEmpty)
        XCTAssertTrue(valhallaUTurn(.uturnRight, sameRoad: false, atMeters: 20).isEmpty)
    }

    /// Un rond-point/une fourche/une fusion ne portent PAS de `roundaboutExitCount` en dehors du
    /// cas rond-point — jamais une valeur fantôme héritée d'un autre champ.
    func testNonRoundaboutTiersNeverCarryARoundaboutExitCount() {
        let track = curvingTrack(segmentCount: 2, segmentLengthMeters: 100, segmentTurnDegrees: 20)
        let result = events(for: track, mapMatched: [track.points[1].coordinate], type: .stayLeft)

        XCTAssertNil(result.first?.roundaboutExitCount)
    }
}
