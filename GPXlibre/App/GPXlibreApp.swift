import SwiftUI

@main
struct GPXlibreApp: App {
    @StateObject private var library = LibraryStore()
    @StateObject private var settings: RideSettingsStore
    @StateObject private var networkMonitor = NetworkMonitor()
    @StateObject private var rideSession: RideSessionManager
    @StateObject private var navigationState = AppNavigationState()

    init() {
        MapLibreBootstrap.configure()
        let settingsStore = RideSettingsStore()
        let monitor = NetworkMonitor()
        _settings = StateObject(wrappedValue: settingsStore)
        _networkMonitor = StateObject(wrappedValue: monitor)
        _rideSession = StateObject(wrappedValue: RideSessionManager(settings: settingsStore, networkMonitor: monitor))
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(library)
                .environmentObject(settings)
                .environmentObject(rideSession)
                .environmentObject(navigationState)
                .environmentObject(networkMonitor)
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
