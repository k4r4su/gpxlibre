import Foundation

/// Une ligne du Road Book (spec "roadbook-mode", it23) — la MÊME donnée qu'un `Checkpoint` du
/// roadbook embarqué Ride (voir `RoadbookAnalyzer`/`Ride/CLAUDE.md`), enrichie des distances
/// partielle/cumulée nécessaires à un affichage façon roadbook papier de rallye. Type-valeur
/// pur, produit par `RoadbookExtractor` — aucune dépendance à `RideSessionManager` ni à
/// `LibraryStore` : le Road Book lit une trace en entrée, il ne pilote rien (spec, point 1).
struct RoadbookManeuver: Identifiable, Hashable {
    let checkpoint: Checkpoint
    /// Distance depuis la manœuvre précédente (ou depuis le départ de la trace pour la
    /// première manœuvre de la liste).
    let partialDistanceMeters: Double
    /// Distance cumulée depuis le départ de la trace.
    let cumulativeDistanceMeters: Double

    var id: UUID { checkpoint.id }
}
