import UIKit

/// Rendu réglable de la trace GPX — épaisseur et couleur (Bloc 3 : réglages 13/14).
/// Défini ici dès le Bloc 1 pour éviter de rechanger la signature de MapProvider deux fois ;
/// branché sur les Réglages au Bloc 3, valeurs par défaut déjà conformes (Gants-épais, orange).
enum TraceWidthPreset: String, CaseIterable, Identifiable, Codable {
    case fine, normale, gantsEpais

    var id: String { rawValue }

    var label: String {
        switch self {
        case .fine: return "Fine"
        case .normale: return "Normale"
        // Renommé "Gants-épais" → "Épais" (fix "thick-label-live-thickness", it13, terrain :
        // libellé jugé confus). rawValue Codable inchangé ("gantsEpais") pour ne pas casser la
        // persistance existante (UserDefaults/JSON par trace) — seul le LABEL affiché change.
        case .gantsEpais: return "Épais"
        }
    }

    /// Épaisseur en points, écran @1x — pensé pour rester lisible au soleil avec des gants.
    var lineWidth: CGFloat {
        switch self {
        case .fine: return 3
        case .normale: return 4.5
        case .gantsEpais: return 6
        }
    }
}

enum TraceColorPreset: String, CaseIterable, Identifiable, Codable {
    case orange, rouge, cyan, jaune, magenta, vertLime

    var id: String { rawValue }

    var label: String {
        switch self {
        case .orange: return "Orange"
        case .rouge: return "Rouge"
        case .cyan: return "Cyan"
        case .jaune: return "Jaune"
        case .magenta: return "Magenta"
        case .vertLime: return "Vert-lime"
        }
    }

    var color: UIColor {
        switch self {
        case .orange: return .systemOrange
        case .rouge: return .systemRed
        case .cyan: return .systemCyan
        case .jaune: return .systemYellow
        case .magenta: return UIColor(red: 0.93, green: 0.13, blue: 0.72, alpha: 1)
        case .vertLime: return UIColor(red: 0.55, green: 0.93, blue: 0.13, alpha: 1)
        }
    }
}

struct TraceAppearance: Equatable {
    var widthPreset: TraceWidthPreset = .gantsEpais
    var colorPreset: TraceColorPreset = .orange
    /// Mode nuit actif : bordure claire plutôt que sombre (Bloc 2/3 — lisibilité par contraste).
    var isNightMode: Bool = false

    var lineWidth: CGFloat { widthPreset.lineWidth }
    var color: UIColor { colorPreset.color }
    /// Contour ("casing") : sombre sur fond clair, clair en mode nuit — jamais par couleur seule.
    var casingColor: UIColor { isNightMode ? .white : .black }
    var casingWidth: CGFloat { lineWidth + 3 }

    /// Le détour reste toujours rouge, pointillé, et 50 % plus épais que la trace — il doit
    /// être plus visible qu'elle, c'est lui qui sauve la balade.
    var detourLineWidth: CGFloat { lineWidth * 1.5 }
}
