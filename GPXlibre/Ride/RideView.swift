import SwiftUI
import CoreLocation
import UIKit

struct RideView: View {
    @EnvironmentObject private var library: LibraryStore
    @EnvironmentObject private var settings: RideSettingsStore
    @EnvironmentObject private var session: RideSessionManager
    @EnvironmentObject private var navigationState: AppNavigationState
    @EnvironmentObject private var waypointStore: RollingWaypointStore
    @EnvironmentObject private var modeStore: RideModeStore
    @EnvironmentObject private var sharedBlockages: SharedBlockageSyncCoordinator
    @EnvironmentObject private var trackRideSettings: TrackRideSettingsStore
    @State private var showDetourConfirmation = false
    @State private var dismissedSharedBlockageAlertID: String?
    @State private var showStatsPanel = false
    @State private var showEndRideSheet = false
    @State private var showDestinationSearch = false
    @State private var mapLoadStatus: MapLoadStatus = .loading
    @State private var is2DNorthUp = false
    @State private var pendingGoToCoordinate: CLLocationCoordinate2D?
    @State private var pendingGoToLabel = ""
    @State private var showGoToActionSheet = false
    @State private var showStopConfirmation = false
    @Environment(\.colorScheme) private var colorScheme

    /// "OSM standard" (item #10, défaut) = automatique, suit le mode sombre système (lui-même
    /// basé sur l'horaire/la luminosité ambiante en "Automatique" iOS) ; Clair/Sombre forcent.
    private var isNightModeActive: Bool {
        switch settings.mapThemePreset {
        case .osmStandard: return colorScheme == .dark
        case .clair: return false
        case .sombre: return true
        case .relief: return false
        }
    }

    /// Relief (#10) = source de tuiles OpenTopoMap, jamais un simple filtre teinté — voir
    /// TileSource. Le pré-cache doit suivre ce même choix (RideMapLibreView.updateUIView
    /// recharge tout le style quand ça change, en conservant trace/détour/route Nav).
    private var activeTileSource: TileSource {
        TileSource.active(for: settings.mapThemePreset)
    }

    /// Épaisseur/couleur lues en direct depuis les Réglages (items #13/14) — un changement
    /// s'applique immédiatement, partout, sans recharger la trace. Override par trace (spec
    /// "per-track-settings") si défini, sinon le réglage global reste le défaut.
    private func traceAppearance(for track: GPXTrack?) -> TraceAppearance {
        let overrides = track.map { trackRideSettings.settings(for: $0.id) }
        return TraceAppearance(
            widthPreset: overrides?.widthOverride ?? settings.traceWidthPreset,
            colorPreset: overrides?.colorOverride ?? settings.traceColorPreset,
            isNightMode: isNightModeActive
        )
    }

    var body: some View {
        Group {
            switch modeStore.mode {
            case .trace:
                if let track = library.selectedTrack {
                    // Sens A→B/B→A + départ personnalisé (spec "per-track-settings") — appliqués
                    // UNE fois ici, jamais écrits dans le fichier GPX source ; tout le reste
                    // (roadbook, projection, stats, rendu) continue de lire `points` normalement.
                    rideContent(track: track.reordered(using: trackRideSettings.settings(for: track.id)))
                } else {
                    emptyState
                }
            case .nav:
                rideContent(track: nil)
            }
        }
    }

    /// La trace/le guidage Nav occupent la zone `bottomPanel` (RoadbookPanelView /
    /// NavGuidancePanelView) — quand c'est le cas, la caméra doit réserver cette hauteur en
    /// plus de la tab bar (spec "camera-inset"), sinon la position se retrouve cachée dessous.
    private func hasBottomPanel(track: GPXTrack?) -> Bool {
        switch modeStore.mode {
        case .trace: return session.currentCheckpoint != nil || !session.checkpoints.isEmpty
        case .nav: return session.navRoute != nil
        }
    }

    /// Bannières éphémères (spec "overlay-grid") : UNE seule visible à la fois, par priorité —
    /// évite tout empilement/chevauchement, contrairement à l'ancien code qui pouvait afficher
    /// blocage + alerte partagée + "Aller à" simultanément.
    private enum BannerKind {
        case mapLoadError(String)
        case blockedPath
        case detour(DetourRoute)
        case goTo(GoToGuidance)
        case sharedBlockageAlert(SharedBlockage)
        case navChooseDestination
        case navError(String)
        case navRouting
    }

