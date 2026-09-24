import XCTest
import CoreLocation
@testable import GPXlibre

/// Itération corrective "fiabilité des checkpoints du Road Book" — retour terrain : "Virage fort"
/// (-90°, et même 0°) là où la trace continue tout droit sur la même route, surtout aux croisements
/// de chemins forestiers/sentiers. Règle produit : pas de vrai changement de direction = pas de
/// checkpoint. Voir `RoadbookAnalyzer.headingChange` pour la cause racine corrigée.
final class RoadbookCheckpointReliabilityTests: XCTestCase {
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

    /// Segments (longueur, virage APRÈS le segment) ; `pointSpacing` > 0 découpe chaque segment en
    /// points réguliers (trace enregistrée dense), sinon un point par sommet (trace planifiée).
    private func track(_ segments: [(length: Double, turnAfter: Double)], pointSpacing: Double = 0) -> GPXTrack {
        var coordinate = CLLocationCoordinate2D(latitude: 47.6, longitude: 7.4)
        var points = [GPXPoint(latitude: coordinate.latitude, longitude: coordinate.longitude)]
        var bearing = 0.0
        for segment in segments {
            let steps = pointSpacing > 0 ? max(Int((segment.length / pointSpacing).rounded()), 1) : 1
            for _ in 0..<steps {
                coordinate = destination(from: coordinate, bearingDegrees: bearing, distanceMeters: segment.length / Double(steps))
                points.append(GPXPoint(latitude: coordinate.latitude, longitude: coordinate.longitude))
            }
            bearing += segment.turnAfter
        }
        return GPXTrack(id: UUID(), name: "Fiabilité", fileName: "f.gpx", importDate: Date(), points: points, waypoints: [])
    }

    private func maneuvers(_ track: GPXTrack, mapMatched: [MapMatchedManeuver] = []) -> [RoadbookManeuver] {
        RoadbookExtractor.maneuvers(
            for: track,
            windowBeforeMeters: NavigationConstants.roadbookWindowBeforeMetersDefault,
            windowAfterMeters: NavigationConstants.roadbookWindowAfterMetersDefault,
            lightThresholdDegrees: NavigationConstants.roadbookLightThresholdDegreesDefault,
            markedThresholdDegrees: NavigationConstants.roadbookMarkedThresholdDegreesDefault,
            hardThresholdDegrees: NavigationConstants.roadbookHardThresholdDegreesDefault,
            veryHardThresholdDegrees: NavigationConstants.roadbookVeryHardThresholdDegreesDefault,
            mergeMinDistanceMeters: RideConstants.turnMergeMinDistanceMetersDefault,
            mapMatchedManeuvers: mapMatched
        )
    }

    private func point(_ track: GPXTrack, atMeters meters: Double) -> CLLocationCoordinate2D {
        TrackProjector.interpolatedCoordinate(atCumulativeDistance: meters, points: track.points, cumulativeDistances: TrackProjector.cumulativeDistances(for: track.points))!
    }

    // MARK: - Tout droit = aucun checkpoint

    /// Trace droite qui croise plusieurs chemins forestiers/sentiers latéraux : Valhalla y renvoie
    /// des manœuvres (la trace, elle, ne tourne pas) — 0 checkpoint.
    func testAStraightTraceCrossingSideTracksHasNoCheckpoint() {
        let straight = track([(1500, 0)], pointSpacing: 20)
        let crossings: [(Double, ValhallaManeuverType)] = [(300, .right), (600, .slightLeft), (900, .left), (1200, .sharpRight)]
        let mapMatched = crossings.map { MapMatchedManeuver(coordinate: point(straight, atMeters: $0.0), type: $0.1, roundaboutExitCount: nil) }

        XCTAssertTrue(maneuvers(straight, mapMatched: mapMatched).isEmpty)
    }

