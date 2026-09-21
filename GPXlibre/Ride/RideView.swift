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
    @State private var mapLoadStatus: MapLoadStatus = .loading
    /// Spec "ride-empty-state-shows-map" (it19) : dismissible mais volontairement PAS persisté
    /// (UserDefaults/etc.) — redevient `false` (bandeau visible) à chaque retour sur l'onglet
    /// Ride depuis un autre onglet (voir `.onChange(of: navigationState.selectedTab)` plus bas),
    /// demande explicite du propriétaire plutôt qu'un "masqué pour de bon".
    @State private var isNoTrackBannerDismissed = false
    /// Spec "ride-restarts-from-zero-on-tab-return" (it19) — voir `.onAppear` plus bas :
    /// distingue le vrai premier lancement de RideView (start, réinitialise vraiment tout) de
    /// tout retour ultérieur sur l'onglet Ride (switchMode, préserve les stats en cours).
    @State private var hasStartedRideSession = false
    @State private var is2DNorthUp = false
    /// Spec "replay-marker-heading-x2" (it17, Bloc 4) : force cap-en-haut pendant un replay
    /// debug si le toggle du menu est activé — NE modifie JAMAIS `is2DNorthUp` lui-même (le
    /// vrai réglage de l'utilisateur reste intact, repris tel quel dès que le replay s'arrête).
    /// `session.debugReplayForcesHeadingUp` reste `false` en usage normal (voir
    /// RideSessionManager.debugSetReplayActive, jamais écrit hors DebugReplayDriver).
    private var effectiveIs2DNorthUp: Bool {
        session.debugReplayForcesHeadingUp ? false : is2DNorthUp
    }
    @State private var pendingGoToCoordinate: CLLocationCoordinate2D?
    @State private var pendingGoToLabel = ""
    @State private var showGoToActionSheet = false
    @State private var showStopConfirmation = false
    @State private var toastMessage: String?
    @Environment(\.colorScheme) private var colorScheme

    /// Spec "map-color-flavors" (it19) : le thème "Sombre" a été retiré (n'existait que côté
    /// raster) — les 3 flavors vectoriels suivent désormais tous automatiquement le mode sombre
    /// système (comme l'ancien "OSM standard"), Relief reste inchangé (pas de variante nuit,
    /// image raster pré-rendue).
    private var isNightModeActive: Bool {
        settings.mapThemePreset != .relief && colorScheme == .dark
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
                // Fix "ride-empty-state-shows-map" (it19, retour terrain : "si pas de trace
                // sélectionnée ça n'affiche rien à part 'aucune trace sélectionnée', on
                // pourrait pas afficher la carte quand même ?") — `rideContent(track: nil)`
                // fonctionne déjà (c'est exactement ce que le Mode Nav, masqué de l'UI depuis
                // it12, utilise) : plus besoin d'un `emptyState` séparé qui masquait toute la
                // carte. Le bandeau "Aucune trace sélectionnée" (dismissible, voir
                // `noActiveTrackBannerLayer`) remplace ce même message, posé PAR-DESSUS la
                // carte au lieu de la remplacer.
                if let track = library.activeTrack {
                    // Sens A→B/B→A + départ personnalisé (spec "per-track-settings") — appliqués
                    // UNE fois ici, jamais écrits dans le fichier GPX source ; tout le reste
                    // (roadbook, projection, stats, rendu) continue de lire `points` normalement.
                    rideContent(track: track.reordered(using: trackRideSettings.settings(for: track.id)))
                } else {
                    rideContent(track: nil)
                }
            case .nav:
                rideContent(track: nil)
            }
        }
    }

    /// Le guidage Nav occupe la zone `directionPanelLayer` (NavGuidancePanelView, EN HAUT —
    /// fix "overlay-layout-grid") — quand c'est le cas, la caméra doit réserver cette hauteur
    /// côté haut (fix "position-anchor"), sinon le calcul d'ancrage de la position serait faux.
    /// Reflète EXACTEMENT la condition d'affichage de `directionPanelLayer`. Le cas "hors trace"
    /// (Mode Trace) est désormais porté par le chip latéral compact (spec "offtrack-compact-
    /// chip", it18, Bloc 1, voir bottomControlsColumn/OffTrackChipView) — comme la bannière
    /// latérale "virage à venir" avant lui, isolé de ce calcul par construction : n'occupe plus
    /// jamais la zone haute pleine-largeur (bug terrain 15/09 : "prend 40 % de l'écran").
    private func hasDirectionPanel(track: GPXTrack?) -> Bool {
        // Spec "stop-guidance-semantics" (it14, Bloc 3) : "roadbook et bannières de guidage se
        // retirent" pendant un guidage arrêté — la détection hors-trace continue de tourner en
        // arrière-plan (session.isOffTrackPaused), seul l'AFFICHAGE se tait.
        guard !session.isGuidanceStopped else { return false }
        // Fix "nav-classic-rebuild" (it21) : ne dépend plus de `modeStore.mode` (toujours
        // `.trace` en usage réel, RideModeSegmentedControl masqué depuis it12/13 — ce guidage
        // n'était donc jamais atteignable). Le guidage classique se déclenche désormais depuis
        // "Aller à" (profil Itinéraire + Valhalla configuré), qu'une trace soit suivie ou non,
        // exactement comme `GoToGuidance` fonctionne déjà en parallèle du Mode Trace.
        return session.navRoute != nil
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
        case navError(String)
        case navRouting
    }

    private func activeBanner(track: GPXTrack?) -> BannerKind? {
        if case .failed(let message) = mapLoadStatus { return .mapLoadError(message) }

        // Fix "nav-classic-rebuild" (it21) : ne dépend plus de `modeStore.mode` (voir
        // hasDirectionPanel ci-dessus, même raison). `.navError`/`.navRouting` UNIQUEMENT tant
        // qu'aucun itinéraire n'est encore affiché (`navRoute == nil`) — un recalcul automatique
        // en arrière-plan (écart soutenu, voir RideSessionManager.updateNavProgress) reste
        // "silencieux, pas de notification" comme demandé : ne réaffiche jamais cette bannière
        // pendant qu'un itinéraire est déjà affiché, succès ou échec du recalcul.
        if session.navRoute == nil {
            if session.isRoutingInProgress { return .navRouting }
            if let error = session.navRoutingError { return .navError(error) }
        }

        // Fix "offtrack-compact-chip" (it18, Bloc 1, terrain 15/09) : le panneau "Portion
        // bloquée ? Contourner" en pleine largeur ne se déclenche plus automatiquement — il
        // s'empilait avec le bandeau hors-trace et prenait ~40 % de l'écran à eux deux. Le
        // chip hors-trace compact (bottomControlsColumn) indique déjà qu'une reprise est en
        // cours ; ce n'est pas bloquant tant que ce chip reste visible. `isBlockedBannerVisible`
        // continue de tourner en arrière-plan (déclenche toujours la même confirmation via le
        // bouton "Bloqué", toujours visible) — seul cet AFFICHAGE automatique est retiré.
        // Backlog (non implémenté ce tour-ci, voir TODO.md) : action contextuelle par
        // appui-long sur le chip hors-trace, "Marquer portion bloquée & Contourner".
        if let detour = session.detourRoute { return .detour(detour) }
        // Spec "rejoin-trace-guidance-banner" (it18, Bloc 5) : un guidage AUTOMATIQUE
        // (divergence soutenue, voir ResumeGuidance.isAutomatic) n'affiche jamais la
        // bannière du haut avec confirmation — celle-ci reste réservée au tap manuel sur la
        // trace. La bannière latérale dédiée (bottomControlsColumn) le remplace.
        if let resume = session.resumeGuidance, !resume.isAutomatic { return .resumeGuidance(resume) }
        if let guidance = session.goToGuidance { return .goTo(guidance) }
        if let alert = nearbySharedBlockageAlert(track: track) { return .sharedBlockageAlert(alert) }
        return nil
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
            //
            // Fix "search-as-tab" (it19, retour terrain : "la loupe passe par-dessus le
            // bandeau/les contrôles Ride") — le bouton loupe flottant qui vivait ici (toujours
            // visible, donc en collision systématique avec tout overlay superposé : bandeau
            // "Aucune trace sélectionnée", bannières...) est retiré : la recherche de
            // destination est désormais un onglet à part entière (voir DestinationSearchTabView/
            // RootView, entre Ride et Biblio), plus de bouton flottant à faire cohabiter avec
            // le reste de la carte.

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
    /// Mode Nav uniquement désormais : le cas Trace "virage à venir" ET "hors trace" sont tous
    /// deux portés par la colonne latérale (spec "lateral-cap-banner-countdown" it12,
    /// "offtrack-compact-chip" it18 — voir bottomControlsColumn), plus jamais cette zone
    /// pleine-largeur (`RoadbookPanelView` n'a donc plus d'appelant ici, fichier intact, voir
    /// TODO.md).
    @ViewBuilder
    private var directionPanelLayer: some View {
        // Fix "nav-classic-rebuild" (it21) : ne dépend plus de `modeStore.mode`, voir
        // hasDirectionPanel ci-dessus.
        if session.navRoute != nil {
            VStack(spacing: 6) {
                NavGuidancePanelView(
                    maneuver: session.currentManeuver,
                    distanceMeters: session.distanceToCurrentManeuverMeters,
                    destinationLabel: session.navRoute?.destinationLabel ?? "",
                    isRecalculating: session.isRecalculatingRoute,
                    // Fix "manual-point-guidance-exclusivity"/"nav-guidance-stop-button" (it22) :
                    // "Revenir à la trace" si une trace reste chargée (réactive son guidage,
                    // annule la destination manuelle) — sinon simple arrêt du guidage riche.
                    stopLabel: library.activeTrack != nil ? "Revenir à la trace" : "Arrêter le guidage",
                    onStop: {
                        if library.activeTrack != nil {
                            session.returnToTraceGuidance()
                        } else {
                            session.stopNav()
                        }
                    }
                )
                // Spec "nav-classic-rebuild" (P1) : bannière secondaire "puis..." — visible
                // UNIQUEMENT si Valhalla signale un enchaînement rapproché (verbal_multi_cue)
                // sur la manœuvre courante.
                if session.currentManeuver?.isMultiCue == true, let next = session.nextManeuver {
                    NavSecondaryBannerView(maneuver: next)
                }
            }
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
        // Fix "orientation-toggle-nav-only-unreachable" (it19, retour terrain : "dans l'onglet
        // Ride, toujours pas de boussole") — ce bloc était restreint à `modeStore.mode == .nav`,
        // OR le Mode Nav est masqué de l'UI depuis it12 (spec "hide-nav-tab", plus de
        // segmented control pour y accéder) : ce bouton n'a donc jamais pu être visible en
        // usage réel. Affiché désormais quel que soit le mode — `SpeedLimitBadgeView`
        // ci-dessous reste conditionné à `session.currentSpeedLimitKmh` (toujours nil en Mode
        // Trace aujourd'hui, `updateSpeedLimit` n'étant appelée que par `updateNavProgress`) :
        // rien à changer là, il restera simplement invisible tant que ce calcul n'est pas
        // branché sur Mode Trace, sans risque de régression.
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
                        // Légende ajoutée (spec "icon-text-consistency", it19, angle
                        // complémentaire "boutons icône seule" — proposition validée par le
                        // propriétaire) : même patron icône + légende courte que les autres
                        // boutons de la colonne gantée (Pause/Reprendre, Me recentrer) —
                        // nomme l'ACTION du tap (la destination), pas l'état courant.
                        VStack(spacing: 2) {
                            Image(systemName: is2DNorthUp ? "location.north.circle.fill" : "location.north.line.fill")
                                .font(.system(size: 20, weight: .bold))
                            Text(is2DNorthUp ? "Cap" : "Nord")
                                .font(.system(size: 9, weight: .semibold))
                        }
                        .foregroundStyle(.white)
                        .frame(width: RideConstants.glovedTapTargetSize, height: RideConstants.glovedTapTargetSize)
                        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                        .background(.black.opacity(0.25), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                    }
                    .accessibilityLabel(is2DNorthUp ? "Revenir à la vue cap-en-haut" : "Vue nord-en-haut")
                    .longPressTooltip(is2DNorthUp ? "Bascule en cap-en-haut : la carte tourne avec ta direction" : "Bascule en nord-en-haut : la carte reste fixe")

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

    /// Colonne de contrôles (fix "overlay-layout-grid", Bug 3 ; côté réglable depuis spec
    /// "controls-side-setting", it14, Bloc 2) : ANCRÉE EN BAS (au-dessus de la tab bar, jamais
    /// au centre) — ordre figé : Me recentrer, bannière roadbook (empilée au-dessus des boutons
    /// de zoom, spec Bloc 2), +, −, Pause↔Play (Stop défini en menu contextuel, spec
    /// "guidance-toggle-stop-pause-play", it15, Bloc 3), Bloqué/Signaler, espacés uniformément
    /// de 12 pt. Le badge vitesse (`speedoBadgeLayer`) permute TOUJOURS du côté opposé (voir
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
                // Spec "stop-guidance-semantics" (it14, Bloc 3), comportement à 2 boutons
                // empilés conservé derrière le feature-flag GUIDANCE_BUTTON_MODE (filet de
                // secours it15, Bloc 3) : "un état guidage arrêté affiche l'icône play discret
                // ... pour relancer si une trace reste selected."
                if RideConstants.guidanceButtonMode == .twoButtons,
                   session.isGuidanceStopped, library.activeTrack != nil {
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
                // Priorité de la colonne latérale (mutuellement exclusifs, jamais empilés) :
                // 1. liaison automatique en cours (spec "rejoin-trace-guidance-banner", it18,
                //    Bloc 5) — plus informative qu'un simple chip une fois qu'un itinéraire de
                //    reprise a été calculé ; 2. chip hors-trace compact (Bloc 1) ; 3. bannière
                //    virage à venir sur trace (it12).
                //
                // Fix "manual-point-guidance-exclusivity" (it22) : toute la colonne se retire
                // dès qu'un guidage manuel (`GuidanceTarget.manualPoint`) est actif — sans ce
                // garde explicite, `session.currentInflection`/`isOffTrackChipVisible` etc.
                // resteraient FIGÉS sur leur dernière valeur d'avant la pause (voir
                // RideSessionManager.handle(location:), le calcul lui-même s'arrête, mais rien
                // ne remet ces propriétés à `nil`/`false`) plutôt que disparaître proprement.
                if session.guidanceTarget == .trace {
                    if RideConstants.rejoindreGuidanceBannerEnabled,
                       let resume = session.resumeGuidance, resume.isAutomatic,
                       let distance = session.resumeGuidanceLiveDistanceMeters {
                        RejoinGuidanceBannerView(distanceMeters: distance, relativeBearingDegrees: resumeRelativeBearingDegrees(to: resume.pinCoordinate))
                            .transition(.ridePanel)
                    } else if isOffTrackChipVisible, let offTrackInfo = offTrackPanelInfo {
                        OffTrackChipView(
                            relativeBearingDegrees: offTrackInfo.relativeBearingDegrees,
                            distanceMeters: offTrackInfo.distanceMeters,
                            pausedSinceDate: session.offTrackPausedSinceDate
                        )
                        .transition(.ridePanel)
                    } else if isLateralBannerVisible, let inflection = session.currentInflection, let distance = session.distanceToCurrentInflectionMeters {
                        LateralCapBannerView(
                            direction: inflection.direction,
                            tier: inflection.tier,
                            distanceMeters: distance,
                            sequenceIndex: inflection.sequenceIndex,
                            totalCount: session.inflectionPoints.count
                        )
                        .transition(.ridePanel)
                    }
                }
                RideGlovedZoomControls(onZoomIn: { session.zoomIn() }, onZoomOut: { session.zoomOut() })
                // Spec "guidance-toggle-stop-pause-play" (it15, Bloc 3) : bouton unique par
                // défaut (Pause↔Play, Stop défini en menu contextuel) — remplace l'empilement
                // Stop + Play séparé, jugé trop lourd visuellement en test terrain.
                if RideConstants.guidanceButtonMode == .twoButtons {
                    RideStopButton { showStopConfirmation = true }
                } else {
                    RideGuidanceToggleButton(
                        isStopped: session.isGuidanceStopped,
                        onPause: commitPause,
                        onResume: { session.resumeGuidanceAfterStop() },
                        onDefiniteStop: commitStop
                    )
                }
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
            .animation(.ridePanel, value: isOffTrackChipVisible)
            .animation(.ridePanel, value: session.resumeGuidance?.isAutomatic ?? false)
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

    /// Bannière latérale cap (spec "lateral-cap-banner-countdown", it12 ; détection remplacée
    /// "roadbook-angle-buckets-replay", it14, voir RoadbookAnalyzer.buildRoadbookEvents et
    /// Réglages > Roadbook) — visible uniquement pour un événement à moins de
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

    /// Chip hors-trace compact (spec "offtrack-compact-chip", it18, Bloc 1) — remplace
    /// `RoadbookPanelView` (bandeau plein-largeur EN HAUT). Mêmes conditions que l'ancien
    /// `directionPanelLayer` côté Trace (seuils ENTER/EXIT inchangés, voir RideConstants), juste
    /// déplacé dans la colonne latérale.
    private var isOffTrackChipVisible: Bool {
        modeStore.mode == .trace && !session.isGuidanceStopped && session.isOffTrackPaused
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
                // garde sa valeur centrée fixe, inchangée. `effectiveIs2DNorthUp` (it17, Bloc 4)
                // remplace `is2DNorthUp` : force cap-en-haut pendant un replay debug si le
                // toggle du menu est activé, sans jamais toucher au réglage réel de l'utilisateur.
                positionAnchorRatio: effectiveIs2DNorthUp ? RideConstants.positionAnchorRatio2D : settings.rideAnchorYFraction
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

            if track == nil {
                noActiveTrackBannerLayer
            }

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
                originalTrackName: track?.name,
                points: session.recordedPoints,
                waypoints: track.map { waypointStore.waypoints(near: $0) } ?? [],
                onFinished: { showEndRideSheet = false }
            )
        }
        // Fix "ride-restarts-from-zero-on-tab-return" (it19, retour terrain : "si je switch sur
        // un autre onglet et reviens sur Ride, ça repart de zéro") — `.onAppear` fire aussi bien
        // au VRAI premier lancement qu'à chaque retour sur l'onglet Ride (TabView appelle
        // onAppear/onDisappear à chaque changement de visibilité, pas juste au montage initial).
        // Appeler `start(track:)` inconditionnellement à chaque fois remettait `rideStartDate`/
        // `averageSpeedKmh`/`maxSpeedKmh`/`totalDistanceTraveledMeters` à zéro sur un simple
        // aller-retour Ride→Biblio→Ride — la trace enregistrée elle-même (`recordedPoints`)
        // survivait déjà correctement (protégée par le garde `recordingTrackID != track.id`,
        // voir RideSessionManager.start), mais les stats affichées, elles, non. `switchMode(
        // track:)` existe déjà précisément pour ce cas ("retour d'onglet SANS repartir de
        // zéro", spec "camera-mode-stability") — `hasStartedRideSession` (local, non persisté)
        // distingue le VRAI premier lancement (start) de tout retour ultérieur (switchMode),
        // y compris après un `.onDisappear` qui a appelé `stop()` entre-temps.
        .onAppear {
            if hasStartedRideSession {
                session.switchMode(track: modeStore.mode == .trace ? track : nil)
            } else {
                hasStartedRideSession = true
                session.start(track: track)
            }
        }
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
                // Spec "ride-empty-state-shows-map" (it19) : le bandeau "Aucune trace
                // sélectionnée" doit réapparaître à CHAQUE retour sur Ride, jamais rester
                // masqué pour de bon après un dismiss — demande explicite du propriétaire.
                isNoTrackBannerDismissed = false
            } else {
                session.stop()
            }
        }
        // Spec "roadbook-jump-to-map" — sans ça, le suivi GPS live (actif dès qu'une position
        // existe et qu'aucun override manuel n'est en cours, voir RideMapLibreView.updateUIView)
        // re-centrerait la caméra sur la position réelle au fix suivant, annulant quasi
        // instantanément le saut vers le point ciblé. Même fenêtre de grâce qu'un pan/pinch
        // manuel (`registerManualGesture`) — pas une suspension indéfinie dédiée : le pilote
        // reste libre d'interagir normalement avec la carte pendant qu'il regarde ce point.
        .onChange(of: navigationState.roadBookFocusRequest) { request in
            guard request != nil else { return }
            session.registerManualGesture()
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
        .onChange(of: settings.turnMergeMinDistanceMeters) { _ in
            session.rebuildCheckpoints()
        }
        // Spec "roadbook-settings-wired" (it14, Bloc 5) : "Chaque changement actif
        // immédiatement sur la carte (pas de kill)" — un seul .onChange combiné (impossible de
        // chaîner plus de 2-3 .onChange proprement en SwiftUI) via un flux synthétique.
        .onChange(of: roadbookSettingsSignature) { _ in
            session.rebuildCheckpoints()
        }
        .onChange(of: settings.keepScreenAwakeInRide) { _ in
            session.applyIdleTimerSetting()
        }
        // Spec "link-recompute-on-divergence" (it18, Bloc 3) : "notification silencieuse
        // Recalcul brève, pas de bannière permanente" — même mécanisme toast que Pause/Stop.
        .onChange(of: session.autoRecomputeToastToken) { _ in
            toastMessage = "Recalcul"
        }
    }

    /// Combine tous les réglages roadbook en une seule valeur `Equatable` — évite d'empiler 7
    /// `.onChange` séparés pour le même effet (`session.rebuildCheckpoints()`).
    private var roadbookSettingsSignature: String {
        "\(settings.roadbookEnabled)-\(settings.roadbookWindowBeforeMeters)-\(settings.roadbookWindowAfterMeters)-\(settings.roadbookLightThresholdDegrees)-\(settings.roadbookMarkedThresholdDegrees)-\(settings.roadbookHardThresholdDegrees)-\(settings.roadbookUTurnThresholdDegrees)"
    }

    /// "Itinéraire ici" en Mode Nav démarre directement le guidage principal (voix +
    /// Fix "nav-classic-rebuild" (it21) manqué sur CE call site précis (corrigé ici en it22,
    /// retour terrain sur l'exclusivité de guidage) : `modeStore.mode == .nav` n'est JAMAIS vrai
    /// en usage réel (RideModeSegmentedControl masqué depuis it12/13) — ce point d'entrée
    /// (tap long sur la carte) ne déclenchait donc jamais le guidage riche, même avec Valhalla
    /// configuré et le profil "Itinéraire" choisi. Même critère que `DestinationSearchTabView`
    /// depuis it21 : profil route + Valhalla disponible → guidage classique complet (réutilise
    /// NavGuidancePanelView, spec it22 "reuse-nav-banner-for-manual-point") ; sinon repli sur le
    /// guidage simple existant. `startNav`/`startGoTo` mettent chacun en pause la reprise de
    /// trace (`cancelResume()`, spec "manual-point-guidance-exclusivity") — un point manuel
    /// défini pendant un Ride en Trace devient donc automatiquement le seul guidage actif.
    private func commitGoTo(profile: GoToProfile) {
        guard let coordinate = pendingGoToCoordinate else { return }
        let label = pendingGoToLabel
        pendingGoToCoordinate = nil
        if profile == .route, session.isRichNavAvailable {
            session.startNav(to: coordinate, label: label)
        } else {
            session.startGoTo(to: coordinate, label: label, profile: profile)
        }
    }

    /// Fix "pause-stop-indistinguishable" (bug terrain, it16) : Pause et Stop défini menaient
    /// tous les deux au même état visuel silencieux (roadbook/bannière disparaissent, aucun
    /// autre signal) — un pilote ne pouvait pas dire lequel des deux venait de se déclencher.
    /// Toast dédié désormais sur CHAQUE chemin, texte distinct (Stop garde "Guidage arrêté",
    /// inchangé) — seule la présentation diffère, l'état isGuidanceStopped reste identique.
    private func commitPause() {
        session.pauseGuidance()
        toastMessage = "Guidage en pause"
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
                is2DNorthUp: effectiveIs2DNorthUp,
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
            // Spec "replay-marker-heading-x2" (it17, Bloc 4) : passé par environnement plutôt
            // qu'en paramètre d'init — voir RideMapLibreView.swift pour le pourquoi (conformité
            // au protocole MapProvider, signature d'init fixe).
            .environment(\.isDebugReplayMarkerActive, session.isDebugReplayActive)
            // Spec "slope-warning-native" (it19) : même raison (conformité MapProvider).
            .environment(\.slopeWarningsEnabled, settings.slopeWarningsEnabled)
            .environment(\.slopeWarningThresholdPercent, settings.slopeWarningThresholdPercent)
            // Spec "nav-classic-rebuild" (it21) : même raison — MapKit (comparaison) n'a pas
            // besoin de parité sur cette distinction visuelle, comme les autres features
            // avancées (chevrons, fond vectoriel, pente).
            .environment(\.navRouteTraveledCoordinateCount, session.navRouteTraveledCoordinateCount)
            // Spec "roadbook-jump-to-map" — même raison (conformité MapProvider) ; MapKit
            // (comparaison) n'a pas besoin de parité sur ce marqueur, comme les autres features
            // avancées ci-dessus.
            .environment(\.roadBookFocusRequest, navigationState.roadBookFocusRequest)
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
        // Fix "manual-point-guidance-exclusivity" (it22, "taper à nouveau sur la trace...
        // réactive le guidage trace et annule la destination manuelle") — sans effet si aucun
        // guidage manuel n'était actif (`returnToTraceGuidance()` est un no-op dans ce cas,
        // `stopNav`/`stopGoTo` sur un état déjà vide).
        if session.guidanceTarget != .trace {
            session.returnToTraceGuidance()
        }
        session.requestResume(pinCoordinate: pin, pinCumulativeDistanceMeters: projection.cumulativeDistanceMeters)
    }

    /// Spec "ride-empty-state-shows-map" (it19, retour terrain : "afficher la carte quand même
    /// mais juste pas la trace, avec un bandeau en haut") — remplace l'ancien `emptyState` plein
    /// écran. Bandeau tout en haut, dismissible (bouton "x"), mais réapparaît à CHAQUE retour
    /// sur l'onglet Ride (voir `.onChange(of: navigationState.selectedTab)`) : jamais masqué
    /// "pour de bon". Tap sur le corps du bandeau = raccourci vers la Bibliothèque (reprend le
    /// CTA "Aller à la Bibliothèque" de l'ancien `emptyState`, sans nouveau `Button` imbriqué —
    /// même patron que le fix "biblio-checkmark-not-activating" : un seul vrai `Button` (le "x"
    /// de fermeture) + `.onTapGesture` sur le reste, jamais deux `Button` empilés.
    private var noActiveTrackBannerLayer: some View {
        VStack {
            if !isNoTrackBannerDismissed {
                HStack(spacing: 10) {
                    Image(systemName: "location.slash")
                        .foregroundStyle(.white.opacity(0.85))
                    Text("Aucune trace sélectionnée")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.white)
                    Spacer()
                    Button {
                        isNoTrackBannerDismissed = true
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.white.opacity(0.85))
                    }
                    .accessibilityLabel("Masquer ce message")
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
                .background(.black.opacity(0.55))
                .background(.ultraThinMaterial)
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                .contentShape(Rectangle())
                .onTapGesture {
                    navigationState.selectedTab = .library
                }
                .accessibilityElement(children: .combine)
                .accessibilityHint("Toucher pour aller à la Bibliothèque")
                .padding(.horizontal, 16)
                .padding(.top, 8)
                .transition(.move(edge: .top).combined(with: .opacity))
            }
            Spacer()
        }
        .animation(.easeInOut(duration: 0.2), value: isNoTrackBannerDismissed)
    }
}
