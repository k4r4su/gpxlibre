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

    /// Détecté via MAP MATCHING Valhalla (spec "valhalla-map-matching-direction-change", it20),
    /// PAS par l'angle géométrique de la trace (qui reste sous `lightThresholdDegrees` par
    /// définition — sinon `.light` l'aurait déjà capturé) : une bifurcation vers une rue/route
    /// différente identifiée par `/trace_route` (changement de manœuvre) sans virage
    /// visuellement marqué sur le tracé GPS lui-même — ex. un léger décalage qui correspond en
    /// réalité à un changement de rue. DISTINCT des 4 paliers ci-dessus, jamais classé parmi eux
    /// (voir RoadbookAnalyzer.buildRoadbookEvents, section map matching).
    case lightDirectionChange

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
        case .lightDirectionChange:
            // Symbole "panneau de signalisation" plutôt qu'une flèche — signale explicitement
            // que ce n'est PAS un virage géométrique classique, mais un changement de rue/route
            // détecté par map matching.
            return direction == .left ? "signpost.left" : "signpost.right"
        }
    }

    var label: String {
        switch self {
        case .light: return "Virage léger"
        case .marked: return "Virage prononcé"
        case .hard: return "Virage fort"
        case .uTurn: return "Demi-tour"
        case .lightDirectionChange: return "Changement de direction"
        }
    }
}
