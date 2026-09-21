import Foundation
import CoreLocation

enum TurnDirection {
    case left, right, straight, uTurn

    var systemImageName: String {
        switch self {
        case .left: return "arrow.turn.up.left"
        case .right: return "arrow.turn.up.right"
        case .straight: return "arrow.up"
        case .uTurn: return "arrow.uturn.up"
        }
    }

    var label: String {
        switch self {
        case .left: return "Gauche"
        case .right: return "Droite"
        case .straight: return "Tout droit"
        case .uTurn: return "Demi-tour"
        }
    }
}

struct Checkpoint: Identifiable, Hashable {
    let id = UUID()
    let coordinate: CLLocationCoordinate2D
    let turnAngleDegrees: Double
    let direction: TurnDirection
    /// Palier d'angle (spec "roadbook-angle-buckets-replay", it14, Bloc 4) — pilote l'icône
    /// affichée (voir RoadbookTier.systemImageName), DISTINCT de `direction` (gauche/droite).
    let tier: RoadbookTier
    let sequenceIndex: Int
    /// Index dans `GPXTrack.points` d'origine — permet de retrouver la distance cumulée du
    /// checkpoint (`trackCumulativeDistances[sourcePointIndex]`) sans re-projeter sa
    /// coordonnée sur la trace.
    let sourcePointIndex: Int
    /// Rang de la sortie prise dans un rond-point (Valhalla `roundabout_exit_count`, spec
    /// "roadbook-route-aware-maneuvers", it24, point 2) — `nil` sauf `tier == .roundabout`.
    /// Champ SÉPARÉ plutôt qu'une valeur associée sur `RoadbookTier` (même patron que
    /// `direction`, déjà distinct du tier) : évite de casser tous les `switch tier` existants
    /// (map/table/PDF) pour une information optionnelle propre à UN SEUL palier.
    let roundaboutExitCount: Int?

    init(
        coordinate: CLLocationCoordinate2D,
        turnAngleDegrees: Double,
        direction: TurnDirection,
        tier: RoadbookTier,
        sequenceIndex: Int,
        sourcePointIndex: Int,
        roundaboutExitCount: Int? = nil
    ) {
        self.coordinate = coordinate
        self.turnAngleDegrees = turnAngleDegrees
        self.direction = direction
        self.tier = tier
        self.sequenceIndex = sequenceIndex
        self.sourcePointIndex = sourcePointIndex
        self.roundaboutExitCount = roundaboutExitCount
    }

    static func == (lhs: Checkpoint, rhs: Checkpoint) -> Bool { lhs.id == rhs.id }
    func hash(into hasher: inout Hasher) { hasher.combine(id) }
}
