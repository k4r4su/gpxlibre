import XCTest
import CoreLocation
@testable import GPXlibre

/// Spec "roadbook-jump-to-map" — retour terrain : "clic sur un virage dans la liste... aller
/// dans l'onglet Ride pour voir de quel virage on parle".
@MainActor
final class AppNavigationStateTests: XCTestCase {
    func testFocusRideMapSwitchesToTheRideTab() {
        let state = AppNavigationState()
        state.selectedTab = .roadBook

        state.focusRideMap(on: CLLocationCoordinate2D(latitude: 45, longitude: 5))

        XCTAssertEqual(state.selectedTab, .ride)
    }

    func testFocusRideMapSetsTheRequestedCoordinate() {
        let state = AppNavigationState()
        let coordinate = CLLocationCoordinate2D(latitude: 45.1, longitude: 5.2)

        state.focusRideMap(on: coordinate)

        XCTAssertEqual(state.roadBookFocusRequest?.coordinate.latitude, coordinate.latitude)
        XCTAssertEqual(state.roadBookFocusRequest?.coordinate.longitude, coordinate.longitude)
    }

    /// Cœur du besoin : retaper la MÊME ligne (même coordonnée) doit quand même redéclencher le
    /// saut de caméra — sans un jeton qui change, `RoadBookFocusRequest` resterait `==` à
    /// lui-même et `.onChange`/l'environnement SwiftUI ne verrait aucune différence.
    func testCallingTwiceWithTheSameCoordinateProducesADifferentRequest() {
        let state = AppNavigationState()
        let coordinate = CLLocationCoordinate2D(latitude: 45.1, longitude: 5.2)

        state.focusRideMap(on: coordinate)
        let firstRequest = state.roadBookFocusRequest
        state.focusRideMap(on: coordinate)
        let secondRequest = state.roadBookFocusRequest

        XCTAssertNotEqual(firstRequest, secondRequest)
    }
}
