import Foundation

/// Deux identités qui ne se mélangent JAMAIS : en Trace la trace GPX est sacrée (jamais
/// modifiée/recalculée) ; en Nav le guidage recalcule automatiquement, comme un GPS classique.
enum RideMode: String, CaseIterable, Identifiable {
    case trace
    case nav

    var id: String { rawValue }

    var label: String {
        switch self {
        case .trace: return "Trace"
        case .nav: return "Nav"
        }
    }
}

@MainActor
final class RideModeStore: ObservableObject {
    @Published var mode: RideMode = .trace
}
