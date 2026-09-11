import Foundation

/// Item Réglages #10. "OSM standard" = automatique (suit le mode sombre système, lui-même
/// piloté par l'horaire/luminosité ambiante en "Automatique" iOS) ; Clair/Sombre forcent.
enum MapThemePreset: String, CaseIterable, Identifiable, Codable {
    case osmStandard, clair, sombre

    var id: String { rawValue }

    var label: String {
        switch self {
        case .osmStandard: return "OSM standard"
        case .clair: return "Clair"
        case .sombre: return "Sombre"
        }
    }
}