    private func activeBanner(track: GPXTrack?) -> BannerKind? {
        if case .failed(let message) = mapLoadStatus { return .mapLoadError(message) }
        switch modeStore.mode {
        case .trace:
            if session.isBlockedBannerVisible { return .blockedPath }
            if let detour = session.detourRoute { return .detour(detour) }
            if let guidance = session.goToGuidance { return .goTo(guidance) }
            if let alert = nearbySharedBlockageAlert(track: track) { return .sharedBlockageAlert(alert) }
            return nil
        case .nav:
            if let guidance = session.goToGuidance { return .goTo(guidance) }
            if session.navRoute == nil { return .navChooseDestination }
            if let error = session.navRoutingError { return .navError(error) }
            if session.isRoutingInProgress { return .navRouting }
            return nil
        }
    }

    @ViewBuilder
    private func bannerView(_ banner: BannerKind?) -> some View {
        switch banner {
        case nil:
            EmptyView()
        case .mapLoadError(let message):
            MapLoadWarningBannerView(message: message)
        case .blockedPath:
            BlockedPathBannerView(
                onContourner: { showDetourConfirmation = true },
                onIgnorer: { session.dismissBlockedPathBanner() }
            )
        case .detour(let detour):
            DetourStatusView(detour: detour, isRequesting: session.isRequestingDetour, onCancel: { session.cancelDetour() })
        case .goTo(let guidance):
            GoToStatusPillView(
                guidance: guidance,
                distanceMeters: session.goToDistanceRemainingMeters,
                isRequesting: session.isRequestingGoTo,
                onCancel: { session.stopGoTo() }
            )
        case .sharedBlockageAlert(let alert):
            SharedBlockageAlertPillView(blockage: alert, onDismiss: { dismissedSharedBlockageAlertID = alert.id })
        case .navChooseDestination:
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
        case .navError(let error):
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
        case .navRouting:
            HStack(spacing: 8) {
                ProgressView().tint(.white)
                Text("Calcul de l'itinéraire…").foregroundStyle(.white).font(.subheadline.bold())
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background(.blue.opacity(0.85))
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
    }

    /// Zone "topBar" (spec Bloc 2) : segmented Trace/Nav centré, recherche calée à droite,
    /// puis au plus une bannière éphémère en dessous (voir activeBanner/bannerView). Cette
    /// zone n'ignore PAS la safe area (contrairement à mapLayer) : elle évite automatiquement
    /// l'encoche/Dynamic Island, comme n'importe quelle vue SwiftUI normale.
    private func topStackLayer(track: GPXTrack?) -> some View {
        VStack {
            HStack {
                Spacer()
                RideModeSegmentedControl(mode: $modeStore.mode)
                Spacer()
            }
            .overlay(alignment: .trailing) {
                Button {
                    showDestinationSearch = true
                } label: {
                    Image(systemName: "magnifyingglass")
                        .font(.system(size: 16, weight: .bold))
                        .foregroundStyle(.white)
                        .frame(width: 40, height: 40)
                        .background(.black.opacity(0.35))
                        .clipShape(Circle())
                }
                .longPressTooltip("Aller à une adresse ou un lieu")
            }
            .padding(.top, 8)
            .padding(.horizontal, 12)

            HStack {
                OSMAttributionView()
                Spacer()
            }
            .padding(.horizontal, 8)
            .padding(.top, 4)

            bannerView(activeBanner(track: track))
                .padding(.top, 8)

            Spacer()
        }
        .animation(.easeInOut(duration: 0.25), value: session.isBlockedBannerVisible)
    }

    @ViewBuilder
    private var bottomPanelLayer: some View {
        if modeStore.mode == .trace,
           session.currentCheckpoint != nil || !session.checkpoints.isEmpty || session.isOffTrackPaused {
            RoadbookPanelView(
                checkpoint: session.currentCheckpoint,
                nextCheckpoint: session.nextCheckpoint,
                totalCount: session.checkpoints.count,
                distanceMeters: session.distanceToCurrentCheckpointMeters,
                isClose: session.isCloseToCheckpoint,
                offTrackInfo: offTrackPanelInfo
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
    }

    /// Cap vers le point de reprise, RELATIF au cap actuel (spec Bloc 2 "resync-hysteresis") —
    /// 0° = droit devant à l'écran, cohérent avec la caméra cap-en-haut.
    private var offTrackPanelInfo: RoadbookPanelView.OffTrackInfo? {
        guard session.isOffTrackPaused,
              let resumeCoordinate = session.offTrackResumeCoordinate,
              let currentLocation = session.currentLocation
        else { return nil }
        let targetBearing = RoadbookAnalyzer.bearing(from: currentLocation.coordinate, to: resumeCoordinate)
        let relativeBearing = RoadbookAnalyzer.signedAngleDifference(from: session.headingDegrees, to: targetBearing)
        return RoadbookPanelView.OffTrackInfo(relativeBearingDegrees: relativeBearing, distanceMeters: session.offTrackResumeDistanceMeters)
    }

    /// Zone "gauche milieu" (spec Bloc 2) : waypoints rapides en Trace, 2D/3D + limite de
    /// vitesse en Nav — jamais collé au bas de l'écran (contrairement à l'ancien layout).
    @ViewBuilder
    private var leftMiddleLayer: some View {
        HStack {
            VStack {
                Spacer()
                if modeStore.mode == .trace {
                    WaypointQuickAddButton()
                } else {
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
                    }
                }
                Spacer()
            }
            .padding(.leading, 20)
            Spacer()
        }
    }

    /// Zone "droite milieu" + "droite-milieu bas" (spec Bloc 2) : Stop / recentrer / zoom
    /// empilés avec un espacement de 12 pt, puis le bouton critique (Bloqué en Trace,
    /// Signaler en Nav) séparé par un espace visuel dédié — jamais mélangé à la même hauteur
    /// que le badge vitesse (zone topRight, totalement indépendante, voir speedBadgeLayer).
    @ViewBuilder
    private var rightMiddleLayer: some View {
        HStack {
            Spacer()
            VStack(spacing: RideOverlayLayout.rightStackSpacing) {
                Spacer()
                RideStopButton { showStopConfirmation = true }
                if session.isManualOverrideActive {
                    RideRecenterButton { session.recenterCamera() }
                }
                RideGlovedZoomControls(onZoomIn: { session.zoomIn() }, onZoomOut: { session.zoomOut() })
                Spacer().frame(height: 24)
                if modeStore.mode == .trace {
                    BlockedPathButton { showDetourConfirmation = true }
                } else {
                    NavReportButton()
                }
                Spacer()
            }
            .animation(.easeInOut(duration: 0.2), value: session.isManualOverrideActive)
            .padding(.trailing, 20)
        }
    }

    /// Zone "haut-droite" (spec Bloc 2) : badge vitesse TOUJOURS à sa place fixe, hors zone
    /// bannières — décalage calculé pour la place PIRE cas (bannière visible), jamais un
    /// simple magic number, pour garantir zéro chevauchement même quand une bannière apparaît.
    private var speedBadgeLayer: some View {
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
            .padding(.top, RideOverlayLayout.topBarHeight + RideOverlayLayout.bannerHeight + RideOverlayLayout.cameraInsetMarginTopPoints)
            .padding(.trailing, 12)
        }
    }

    /// Point d'entrée : mesure la VRAIE safe area (encoche/Dynamic Island en haut ; tab bar +
    /// home indicator combinés en bas) par comparaison de coordonnées GLOBALES plutôt que via
    /// `GeometryProxy.safeAreaInsets` — cette dernière s'est avérée peu fiable ici : un
    /// GeometryReader qui ignore lui-même la safe area (essayé dans une itération précédente
    /// de ce fix) rapportait 0, confirmé visuellement (segmented control chevauchant
    /// l'encoche). En laissant CE reader respecter normalement la safe area, son
    /// `frame(in: .global).minY` est exactement la vraie marge haute, et
    /// `écran - frame.maxY` la vraie marge basse (tab bar comprise, celle-ci étant injectée
    /// par SwiftUI comme safe area supplémentaire pour le contenu d'un onglet de TabView).
    /// Seul `mapLayer` ignore la safe area (voir rideContentBody) ; le reste de l'UI l'évite
    /// normalement, comme avant ce fix.
    private func rideContent(track: GPXTrack?) -> some View {
        GeometryReader { geometry in
            let frame = geometry.frame(in: .global)
            let safeAreaTop = frame.minY
            let safeAreaBottom = max(UIScreen.main.bounds.height - frame.maxY, 0)
            let insets = RideOverlayLayout.computeMapInsets(
                safeAreaTop: safeAreaTop,
                safeAreaBottom: safeAreaBottom,
                hasBottomPanel: hasBottomPanel(track: track),
                hasBanner: activeBanner(track: track) != nil,
                isLandscape: geometry.size.width > geometry.size.height
            )
            rideContentBody(track: track, insets: insets)
        }
    }

    private func rideContentBody(track: GPXTrack?, insets: RideOverlayLayout.MapInsets) -> some View {
        ZStack(alignment: .bottom) {
            mapLayer(track: track, insets: insets)
                .ignoresSafeArea()

            topStackLayer(track: track)
            bottomPanelLayer
            leftMiddleLayer
            rightMiddleLayer
            speedBadgeLayer

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
        .confirmationDialog(
            pendingGoToLabel,
            isPresented: $showGoToActionSheet,
            titleVisibility: .visible
        ) {
            Button("Itinéraire ici (route)") { commitGoTo(profile: .route) }
            Button("Y aller à vol d'oiseau") { commitGoTo(profile: .offroad) }
            Button("Mixte (route + vol d'oiseau)") { commitGoTo(profile: .mixed) }
            Button("Annuler", role: .cancel) { pendingGoToCoordinate = nil }
        } message: {
            Text("La trace chargée n'est jamais modifiée par ce guidage.")
        }
        .confirmationDialog(
            "Arrêter le guidage ?",
            isPresented: $showStopConfirmation,
            titleVisibility: .visible
        ) {
            Button("Arrêter", role: .destructive) { commitStop() }
            Button("Continuer", role: .cancel) {}
        } message: {
            Text("La caméra se libère et les panneaux se masquent. L'enregistrement en cours est mis en pause.")
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
            NavDestinationSearchView { coordinate, label, profile in
                if modeStore.mode == .nav, profile == .route {
                    session.startNav(to: coordinate, label: label)
                } else {
                    session.startGoTo(to: coordinate, label: label, profile: profile)
                }
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
                // switchMode (pas start) : un simple retour d'onglet ne doit jamais réinitialiser
                // le zoom (spec "camera-mode-stability", Bloc 5 — "pas de fit-bounds non désiré").
                session.switchMode(track: modeStore.mode == .trace ? track : nil)
            } else {
                session.stop()
            }
        }
        .onChange(of: modeStore.mode) { newMode in
            switch newMode {
            case .trace:
                session.stopNav()
                session.switchMode(track: track)
            case .nav:
                session.switchMode(track: nil)
            }
        }
        .onChange(of: settings.turnThresholdDegrees) { _ in
            session.rebuildCheckpoints()
        }
        .onChange(of: settings.turnMergeMinDistanceMeters) { _ in
            session.rebuildCheckpoints()
        }
        .onChange(of: settings.keepScreenAwakeInRide) { _ in
            session.applyIdleTimerSetting()
        }
    }

    /// "Itinéraire ici" en Mode Nav démarre directement le guidage principal (voix +
    /// tour-par-tour, c'est exactement le rôle du Mode Nav) ; partout ailleurs (Mode Trace,
    /// ou profils vol d'oiseau/mixte y compris en Nav) c'est un guidage parallèle "Aller à"
    /// qui ne touche jamais la trace chargée.
    private func commitGoTo(profile: GoToProfile) {
        guard let coordinate = pendingGoToCoordinate else { return }
        let label = pendingGoToLabel
        pendingGoToCoordinate = nil
        if modeStore.mode == .nav, profile == .route {
            session.startNav(to: coordinate, label: label)
        } else {
            session.startGoTo(to: coordinate, label: label, profile: profile)
        }
    }

    /// Stop universel (spec Bloc 4) : état propre en 1 geste (confirmation déjà passée),
    /// propose l'export seulement si plus d'1 km a été enregistré.
    private func commitStop() {
        let distance = session.recordedDistanceMeters
        session.stopGuidance()
        is2DNorthUp = false
        if distance > 1000 {
            showEndRideSheet = true
        }
    }

    /// Spec Bloc 5 : pill d'alerte si la trace chargée passe à moins de 300 m d'un point
    /// bloqué connu de la base partagée — masquée pour la session en cours après un tap
    /// sur la croix (pas une suppression définitive, juste ignorée jusqu'au prochain point).
    private func nearbySharedBlockageAlert(track: GPXTrack?) -> SharedBlockage? {
        guard let track,
              let nearest = sharedBlockages.nearestKnownBlockage(alongTrackPoints: track.points.map(\.coordinate)),
              nearest.id != dismissedSharedBlockageAlertID
        else { return nil }
        return nearest
    }

    /// Bascule entre les deux implémentations conformes à MapProvider — MapLibre est le
    /// moteur actif par défaut (MapEngineConstants.active), MapKit reste intact pour
    /// comparaison sans être instancié.
    @ViewBuilder
    private func mapLayer(track: GPXTrack?, insets: RideOverlayLayout.MapInsets) -> some View {
        switch MapEngineConstants.active {
        case .mapLibre:
            RideMapLibreView(
                track: track,
                checkpoints: session.checkpoints,
                waypoints: track.map { waypointStore.waypoints(near: $0) } ?? [],
                navRoute: session.navRoute,
                traceAppearance: traceAppearance(for: track),
                tileSource: activeTileSource,
                currentLocation: session.currentLocation,
                headingDegrees: session.headingDegrees,
                cameraDistanceMeters: session.effectiveCameraDistanceMeters,
                cameraContentInsetTop: insets.cameraTop,
                cameraContentInsetBottom: insets.cameraBottom,
                cameraContentInsetLeft: insets.cameraLeft,
                cameraContentInsetRight: insets.cameraRight,
                northUp: settings.mapOrientationNorthUp,
                is2DNorthUp: is2DNorthUp,
                isManualOverrideActive: session.isManualOverrideActive,
                cameraCommandToken: session.cameraCommandToken,
                detourRoute: session.detourRoute,
                goToGuidance: session.goToGuidance,
                sharedBlockages: sharedBlockages.blockages,
                chevronSpacingMeters: track.map { trackRideSettings.settings(for: $0.id).chevronSpacingMeters } ?? RideConstants.directionArrowSpacingMetersDefault,
                onManualGesture: { session.registerManualGesture() },
                onStatusChange: { mapLoadStatus = $0 },
                onLongPress: { coordinate in
                    pendingGoToCoordinate = coordinate
                    pendingGoToLabel = "Point sur la carte"
                    showGoToActionSheet = true
                }
            )
        case .mapKit:
            RideMapView(
                track: track,
                checkpoints: session.checkpoints,
                waypoints: track.map { waypointStore.waypoints(near: $0) } ?? [],
                navRoute: session.navRoute,
                traceAppearance: traceAppearance(for: track),
                tileSource: activeTileSource,
                currentLocation: session.currentLocation,
                headingDegrees: session.headingDegrees,
                cameraDistanceMeters: session.effectiveCameraDistanceMeters,
                cameraContentInsetTop: insets.cameraTop,
                cameraContentInsetBottom: insets.cameraBottom,
                cameraContentInsetLeft: insets.cameraLeft,
                cameraContentInsetRight: insets.cameraRight,
                northUp: settings.mapOrientationNorthUp,
                is2DNorthUp: is2DNorthUp,
                isManualOverrideActive: session.isManualOverrideActive,
                cameraCommandToken: session.cameraCommandToken,
                detourRoute: session.detourRoute,
                goToGuidance: session.goToGuidance,
                sharedBlockages: sharedBlockages.blockages,
                chevronSpacingMeters: track.map { trackRideSettings.settings(for: $0.id).chevronSpacingMeters } ?? RideConstants.directionArrowSpacingMetersDefault,
                onManualGesture: { session.registerManualGesture() },
                onStatusChange: { mapLoadStatus = $0 },
                onLongPress: { coordinate in
                    pendingGoToCoordinate = coordinate
                    pendingGoToLabel = "Point sur la carte"
                    showGoToActionSheet = true
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
