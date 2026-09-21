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

    /// Fix "roadbook-landmark-id-stability" (retour terrain, session it25 : "il n'y a que des
    /// flèches, pas d'emoji de repère" — jamais un seul ne s'affichait). Root cause :
    /// `let id = UUID()` générait un id ALÉATOIRE à CHAQUE construction, or
    /// `RoadBookTabView.maneuvers` est une propriété CALCULÉE réévaluée à chaque rendu SwiftUI
    /// (chaque fix GPS en mode Assisté) — les `Checkpoint` du même point de la trace obtenaient
    /// donc un id DIFFÉRENT à chaque rendu, désynchronisant immédiatement
    /// `RoadBookTabView.landmarks: [UUID: RoadbookLandmarkInfo?]` (rempli une fois avec les ids
    /// du PREMIER rendu) de la liste réellement affichée l'instant d'après.
    ///
    /// `sourcePointIndex` est stable et UNIQUE PAR TRACE (`mergeNearby`/
    /// `mergingMapMatchedDirectionChanges` ne produisent jamais deux checkpoints au même index)
    /// tant que la trace/les réglages de détection ne changent pas — un id dérivé de cette seule
    /// valeur reste donc identique d'un recalcul à l'autre. Deux traces DIFFÉRENTES peuvent
    /// partager le même `sourcePointIndex` : voir `RoadBookTabView`, qui vide `landmarks` au
    /// changement de trace pour ne jamais laisser un repère d'une autre trace s'y mélanger.
    var id: UUID { Self.deterministicID(forSourcePointIndex: sourcePointIndex) }

    private static func deterministicID(forSourcePointIndex index: Int) -> UUID {
        let hex = String(format: "%032x", max(index, 0))
        let last32 = String(hex.suffix(32))
        let uuidString = [
            last32.prefix(8),
            last32.dropFirst(8).prefix(4),
            last32.dropFirst(12).prefix(4),
            last32.dropFirst(16).prefix(4),
            last32.dropFirst(20).prefix(12),
        ].joined(separator: "-")
        return UUID(uuidString: uuidString) ?? UUID()
    }

    static func == (lhs: Checkpoint, rhs: Checkpoint) -> Bool { lhs.sourcePointIndex == rhs.sourcePointIndex }
    func hash(into hasher: inout Hasher) { hasher.combine(sourcePointIndex) }
}
