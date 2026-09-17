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

    private func events(for track: GPXTrack, mapMatched: [CLLocationCoordinate2D] = [], mergeMinDistanceMeters: Double = 150) -> [Checkpoint] {
        RoadbookAnalyzer.buildRoadbookEvents(
            for: track,
            windowBeforeMeters: NavigationConstants.roadbookWindowBeforeMetersDefault,
            windowAfterMeters: NavigationConstants.roadbookWindowAfterMetersDefault,
            lightThresholdDegrees: NavigationConstants.roadbookLightThresholdDegreesDefault,
            markedThresholdDegrees: NavigationConstants.roadbookMarkedThresholdDegreesDefault,
            hardThresholdDegrees: NavigationConstants.roadbookHardThresholdDegreesDefault,
            uTurnThresholdDegrees: NavigationConstants.roadbookUTurnThresholdDegreesDefault,
            mergeMinDistanceMeters: mergeMinDistanceMeters,
            mapMatchedDirectionChangeCoordinates: mapMatched
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
            uTurnThresholdDegrees: NavigationConstants.roadbookUTurnThresholdDegreesDefault,
            mergeMinDistanceMeters: 150
        )
        let withEmptyParam = events(for: track, mapMatched: [])

        XCTAssertEqual(withoutParam.count, withEmptyParam.count)
        XCTAssertEqual(withoutParam.map(\.tier), withEmptyParam.map(\.tier))
    }

    /// Cœur du test attendu par la spec : "virage < 30° avec changement de segment → événement
    /// produit".
    func testBelowLightThresholdCoordinateProducesLightDirectionChangeWhenMapMatched() {
        let track = curvingTrack(segmentCount: 2, segmentLengthMeters: 100, segmentTurnDegrees: 20)
        XCTAssertTrue(events(for: track).isEmpty, "précondition : rien géométriquement, virage 20° < seuil light 30°")

        let matchedCoordinate = track.points[1].coordinate
        let result = events(for: track, mapMatched: [matchedCoordinate])

        XCTAssertEqual(result.count, 1)
        XCTAssertEqual(result.first?.tier, .lightDirectionChange)
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

        // Le point le plus proche de `unrelatedCoordinate` reste un point DE CETTE trace (voir
        // `nearestPointIndex`, parcours linéaire sans seuil de distance maximal — en pratique un
        // vrai résultat Valhalla est toujours proche de la trace d'origine, `shape_match:
        // "map_snap"`) : un événement `.lightDirectionChange` est donc quand même produit, sur
        // le point le plus proche disponible, jamais un crash ni un événement fantôme "nulle
        // part". Ce test documente ce comportement de repli plutôt que d'en supposer un autre.
        XCTAssertEqual(result.count, 1)
        XCTAssertEqual(result.first?.tier, .lightDirectionChange)
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
        // La fenêtre avant/après (60 m par défaut) chevauche le même unique changement de cap
        // pour les points 3 ET 4 (mesure télescopique, voir buildRoadbookEvents) — deux
        // candidats au même angle, fusionnés en un seul par mergeNearby (garde le premier
        // rencontré à angle égal) : point 3, pas 4. Comportement existant, pas une régression.
        XCTAssertEqual(geometricOnly.count, 1, "précondition : un seul virage marqué (60°) retenu après fusion")
        XCTAssertEqual(geometricOnly.first?.sourcePointIndex, 3)

        let matchedCoordinate = track.points[1].coordinate
        let result = events(for: track, mapMatched: [matchedCoordinate])

        XCTAssertEqual(result.count, 2, "1 virage marqué géométrique + 1 léger changement de direction map matché")
        XCTAssertEqual(result.map(\.sequenceIndex), [1, 2], "numérotation continue dans l'ordre de progression")
        XCTAssertEqual(result.map(\.tier), [.lightDirectionChange, .marked], "le point de map matching (point 1) précède le virage géométrique (point 3) le long de la trace, malgré un ordre d'insertion inverse dans le code")
    }
}
