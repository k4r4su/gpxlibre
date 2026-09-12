import Foundation

/// Item Réglages #10. "OSM standard" = automatique (suit le mode sombre système, lui-même
/// piloté par l'horaire/luminosité ambiante en "Automatique" iOS) ; Clair/Sombre forcent.
/// "Relief" = tuiles OpenTopoMap (ombrage + courbes de niveau) — source de tuiles différente,
/// pas un simple filtre (voir TileSource).
enum MapThemePreset: String, CaseIterable, Identifiable, Codable {
    case osmStandard, clair, sombre, relief

    var id: String { rawValue }

    var label: String {
        switch self {
        case .osmStandard: return "Standard"
        case .clair: return "Clair"
        case .sombre: return "Sombre"
        case .relief: return "Relief"
        }
    }
}
