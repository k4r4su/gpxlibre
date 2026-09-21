import XCTest
import CoreLocation
@testable import GPXlibre

/// Spec "valhalla-map-matching-direction-change" (it20), filtrage route-aware ajouté en it24
/// (point 1) — vérifie uniquement la logique PURE d'extraction/filtrage des manœuvres
/// intermédiaires (aucun réseau ici, voir CLAUDE.md pour le pourquoi de `/trace_route` plutôt
/// que `/trace_attributes`).
final class ValhallaMapMatchingServiceTests: XCTestCase {
    private let coordinates = [
        CLLocationCoordinate2D(latitude: 45.00, longitude: 5.00),
        CLLocationCoordinate2D(latitude: 45.01, longitude: 5.00),
        CLLocationCoordinate2D(latitude: 45.02, longitude: 5.00),
        CLLocationCoordinate2D(latitude: 45.03, longitude: 5.00),
    ]

    func testExcludesFirstAndLastManeuverKeepingOnlyIntermediateOnes() {
        let maneuvers = [
            ValhallaManeuver(type: ValhallaManeuverType.start.rawValue, beginShapeIndex: 0), // Départ
            ValhallaManeuver(type: ValhallaManeuverType.right.rawValue, beginShapeIndex: 1), // intermédiaire
            ValhallaManeuver(type: ValhallaManeuverType.left.rawValue, beginShapeIndex: 2), // intermédiaire
            ValhallaManeuver(type: ValhallaManeuverType.destination.rawValue, beginShapeIndex: 3), // Arrivée
        ]

        let result = ValhallaMapMatchingService.intermediateManeuvers(maneuvers: maneuvers, legCoordinates: coordinates)

        XCTAssertEqual(result.count, 2)
        XCTAssertEqual(result[0].coordinate.latitude, coordinates[1].latitude, accuracy: 0.0000001)
        XCTAssertEqual(result[1].coordinate.latitude, coordinates[2].latitude, accuracy: 0.0000001)
    }

    func testFewerThanThreeManeuversProducesNoIntermediateManeuver() {
        let maneuvers = [
            ValhallaManeuver(type: ValhallaManeuverType.start.rawValue, beginShapeIndex: 0),
            ValhallaManeuver(type: ValhallaManeuverType.destination.rawValue, beginShapeIndex: 3),
        ]

        XCTAssertTrue(ValhallaMapMatchingService.intermediateManeuvers(maneuvers: maneuvers, legCoordinates: coordinates).isEmpty)
    }

    func testOutOfBoundsBeginShapeIndexIsSkippedRatherThanCrashing() {
        let maneuvers = [
            ValhallaManeuver(type: ValhallaManeuverType.start.rawValue, beginShapeIndex: 0),
            ValhallaManeuver(type: ValhallaManeuverType.right.rawValue, beginShapeIndex: 999),
            ValhallaManeuver(type: ValhallaManeuverType.destination.rawValue, beginShapeIndex: 3),
        ]

        XCTAssertTrue(ValhallaMapMatchingService.intermediateManeuvers(maneuvers: maneuvers, legCoordinates: coordinates).isEmpty)
    }

    // MARK: - Filtrage route-aware (spec "roadbook-route-aware-maneuvers", it24, point 1)

    /// Cœur du bug terrain corrigé : une manœuvre `.continueStraight` (la route change de nom
    /// SANS virage réel) ne doit jamais devenir un événement roadbook.
    func testContinueStraightIsFilteredOut() {
        let maneuvers = [
            ValhallaManeuver(type: ValhallaManeuverType.start.rawValue, beginShapeIndex: 0),
            ValhallaManeuver(type: ValhallaManeuverType.continueStraight.rawValue, beginShapeIndex: 1),
            ValhallaManeuver(type: ValhallaManeuverType.destination.rawValue, beginShapeIndex: 3),
        ]

        XCTAssertTrue(ValhallaMapMatchingService.intermediateManeuvers(maneuvers: maneuvers, legCoordinates: coordinates).isEmpty)
    }

    /// Même exclusion pour `.becomes` (la route change de nom, toujours sans virage).
    func testBecomesIsFilteredOut() {
        let maneuvers = [
            ValhallaManeuver(type: ValhallaManeuverType.start.rawValue, beginShapeIndex: 0),
            ValhallaManeuver(type: ValhallaManeuverType.becomes.rawValue, beginShapeIndex: 1),
            ValhallaManeuver(type: ValhallaManeuverType.destination.rawValue, beginShapeIndex: 3),
        ]

        XCTAssertTrue(ValhallaMapMatchingService.intermediateManeuvers(maneuvers: maneuvers, legCoordinates: coordinates).isEmpty)
    }

    /// Une vraie manœuvre de virage (`.right`) est conservée — non-régression du cas nominal.
    func testARealTurnIsKept() {
        let maneuvers = [
            ValhallaManeuver(type: ValhallaManeuverType.start.rawValue, beginShapeIndex: 0),
            ValhallaManeuver(type: ValhallaManeuverType.right.rawValue, beginShapeIndex: 1),
            ValhallaManeuver(type: ValhallaManeuverType.destination.rawValue, beginShapeIndex: 3),
        ]

        let result = ValhallaMapMatchingService.intermediateManeuvers(maneuvers: maneuvers, legCoordinates: coordinates)

        XCTAssertEqual(result.count, 1)
        XCTAssertEqual(result.first?.type, .right)
    }

    /// Un rond-point conserve son `roundabout_exit_count`, nécessaire au pictogramme (point 2).
    func testRoundaboutKeepsItsExitCount() {
        let maneuvers = [
            ValhallaManeuver(type: ValhallaManeuverType.start.rawValue, beginShapeIndex: 0),
            ValhallaManeuver(type: ValhallaManeuverType.roundaboutExit.rawValue, beginShapeIndex: 1, roundaboutExitCount: 3),
            ValhallaManeuver(type: ValhallaManeuverType.destination.rawValue, beginShapeIndex: 3),
        ]

        let result = ValhallaMapMatchingService.intermediateManeuvers(maneuvers: maneuvers, legCoordinates: coordinates)

        XCTAssertEqual(result.first?.type, .roundaboutExit)
        XCTAssertEqual(result.first?.roundaboutExitCount, 3)
    }

    /// Un type Valhalla inconnu (`init(rawValue:)` échoue) retombe sur `.none` — filtré comme
    /// n'importe quelle manœuvre non pertinente, jamais un crash sur une future valeur Valhalla.
    func testUnknownTypeFallsBackToNoneAndIsFilteredOut() {
        let maneuvers = [
            ValhallaManeuver(type: ValhallaManeuverType.start.rawValue, beginShapeIndex: 0),
            ValhallaManeuver(type: 999, beginShapeIndex: 1),
            ValhallaManeuver(type: ValhallaManeuverType.destination.rawValue, beginShapeIndex: 3),
        ]

        XCTAssertTrue(ValhallaMapMatchingService.intermediateManeuvers(maneuvers: maneuvers, legCoordinates: coordinates).isEmpty)
    }
}
