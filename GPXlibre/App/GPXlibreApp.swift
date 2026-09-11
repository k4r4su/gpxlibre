import SwiftUI

@main
struct GPXlibreApp: App {
    @StateObject private var library = LibraryStore()
    @StateObject private var settings: RideSettingsStore
    @StateObject private var rideSession: RideSessionManager
    @StateObject private var navigationState = AppNavigationState()

    init() {
        let settingsStore = RideSettingsStore()
        _settings = StateObject(wrappedValue: settingsStore)
        _rideSession = StateObject(wrappedValue: RideSessionManager(settings: settingsStore))
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(library)
                .environmentObject(settings)
                .environmentObject(rideSession)
                .environmentObject(navigationState)
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
