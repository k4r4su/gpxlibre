import XCTest
import CoreLocation
@testable import GPXlibre

/// Spec "rejoin-nearest-by-air" (it19, bug terrain) : le guidage hors-trace doit cibler le
/// point de la trace le plus proche à VOL D'OISEAU parmi TOUS ses points, pas seulement le
/// point suivant dans l'ordre chronologique — reproduit ici le bug exact décrit par le pilote
/// ("point suivant à 15 km par la route, un autre point de la trace à 2 km à vol d'oiseau").
final class TrackProjectorNearestPointTests: XCTestCase {
    private func points(_ coordinates: [(Double, Double)]) -> [GPXPoint] {
        coordinates.map { GPXPoint(latitude: $0.0, longitude: $0.1) }
    }

    func testPicksTheGloballyNearestPointEvenWhenFarInTraceOrder() {
        // index0/1/2 : jambe proche du départ, toutes à plusieurs km de la position testée.
        // index3 (DERNIER point, donc le plus loin possible dans l'ordre chronologique depuis
        // index0) : à seulement ~55 m — c'est LUI qui doit être choisi, pas index1 ("suivant"
        // logique depuis index0, ici à ~5,6 km).
        let trackPoints = points([
            (45.0, 5.0),
            (45.0, 5.01),
            (45.0, 5.02),
            (45.0495, 5.0),
        ])
        let cumulativeDistances = TrackProjector.cumulativeDistances(for: trackPoints)
        let query = CLLocationCoordinate2D(latitude: 45.0495, longitude: 5.0 + 0.00005)

        guard let result = TrackProjector.nearestPointByAirDistance(to: query, in: trackPoints, cumulativeDistances: cumulativeDistances) else {
            return XCTFail("doit trouver un candidat sur une trace non vide")
        }

        XCTAssertEqual(result.coordinate.latitude, trackPoints[3].coordinate.latitude, accuracy: 0.00001)
        XCTAssertEqual(result.coordinate.longitude, trackPoints[3].coordinate.longitude, accuracy: 0.00001)
        XCTAssertEqual(result.cumulativeDistanceMeters, cumulativeDistances[3], accuracy: 0.01)

        // Vérifie explicitement que le point "suivant chronologique" (index1) aurait été un
        // MOINS bon choix — c'est exactement le bug terrain corrigé.
        let chronologicalNextDistance = RoadbookAnalyzer.distanceMeters(query, trackPoints[1].coordinate)
        let chosenDistance = RoadbookAnalyzer.distanceMeters(query, result.coordinate)
        XCTAssertLessThan(chosenDistance, chronologicalNextDistance)
    }

    func testReturnsNilForEmptyTrack() {
        XCTAssertNil(TrackProjector.nearestPointByAirDistance(
            to: CLLocationCoordinate2D(latitude: 45, longitude: 5),
            in: [],
            cumulativeDistances: []
        ))
    }

    func testReturnsNilWhenCumulativeDistancesLengthMismatchesPoints() {
        let trackPoints = points([(45.0, 5.0), (45.0, 5.01)])
        XCTAssertNil(TrackProjector.nearestPointByAirDistance(
            to: CLLocationCoordinate2D(latitude: 45, longitude: 5),
            in: trackPoints,
            cumulativeDistances: [0]
        ))
    }

    func testSinglePointTrackAlwaysReturnsThatPoint() {
        let trackPoints = points([(45.0, 5.0)])
        let cumulativeDistances = TrackProjector.cumulativeDistances(for: trackPoints)
        let result = TrackProjector.nearestPointByAirDistance(
            to: CLLocationCoordinate2D(latitude: 46, longitude: 6),
            in: trackPoints,
            cumulativeDistances: cumulativeDistances
        )
        XCTAssertEqual(result?.coordinate.latitude, 45.0)
        XCTAssertEqual(result?.coordinate.longitude, 5.0)
    }
}
