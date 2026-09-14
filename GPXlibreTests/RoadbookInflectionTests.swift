import XCTest
import CoreLocation
@testable import GPXlibre

/// Vérifie `RoadbookAnalyzer.buildRoadbookEvents` (spec "roadbook-angle-buckets-replay", it14,
/// Bloc 4 — roadbook rebuilt from scratch, REMPLACE buildCheckpoints/buildInflectionPoints) :
/// la mesure de tangente sur fenêtre avant/après, et la segmentation en paliers d'angle.
final class RoadbookInflectionTests: XCTestCase {
    /// Déplace un point d'un cap/distance donné (formule de destination great-circle).
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

    private func events(for track: GPXTrack, mergeMinDistanceMeters: Double = 50) -> [Checkpoint] {
        RoadbookAnalyzer.buildRoadbookEvents(
            for: track,
            windowBeforeMeters: NavigationConstants.roadbookWindowBeforeMetersDefault,
            windowAfterMeters: NavigationConstants.roadbookWindowAfterMetersDefault,
            lightThresholdDegrees: NavigationConstants.roadbookLightThresholdDegreesDefault,
            markedThresholdDegrees: NavigationConstants.roadbookMarkedThresholdDegreesDefault,
            hardThresholdDegrees: NavigationConstants.roadbookHardThresholdDegreesDefault,
            uTurnThresholdDegrees: NavigationConstants.roadbookUTurnThresholdDegreesDefault,
            mergeMinDistanceMeters: mergeMinDistanceMeters
        )
    }

    /// Cœur de la feature (hérité de "lateral-cap-banner-countdown", it12) : un virage
    /// progressif ("naturel") dont l'angle PAR SEGMENT est faible, mais qui tourne net sur la
    /// fenêtre avant/après complète, doit être détecté — 10 segments de 20 m à 8°, 80° cumulés
    /// sur 200 m, bien au-delà de ce qu'un seuil ponctuel ±20 m capterait.
    func testGradualCurveDetectedViaWindow() {
        let track = curvingTrack(segmentCount: 10, segmentLengthMeters: 20, segmentTurnDegrees: 8)
        let result = events(for: track)
        XCTAssertFalse(result.isEmpty, "l'angle mesuré sur la fenêtre avant/après doit détecter cette courbe progressive")
        XCTAssertEqual(result.first?.direction, .right, "cap croissant = virage à droite")
    }

    /// Une vraie "split" nette (tout l'angle en un point) doit aussi déclencher.
    func testSharpSplitAlsoTriggersAnEvent() {
        let track = curvingTrack(segmentCount: 4, segmentLengthMeters: 30, segmentTurnDegrees: 70)
        XCTAssertFalse(events(for: track).isEmpty)
    }

    /// Une trace parfaitement droite ne doit jamais produire d'événement.
    func testStraightTrackProducesNoEvents() {
        let track = curvingTrack(segmentCount: 10, segmentLengthMeters: 50, segmentTurnDegrees: 0)
        XCTAssertTrue(events(for: track).isEmpty)
    }

    /// Un virage sous le seuil "light" (< 30°) — même isolé — ne doit rien produire (spec :
    /// "< 30° : rien, tout droit, pas affiché"). Segments LONGS (100 m, > fenêtre 60 m) pour
    /// un seul sommet isolé mesuré proprement, sans capter un virage voisin.
    func testBelowLightThresholdProducesNoEvent() {
        let track = curvingTrack(segmentCount: 2, segmentLengthMeters: 100, segmentTurnDegrees: 20)
        XCTAssertTrue(events(for: track).isEmpty)
    }

    /// Deux candidats trop rapprochés fusionnent en un seul (garde l'angle le plus marqué).
    func testNearbyEventsMergeIntoOne() {
        let track = curvingTrack(segmentCount: 10, segmentLengthMeters: 15, segmentTurnDegrees: 8)
        let result = events(for: track, mergeMinDistanceMeters: 150)
        for i in 1..<result.count {
            let distance = RoadbookAnalyzer.distanceMeters(result[i - 1].coordinate, result[i].coordinate)
            XCTAssertGreaterThanOrEqual(distance, 150, "deux événements retenus ne doivent jamais être plus proches que mergeMinDistanceMeters")
        }
    }

    /// Segmentation en paliers (spec "standards marché type Waze/MUTCD") : UN SEUL sommet
    /// (2 segments longs, 100 m > fenêtre 60 m, pour que la mesure ne capte que ce virage)
    /// classé directement selon son angle exact.
    func testAngleBucketsMapToExpectedTiers() {
        let lightTrack = curvingTrack(segmentCount: 2, segmentLengthMeters: 100, segmentTurnDegrees: 35)
        XCTAssertEqual(events(for: lightTrack).first?.tier, .light)

        let markedTrack = curvingTrack(segmentCount: 2, segmentLengthMeters: 100, segmentTurnDegrees: 60)
        XCTAssertEqual(events(for: markedTrack).first?.tier, .marked)

        let hardTrack = curvingTrack(segmentCount: 2, segmentLengthMeters: 100, segmentTurnDegrees: 100)
        XCTAssertEqual(events(for: hardTrack).first?.tier, .hard)

        let uTurnTrack = curvingTrack(segmentCount: 2, segmentLengthMeters: 100, segmentTurnDegrees: 150)
        XCTAssertEqual(events(for: uTurnTrack).first?.tier, .uTurn)
        XCTAssertEqual(events(for: uTurnTrack).first?.direction, .uTurn)
    }
}
