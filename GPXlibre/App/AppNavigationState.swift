import Foundation

enum AppTab: Hashable {
    // Spec "search-as-tab" (it19) : `search` ajouté ENTRE `ride` et `library` — reflète l'ordre
    // demandé dans le tab bar (Ride/Loupe/Biblio/Réglages), voir RootView.swift.
    case ride, search, library, settings
}

/// Permet à n'importe quelle vue (ex : "Utiliser pour le Ride" dans le détail d'une trace)
/// de faire basculer l'onglet actif sans casser la navigation existante de la Bibliothèque.
@MainActor
final class AppNavigationState: ObservableObject {
    @Published var selectedTab: AppTab = .ride
}
