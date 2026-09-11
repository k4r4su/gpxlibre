import SwiftUI

@main
struct GPXlibreApp: App {
    @StateObject private var library = LibraryStore()
    @StateObject private var settings: RideSettingsStore
    @StateObject private var networkMonitor = NetworkMonitor()
    @StateObject private var rideSession: RideSessionManager
    @StateObject private var navigationState = AppNavigationState()
    @StateObject private var downloadedRegions = DownloadedRegionStore()
    @StateObject private var waypointStore = RollingWaypointStore()
    @StateObject private var rideModeStore = RideModeStore()
    @StateObject private var navFavorites = NavFavoritesStore()

    init() {
        MapLibreBootstrap.configure()
        let settingsStore = RideSettingsStore()
        let monitor = NetworkMonitor()
        let modeStore = RideModeStore()
        _settings = StateObject(wrappedValue: settingsStore)
        _networkMonitor = StateObject(wrappedValue: monitor)
        _rideModeStore = StateObject(wrappedValue: modeStore)
        _rideSession = StateObject(wrappedValue: RideSessionManager(settings: settingsStore, networkMonitor: monitor, modeStore: modeStore))
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(library)
                .environmentObject(settings)
                .environmentObject(rideSession)
                .environmentObject(navigationState)
                .environmentObject(networkMonitor)
                .environmentObject(downloadedRegions)
                .environmentObject(waypointStore)
                .environmentObject(rideModeStore)
                .environmentObject(navFavorites)
                .onOpenURL { url in
                    library.importTrack(from: url)
                }
                .fullScreenCover(isPresented: onboardingBinding) {
                    OnboardingView(isPresented: onboardingBinding)
                        .environmentObject(library)
                        .environmentObject(settings)
                }
        }
    }

    private var onboardingBinding: Binding<Bool> {
        Binding(
            get: { !settings.hasSeenOnboarding },
            set: { isShowing in settings.hasSeenOnboarding = !isShowing }
        )
    }
}
