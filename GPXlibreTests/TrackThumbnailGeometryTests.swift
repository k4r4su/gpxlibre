import XCTest
import CoreLocation
@testable import GPXlibre

/// Vérification directe de la projection de la miniature Biblio (spec
/// "biblio-preview-direction", it11) — fonctions pures, aucun disque/GPS/UserDefaults touché.
final class TrackThumbnailGeometryTests: XCTestCase {
    func testProjectionStaysWithinUnitSquareAndTouchesExtremes() {
        let points = [
            GPXPoint(latitude: 45.0, longitude: 5.0),
            GPXPoint(latitude: 45.01, longitude: 5.01),
            GPXPoint(latitude: 45.0, longitude: 5.02),
        ]
        let projection = TrackThumbnailGeometry.project(points: points, chevronSpacingMeters: 500)

        XCTAssertEqual(projection.points.count, points.count)
        for point in projection.points {
            XCTAssertGreaterThanOrEqual(point.x, -0.0001)
            XCTAssertLessThanOrEqual(point.x, 1.0001)
            XCTAssertGreaterThanOrEqual(point.y, -0.0001)
            XCTAssertLessThanOrEqual(point.y, 1.0001)
        }
        // Le point le plus au nord (latitude max) doit être le plus haut à l'écran (y minimal).
        let northIndex = 1
        let minY = projection.points.map(\.y).min()
        XCTAssertEqual(projection.points[northIndex].y, minY!, accuracy: 0.0001)
    }

    func testEmptyOrSinglePointTrackProducesEmptyProjection() {
        XCTAssertTrue(TrackThumbnailGeometry.project(points: [], chevronSpacingMeters: 500).points.isEmpty)
        let single = TrackThumbnailGeometry.project(points: [GPXPoint(latitude: 45, longitude: 5)], chevronSpacingMeters: 500)
        XCTAssertEqual(single.points.count, 1)
        XCTAssertTrue(single.chevrons.isEmpty)
    }

    /// Le cœur de la spec : inverser le sens (points réordonnés, comme fait
    /// TrackSettingsView via `GPXTrack.reordered(using:)`) doit inverser le cap des chevrons
    /// d'environ 180°, sans recalcul GPS — juste la même géométrie parcourue à l'envers.
    func testReversingPointOrderFlipsChevronBearingBy180Degrees() {
        let forwardPoints = [
            GPXPoint(latitude: 45.0, longitude: 0.0),
            GPXPoint(latitude: 45.0, longitude: 0.0127), // ~1000 m est à cette latitude
        ]
        let reversedPoints = Array(forwardPoints.reversed())

        let forward = TrackThumbnailGeometry.project(points: forwardPoints, chevronSpacingMeters: 250)
        let reversed = TrackThumbnailGeometry.project(points: reversedPoints, chevronSpacingMeters: 250)

        XCTAssertFalse(forward.chevrons.isEmpty)
        XCTAssertFalse(reversed.chevrons.isEmpty)

        let forwardBearing = forward.chevrons[0].bearingDegrees
        let reversedBearing = reversed.chevrons[0].bearingDegrees
        let delta = abs(forwardBearing - reversedBearing).truncatingRemainder(dividingBy: 360)
        XCTAssertEqual(min(delta, 360 - delta), 180, accuracy: 1)
    }

    /// Fix "biblio-chevrono-cap" (it14, Bloc 9) : une trace longue avec l'espacement carte
    /// pleine (100 m, défaut it12) produirait des dizaines de chevrons sur la miniature — cap
    /// à 10 maximum, sous-échantillonnés en couvrant TOUTE la trace (pas concentrés au début).
    func testLongTrackCapsChevronCountAndSpreadsEvenly() {
        // ~5 km plein est, 51 points à 100 m — 100 m d'espacement produit ~50 chevrons bruts.
        var points: [GPXPoint] = []
        for i in 0...50 {
            points.append(GPXPoint(latitude: 45.0, longitude: Double(i) * 0.00127))
        }
        let projection = TrackThumbnailGeometry.project(points: points, chevronSpacingMeters: 100)

        XCTAssertLessThanOrEqual(projection.chevrons.count, 10)
        XCTAssertGreaterThanOrEqual(projection.chevrons.count, 5)
        // Répartition sur toute la longueur : le premier chevron doit rester proche du DÉBUT
        // de la trace (x proche de 0) et le dernier proche de la FIN (x proche de 1), pas tous
        // regroupés au départ (ce qu'un simple `prefix(8)` aurait produit).
        guard let first = projection.chevrons.first, let last = projection.chevrons.last else {
            return XCTFail("chevrons attendus sur une trace de 5 km")
        }
        XCTAssertLessThan(first.point.x, 0.3)
        XCTAssertGreaterThan(last.point.x, 0.7)
    }

    func testShortTrackBelowCapIsUnaffected() {
        let points = [
            GPXPoint(latitude: 45.0, longitude: 0.0),
            GPXPoint(latitude: 45.0, longitude: 0.0127),
        ]
        let projection = TrackThumbnailGeometry.project(points: points, chevronSpacingMeters: 250)
        // Même géométrie que DirectionChevronComputerTests.
        // testChevronsAreEvenlySpacedAlongAStraightEastwardSegment (4 chevrons bruts, ~1000 m
        // à 250 m d'espacement) — sous le cap de 10 : liste inchangée, pas de padding
        // artificiel jusqu'à un minimum de 5.
        XCTAssertEqual(projection.chevrons.count, 4)
    }
}
