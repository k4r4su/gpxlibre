import XCTest
@testable import GPXlibre

/// Spec "routing-active-service-indicator" (it24, point 0) — logique PURE de l'indicateur
/// (aucun réseau ici, voir `RoutingProviderTests` pour la couverture bout-en-bout via la chaîne
/// de repli). Instance FRAÎCHE à chaque test, jamais `.shared`.
@MainActor
final class RoutingActivityMonitorTests: XCTestCase {
    func testStartsWithNoRecentRequest() {
        let monitor = RoutingActivityMonitor()
        XCTAssertNil(monitor.lastEvent)
    }

    func testRecordingASuccessUpdatesTheLastEvent() {
        let monitor = RoutingActivityMonitor()
        let date = Date()

        monitor.recordSuccess(provider: .valhalla, date: date)

        XCTAssertEqual(monitor.lastEvent, RoutingActivityEvent(provider: .valhalla, date: date))
    }

    /// "mis à jour en live à chaque appel de routage réel" — un appel plus récent remplace
    /// toujours le précédent, quel que soit le service.
    func testANewerSuccessOverwritesThePreviousOne() {
        let monitor = RoutingActivityMonitor()
        monitor.recordSuccess(provider: .valhalla, date: Date(timeIntervalSince1970: 0))
        monitor.recordSuccess(provider: .osrm, date: Date(timeIntervalSince1970: 1))

        XCTAssertEqual(monitor.lastEvent?.provider, .osrm)
    }
}
