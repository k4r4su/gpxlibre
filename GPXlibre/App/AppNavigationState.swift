import Foundation
import CoreLocation

enum AppTab: Hashable {
    // Spec "search-as-tab" (it19) : `search` ajouté ENTRE `ride` et `library` — reflète l'ordre
    // demandé dans le tab bar (Ride/Loupe/Biblio/Réglages), voir RootView.swift.
    // Spec "roadbook-mode" (it23) : `roadBook` ajouté ENTRE `search` et `library` — nouvel
    // onglet dédié, totalement découplé de l'état de Ride actif (voir RoadBook/CLAUDE.md).
    case ride, search, roadBook, library, settings
}

/// Spec "roadbook-jump-to-map" — retour terrain : "quand on clique sur un virage dans la
/// liste, est-ce que ça peut aller dans l'onglet Ride pour voir de quel virage on parle... il
/// faut aussi un indicateur pour savoir lequel c'est". Porte la coordonnée à cibler sur la
/// carte Ride + un jeton unique : une coordonnée seule ne changerait pas si on retape la MÊME
/// ligne (SwiftUI ne détecterait alors aucune différence), le jeton force le redéclenchement.
struct RoadBookFocusRequest: Equatable {
    let coordinate: CLLocationCoordinate2D
    let token: UUID

    static func == (lhs: Self, rhs: Self) -> Bool { lhs.token == rhs.token }
}

/// Permet à n'importe quelle vue (ex : "Utiliser pour le Ride" dans le détail d'une trace)
/// de faire basculer l'onglet actif sans casser la navigation existante de la Bibliothèque.
@MainActor
final class AppNavigationState: ObservableObject {
    @Published var selectedTab: AppTab = .ride
    @Published var roadBookFocusRequest: RoadBookFocusRequest?

    /// Point d'entrée UNIQUE pour "montre-moi ce point sur la carte Ride" (spec
    /// "roadbook-jump-to-map") — utilisé par `RoadBookTabView`, jamais un accès direct de ce
    /// module à `RideSessionManager` (invariant "Road Book totalement découplé de l'état de
    /// Ride actif", voir RoadBook/CLAUDE.md) : cette classe reste le SEUL point de passage
    /// entre les deux onglets.
    func focusRideMap(on coordinate: CLLocationCoordinate2D) {
        roadBookFocusRequest = RoadBookFocusRequest(coordinate: coordinate, token: UUID())
        selectedTab = .ride
    }
}
