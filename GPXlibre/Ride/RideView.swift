import SwiftUI

struct RideView: View {
    @EnvironmentObject private var library: LibraryStore
    @EnvironmentObject private var settings: RideSettingsStore
    @EnvironmentObject private var session: RideSessionManager
    @EnvironmentObject private var navigationState: AppNavigationState
    @EnvironmentObject private var waypointStore: RollingWaypointStore
    @State private var showDetourConfirmation = false
    @State private var showStatsPanel = false

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
            mapLayer(for: track)
                .ignoresSafeArea()

            VStack {
                HStack {
                    OSMAttributionView()
                    Spacer()
                }
                Spacer()
            }
            .padding(8)

            VStack {
                if session.isBlockedBannerVisible {
                    BlockedPathBannerView(
                        onContourner: { showDetourConfirmation = true },
                        onIgnorer: { session.dismissBlockedPathBanner() }
                    )
                    .padding(.top, 8)
                }
                if let detour = session.detourRoute {
                    DetourStatusView(detour: detour, isRequesting: session.isRequestingDetour, onCancel: { session.cancelDetour() })
                }
                Spacer()
            }
            .animation(.easeInOut(duration: 0.25), value: session.isBlockedBannerVisible)

            if session.currentCheckpoint != nil || !session.checkpoints.isEmpty {
                RoadbookPanelView(
                    checkpoint: session.currentCheckpoint,
                    totalCount: session.checkpoints.count,
                    distanceMeters: session.distanceToCurrentCheckpointMeters,
                    isClose: session.isCloseToCheckpoint
                )
            }

            HStack {
                Spacer()
                VStack {
                    Spacer()
                    BlockedPathButton { showDetourConfirmation = true }
                        .padding(.trailing, 20)
                        .padding(.bottom, session.currentCheckpoint != nil ? 140 : 24)
                }
            }

            HStack {
                VStack {
                    Spacer()
                    WaypointQuickAddButton()
                        .padding(.leading, 20)
                        .padding(.bottom, session.currentCheckpoint != nil ? 140 : 24)
                }
                Spacer()
            }

            HStack {
                Spacer()
                VStack {
                    if showStatsPanel {
                        RideStatsPanel(
                            currentSpeedKmh: session.smoothedSpeedKmh,
                            averageSpeedKmh: session.averageSpeedKmh,
                            maxSpeedKmh: session.maxSpeedKmh,
                            distanceRemainingMeters: session.distanceRemainingMeters,
                            percentComplete: session.percentComplete,
                            estimatedArrivalDate: session.estimatedArrivalDate,
                            onCollapse: { withAnimation { showStatsPanel = false } }
                        )
                        .frame(width: 230)
                    } else {
                        RideStatsBadge(currentSpeedKmh: session.smoothedSpeedKmh) {
                            withAnimation { showStatsPanel = true }
                        }
                    }
                    Spacer()
                }
            }
            .padding(.top, 44)
            .padding(.trailing, 12)

            FlashOverlayView(trigger: session.flashSequenceToken, flashCount: settings.flashCount)
        }
        .confirmationDialog("Chemin bloqué", isPresented: $showDetourConfirmation, titleVisibility: .visible) {
            Button("Contourner (route)") { session.requestDetour(profile: .route) }
            Button("Contourner (piste)") { session.requestDetour(profile: .offroad) }
            Button("Rejoindre sans réseau") { session.requestDirectDetour() }
            Button("Annuler", role: .cancel) { session.dismissBlockedPathBanner() }
        } message: {
            Text("La trace d'origine reste affichée telle quelle. Le détour est temporaire.")
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

    /// Bascule entre les deux implémentations conformes à MapProvider — MapLibre est le
    /// moteur actif par défaut (MapEngineConstants.active), MapKit reste intact pour
    /// comparaison sans être instancié.
    @ViewBuilder
    private func mapLayer(for track: GPXTrack) -> some View {
        switch MapEngineConstants.active {
        case .mapLibre:
            RideMapLibreView(
                track: track,
                checkpoints: session.checkpoints,
                waypoints: waypointStore.waypoints(near: track),
                currentLocation: session.currentLocation,
                headingDegrees: session.headingDegrees,
                cameraDistanceMeters: session.cameraDistanceMeters,
                northUp: settings.mapOrientationNorthUp,
                isManualOverrideActive: session.isManualOverrideActive,
                detourRoute: session.detourRoute,
                onManualGesture: { session.registerManualGesture() }
            )
        case .mapKit:
            RideMapView(
                track: track,
                checkpoints: session.checkpoints,
                waypoints: waypointStore.waypoints(near: track),
                currentLocation: session.currentLocation,
                headingDegrees: session.headingDegrees,
                cameraDistanceMeters: session.cameraDistanceMeters,
                northUp: settings.mapOrientationNorthUp,
                isManualOverrideActive: session.isManualOverrideActive,
                detourRoute: session.detourRoute,
                onManualGesture: { session.registerManualGesture() }
            )
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
