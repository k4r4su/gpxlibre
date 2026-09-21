import Foundation

/// Spec "routing-active-service-indicator" (it24, point 0) — retour terrain du propriétaire :
/// "le toggle Valhalla est activé côté Réglages, mais il n'y a aujourd'hui aucun moyen de
/// confirmer à l'œil quel service répond réellement à un instant donné (Valhalla, ou repli
/// silencieux vers OSRM)". Enregistre le dernier service ayant EFFECTIVEMENT répondu à une
/// requête de routage RÉELLE — jamais un statut figé au démarrage : mis à jour EN LIVE à chaque
/// appel réussi, quel que soit le chemin de code (`RoutingProviderResolver`, pour le
/// contournement/la reprise hors-trace/le hors-route d'Aller à ; `ValhallaNavigationService`,
/// pour le guidage classique riche d'Aller à — voir `RideSessionManager.requestNavRoute`, seul
/// autre point de code où une requête de ROUTAGE Valhalla part réellement).
///
/// Volontairement AUCUN 4e état "erreur"/"les deux ont échoué" — la fiche n'en demande que 3
/// ("Valhalla" / "OSRM (repli)" / "Aucune requête récente") : un échec total ne change jamais
/// `lastEvent`, il reste sur le dernier service ayant RÉELLEMENT répondu (ou `nil` si aucun
/// appel n'a encore abouti) — ce que "ayant effectivement répondu" veut dire noir sur blanc.
enum RoutingActivityProvider: String, Equatable {
    case valhalla
    case osrm
}

struct RoutingActivityEvent: Equatable {
    let provider: RoutingActivityProvider
    let date: Date
}

/// Même patron que `NetworkMonitor` (Services/) : `@MainActor final class ... : ObservableObject`
/// avec un singleton `shared` pour l'usage réel, mais `init()` reste accessible pour permettre à
/// un test d'instancier une copie ISOLÉE plutôt que de muter l'état partagé (voir
/// `RoutingActivityMonitorTests`).
@MainActor
final class RoutingActivityMonitor: ObservableObject {
    static let shared = RoutingActivityMonitor()

    @Published private(set) var lastEvent: RoutingActivityEvent?

    init() {}

    func recordSuccess(provider: RoutingActivityProvider, date: Date = Date()) {
        lastEvent = RoutingActivityEvent(provider: provider, date: date)
    }
}
