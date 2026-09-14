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
    @EnvironmentObject private var vectorPackages: VectorPackageStore
    @EnvironmentObject private var networkMonitor: NetworkMonitor
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
    @State private var toastMessage: String?
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

    /// Fond de carte effectif (spec "vector-pmtiles", it11) — résolu par `MapSourceResolver`
    /// (pur, testable) : paquet vectoriel local actif > vectoriel hébergé (en ligne) > raster
    /// existant (mode avion sans paquet, comportement inchangé). Le raster ne part pas.
    private var activeMapSource: MapSourceSelection {
        MapSourceResolver.resolve(
            activeVectorPackageFileURL: vectorPackages.activeFileURL,
            isNetworkReachable: networkMonitor.isReachable,
            themePreset: settings.mapThemePreset
        )
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
                if let track = library.activeTrack {
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

    /// Le guidage Nav / l'alerte "hors trace" occupent la zone `directionPanelLayer`
    /// (NavGuidancePanelView / RoadbookPanelView, EN HAUT — fix "overlay-layout-grid") — quand
    /// c'est le cas, la caméra doit réserver cette hauteur côté haut (fix "position-anchor"),
    /// sinon le calcul d'ancrage de la position serait faux. Reflète EXACTEMENT la condition
    /// d'affichage de `directionPanelLayer`. Le cas "virage à venir" (Mode Trace, on-track) est
    /// désormais porté par la bannière LATÉRALE (spec "lateral-cap-banner-countdown", it12,
    /// voir lateralCapBannerLayer) — isolée de ce calcul par construction, donc absente d'ici.
    private func hasDirectionPanel(track: GPXTrack?) -> Bool {
        // Spec "stop-guidance-semantics" (it14, Bloc 3) : "roadbook et bannières de guidage se
        // retirent" pendant un guidage arrêté — la détection hors-trace continue de tourner en
        // arrière-plan (session.isOffTrackPaused), seul l'AFFICHAGE se tait.
        guard !session.isGuidanceStopped else { return false }
        switch modeStore.mode {
        case .trace: return session.isOffTrackPaused
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
        case resumeGuidance(ResumeGuidance)
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
            if let resume = session.resumeGuidance { return .resumeGuidance(resume) }
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
        case .resumeGuidance(let guidance):
            ResumeGuidanceCardView(
                guidance: guidance,
                isRequesting: session.isRequestingResume,
                routingError: session.resumeRoutingError,
                birdDistanceMeters: session.currentLocation.map { RoadbookAnalyzer.distanceMeters($0.coordinate, guidance.pinCoordinate) },
                relativeBearingDegrees: resumeRelativeBearingDegrees(to: guidance.pinCoordinate),
                onConfirm: { session.confirmResume() },
                onCancel: { session.cancelResume() }
            )
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

    /// Zone haute (fix "overlay-layout-grid", Bug 3) : segmented Trace/Nav centré, recherche
    /// calée à droite, PUIS au plus une bannière éphémère, PUIS le panneau de direction pleine
    /// largeur — TOUT en haut, rien de tout ça en bas (c'est ce qui se confondait avec la tab
    /// bar). Cette zone n'ignore PAS la safe area (contrairement à mapLayer) : elle évite
    /// automatiquement l'encoche/Dynamic Island, comme n'importe quelle vue SwiftUI normale.
    private func topStackLayer(track: GPXTrack?) -> some View {
        VStack {
            // Nav masqué du contrôle visuel (spec "hide-nav-tab", it12) — Trace actif par
            // défaut (RideModeStore.mode), case vide à dessein là où vivait le Picker. Code
            // Nav (RideMode.nav, RideModeSegmentedControl, tout le branchement .nav ci-dessous)
            // intact : sera relancé dans une itération future, après la trace door-to-door.
            HStack {
                Spacer()
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
                OSMAttributionView(mapSource: activeMapSource)
                Spacer()
            }
            .padding(.horizontal, 8)
            .padding(.top, 4)

            bannerView(activeBanner(track: track))
                .padding(.top, 8)
                .transition(.move(edge: .top).combined(with: .opacity))

            directionPanelLayer
                .padding(.top, 8)
                .transition(.move(edge: .top).combined(with: .opacity))

            Spacer()
        }
        // Fix "panel-consistency" (Bug 6) : fondu + léger slide, jamais d'apparition brute.
        .animation(.easeInOut(duration: 0.2), value: session.isBlockedBannerVisible)
        .animation(.easeInOut(duration: 0.2), value: hasDirectionPanel(track: track))
    }

    /// Panneau de direction (fix "overlay-layout-grid", Bug 3) : EN HAUT, pleine largeur —
    /// jamais en bas, où il se confondait avec la tab bar et masquait la position (Bug 2).
    /// Trace : uniquement l'alerte "hors trace" désormais (le cas "virage à venir" est porté
    /// par la bannière latérale, voir lateralCapBannerLayer et hasDirectionPanel ci-dessus).
    @ViewBuilder
    private var directionPanelLayer: some View {
        if modeStore.mode == .trace, !session.isGuidanceStopped, session.isOffTrackPaused, let offTrackInfo = offTrackPanelInfo {
            RoadbookPanelView(offTrackInfo: offTrackInfo)
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

    /// Cap relatif vers le pin "Reprendre ici" (Bloc 3, mode dégradé sans route) — même
    /// calcul que `offTrackPanelInfo`, réutilisé pour rester cohérent visuellement.
    private func resumeRelativeBearingDegrees(to pin: CLLocationCoordinate2D) -> Double? {
        guard let currentLocation = session.currentLocation else { return nil }
        let targetBearing = RoadbookAnalyzer.bearing(from: currentLocation.coordinate, to: pin)
        return RoadbookAnalyzer.signedAngleDifference(from: session.headingDegrees, to: targetBearing)
    }

    /// Zone "gauche milieu" (spec Bloc 2) : 2D/3D + limite de vitesse en Nav — jamais collé
    /// au bas de l'écran (contrairement à l'ancien layout). Vide en Trace depuis la
    /// suppression du POI rapide (chore "remove-poi", itération 10) : rien ne remplace le
    /// bouton "Point", conformément à la philosophie "moins de boutons".
    @ViewBuilder
    private var leftMiddleLayer: some View {
        if modeStore.mode == .nav {
            HStack {
                VStack {
                    Spacer()
                    VStack(spacing: 10) {
                        Button {
                            is2DNorthUp.toggle()
                        } label: {
                            // Spec "2d-only" (it11) : plus de notion de 3D à afficher (la
                            // carte a toujours été plate depuis ce fix) — l'icône reflète
                            // l'orientation réelle du toggle, cap-en-haut vs nord-en-haut.
                            Image(systemName: is2DNorthUp ? "location.north.circle.fill" : "location.north.line.fill")
                                .font(.title3)
                                .foregroundStyle(.white)
                                .frame(width: 40, height: 40)
                                .background(.black.opacity(0.6))
                                .clipShape(Circle())
                        }
                        .accessibilityLabel(is2DNorthUp ? "Revenir à la vue cap-en-haut" : "Vue nord-en-haut")

                        if let limit = session.currentSpeedLimitKmh {
                            SpeedLimitBadgeView(speedLimitKmh: limit, isOverLimit: session.isOverSpeedLimit)
                        }
                    }
                    Spacer()
                }
                .padding(.leading, 20)
                Spacer()
            }
        }
    }

    /// Colonne de contrôles (fix "overlay-layout-grid", Bug 3 ; côté réglable depuis spec
    /// "controls-side-setting", it14, Bloc 2) : ANCRÉE EN BAS (au-dessus de la tab bar, jamais
    /// au centre) — ordre figé : Me recentrer, bannière roadbook (empilée au-dessus des boutons
    /// de zoom, spec Bloc 2), +, −, Stop, Bloqué/Signaler, espacés uniformément de 12 pt. Le
    /// badge vitesse (`speedoBadgeLayer`) permute TOUJOURS du côté opposé (voir
    /// `RideSettingsStore.controlsSide`) — jamais de chevauchement possible, les deux zones
    /// bougent ensemble. Largeur FIXE (92 pt, celle de la bannière) : l'apparition/disparition
    /// de la bannière ne doit jamais faire bouger horizontalement les boutons en dessous.
    @ViewBuilder
    private var bottomControlsColumn: some View {
        HStack {
            if settings.controlsSide == .right { Spacer() }
            VStack(spacing: RideOverlayLayout.rightStackSpacing) {
                Spacer()
                if session.isManualOverrideActive {
                    RideRecenterButton { session.recenterCamera() }
                }
                // Spec "stop-guidance-semantics" (it14, Bloc 3) : "un état guidage arrêté
                // affiche l'icône play discret... pour relancer si une trace reste selected."
                if session.isGuidanceStopped, library.activeTrack != nil {
                    Button {
                        session.resumeGuidanceAfterStop()
                    } label: {
                        Image(systemName: "play.fill")
                            .font(.system(size: 18, weight: .bold))
                            .foregroundStyle(.white)
                            .frame(width: RideConstants.glovedTapTargetSize, height: RideConstants.glovedTapTargetSize)
                            .background(.green.opacity(0.55), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                    }
                    .accessibilityLabel("Reprendre le guidage")
                    .longPressTooltip("Reprendre le guidage")
                    .transition(.scale.combined(with: .opacity))
                }
                if isLateralBannerVisible, let inflection = session.currentInflection, let distance = session.distanceToCurrentInflectionMeters {
                    LateralCapBannerView(
                        direction: inflection.direction,
                        distanceMeters: distance,
                        sequenceIndex: inflection.sequenceIndex,
                        totalCount: session.inflectionPoints.count
                    )
                    .transition(.ridePanel)
                }
                RideGlovedZoomControls(onZoomIn: { session.zoomIn() }, onZoomOut: { session.zoomOut() })
                RideStopButton { showStopConfirmation = true }
                if modeStore.mode == .trace {
                    BlockedPathButton { showDetourConfirmation = true }
                } else {
                    NavReportButton()
                }
            }
            .frame(width: 92)
            .animation(.easeInOut(duration: 0.2), value: session.isManualOverrideActive)
            .animation(.easeInOut(duration: 0.2), value: session.isGuidanceStopped)
            .animation(.ridePanel, value: isLateralBannerVisible)
            .padding(settings.controlsSide == .right ? .trailing : .leading, 20)
            .padding(.bottom, RideOverlayLayout.cameraInsetMarginBottomPoints)
            if settings.controlsSide == .left { Spacer() }
        }
    }

    /// Badge vitesse (fix "overlay-layout-grid", Bug 3) : ancré juste au-dessus de la tab bar,
    /// TOUJOURS du côté opposé à `bottomControlsColumn` (spec "controls-side-setting", it14) —
    /// zone totalement séparée de la colonne de contrôles, jamais mélangée.
    private var speedoBadgeLayer: some View {
        HStack {
            if settings.controlsSide == .left { Spacer() }
            VStack {
                Spacer()
                if showStatsPanel {
                    RideStatsPanel(
                        currentSpeedKmh: session.rawSpeedKmh,
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
                    RideStatsBadge(currentSpeedKmh: session.rawSpeedKmh) {
                        withAnimation { showStatsPanel = true }
                    }
                }
            }
            .padding(settings.controlsSide == .left ? .trailing : .leading, 20)
            .padding(.bottom, RideOverlayLayout.cameraInsetMarginBottomPoints)
            if settings.controlsSide == .right { Spacer() }
        }
    }

    /// Bannière latérale cap (spec "lateral-cap-banner-countdown", it12) — visible uniquement
    /// pour une VRAIE inflexion dure (angle cumulé > `bannerInflectionThresholdDegrees` sur
    /// `bannerInflectionWindowMeters`, voir RoadbookAnalyzer.buildInflectionPoints), à moins de
    /// `bannerAlertStartMeters`, et jamais pendant l'alerte "hors trace" (message déjà donné en
    /// haut, pas de double message). N'entre JAMAIS dans `hasDirectionPanel`/
    /// `computeMapInsets` — calque isolé, zéro remontée d'ancre/zoom (fix "overlay-never-
    /// pushes").
    private var isLateralBannerVisible: Bool {
        modeStore.mode == .trace
            && !session.isGuidanceStopped
            && !session.isOffTrackPaused
            && session.currentInflection != nil
            && (session.distanceToCurrentInflectionMeters ?? .infinity) <= RideConstants.bannerAlertStartMeters
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
                screenHeight: UIScreen.main.bounds.height,
                hasDirectionPanel: hasDirectionPanel(track: track),
                hasBanner: activeBanner(track: track) != nil,
                isLandscape: geometry.size.width > geometry.size.height,
                // Spec "ride-anchor-lowered-setting" (it14) : le réglage utilisateur ne
                // s'applique qu'en mode suivi cap-en-haut (la "conduite" réelle) — nord-en-haut
                // garde sa valeur centrée fixe, inchangée.
                positionAnchorRatio: is2DNorthUp ? RideConstants.positionAnchorRatio2D : settings.rideAnchorYFraction
            )
            rideContentBody(track: track, insets: insets)
        }
    }

    private func rideContentBody(track: GPXTrack?, insets: RideOverlayLayout.MapInsets) -> some View {
        ZStack(alignment: .bottom) {
            mapLayer(track: track, insets: insets)
                .ignoresSafeArea()

            topStackLayer(track: track)
            leftMiddleLayer
            bottomControlsColumn
            speedoBadgeLayer

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
            // Renommés (spec "offroad-routing-preference", it13) : .offroad route désormais
            // réellement en hors-route (pistes/chemins), ce n'est plus une ligne droite.
            Button("Itinéraire piste (hors-route)") { commitGoTo(profile: .offroad) }
            Button("Mixte (route + piste)") { commitGoTo(profile: .mixed) }
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
            Text("La trace reste affichée et l'enregistrement continue — seuls le roadbook et les bannières de guidage se retirent.")
        }
        .rideToast(message: toastMessage)
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
    /// ou profils piste/mixte y compris en Nav) c'est un guidage parallèle "Aller à"
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

    /// Stop universel (spec "stop-guidance-semantics", it14, Bloc 3, sémantique confirmée) :
    /// arrête le guidage en 1 geste (confirmation déjà passée), reste en vue Ride, trace et
    /// vitesse restent affichées, enregistrement jamais interrompu. Ne propose PLUS l'export
    /// automatiquement (avant it14 : si > 1 km) — Stop n'est plus "terminer la sortie", cette
    /// action reste distincte et déjà accessible via le panneau de stats (RideStatsPanel.
    /// onEndRide), inchangé.
    private func commitStop() {
        session.stopGuidance()
        toastMessage = "Guidage arrêté"
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
                mapSource: activeMapSource,
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
                resumeGuidance: session.resumeGuidance,
                sharedBlockages: sharedBlockages.blockages,
                chevronSpacingMeters: track.map { trackRideSettings.settings(for: $0.id).chevronSpacingMeters } ?? RideConstants.directionArrowSpacingMetersDefault,
                onManualGesture: { session.registerManualGesture() },
                onStatusChange: { mapLoadStatus = $0 },
                onLongPress: { coordinate in
                    pendingGoToCoordinate = coordinate
                    pendingGoToLabel = "Point sur la carte"
                    showGoToActionSheet = true
                },
                onTrackTap: { coordinate, toleranceMeters in
                    handleTrackTap(track: track, coordinate: coordinate, toleranceMeters: toleranceMeters)
                }
            )
        case .mapKit:
            RideMapView(
                track: track,
                checkpoints: session.checkpoints,
                waypoints: track.map { waypointStore.waypoints(near: $0) } ?? [],
                navRoute: session.navRoute,
                traceAppearance: traceAppearance(for: track),
                mapSource: activeMapSource,
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
                resumeGuidance: session.resumeGuidance,
                sharedBlockages: sharedBlockages.blockages,
                chevronSpacingMeters: track.map { trackRideSettings.settings(for: $0.id).chevronSpacingMeters } ?? RideConstants.directionArrowSpacingMetersDefault,
                onManualGesture: { session.registerManualGesture() },
                onStatusChange: { mapLoadStatus = $0 },
                onLongPress: { coordinate in
                    pendingGoToCoordinate = coordinate
                    pendingGoToLabel = "Point sur la carte"
                    showGoToActionSheet = true
                },
                onTrackTap: { coordinate, toleranceMeters in
                    handleTrackTap(track: track, coordinate: coordinate, toleranceMeters: toleranceMeters)
                }
            )
        }
    }

    /// Bloc 3 "resume-at-point" : décision "est-ce assez près de la trace ?" centralisée ici
    /// (comme pour `onLongPress`), jamais dupliquée dans les moteurs de carte. Un seul
    /// guidage à la fois — retaper pendant qu'un guidage existe déjà est ignoré (annuler
    /// d'abord). Trace-only : sans objet en Mode Nav (pas de trace chargée).
    private func handleTrackTap(track: GPXTrack?, coordinate: CLLocationCoordinate2D, toleranceMeters: Double) {
        guard modeStore.mode == .trace, let track, track.points.count > 1, session.resumeGuidance == nil else { return }
        let cumulative = TrackProjector.cumulativeDistances(for: track.points)
        guard let projection = TrackProjector.project(coordinate, onto: track.points, cumulativeDistances: cumulative),
              projection.distanceToTrackMeters <= toleranceMeters,
              let pin = TrackProjector.coordinate(in: track.points, cumulativeDistances: cumulative, atCumulativeDistance: projection.cumulativeDistanceMeters)
        else { return }
        session.requestResume(pinCoordinate: pin, pinCumulativeDistanceMeters: projection.cumulativeDistanceMeters)
    }

    private var emptyState: some View {
        VStack(spacing: 16) {
            // Nav masqué (spec "hide-nav-tab", it12) — voir topStackLayer.
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
