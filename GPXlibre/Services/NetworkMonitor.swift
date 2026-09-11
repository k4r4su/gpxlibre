import Foundation
import Network

/// Source unique de vérité sur la disponibilité réseau. Utilisé par le détour (contourner
/// en ligne vs guidage direct hors-ligne) et par le pré-cache de tuiles (axes suivants) —
/// pour que le Ride en mode avion reste bien silencieux radio.
@MainActor
final class NetworkMonitor: ObservableObject {
    @Published private(set) var isReachable = false
    @Published private(set) var isExpensiveOrConstrained = false

    private let monitor = NWPathMonitor()
    private let queue = DispatchQueue(label: "GPXlibre.NetworkMonitor")

    init() {
        monitor.pathUpdateHandler = { [weak self] path in
            Task { @MainActor in
                self?.isReachable = path.status == .satisfied
                self?.isExpensiveOrConstrained = path.isExpensive || path.isConstrained
            }
        }
        monitor.start(queue: queue)
    }

    deinit {
        monitor.cancel()
    }
}
