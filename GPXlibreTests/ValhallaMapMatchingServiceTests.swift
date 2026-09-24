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

    /// Fix "roadbook-no-false-uturn" (it26 point 2) : un demi-tour Valhalla n'est CONFIRMÉ que si
    /// la rue d'après (`street_names` du demi-tour) est celle d'avant (`street_names` de la
    /// manœuvre précédente). Rue différente ou sans nom (fréquent en campagne) : non confirmé.
    func testUTurnIsConfirmedOnlyWhenTheStreetBeforeAndAfterIsTheSame() {
        func uTurn(before: [String], after: [String]) -> MapMatchedManeuver? {
            ValhallaMapMatchingService.intermediateManeuvers(maneuvers: [
                ValhallaManeuver(type: ValhallaManeuverType.start.rawValue, beginShapeIndex: 0, streetNames: before),
                ValhallaManeuver(type: ValhallaManeuverType.uturnLeft.rawValue, beginShapeIndex: 1, streetNames: after),
                ValhallaManeuver(type: ValhallaManeuverType.destination.rawValue, beginShapeIndex: 3),
            ], legCoordinates: coordinates).first
        }

        XCTAssertEqual(uTurn(before: ["D 83", "Route de Colmar"], after: ["D 83"])?.isSameRoadUTurn, true)
        XCTAssertEqual(uTurn(before: ["D 83"], after: ["Rue du Moulin"])?.isSameRoadUTurn, false)
        XCTAssertEqual(uTurn(before: [], after: [])?.isSameRoadUTurn, false)
    }

    func testStreetNamesAreDecodedFromTheValhallaManeuverJSON() throws {
        let json = #"{"type":13,"begin_shape_index":2,"street_names":["D 83"]}"#
        let maneuver = try JSONDecoder().decode(ValhallaManeuver.self, from: Data(json.utf8))
        XCTAssertEqual(maneuver.streetNames, ["D 83"])

        let unnamed = try JSONDecoder().decode(ValhallaManeuver.self, from: Data(#"{"type":13,"begin_shape_index":2}"#.utf8))
        XCTAssertEqual(unnamed.streetNames, [])
    }

    /// Fix "roadbook-maneuver-position-from-route" (it26 point 1) : chaque manœuvre porte sa
    /// progression le long de la route recalée ENTIÈRE — tronçons (`legs`) précédents inclus,
    /// jamais relative à son seul tronçon. Deux tronçons de ~3,3 km (points tous les ~1,1 km),
    /// manœuvre au 2e point du SECOND tronçon : ~4,4 km sur ~6,7 km.
    func testRouteProgressFractionSpansAllLegsOfTheMatchedRoute() {
        let firstLeg = coordinates
        let secondLeg = coordinates.map { CLLocationCoordinate2D(latitude: $0.latitude + 0.03, longitude: $0.longitude) }
        let turnInSecondLeg = [
            ValhallaManeuver(type: ValhallaManeuverType.start.rawValue, beginShapeIndex: 0),
            ValhallaManeuver(type: ValhallaManeuverType.right.rawValue, beginShapeIndex: 1),
            ValhallaManeuver(type: ValhallaManeuverType.destination.rawValue, beginShapeIndex: 3),
        ]

        let result = ValhallaMapMatchingService.matchedManeuvers(legs: [
            (maneuvers: [], coordinates: firstLeg),
            (maneuvers: turnInSecondLeg, coordinates: secondLeg),
        ])

        let legLength = TrackProjector.cumulativeDistances(for: firstLeg.map { GPXPoint(latitude: $0.latitude, longitude: $0.longitude) }).last ?? 0
        let expected = (legLength + legLength / 3) / (2 * legLength)
        XCTAssertEqual(result.count, 1)
        XCTAssertEqual(result.first?.routeProgressFraction ?? -1, expected, accuracy: 0.001)
    }
}
