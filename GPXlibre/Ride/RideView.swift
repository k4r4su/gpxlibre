import SwiftUI
import CoreLocation

struct RideView: View {
    @EnvironmentObject private var library: LibraryStore
    @EnvironmentObject private var settings: RideSettingsStore
    @EnvironmentObject private var session: RideSessionManager
    @EnvironmentObject private var navigationState: AppNavigationState
    @EnvironmentObject private var waypointStore: RollingWaypointStore
    @EnvironmentObject private var modeStore: RideModeStore
    @State private var showDetourConfirmation = false
    @State private var showStatsPanel = false
    @State private var showEndRideSheet = false
    @State private var showDestinationSearch = false
    @State private var mapLoadStatus: MapLoadStatus = .loading
    @State private var is2DNorthUp = false
    @Environment(\.colorScheme) private var colorScheme

    /// "OSM standard" (item #10, défaut) = automatique, suit le mode sombre système (lui-même
    /// basé sur l'horaire/la luminosité ambiante en "Automatique" iOS) ; Clair/Sombre forcent.
    private var isNightModeActive: Bool {
        switch settings.mapThemePreset {
        case .osmStandard: return colorScheme == .dark
        case .clair: return false
        case .sombre: return true
        }
    }

    /// Épaisseur/couleur lues en direct depuis les Réglages (items #13/14) — un changement
    /// s'applique immédiatement, partout, sans recharger la trace.
    private var currentTraceAppearance: TraceAppearance {
        TraceAppearance(
            widthPreset: settings.traceWidthPreset,
            colorPreset: settings.traceColorPreset,
            isNightMode: isNightModeActive
        )
    }

    var body: some View {
        Group {
            switch modeStore.mode {
            case .trace:
                if let track = library.selectedTrack {
                    rideContent(track: track)
                } else {
                    emptyState
                }
            case .nav:
                rideContent(track: nil)
            }
        }
    }

