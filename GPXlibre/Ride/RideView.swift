import SwiftUI

struct RideView: View {
    @EnvironmentObject private var library: LibraryStore
    @EnvironmentObject private var settings: RideSettingsStore
    @EnvironmentObject private var session: RideSessionManager
    @EnvironmentObject private var navigationState: AppNavigationState

    var body: some View {
        Group {
            if let track = library.selectedTrack {
                rideContent(for: track)
            } else {
                emptyState
            }
        }
    }

    private func rideContent(for track: GPXTrack) -> some View {
        ZStack(alignment: .bottom) {
            RideMapView(
                track: track,
                checkpoints: session.checkpoints,
                currentLocation: session.currentLocation,
                headingDegrees: session.headingDegrees,
                cameraDistanceMeters: session.cameraDistanceMeters,
                northUp: settings.mapOrientationNorthUp,
                isManualOverrideActive: session.isManualOverrideActive,
                onManualGesture: { session.registerManualGesture() }
            )
            .ignoresSafeArea()

            if session.currentCheckpoint != nil || !session.checkpoints.isEmpty {
                RoadbookPanelView(
                    checkpoint: session.currentCheckpoint,
                    totalCount: session.checkpoints.count,
                    distanceMeters: session.distanceToCurrentCheckpointMeters,
                    isClose: session.isCloseToCheckpoint
                )
            }

            FlashOverlayView(trigger: session.flashSequenceToken, flashCount: settings.flashCount)
        }
        .onAppear { session.start(track: track) }
        .onDisappear { session.stop() }
        .onChange(of: track.id) { _ in session.start(track: track) }
        .onChange(of: navigationState.selectedTab) { tab in
            if tab == .ride {
                session.start(track: track)
            } else {
                session.stop()
            }
        }
        .onChange(of: settings.turnThresholdDegrees) { _ in
            session.rebuildCheckpoints()
        }
        .onChange(of: settings.keepScreenAwakeInRide) { _ in
            session.applyIdleTimerSetting()
        }
    }

    private var emptyState: some View {
        VStack(spacing: 16) {
            Image(systemName: "location.slash")
                .font(.system(size: 48))
                .foregroundStyle(.secondary)
            Text("Aucune trace sélectionnée")
                .font(.title2.bold())
            Text("Choisis une trace dans la Bibliothèque, puis \"Utiliser pour le Ride\".")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
            Button("Aller à la Bibliothèque") {
                navigationState.selectedTab = .library
            }
            .buttonStyle(.borderedProminent)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(.systemBackground))
    }
}
