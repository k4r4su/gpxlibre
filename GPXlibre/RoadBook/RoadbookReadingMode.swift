import Foundation

/// Deux modes de lecture du Road Book (spec "roadbook-mode", it23, point 1) :
/// - `.gpsAssisted` : countdown de distance qui diminue avec la position RÉELLE — recalculé de
///   façon totalement indépendante du Ride actif (voir `RoadbookLiveProgress`), jamais via
///   `RideSessionManager`.
/// - `.classic` : distances FIXES précalculées entre points, aucun countdown live — esprit
///   roadbook papier de rallye, l'utilisateur suit avec son propre compteur kilométrique.
///
/// Les DEUX modes lisent EXACTEMENT la même liste `[RoadbookManeuver]` (une seule source de
/// vérité, comme l'export PDF) — seul l'AFFICHAGE de la distance jusqu'à la prochaine manœuvre
/// diffère, jamais deux listes ou deux calculs de distance partielle/cumulée séparés.
enum RoadbookReadingMode: String, CaseIterable, Identifiable, Codable {
    case gpsAssisted, classic

    var id: String { rawValue }

    var label: String {
        switch self {
        case .gpsAssisted: return "Assisté GPS"
        case .classic: return "Roadbook classique"
        }
    }

    var description: String {
        switch self {
        case .gpsAssisted: return "La distance jusqu'à la prochaine manœuvre diminue avec ta position réelle."
        case .classic: return "Distances fixes précalculées — suis avec ton propre compteur kilométrique, esprit rallye papier."
        }
    }
}
