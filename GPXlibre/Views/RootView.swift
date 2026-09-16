import SwiftUI

struct RootView: View {
    @EnvironmentObject private var navigationState: AppNavigationState

    var body: some View {
        TabView(selection: $navigationState.selectedTab) {
            RideView()
                .tabItem { Label("Ride", systemImage: "location.north.line.fill") }
                .tag(AppTab.ride)

            // Spec "search-as-tab" (it19) : recherche de destination sortie de la carte Ride
            // (bouton flottant retiré) pour devenir son propre onglet, entre Ride et Biblio
            // comme demandé.
            DestinationSearchTabView()
                .tabItem { Label("Aller à", systemImage: "magnifyingglass") }
                .tag(AppTab.search)

            LibraryView()
                .tabItem { Label("Biblio", systemImage: "map") }
                .tag(AppTab.library)

            SettingsView()
                .tabItem { Label("Réglages", systemImage: "gearshape") }
                .tag(AppTab.settings)
        }
    }
}
