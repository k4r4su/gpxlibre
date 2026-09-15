import Foundation
import CoreLocation

/// "Reprendre la trace ici" (Bloc 3, itération 10) : le rider tape plus loin sur la trace
/// affichée (hors-trace, en forêt) pour être guidé par la route jusqu'à ce point précis
/// plutôt que de continuer à l'aveugle en offroad. Ne modifie JAMAIS `track`/checkpoints —
/// un guidage parallèle, réversible à tout instant, en miroir du détour existant
/// (`DetourRoute`/`DetourRoutingService`).
enum ResumePhase {
    /// Pin posé, distance à vol d'oiseau visible immédiatement, itinéraire en cours de calcul
    /// ou déjà reçu — le roadbook normal continue de tourner en tâche de fond, rien n'est
    /// figé tant que l'utilisateur n'a pas confirmé (réversible sans aucune conséquence).
    case previewing
    /// Confirmé : la progression normale du roadbook est gelée, le guidage suit la route
    /// (ou le vol d'oiseau en mode dégradé) jusqu'à la jonction avec la trace.
    case active
}

struct ResumeGuidance {
    let pinCoordinate: CLLocationCoordinate2D
    /// Position du pin sur la trace (déjà réordonnée si sens/départ personnalisés), en
    /// distance cumulée depuis le premier point — permet de resynchroniser les checkpoints
    /// sans reprojeter le pin (même patron que `Checkpoint.sourcePointIndex`).
    let pinCumulativeDistanceMeters: Double
    /// Vide tant que non calculé, ou en mode dégradé (pas de réseau) — jamais de tracé
    /// fantôme dans ce cas, juste le pin.
    var routeCoordinates: [CLLocationCoordinate2D] = []
    /// true dès qu'OSRM a répondu (preview ou active) — un pin fraîchement posé démarre à
    /// false le temps du calcul.
    var isRouted = false
    var routeDistanceMeters: Double?
    var phase: ResumePhase
    /// Distingue l'origine du guidage (spec "link-recompute-on-divergence"/"rejoin-trace-
    /// guidance-banner", it18, Blocs 3/5) : `false` (défaut) = tap manuel sur la trace,
    /// bannière du haut avec confirmation (ResumeGuidanceCardView) ; `true` = divergence
    /// soutenue détectée automatiquement (RideSessionManager.updateAutoRecompute) — démarre
    /// directement en phase `.active` (pas de confirmation demandée), affichage via la
    /// bannière latérale dédiée (RejoinGuidanceBannerView) plutôt que la bannière du haut.
    var isAutomatic = false
    let startedAt = Date()
}
