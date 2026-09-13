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
}
