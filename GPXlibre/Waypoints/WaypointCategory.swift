import Foundation

enum WaypointCategory: String, Codable, CaseIterable, Identifiable {
    case essence, eau, bivouac, vue, danger
    /// Ajoutés pour le signalement 1-tap Mode Nav (Bloc 2) — local uniquement, pas de
    /// serveur de partage en v1 (voir WaypointCategoryExtensions.navReportCategories).
    case bouchon, attention

    var id: String { rawValue }

    var label: String {
        switch self {
        case .essence: return "Essence"
        case .eau: return "Eau"
        case .bivouac: return "Bivouac"
        case .vue: return "Point de vue"
        case .danger: return "Danger"
        case .bouchon: return "Bouchon"
        case .attention: return "Attention"
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
