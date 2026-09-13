import XCTest
import CoreLocation
@testable import GPXlibre

/// Vérifie `RoadbookAnalyzer.buildInflectionPoints` (spec "lateral-cap-banner-countdown",
/// it12) — en particulier le cas qui motive cette fonction séparée de `buildCheckpoints` :
/// un virage progressif ("naturel") dont AUCUN point isolé ne dépasse le seuil ponctuel du
/// roadbook, mais qui tourne net sur sa fenêtre glissante.
final class RoadbookInflectionTests: XCTestCase {
    /// Déplace un point d'un cap/distance donné (formule de destination great-circle) — les
    /// tests existants (DirectionChevronComputerTests) construisent leurs traces par simples
    /// décalages de longitude ; une courbe a besoin d'un vrai calcul de destination par cap.
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

    /// Trace qui tourne d'un incrément FIXE de cap à chaque segment (courbe régulière) —
    /// `segmentTurnDegrees` par `segmentLengthMeters`, `segmentCount` segments.
    private func curvingTrack(segmentCount: Int, segmentLengthMeters: Double, segmentTurnDegrees: Double) -> GPXTrack {
        var points = [GPXPoint(latitude: 45.0, longitude: 5.0)]
        var bearing = 0.0
        var coordinate = points[0].coordinate
        for _ in 0..<segmentCount {
            coordinate = destination(from: coordinate, bearingDegrees: bearing, distanceMeters: segmentLengthMeters)
            points.append(GPXPoint(latitude: coordinate.latitude, longitude: coordinate.longitude))
            bearing += segmentTurnDegrees
        }
        return GPXTrack(id: UUID(), name: "Courbe", fileName: "courbe.gpx", importDate: Date(), points: points, waypoints: [])
    }

    /// Cœur de la feature : 10 segments de 20 m, 6° de cap gagnés à chaque segment — delta
    /// ponctuel (~12° avec un lissage ±20 m) largement sous le seuil roadbook par défaut (35°,
    /// `buildCheckpoints` ne détecte donc RIEN ici), mais 60° cumulés sur les ~150 m de fenêtre
    /// — exactement le cas "virage naturel dur" que la bannière latérale doit couvrir.
    func testGradualCurveBelowPerPointThresholdStillTriggersCumulatively() {
        let track = curvingTrack(segmentCount: 10, segmentLengthMeters: 20, segmentTurnDegrees: 6)

        let checkpoints = RoadbookAnalyzer.buildCheckpoints(
            for: track,
            turnThresholdDegrees: RideConstants.turnThresholdDegreesDefault
        )
        XCTAssertTrue(checkpoints.isEmpty, "le seuil ponctuel du roadbook ne doit rien détecter sur une courbe aussi progressive")

        let inflections = RoadbookAnalyzer.buildInflectionPoints(
            for: track,
            thresholdDegrees: RideConstants.bannerInflectionThresholdDegrees,
            windowMeters: RideConstants.bannerInflectionWindowMeters,
            mergeMinDistanceMeters: RideConstants.turnMergeMinDistanceMetersDefault
        )
        XCTAssertFalse(inflections.isEmpty, "l'angle cumulé sur la fenêtre glissante doit déclencher une inflexion")
        XCTAssertEqual(inflections.first?.direction, .right, "cap croissant = virage à droite")
    }

    /// Une vraie "split" nette (tout l'angle dans un petit sous-segment) doit aussi déclencher —
    /// la fenêtre glissante ne doit pas "diluer" un virage déjà net.
    func testSharpSplitAlsoTriggersAnInflection() {
        let track = curvingTrack(segmentCount: 2, segmentLengthMeters: 30, segmentTurnDegrees: 70)

        let inflections = RoadbookAnalyzer.buildInflectionPoints(
            for: track,
            thresholdDegrees: RideConstants.bannerInflectionThresholdDegrees,
            windowMeters: RideConstants.bannerInflectionWindowMeters,
            mergeMinDistanceMeters: RideConstants.turnMergeMinDistanceMetersDefault
        )
        XCTAssertFalse(inflections.isEmpty)
    }

    /// Une trace parfaitement droite ne doit jamais produire d'inflexion.
    func testStraightTrackProducesNoInflections() {
        let track = curvingTrack(segmentCount: 10, segmentLengthMeters: 50, segmentTurnDegrees: 0)
        let inflections = RoadbookAnalyzer.buildInflectionPoints(
            for: track,
            thresholdDegrees: RideConstants.bannerInflectionThresholdDegrees,
            windowMeters: RideConstants.bannerInflectionWindowMeters,
            mergeMinDistanceMeters: RideConstants.turnMergeMinDistanceMetersDefault
        )
        XCTAssertTrue(inflections.isEmpty)
    }

    /// Deux candidats trop rapprochés fusionnent en un seul (garde l'angle le plus marqué) —
    /// même règle de fusion que `buildCheckpoints` (mergeNearby, partagée).
    func testNearbyInflectionsMergeIntoOne() {
        let track = curvingTrack(segmentCount: 10, segmentLengthMeters: 15, segmentTurnDegrees: 8)
        let inflections = RoadbookAnalyzer.buildInflectionPoints(
            for: track,
            thresholdDegrees: RideConstants.bannerInflectionThresholdDegrees,
            windowMeters: RideConstants.bannerInflectionWindowMeters,
            mergeMinDistanceMeters: 150
        )
        for i in 1..<inflections.count {
            let distance = RoadbookAnalyzer.distanceMeters(inflections[i - 1].coordinate, inflections[i].coordinate)
            XCTAssertGreaterThanOrEqual(distance, 150, "deux inflexions retenues ne doivent jamais être plus proches que mergeMinDistanceMeters")
        }
    }
}
