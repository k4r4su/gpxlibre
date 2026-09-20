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
    /// Cap absolu (0-360°) du segment de trace juste APRÈS la manœuvre — spec "roadbook-mode"
    /// it23quater, retour terrain : référence rallye montrée par le propriétaire, chaque ligne
    /// affiche un cap absolu à suivre après le virage (ex. "304°"), pas seulement une flèche
    /// relative. Calculé dans `RoadbookExtractor` (bearing du segment sortant), jamais stocké
    /// dans `Checkpoint` lui-même (type partagé avec Ride/RideMapLibreView, éviter d'y ajouter
    /// un champ dont ces autres consommateurs n'ont pas besoin).
    let headingDegrees: Double

    var id: UUID { checkpoint.id }
}
