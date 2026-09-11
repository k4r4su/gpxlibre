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
    let sequenceIndex: Int

    static func == (lhs: Checkpoint, rhs: Checkpoint) -> Bool { lhs.id == rhs.id }
    func hash(into hasher: inout Hasher) { hasher.combine(id) }
}
