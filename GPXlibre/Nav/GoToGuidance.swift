import Foundation
import CoreLocation

/// "Aller à" universel (Bloc 4) : guidage PARALLÈLE, jamais un remplacement de la trace
/// sacrée ni du Mode Nav principal — toujours en pointillés cyan, distinct de la trace
/// (orange) et du détour (rouge).
enum GoToProfile: String, CaseIterable, Identifiable {
    case route, offroad, mixed

    var id: String { rawValue }

    var label: String {
        switch self {
        case .route: return "Itinéraire"
        case .offroad: return "Vol d'oiseau"
        case .mixed: return "Mixte"
        }
    }

    var systemImageName: String {
        switch self {
        case .route: return "road.lanes"
        case .offroad: return "location.north.line.fill"
        case .mixed: return "arrow.triangle.branch"
        }
    }
}

struct GoToGuidance {
    let coordinates: [CLLocationCoordinate2D]
    let profile: GoToProfile
    let destinationCoordinate: CLLocationCoordinate2D
    let destinationLabel: String
    let computedAt = Date()
}
