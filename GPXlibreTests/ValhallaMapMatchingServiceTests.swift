import XCTest
import CoreLocation
@testable import GPXlibre

/// Spec "valhalla-map-matching-direction-change" (it20) — vérifie uniquement la logique PURE
/// d'extraction des manœuvres intermédiaires (aucun réseau ici, voir CLAUDE.md pour le pourquoi
/// de `/trace_route` plutôt que `/trace_attributes`).
final class ValhallaMapMatchingServiceTests: XCTestCase {
    private let coordinates = [
        CLLocationCoordinate2D(latitude: 45.00, longitude: 5.00),
        CLLocationCoordinate2D(latitude: 45.01, longitude: 5.00),
        CLLocationCoordinate2D(latitude: 45.02, longitude: 5.00),
        CLLocationCoordinate2D(latitude: 45.03, longitude: 5.00),
    ]

    func testExcludesFirstAndLastManeuverKeepingOnlyIntermediateOnes() {
        let maneuvers = [
            ValhallaManeuver(beginShapeIndex: 0), // Départ
            ValhallaManeuver(beginShapeIndex: 1), // intermédiaire
            ValhallaManeuver(beginShapeIndex: 2), // intermédiaire
            ValhallaManeuver(beginShapeIndex: 3), // Arrivée
        ]

        let result = ValhallaMapMatchingService.intermediateManeuverCoordinates(maneuvers: maneuvers, legCoordinates: coordinates)

        XCTAssertEqual(result.count, 2)
        XCTAssertEqual(result[0].latitude, coordinates[1].latitude, accuracy: 0.0000001)
        XCTAssertEqual(result[1].latitude, coordinates[2].latitude, accuracy: 0.0000001)
    }

    func testFewerThanThreeManeuversProducesNoIntermediateCoordinate() {
        let maneuvers = [ValhallaManeuver(beginShapeIndex: 0), ValhallaManeuver(beginShapeIndex: 3)]

        XCTAssertTrue(ValhallaMapMatchingService.intermediateManeuverCoordinates(maneuvers: maneuvers, legCoordinates: coordinates).isEmpty)
    }

    func testOutOfBoundsBeginShapeIndexIsSkippedRatherThanCrashing() {
        let maneuvers = [
            ValhallaManeuver(beginShapeIndex: 0),
            ValhallaManeuver(beginShapeIndex: 999),
            ValhallaManeuver(beginShapeIndex: 3),
        ]

        XCTAssertTrue(ValhallaMapMatchingService.intermediateManeuverCoordinates(maneuvers: maneuvers, legCoordinates: coordinates).isEmpty)
    }
}
