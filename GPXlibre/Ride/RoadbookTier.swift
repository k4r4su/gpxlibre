import Foundation

/// Palier d'angle du roadbook (spec "roadbook-angle-buckets-replay", it14, Bloc 4 — segmentation
/// inspirée des standards marché type Waze/MUTCD pour la signalisation de virage) :
///
/// - < 30° : rien (tout droit, pas affiché — voir RoadbookAnalyzer.buildRoadbookEvents)
/// - 30-44° : `.light` — virage léger
/// - 45-89° : `.marked` — virage prononcé
/// - 90-134° : `.hard` — virage fort
/// - ≥ 135° : `.uTurn` — demi-tour
enum RoadbookTier: Equatable {
    case light, marked, hard, uTurn

    /// Icône DISTINCTE par palier (demandé explicitement) — combinée à `TurnDirection` pour
    /// distinguer gauche/droite, sauf `.uTurn` (une seule icône, symétrique par nature).
    func systemImageName(direction: TurnDirection) -> String {
        switch self {
        case .light:
            return direction == .left ? "arrow.up.left" : "arrow.up.right"
        case .marked:
            return direction == .left ? "arrow.turn.up.left" : "arrow.turn.up.right"
        case .hard:
            return direction == .left ? "arrow.turn.down.left" : "arrow.turn.down.right"
        case .uTurn:
            return "arrow.uturn.up"
        }
    }

    var label: String {
        switch self {
        case .light: return "Virage léger"
        case .marked: return "Virage prononcé"
        case .hard: return "Virage fort"
        case .uTurn: return "Demi-tour"
        }
    }
}
