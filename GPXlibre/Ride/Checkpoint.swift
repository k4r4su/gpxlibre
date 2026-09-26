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
        case .left: return String(localized: "Gauche", bundle: .appLanguage)
        case .right: return String(localized: "Droite", bundle: .appLanguage)
        case .straight: return String(localized: "Tout droit", bundle: .appLanguage)
        case .uTurn: return String(localized: "Demi-tour", bundle: .appLanguage)
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
    /// Distance cumulée EXACTE de l'événement le long de la trace (fix "roadbook-maneuver-
    /// position-from-route", it26 point 1). Pour une manœuvre Valhalla, c'est la position du VRAI
    /// carrefour (géométrie recalée) projetée et INTERPOLÉE sur son segment de trace — pas la
    /// distance du point GPX voisin, qui décalait l'annonce de 15 à 120 m selon la densité
    /// d'enregistrement. `nil` = checkpoint construit hors `RoadbookAnalyzer` (tests) : repli
    /// sur `trackCumulativeDistances[sourcePointIndex]`, voir `cumulativeDistanceMeters(using:)`.
    let trackCumulativeDistanceMeters: Double?

    init(
        coordinate: CLLocationCoordinate2D,
        turnAngleDegrees: Double,
        direction: TurnDirection,
        tier: RoadbookTier,
        sequenceIndex: Int,
        sourcePointIndex: Int,
        roundaboutExitCount: Int? = nil,
        trackCumulativeDistanceMeters: Double? = nil
    ) {
        self.coordinate = coordinate
        self.turnAngleDegrees = turnAngleDegrees
        self.direction = direction
        self.tier = tier
        self.sequenceIndex = sequenceIndex
        self.sourcePointIndex = sourcePointIndex
        self.roundaboutExitCount = roundaboutExitCount
        self.trackCumulativeDistanceMeters = trackCumulativeDistanceMeters
    }

    /// Seul point de lecture de la distance cumulée d'un événement (Ride ET Road Book) — jamais
    /// `cumulativeDistances[sourcePointIndex]` directement, qui ignorerait la position exacte.
    func cumulativeDistanceMeters(using trackCumulativeDistances: [Double]) -> Double? {
        if let trackCumulativeDistanceMeters { return trackCumulativeDistanceMeters }
        return trackCumulativeDistances.indices.contains(sourcePointIndex) ? trackCumulativeDistances[sourcePointIndex] : nil
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
    /// Dérivé de la POSITION de l'événement le long de la trace (décimètres) quand elle est
    /// connue — déterministe d'un recalcul à l'autre, et UNIQUE même si deux manœuvres Valhalla
    /// tombent sur le même segment d'une trace peu dense (même point GPX voisin, donc même
    /// `sourcePointIndex` — collision d'id possible avant it26). Repli sur `sourcePointIndex`
    /// sinon, décalé hors de la plage des positions pour ne jamais collisionner avec elles. Deux
    /// parcours DIFFÉRENTS (trace ou sens) peuvent produire le même id : voir `RoadBookTabView`,
    /// qui vide `landmarks` à chaque changement de `traversalKey`.
    var id: UUID { Self.deterministicID(forKey: identityKey) }

    private var identityKey: Int {
        guard let trackCumulativeDistanceMeters else { return Self.indexKeyOffset + max(sourcePointIndex, 0) }
        return Int((max(trackCumulativeDistanceMeters, 0) * 10).rounded())
    }

    /// 2^40 décimètres ≈ 110 millions de km — aucune position réelle n'atteint cette plage.
    private static let indexKeyOffset = 1 << 40

    private static func deterministicID(forKey index: Int) -> UUID {
        let hex = String(format: "%032lx", max(index, 0))
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

    static func == (lhs: Checkpoint, rhs: Checkpoint) -> Bool { lhs.identityKey == rhs.identityKey }
    func hash(into hasher: inout Hasher) { hasher.combine(identityKey) }
}
