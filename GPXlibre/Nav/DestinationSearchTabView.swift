import SwiftUI

/// Spec "search-as-tab" (it19, retour terrain : "la loupe passe par-dessus le bandeau/les
/// contrôles Ride, possibilité de la mettre ailleurs ? genre dans le menu Ride/Loupe/Biblio/
/// Réglages") — la recherche de destination ("Aller à") devient un onglet à part entière
/// (voir RootView) plutôt qu'un bouton flottant en haut de la carte Ride, qui entrait
/// systématiquement en collision avec tout ce qui se superpose là (bandeau "Aucune trace
/// sélectionnée", bannières roadbook/hors-trace...).
///
/// Réutilise `NavDestinationSearchView` TEL QUEL (ses propres `dismiss()` internes, pensés
/// pour une présentation en sheet, deviennent des no-op inoffensifs hors contexte de
/// présentation modale — comportement documenté de `\.dismiss`) : seule la sélection change,
/// au lieu de fermer une sheet elle lance le guidage ET bascule automatiquement sur l'onglet
/// Ride pour le montrer, exactement comme fermer l'ancienne sheet révélait RideView derrière.
struct DestinationSearchTabView: View {
    @EnvironmentObject private var session: RideSessionManager
    @EnvironmentObject private var modeStore: RideModeStore
    @EnvironmentObject private var navigationState: AppNavigationState

    var body: some View {
        NavDestinationSearchView { coordinate, label, profile in
            if modeStore.mode == .nav, profile == .route {
                session.startNav(to: coordinate, label: label)
            } else {
                session.startGoTo(to: coordinate, label: label, profile: profile)
            }
            navigationState.selectedTab = .ride
        }
    }
}