    private func rideContent(track: GPXTrack?) -> some View {
        ZStack(alignment: .bottom) {
            mapLayer(track: track)
                .ignoresSafeArea()

            VStack {
                RideModeSegmentedControl(mode: $modeStore.mode)
                    .padding(.top, 8)

                HStack {
                    OSMAttributionView()
                    Spacer()
                }
                .padding(.horizontal, 8)
                .padding(.top, 4)

                if case .failed(let message) = mapLoadStatus {
                    MapLoadWarningBannerView(message: message)
                        .padding(.top, 8)
                }

                if modeStore.mode == .trace {
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
                } else {
                    navStatusBanner
                }

                Spacer()
            }
            .animation(.easeInOut(duration: 0.25), value: session.isBlockedBannerVisible)

            if modeStore.mode == .trace, session.currentCheckpoint != nil || !session.checkpoints.isEmpty {
                RoadbookPanelView(
                    checkpoint: session.currentCheckpoint,
                    totalCount: session.checkpoints.count,
                    distanceMeters: session.distanceToCurrentCheckpointMeters,
                    isClose: session.isCloseToCheckpoint
                )
            }

            if modeStore.mode == .nav, session.navRoute != nil {
                NavGuidancePanelView(
                    maneuver: session.currentManeuver,
                    distanceMeters: session.distanceToCurrentManeuverMeters,
                    destinationLabel: session.navRoute?.destinationLabel ?? "",
                    isRecalculating: session.isRecalculatingRoute
                )
            }

            if modeStore.mode == .trace {
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
            } else {
                HStack {
                    Spacer()
                    VStack {
                        Spacer()
                        NavReportButton()
                            .padding(.trailing, 20)
                            .padding(.bottom, session.navRoute != nil ? 140 : 24)
                    }
                }
            }

            if modeStore.mode == .nav {
                HStack {
                    VStack(spacing: 10) {
                        Button {
                            is2DNorthUp.toggle()
                        } label: {
                            Text(is2DNorthUp ? "3D" : "2D")
                                .font(.caption.bold())
                                .foregroundStyle(.white)
                                .frame(width: 40, height: 40)
                                .background(.black.opacity(0.6))
                                .clipShape(Circle())
                        }
                        .accessibilityLabel(is2DNorthUp ? "Revenir à la vue cap-en-haut" : "Vue 2D nord-en-haut")

                        if let limit = session.currentSpeedLimitKmh {
                            SpeedLimitBadgeView(speedLimitKmh: limit, isOverLimit: session.isOverSpeedLimit)
                        }
                        Spacer()
                    }
                    .padding(.leading, 12)
                    .padding(.top, 90)
                    Spacer()
                }
            }

            HStack {
                Spacer()
                VStack {
                    Spacer()
                    if session.isManualOverrideActive {
                        RideRecenterButton { session.recenterCamera() }
                    }
                    RideGlovedZoomControls(onZoomIn: { session.zoomIn() }, onZoomOut: { session.zoomOut() })
                    Spacer()
                }
                .animation(.easeInOut(duration: 0.2), value: session.isManualOverrideActive)
                .padding(.trailing, 12)
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
                            recordedPointsCount: session.recordedPointsCount,
                            onCollapse: { withAnimation { showStatsPanel = false } },
                            onEndRide: { showEndRideSheet = true }
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
            .padding(.top, 90)
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
        .sheet(isPresented: $showEndRideSheet) {
            EndRideView(
                trackName: track?.name ?? "Sortie Nav",
                points: session.recordedPoints,
                waypoints: track.map { waypointStore.waypoints(near: $0) } ?? [],
                onFinished: { showEndRideSheet = false }
            )
        }
        .sheet(isPresented: $showDestinationSearch) {
            NavDestinationSearchView { coordinate, label in
                session.startNav(to: coordinate, label: label)
            }
        }
        .onAppear { session.start(track: track) }
        .onDisappear { session.stop() }
        .onChange(of: track?.id) { _ in
            guard modeStore.mode == .trace else { return }
            session.start(track: track)
        }
        .onChange(of: navigationState.selectedTab) { tab in
            if tab == .ride {
                session.start(track: modeStore.mode == .trace ? track : nil)
            } else {
                session.stop()
            }
        }
        .onChange(of: modeStore.mode) { newMode in
            switch newMode {
            case .trace:
                session.stopNav()
                session.start(track: track)
            case .nav:
                session.start(track: nil)
            }
        }
        .onChange(of: settings.turnThresholdDegrees) { _ in
            session.rebuildCheckpoints()
        }
        .onChange(of: settings.keepScreenAwakeInRide) { _ in
            session.applyIdleTimerSetting()
        }
    }

    private var navStatusBanner: some View {
        Group {
            if session.navRoute == nil {
                Button {
                    showDestinationSearch = true
                } label: {
                    Label("Choisir une destination", systemImage: "magnifyingglass")
                        .font(.subheadline.bold())
                        .foregroundStyle(.white)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 10)
                        .background(.blue.opacity(0.85))
                        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                }
                .padding(.top, 8)
            } else if let error = session.navRoutingError {
                HStack {
                    Text(error)
                        .font(.subheadline.bold())
                        .foregroundStyle(.white)
                    Spacer()
                    Button("Fermer") { session.stopNav() }
                        .font(.caption.bold())
                        .foregroundStyle(.white)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .background(.red.opacity(0.85))
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                .padding(.horizontal)
                .padding(.top, 8)
            } else if session.isRoutingInProgress {
                HStack(spacing: 8) {
                    ProgressView().tint(.white)
                    Text("Calcul de l'itinéraire…").foregroundStyle(.white).font(.subheadline.bold())
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .background(.blue.opacity(0.85))
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                .padding(.top, 8)
            }
        }
    }

    /// Bascule entre les deux implémentations conformes à MapProvider — MapLibre est le
    /// moteur actif par défaut (MapEngineConstants.active), MapKit reste intact pour
    /// comparaison sans être instancié.
    @ViewBuilder
    private func mapLayer(track: GPXTrack?) -> some View {
        switch MapEngineConstants.active {
        case .mapLibre:
            RideMapLibreView(
                track: track,
                checkpoints: session.checkpoints,
                waypoints: track.map { waypointStore.waypoints(near: $0) } ?? [],
                navRoute: session.navRoute,
                traceAppearance: currentTraceAppearance,
                currentLocation: session.currentLocation,
                headingDegrees: session.headingDegrees,
                cameraDistanceMeters: session.effectiveCameraDistanceMeters,
                northUp: settings.mapOrientationNorthUp,
                is2DNorthUp: is2DNorthUp,
                isManualOverrideActive: session.isManualOverrideActive,
                cameraCommandToken: session.cameraCommandToken,
                detourRoute: session.detourRoute,
                onManualGesture: { session.registerManualGesture() },
                onStatusChange: { mapLoadStatus = $0 },
                onLongPress: { coordinate in
                    guard modeStore.mode == .nav else { return }
                    session.startNav(to: coordinate, label: "Point sur la carte")
                }
            )
        case .mapKit:
            RideMapView(
                track: track,
                checkpoints: session.checkpoints,
                waypoints: track.map { waypointStore.waypoints(near: $0) } ?? [],
                navRoute: session.navRoute,
                traceAppearance: currentTraceAppearance,
                currentLocation: session.currentLocation,
                headingDegrees: session.headingDegrees,
                cameraDistanceMeters: session.effectiveCameraDistanceMeters,
                northUp: settings.mapOrientationNorthUp,
                is2DNorthUp: is2DNorthUp,
                isManualOverrideActive: session.isManualOverrideActive,
                cameraCommandToken: session.cameraCommandToken,
                detourRoute: session.detourRoute,
                onManualGesture: { session.registerManualGesture() },
                onStatusChange: { mapLoadStatus = $0 },
                onLongPress: { coordinate in
                    guard modeStore.mode == .nav else { return }
                    session.startNav(to: coordinate, label: "Point sur la carte")
                }
            )
        }
    }

    private var emptyState: some View {
        VStack(spacing: 16) {
            RideModeSegmentedControl(mode: $modeStore.mode)
                .padding(.bottom, 8)
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