    /// Cause racine du retour terrain : un point GPX DUPLIQUÉ (segment de 0 m, cap fictif de 0°) sur
    /// une ligne droite peu dense injectait deux faux virages de ±90°.
    func testADuplicatedPointOnAStraightSparseTraceIsNotACheckpoint() {
        var points = track([(300, 0), (0.0001, 0), (239, 0), (300, 0)]).points
        points.insert(points[2], at: 2) // doublon exact
        let sparse = GPXTrack(id: UUID(), name: "Doublon", fileName: "d.gpx", importDate: Date(), points: points, waypoints: [])

        XCTAssertTrue(maneuvers(sparse).isEmpty)
    }

    /// Route qui courbe progressivement sans changer de nom (90° sur 600 m) : 0 checkpoint.
    func testAGradualCurveOnTheSameRoadHasNoCheckpoint() {
        let curve = track(Array(repeating: (20.0, 3.0), count: 30), pointSpacing: 20)
        XCTAssertTrue(maneuvers(curve).isEmpty)
    }

    // MARK: - Vrais changements de direction

    /// Vrai virage à angle droit (100°, loin de la frontière fort/prononcé de 90°) : 1 checkpoint,
    /// libellé et sens cohérents avec l'angle calculé, cap affiché = cap suivi APRÈS (0-360°).
    func testARealRightAngleTurnIsOneCoherentCheckpoint() {
        let turn = track([(400, -100), (400, 0)], pointSpacing: 20)
        let result = maneuvers(turn)

        XCTAssertEqual(result.count, 1)
        XCTAssertEqual(result.first?.checkpoint.tier, .hard)
        XCTAssertEqual(result.first?.checkpoint.tier.label, "Virage fort")
        XCTAssertEqual(result.first?.checkpoint.direction, .left)
        XCTAssertEqual(result.first?.checkpoint.turnAngleDegrees ?? 0, 100, accuracy: 3)
        XCTAssertEqual(result.first?.cumulativeDistanceMeters ?? 0, 400, accuracy: 25)
        XCTAssertEqual(result.first?.headingDegrees ?? 0, 260, accuracy: 3, "cap vers l'ouest, jamais négatif")
    }

    /// Réplique géométrique (synthétique) de la trace du retour terrain autour de 20,5 km : nord,
    /// vrai virage à gauche de ~102°, 31 m, point dupliqué, puis ~600 m tout droit plein ouest.
    /// Avant : "Virage fort" décalé sur le doublon (cap affiché 0°) ET "Virage fort" fantôme 240 m
    /// plus loin (cap -89°). Après : un seul checkpoint, au vrai sommet, cap ~270°.
    func testTheFieldReportGeometryHasOneCheckpointAtTheRealTurnOnly() {
        var points = track([(400, -102), (31, 0), (0.0001, 0), (239, 0), (58, 0), (302, 0)]).points
        points.insert(points[2], at: 2)
        let field = GPXTrack(id: UUID(), name: "Terrain", fileName: "t.gpx", importDate: Date(), points: points, waypoints: [])

        let result = maneuvers(field)

        XCTAssertEqual(result.count, 1, "plus de 'Virage fort' fantôme sur la ligne droite qui suit")
        XCTAssertEqual(result.first?.cumulativeDistanceMeters ?? 0, 400, accuracy: 1, "au vrai sommet, pas sur le point dupliqué 31 m plus loin")
        XCTAssertEqual(result.first?.checkpoint.direction, .left)
        XCTAssertEqual(result.first?.checkpoint.turnAngleDegrees ?? 0, 102, accuracy: 5)
        XCTAssertEqual(result.first?.checkpoint.tier.label, "Virage fort")
        XCTAssertEqual(result.first?.headingDegrees ?? 0, 258, accuracy: 5, "cap moyen après le virage, jamais le 0° d'un segment de 0 m")
    }

