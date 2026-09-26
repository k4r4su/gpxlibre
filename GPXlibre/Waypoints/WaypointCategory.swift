import Foundation

enum WaypointCategory: String, Codable, CaseIterable, Identifiable {
    case essence, eau, bivouac, vue, danger
    /// Ajoutés pour le signalement 1-tap Mode Nav (Bloc 2) — local uniquement, pas de
    /// serveur de partage en v1 (voir WaypointCategoryExtensions.navReportCategories).
    case bouchon, attention

    var id: String { rawValue }

    var label: String {
        switch self {
        case .essence: return String(localized: "Essence", bundle: .appLanguage)
        case .eau: return String(localized: "Eau", bundle: .appLanguage)
        case .bivouac: return String(localized: "Bivouac", bundle: .appLanguage)
        case .vue: return String(localized: "Point de vue", bundle: .appLanguage)
        case .danger: return String(localized: "Danger", bundle: .appLanguage)
        case .bouchon: return String(localized: "Bouchon", bundle: .appLanguage)
        case .attention: return String(localized: "Attention", bundle: .appLanguage)
        }
    }

    var systemImageName: String {
        switch self {
        case .essence: return "fuelpump.fill"
        case .eau: return "drop.fill"
        case .bivouac: return "tent.fill"
        case .vue: return "binoculars.fill"
        case .danger: return "exclamationmark.triangle.fill"
        case .bouchon: return "car.fill"
        case .attention: return "exclamationmark.circle.fill"
        }
    }
}
