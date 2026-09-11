import Foundation

enum WaypointCategory: String, Codable, CaseIterable, Identifiable {
    case essence, eau, bivouac, vue, danger

    var id: String { rawValue }

    var label: String {
        switch self {
        case .essence: return "Essence"
        case .eau: return "Eau"
        case .bivouac: return "Bivouac"
        case .vue: return "Point de vue"
        case .danger: return "Attention"
        }
    }

    var systemImageName: String {
        switch self {
        case .essence: return "fuelpump.fill"
        case .eau: return "drop.fill"
        case .bivouac: return "tent.fill"
        case .vue: return "binoculars.fill"
        case .danger: return "exclamationmark.triangle.fill"
        }
    }
}
