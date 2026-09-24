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
            veryHardThresholdDegrees: NavigationConstants.roadbookVeryHardThresholdDegreesDefault,
            mergeMinDistanceMeters: mergeMinDistanceMeters
        )
    }

    /// Fix "roadbook-turn-angle-from-heading-chords" — règle produit : une route qui courbe
    /// PROGRESSIVEMENT (80° répartis sur 200 m) n'est pas un changement de direction, 0 checkpoint.
    /// Inverse volontaire de l'ancien test it12 "courbe progressive détectée via la fenêtre" : la
    /// somme des écarts de cap sur des segments entiers additionnait toute la courbe.
    func testAGradualCurveIsNotACheckpoint() {
        let track = curvingTrack(segmentCount: 10, segmentLengthMeters: 20, segmentTurnDegrees: 8)
        XCTAssertTrue(events(for: track).isEmpty)
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
        // 15° tous les 15 m : plusieurs sommets consécutifs dépassent chacun le seuil minimal.
        let track = curvingTrack(segmentCount: 10, segmentLengthMeters: 15, segmentTurnDegrees: 15)
        let result = events(for: track, mergeMinDistanceMeters: 150)
        XCTAssertFalse(result.isEmpty, "précondition : la courbe est bien détectée")
        for i in result.indices.dropFirst() {
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

        // Avant it26, 150° donnait `.uTurn` : c'est précisément le faux demi-tour corrigé.
        let veryHardTrack = curvingTrack(segmentCount: 2, segmentLengthMeters: 100, segmentTurnDegrees: 150)
        XCTAssertEqual(events(for: veryHardTrack).first?.tier, .veryHard)
        XCTAssertEqual(events(for: veryHardTrack).first?.direction, .right)
    }

    // MARK: - Demi-tour = même route en sens inverse (fix "roadbook-no-false-uturn", it26 point 2)

    /// Trace à tours VARIABLES par segment (longueur, virage APRÈS le segment).
    private func track(segments: [(length: Double, turnAfter: Double)]) -> GPXTrack {
        var points = [GPXPoint(latitude: 45.0, longitude: 5.0)]
        var bearing = 0.0
        var coordinate = points[0].coordinate
        for segment in segments {
            coordinate = destination(from: coordinate, bearingDegrees: bearing, distanceMeters: segment.length)
            points.append(GPXPoint(latitude: coordinate.latitude, longitude: coordinate.longitude))
            bearing += segment.turnAfter
        }
        return GPXTrack(id: UUID(), name: "Segments", fileName: "segments.gpx", importDate: Date(), points: points, waypoints: [])
    }

    /// Test demandé par la fiche it26 : un virage de 160° est un changement de route, classé
    /// "virage très serré" AVEC son sens — jamais demi-tour.
    func testA160DegreeTurnIsAVeryTightTurnWithItsSideNeverAUTurn() {
        let right = events(for: curvingTrack(segmentCount: 2, segmentLengthMeters: 100, segmentTurnDegrees: 160))
        XCTAssertEqual(right.first?.tier, .veryHard)
        XCTAssertEqual(right.first?.direction, .right)
        XCTAssertEqual(right.first?.tier.label, "Virage très serré")

        let left = events(for: curvingTrack(segmentCount: 2, segmentLengthMeters: 100, segmentTurnDegrees: -160))
        XCTAssertEqual(left.first?.tier, .veryHard)
        XCTAssertEqual(left.first?.direction, .left)
    }

    /// Épingle/lacet : 180° cumulés sur la fenêtre (deux virages à 90° à 40 m d'écart), mais la
    /// trace repart sur une AUTRE branche, 40 m à côté — même au-delà de 175°, ce n'est pas un
    /// demi-tour. Cas réel : 5 lacets de ce type restaient "demi-tour" sur un seul trajet de
    /// 110 km du propriétaire avec la seule règle d'angle.
    func testAHairpinBeyond175DegreesThatLeavesOnAnotherBranchIsAVeryTightTurn() {
        let hairpin = track(segments: [(300, 90), (40, 90), (300, 0)])
        let result = events(for: hairpin)

        XCTAssertEqual(result.count, 1)
        XCTAssertGreaterThanOrEqual(result.first?.turnAngleDegrees ?? 0, NavigationConstants.roadbookUTurnMinDegrees, "précondition : angle cumulé au-delà du seuil demi-tour")
        XCTAssertEqual(result.first?.tier, .veryHard)
        XCTAssertEqual(result.first?.direction, .right)
    }

    /// Vrai demi-tour : la trace repart EXACTEMENT sur son propre tracé.
    func testAReversalOnTheSamePathIsAUTurn() {
        let reversal = track(segments: [(400, 180), (400, 0)])
        let result = events(for: reversal)

        XCTAssertEqual(result.count, 1)
        XCTAssertEqual(result.first?.tier, .uTurn)
        XCTAssertEqual(result.first?.direction, .uTurn)
    }

    /// Demi-tour dans les premiers mètres (sortie de place, cour) : manœuvre de stationnement,
    /// pas une instruction de parcours — ignoré.
    func testAReversalRightAfterTheStartIsIgnoredAsAParkingManeuver() {
        let parking = track(segments: [(100, 180), (400, 0)])
        XCTAssertFalse(events(for: parking).contains { $0.tier == .uTurn })
    }
}
