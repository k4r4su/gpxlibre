import Foundation

enum AppTab: Hashable {
    case ride, library, settings
}

/// Permet à n'importe quelle vue (ex : "Utiliser pour le Ride" dans le détail d'une trace)
/// de faire basculer l'onglet actif sans casser la navigation existante de la Bibliothèque.
@MainActor
final class AppNavigationState: ObservableObject {
    @Published var selectedTab: AppTab = .ride
}
