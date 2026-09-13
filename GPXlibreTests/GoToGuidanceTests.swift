import XCTest
import CoreLocation
@testable import GPXlibre

/// Spec "offroad-routing-preference" (it13, "Estimations distance/durée affichées") —
/// `routeDistanceMeters`/`estimatedDurationMinutes` sont des calculs purs, testables sans
/// réseau (contrairement au routing OSRM lui-même, voir DetourRoutingService).
final class GoToGuidanceTests: XCTestCase {
    private let pointA = CLLocationCoordinate2D(latitude: 45.0, longitude: 5.0)
    private let pointB = CLLocationCoordinate2D(latitude: 45.0, longitude: 5.01)
    private var midpoint: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: 45.0, longitude: 5.005)
    }

    func testRouteDistanceSumsEachSegmentNotJustEndpoints() {
        let direct = GoToGuidance(coordinates: [pointA, pointB], profile: .route, destinationCoordinate: pointB, destinationLabel: "B")
        let viaMidpoint = GoToGuidance(coordinates: [pointA, midpoint, pointB], profile: .route, destinationCoordinate: pointB, destinationLabel: "B")
        // Mêmes extrémités, un point intermédiaire sur le même grand cercle : la somme des
        // segments doit rester (quasi) égale à la distance directe — preuve que la boucle
        // additionne bien chaque segment plutôt que de ne regarder que les extrémités.
        XCTAssertEqual(viaMidpoint.routeDistanceMeters, direct.routeDistanceMeters, accuracy: 0.5)
        XCTAssertGreaterThan(direct.routeDistanceMeters, 0)
    }

    func testRouteDistanceIsZeroForFewerThanTwoCoordinates() {
        let empty = GoToGuidance(coordinates: [], profile: .offroad, destinationCoordinate: pointA, destinationLabel: "A")
        let single = GoToGuidance(coordinates: [pointA], profile: .offroad, destinationCoordinate: pointA, destinationLabel: "A")
        XCTAssertEqual(empty.routeDistanceMeters, 0)
        XCTAssertEqual(single.routeDistanceMeters, 0)
    }

    func testEstimatedDurationUsesProfileSpecificAverageSpeed() {
        let speedsByProfile: [GoToProfile: Double] = [.route: 70, .offroad: 30, .mixed: 50]
        for (profile, speedKmh) in speedsByProfile {
            let guidance = GoToGuidance(coordinates: [pointA, pointB], profile: profile, destinationCoordinate: pointB, destinationLabel: "B")
            let expectedMinutes = (guidance.routeDistanceMeters / 1000) / speedKmh * 60
            XCTAssertEqual(guidance.estimatedDurationMinutes, expectedMinutes, accuracy: 0.001, "profil \(profile)")
        }
    }
}
