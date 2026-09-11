import SwiftUI

struct RootView: View {
    @EnvironmentObject private var navigationState: AppNavigationState

    var body: some View {
        TabView(selection: $navigationState.selectedTab) {
            RideView()
                .tabItem { Label("Ride", systemImage: "location.north.line.fill") }
                .tag(AppTab.ride)

            LibraryView()
                .tabItem { Label("Biblio", systemImage: "map") }
                .tag(AppTab.library)

            SettingsView()
                .tabItem { Label("Réglages", systemImage: "gearshape") }
                .tag(AppTab.settings)
        }
    }
}
