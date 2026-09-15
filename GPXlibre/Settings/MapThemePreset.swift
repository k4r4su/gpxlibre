import Foundation

/// Item Réglages #10 (spec "map-color-flavors", it19 — remplace l'ancien quatuor Standard/
/// Clair/Sombre/Relief). "Sombre" RETIRÉ de la liste (demande explicite du prompt : le style
/// vectoriel embarqué n'a jamais eu de variante sombre, seul le raster OSM pouvait l'appliquer
/// via un filtre — accroc hors-ligne documenté en it18-bis, TODO.md). "Relief" reste identique
/// (tuiles OpenTopoMap, renommage reporté). Les 3 autres valeurs sont des PALETTES DE COULEUR
/// (voir `MapColorFlavor`) appliquées au MÊME style vectoriel — contrairement à l'ancien système
/// où Standard/Clair étaient déjà, en pratique, rigoureusement identiques (aucune couche de code
/// ne les distinguait), celles-ci produisent un rendu visuellement distinct.
enum MapThemePreset: String, CaseIterable, Identifiable, Codable {
    case standard, hauteContraste, terreux, relief

    var id: String { rawValue }

    var label: String {
        switch self {
        case .standard: return "Standard"
        case .hauteContraste: return "Contraste élevé"
        case .terreux: return "Terreux"
        case .relief: return "Relief"
        }
    }

    /// `nil` pour Relief (raster OpenTopoMap, pas concerné par les palettes de couleur du style
    /// vectoriel) — voir `MapSourceResolver`/`MapEngineConstants.buildVectorStyleJSON`.
    var colorFlavor: MapColorFlavor? {
        switch self {
        case .standard: return .standard
        case .hauteContraste: return .hauteContraste
        case .terreux: return .terreux
        case .relief: return nil
        }
    }
}