    func testARoundaboutAndAForkOnAStraightTraceAreKept() {
        let straight = track([(1500, 0)], pointSpacing: 20)
        let result = maneuvers(straight, mapMatched: [
            MapMatchedManeuver(coordinate: point(straight, atMeters: 400), type: .roundaboutExit, roundaboutExitCount: 2),
            MapMatchedManeuver(coordinate: point(straight, atMeters: 1000), type: .stayLeft, roundaboutExitCount: nil),
        ])

        XCTAssertEqual(result.map(\.checkpoint.tier), [.roundabout, .fork])
    }

    /// Libellé/sens toujours issus de la géométrie de la trace suivie, jamais de la catégorie
    /// Valhalla (qui peut décrire l'angle vers une branche latérale) : Valhalla dit "léger à
    /// droite" sur un carrefour où la trace tourne de 100° à GAUCHE → un seul checkpoint, gauche,
    /// "Virage fort".
    func testAValhallaTurnNeverOverridesTheLabelOrSideOfTheTraceGeometry() {
        let turn = track([(400, -100), (400, 0)], pointSpacing: 20)
        let result = maneuvers(turn, mapMatched: [MapMatchedManeuver(coordinate: point(turn, atMeters: 400), type: .slightRight, roundaboutExitCount: nil)])

        XCTAssertEqual(result.count, 1)
        XCTAssertEqual(result.first?.checkpoint.direction, .left)
        XCTAssertEqual(result.first?.checkpoint.tier.label, "Virage fort")
    }

    // MARK: - Virages rapprochés

    /// Deux virages dans le MÊME sens à moins de `roadbookTurnClusterMeters` : un seul checkpoint,
    /// portant le virage net (épingle : 2 × 90° → 180°, "très serré").
    func testTwoCloseSameSideTurnsMergeIntoOneWithTheNetAngle() {
        let hairpin = track([(300, 90), (35, 90), (300, 0)], pointSpacing: 5)
        let result = maneuvers(hairpin)

        XCTAssertEqual(result.count, 1)
        XCTAssertEqual(result.first?.checkpoint.direction, .right)
        XCTAssertEqual(result.first?.checkpoint.tier, .veryHard)
    }

    /// Aller-retour de cap parasite (zigzag d'un artefact de matching) : gauche puis droite aussitôt,
    /// cap final inchangé — ignoré.
    func testAZigzagArtifactIsIgnored() {
        let zigzag = track([(300, -40), (15, 40), (300, 0)], pointSpacing: 5)
        XCTAssertTrue(maneuvers(zigzag).isEmpty)
    }

    /// Deux vrais virages bien séparés : tous les deux conservés, distances partielle ET cumulée
    /// recalculées après filtrage (partielle = depuis le checkpoint CONSERVÉ précédent).
    func testTwoSeparatedTurnsAreBothKeptWithRecomputedDistances() {
        let chicane = track([(300, 0), (0.0001, 0), (300, 90), (500, -90), (300, 0)], pointSpacing: 20)
        let result = maneuvers(chicane)

        XCTAssertEqual(result.map(\.checkpoint.direction), [.right, .left])
        XCTAssertEqual(result[0].cumulativeDistanceMeters, 600, accuracy: 25)
        XCTAssertEqual(result[1].cumulativeDistanceMeters, 1100, accuracy: 25)
        XCTAssertEqual(result[1].partialDistanceMeters, result[1].cumulativeDistanceMeters - result[0].cumulativeDistanceMeters, accuracy: 0.001)
    }

    /// Cohérence libellé/angle : sur toute trace, jamais un checkpoint "virage" sous le seuil minimal.
    func testNoTurnLabelBelowTheMinimalAngle() {
        let wiggly = track((0..<60).map { ($0.isMultiple(of: 2) ? 12.0 : 18.0, $0.isMultiple(of: 3) ? 14.0 : -9.0) })
        for maneuver in maneuvers(wiggly) where [.light, .marked, .hard, .veryHard].contains(maneuver.checkpoint.tier) {
            XCTAssertGreaterThanOrEqual(maneuver.checkpoint.turnAngleDegrees, NavigationConstants.roadbookLightThresholdDegreesDefault)
        }
    }
}
