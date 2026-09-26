import SwiftUI
import CoreLocation

/// Onglet Road Book (spec "roadbook-mode", it23, point 1 ; refonte UI/UX "roadbook-ui-redesign",
/// it25) — lecture d'une trace en mode liste de directions pures, esprit roadbook papier de
/// rallye. Affiche TOUJOURS la trace active (`LibraryStore.activeTrackID`, source unique partagée
/// avec Bibliothèque et Ride, it29) : aucune sélection de trace ici — le raccourci en haut à gauche
/// affiche son nom en lecture seule et mène à la Bibliothèque, seul endroit où la changer. Ne pilote
/// RIEN : jamais un accès à `RideSessionManager`, jamais une écriture dans `LibraryStore`
/// (invariant it10).
struct RoadBookTabView: View {
    @EnvironmentObject private var library: LibraryStore
    @EnvironmentObject private var settings: RideSettingsStore
    /// Fix "roadbook-reversed-direction-broken" (retour terrain : "Assisté GPS fonctionne en
    /// sens A→B mais affiche immédiatement 'Toutes les manœuvres ont été passées' en sens
    /// inversé") — root cause : cet écran n'appliquait JAMAIS le sens de parcours par trace
    /// (`TrackRideSettings.isReversed`, spec "per-track-settings", it13), contrairement à
    /// `RideView.swift` (`track.reordered(using: trackRideSettings.settings(for: track.id))`,
    /// voir son `rideContent`). Les manœuvres/la projection GPS restaient donc calculées sur
    /// l'ordre CANONIQUE A→B stocké quel que soit le sens choisi dans Réglages de trace — en
    /// sens inversé, la position réelle (proche du point B canonique) projette une distance
    /// cumulée déjà supérieure à celle de TOUTES les manœuvres dès le premier point, d'où
    /// "tout est déjà passé". Voir `selectedTrack` ci-dessous.
    @EnvironmentObject private var trackRideSettings: TrackRideSettingsStore
    @EnvironmentObject private var networkMonitor: NetworkMonitor
    @EnvironmentObject private var navigationState: AppNavigationState

    @State private var showExportOptions = false
    @StateObject private var locationManager = LocationManager()
    /// Repères VISIBLES (jalon it28) : téléchargement par tronçons avec progression, cache par
    /// trace, complément par catégorie, sélection pour le parcours affiché — best-effort, ne bloque
    /// JAMAIS l'affichage des manœuvres elles-mêmes. Voir `RoadbookLandmarkLoader`.
    @StateObject private var landmarkLoader = RoadbookLandmarkLoader()

    private var landmarkSelection: RoadbookLandmarkSelection { landmarkLoader.selection }

    /// Repère affiché AVEC chaque changement de direction (clé = `RoadbookManeuver.id`).
    private var landmarks: [UUID: RoadbookLandmarkInfo?] {
        landmarkSelection.attached.mapValues { Optional($0) }
    }

    /// Détection route-aware Valhalla (spec "roadbook-valhalla-route-aware", retour terrain :
    /// "le Road Book n'a jamais utilisé la détection route-aware de Valhalla, contrairement à
    /// la bannière latérale du Ride") — même mécanisme que `RideSessionManager.
    /// triggerMapMatchingIfNeeded`/`RoadbookMapMatchCache`, dupliqué ICI plutôt que partagé
    /// pour garder ce module décorrélé du fichier `RideSessionManager` (invariant "totalement
    /// découplé de l'état de Ride actif") — mais le CACHE DISQUE, lui, est bien le même
    /// (`Documents/RoadbookMapMatchCache/`, clé = `GPXTrack.traversalKey`, trace ET sens) : un
    /// trajet déjà map-matché depuis l'onglet Ride dans le même sens profite d'un cache-hit
    /// immédiat ici, et vice-versa.
    @State private var mapMatchedManeuvers: [MapMatchedManeuver] = []
    @State private var mapMatchCache = RoadbookMapMatchCache()
    @State private var mapMatchingProvider: MapMatchingProvider = ValhallaMapMatchingProvider()
    @State private var mapMatchingTask: Task<Void, Never>?
    @State private var mapMatchedTraversalKey: String?

    /// Palette jour/nuit RÉSOLUE (spec "roadbook-ui-redesign", it25, point 0) — recalculée à
    /// l'apparition, à chaque mise à jour de position, à chaque changement du réglage manuel, ET
    /// périodiquement (`paletteReevaluationIntervalSeconds`) pendant que l'écran reste ouvert :
    /// sans ce filet, un Road Book ouvert à cheval sur le coucher du soleil resterait figé sur la
    /// palette du moment de l'ouverture.
    @State private var resolvedPalette: RoadbookPalette = .paper

    /// Trace ACTIVE dans le sens réellement parcouru (fix "roadbook-reversed-direction-broken" ;
    /// source unique it29, voir `RoadbookTrackSource`). Tout ce qui dépend de l'ordre des points
    /// est mis en cache par `traversalKey` (trace ET sens), jamais par `id` seul.
    private var selectedTrack: GPXTrack? {
        RoadbookTrackSource.displayedTrack(library: library, trackRideSettings: trackRideSettings)
    }

    private var maneuvers: [RoadbookManeuver] {
        guard let track = selectedTrack else { return [] }
        return RoadbookExtractor.maneuvers(
            for: track,
            windowBeforeMeters: settings.roadbookWindowBeforeMeters,
            windowAfterMeters: settings.roadbookWindowAfterMeters,
            lightThresholdDegrees: settings.roadbookLightThresholdDegrees,
            markedThresholdDegrees: settings.roadbookMarkedThresholdDegrees,
            hardThresholdDegrees: settings.roadbookHardThresholdDegrees,
            veryHardThresholdDegrees: settings.roadbookVeryHardThresholdDegrees,
            mergeMinDistanceMeters: settings.turnMergeMinDistanceMeters,
            mapMatchedManeuvers: mapMatchedManeuvers
        )
    }

    /// `nil` tant que le toggle Réglages > Avancé > Routage Valhalla est désactivé ou l'endpoint
    /// vide — dans ce cas, `triggerMapMatchingIfNeeded` ne fait aucun appel réseau et le Road
    /// Book retombe silencieusement sur la détection géométrique seule, comportement identique
    /// à avant ce fix (jamais un échec qui ferait croire à une précision route-aware absente).
    private var currentValhallaConfiguration: ValhallaConfiguration? {
        guard settings.valhallaEnabled, !settings.valhallaEndpointURLString.isEmpty else { return nil }
        return ValhallaConfiguration(
            endpointURLString: settings.valhallaEndpointURLString,
            username: ValhallaKeychainStore.username(),
            password: ValhallaKeychainStore.password()
        )
    }

    /// Virages ET repères en ligne dédiée, dans l'ordre de la trace — la liste que TOUS les
    /// affichages du Road Book parcourent (it30 : priorité par ordre d'arrivée).
    private var entries: [RoadbookEntry] {
        RoadbookEntry.merge(maneuvers: maneuvers, landmarks: landmarkSelection.standalone)
    }

    /// Prochain élément (virage OU repère, le plus proche) — `nil` tant que le mode Assisté GPS
    /// n'a pas de position exploitable.
    private var liveEntry: (index: Int, distanceRemainingMeters: Double)? {
        guard let current = liveCumulativeDistanceMeters else { return nil }
        return RoadbookLiveProgress.nextEntry(entries: entries, currentCumulativeDistanceMeters: current)
    }

    /// Hors trace (it30) : même règle que le Ride (`OffTrackDetector`), mis à jour à chaque
    /// position en mode Assisté GPS.
    @State private var offTrack = RoadbookOffTrackState()

    private func updateOffTrack() {
        guard settings.roadbookReadingMode == .gpsAssisted, let track = selectedTrack, let location = locationManager.currentLocation else {
            offTrack.reset()
            return
        }
        offTrack.update(location: location, points: track.points, cumulativeDistances: TrackProjector.cumulativeDistances(for: track.points))
    }

    /// Position actuelle projetée sur la trace (distance cumulée) — mode Assisté GPS uniquement.
    private var liveCumulativeDistanceMeters: Double? {
        guard settings.roadbookReadingMode == .gpsAssisted,
              let track = selectedTrack, let location = locationManager.currentLocation
        else { return nil }
        let cumulativeDistances = TrackProjector.cumulativeDistances(for: track.points)
        return TrackProjector.project(location.coordinate, onto: track.points, cumulativeDistances: cumulativeDistances)?.cumulativeDistanceMeters
    }

    private var paletteColors: RoadbookPaletteColors { .resolved(for: resolvedPalette) }

    var body: some View {
        NavigationStack {
            Group {
                if let track = selectedTrack {
                    content(track: track)
                } else {
                    // Fix "content-unavailable-view-ios17-only" : `ContentUnavailableView` est
                    // iOS 17+, incompatible avec la cible 16.0 du projet — état vide maison,
                    // même patron visuel que `LibraryView.emptyState`.
                    VStack(spacing: 20) {
                        RoadBookEmptyState(
                            title: String(localized: "Aucune trace active", bundle: .appLanguage),
                            systemImage: "list.bullet.rectangle",
                            message: String(localized: "Active une trace dans la Bibliothèque : le Road Book affiche toujours la trace active.", bundle: .appLanguage)
                        )
                        .frame(maxHeight: 320)
                        Button {
                            navigationState.showLibrary()
                        } label: {
                            Label("Ouvrir la Bibliothèque", systemImage: "books.vertical")
                        }
                        .buttonStyle(.borderedProminent)
                    }
                }
            }
            .navigationTitle("Road Book")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    // Raccourci vers la Bibliothèque (it29) : nom de la trace active en LECTURE
                    // SEULE, jamais un sélecteur — changer de trace se fait dans la Bibliothèque.
                    RoadbookLibraryShortcut(trackName: selectedTrack?.name) {
                        navigationState.showLibrary()
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        showExportOptions = true
                    } label: {
                        Image(systemName: "square.and.arrow.up")
                    }
                    .disabled(selectedTrack == nil)
                    .accessibilityLabel("Exporter en PDF")
                }
            }
            .sheet(isPresented: $showExportOptions) {
                if let track = selectedTrack {
                    RoadbookExportOptionsView(trackName: track.name, maneuvers: maneuvers, landmarkCheckpoints: landmarkSelection.standalone, options: $settings.roadbookPDFOptions, landmarks: landmarks)
                }
            }
        }
        // Spec "roadbook-ui-redesign" (it25, point 0) — périmètre EXPLICITEMENT limité à cet
        // écran (ni la carte Ride, ni le reste de l'app) : appliqué ICI, à la racine du Road
        // Book uniquement, jamais plus haut dans la hiérarchie de vues.
        .environment(\.colorScheme, paletteColors.colorScheme)
        .environment(\.roadbookPaletteColors, paletteColors)
        .background(paletteColors.background.ignoresSafeArea())
        .onAppear {
            if settings.roadbookReadingMode == .gpsAssisted {
                locationManager.requestAuthorization()
                locationManager.startUpdating()
            }
            updateResolvedPalette()
            landmarkLoader.isOnline = { [weak networkMonitor] in networkMonitor?.isReachable ?? true }
            // Spec "roadbook-keep-screen-awake" (it25, retour terrain : "l'écran doit rester
            // allumé dans road book, il a tendance à s'arrêter") — un roadbook papier ne s'éteint
            // jamais tout seul ; inconditionnel tant que cet écran est affiché, aucun réglage
            // séparé (contrairement à Ride, où certains préfèrent économiser la batterie).
            IdleTimerCoordinator.setActive(true, for: .roadBook)
        }
        .onDisappear {
            locationManager.stopUpdating()
            IdleTimerCoordinator.setActive(false, for: .roadBook)
        }
        .onChange(of: settings.roadbookReadingMode) { mode in
            if mode == .gpsAssisted {
                locationManager.requestAuthorization()
                locationManager.startUpdating()
            } else {
                locationManager.stopUpdating()
            }
        }
        .onChange(of: settings.roadbookPaletteSetting) { _ in updateResolvedPalette() }
        .onChange(of: locationManager.currentLocation?.coordinate.latitude) { _ in
            updateResolvedPalette()
            updateOffTrack()
        }
        .onChange(of: locationManager.currentLocation?.coordinate.longitude) { _ in updateOffTrack() }
        .onChange(of: selectedTrack?.traversalKey) { _ in
            offTrack.reset()
            updateOffTrack()
        }
        .onChange(of: settings.roadbookReadingMode) { _ in updateOffTrack() }
        .onReceive(Timer.publish(every: RoadBookConstants.paletteReevaluationIntervalSeconds, on: .main, in: .common).autoconnect()) { _ in
            updateResolvedPalette()
        }
        // `.task(id:)` annule/relance automatiquement si la trace sélectionnée OU son sens de
        // parcours change (`traversalKey`, fix "mapmatch-cache-direction-aware" — le sens peut
        // changer depuis Réglages de trace pendant que cet onglet reste vivant dans le TabView,
        // sans que `id` ne change) — jamais besoin de gérer l'annulation à la main (voir
        // RoadBook/CLAUDE.md pour le détail du fonctionnement best-effort, point par point).
        .task(id: selectedTrack?.traversalKey) {
            guard let track = selectedTrack else {
                mapMatchedManeuvers = []
                return
            }
            triggerMapMatchingIfNeeded(for: track)
            #if DEBUG
            RoadbookDebugDump.log(trackName: track.name, maneuvers: maneuvers, mapMatched: mapMatchedManeuvers)
            #endif
            updateLandmarks()
        }
        .onChange(of: maneuvers) { _ in updateLandmarks() }
        .onChange(of: settings.roadbookLandmarkCategories) { _ in updateLandmarks() }
        .onChange(of: networkMonitor.isReachable) { isReachable in
            if isReachable { landmarkLoader.retry() }
        }
    }

    private func updateResolvedPalette() {
        resolvedPalette = RoadbookPaletteResolver.resolve(
            override: settings.roadbookPaletteSetting.overrideValue,
            coordinate: locationManager.currentLocation?.coordinate
        )
    }

    /// Déclenche le map matching Valhalla EN TÂCHE DE FOND, une fois par trace RÉELLEMENT
    /// différente — même patron que `RideSessionManager.triggerMapMatchingIfNeeded` (voir
    /// Ride/CLAUDE.md pour le détail du fonctionnement cache-hit/cache-miss), dupliqué ici pour
    /// garder ce module décorrélé du fichier `RideSessionManager`. Dégradation propre partout :
    /// Valhalla désactivé/non configuré → aucun appel réseau, roadbook géométrique identique à
    /// avant ce fix ; échec réseau (`try?`) → même résultat, jamais de crash ni de blocage.
    private func triggerMapMatchingIfNeeded(for track: GPXTrack) {
        let traversalKey = track.traversalKey
        guard mapMatchedTraversalKey != traversalKey else { return }
        mapMatchedTraversalKey = traversalKey
        mapMatchingTask?.cancel()

        guard let configuration = currentValhallaConfiguration else {
            mapMatchedManeuvers = []
            return
        }

        if let cached = mapMatchCache.maneuvers(for: track) {
            mapMatchedManeuvers = cached
            return
        }

        mapMatchedManeuvers = []
        let sampled = Self.downsampledForMapMatching(track.points.map(\.coordinate))
        let provider = mapMatchingProvider

        mapMatchingTask = Task {
            guard let matched = try? await provider.matchRoute(coordinates: sampled, configuration: configuration) else { return }
            guard !Task.isCancelled else { return }
            await MainActor.run {
                guard selectedTrack?.traversalKey == traversalKey else { return }
                mapMatchCache.store(traversalKey: traversalKey, maneuvers: matched)
                mapMatchedManeuvers = matched
                #if DEBUG
                RoadbookDebugDump.log(trackName: selectedTrack?.name ?? "", maneuvers: maneuvers, mapMatched: matched)
                #endif
            }
        }
    }

    /// Repères visibles pour le parcours et les catégories affichés — le chargeur décide seul s'il
    /// faut télécharger (catégories manquantes seulement) ou juste refaire la sélection.
    private func updateLandmarks() {
        guard let track = selectedTrack else { return }
        landmarkLoader.update(
            trackID: track.id,
            traversalKey: track.traversalKey,
            points: track.points,
            maneuvers: maneuvers,
            enabled: settings.roadbookLandmarkCategories
        )
    }

    /// Sous-échantillonnage UNIFORME avant map matching — même patron que `RideSessionManager.
    /// downsampledForMapMatching`, dupliqué ici plutôt que partagé (invariant "totalement
    /// découplé de l'état de Ride actif" : ce module n'importe jamais RideSessionManager.swift).
    private static func downsampledForMapMatching(_ coordinates: [CLLocationCoordinate2D]) -> [CLLocationCoordinate2D] {
        let maxPoints = RideConstants.mapMatchingMaxTracePoints
        guard coordinates.count > maxPoints, maxPoints > 1 else { return coordinates }
        let step = Double(coordinates.count - 1) / Double(maxPoints - 1)
        return (0..<maxPoints).map { coordinates[Int((Double($0) * step).rounded())] }
    }

    /// Retour terrain (it25, capture en paysage) : "essaye de caler [le sélecteur de mode] à
    /// droite en vertical, j'aimerais donner la priorité à la direction et la distance avant le
    /// changement de trace" — en paysage, le sélecteur/badge quittent la bande du haut (qui
    /// mangeait de la hauteur, précieuse sur un écran deux fois moins haut) pour une colonne
    /// étroite à DROITE de tout l'écran (hero + liste), rendant à la carte hero toute la largeur
    /// ET la hauteur libérée. Portrait INCHANGÉ (ligne du haut, déjà confirmé correct).
    @ViewBuilder
    private func content(track: GPXTrack) -> some View {
        if verticalSizeClass == .compact {
            HStack(spacing: 0) {
                VStack(spacing: 0) {
                    landmarkProgress
                    mainArea(track: track)
                }
                .frame(maxWidth: .infinity)
                landscapeModeColumn
            }
        } else {
            VStack(spacing: 0) {
                modePickerRow
                landmarkProgress
                mainArea(track: track)
            }
        }
    }

    /// Bandeau de chargement des repères (jalon it28) — une ligne, seulement tant qu'il y a
    /// quelque chose à dire ; les directions en dessous restent utilisables.
    @ViewBuilder
    private var landmarkProgress: some View {
        if landmarkLoader.isBannerVisible {
            RoadbookLandmarkProgressView(phase: landmarkLoader.phase, stats: landmarkLoader.stats) { landmarkLoader.retry() }
                .transition(.opacity)
        }
    }

    private var modePickerRow: some View {
        HStack(spacing: 10) {
            Picker("Mode de lecture", selection: $settings.roadbookReadingMode) {
                ForEach(RoadbookReadingMode.allCases) { mode in
                    Text(mode.label).tag(mode)
                }
            }
            .pickerStyle(.segmented)

            // Spec "roadbook-ui-redesign" (it25, point 4) — retour terrain : "confirmer d'un
            // coup d'œil, depuis l'écran Road Book lui-même, que c'est bien Valhalla qui a
            // généré les données affichées". Réutilise `RoutingActivityMonitor` (it24, point
            // 0), déjà affiché en Réglages > Avancé — même source, deux endroits.
            RoutingServiceBadge()
        }
        .padding(.horizontal)
        .padding(.top, 12)
        .padding(.bottom, 4)
    }

    /// Colonne étroite à droite, PAYSAGE uniquement — deux boutons de mode empilés + le badge de
    /// service, remplacent le `Picker` segmenté horizontal (pas de style natif vertical pour
    /// `.segmented`, d'où ce contrôle maison).
    private var landscapeModeColumn: some View {
        VStack(spacing: 12) {
            landscapeModeButton(.gpsAssisted, systemImage: "location.fill", shortLabel: "GPS")
            landscapeModeButton(.classic, systemImage: "list.bullet", shortLabel: String(localized: "Liste", bundle: .appLanguage))
            RoutingServiceBadge()
                .fixedSize()
            Spacer(minLength: 0)
        }
        .padding(.vertical, 14)
        .padding(.horizontal, 8)
        .frame(width: 94)
    }

    private func landscapeModeButton(_ mode: RoadbookReadingMode, systemImage: String, shortLabel: String) -> some View {
        let isSelected = settings.roadbookReadingMode == mode
        return Button {
            settings.roadbookReadingMode = mode
        } label: {
            VStack(spacing: 3) {
                Image(systemName: systemImage)
                    .font(.system(size: 17, weight: .semibold))
                Text(shortLabel)
                    .font(.caption2.bold())
            }
            .frame(width: 76, height: 52)
            .background(isSelected ? Color.accentColor.opacity(0.25) : Color.primary.opacity(0.08), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            .foregroundStyle(isSelected ? Color.accentColor : .primary)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(mode.label)
    }

    @ViewBuilder
    private func mainArea(track: GPXTrack) -> some View {
        if maneuvers.isEmpty {
            RoadBookEmptyState(
                title: String(localized: "Aucune manœuvre détectée", bundle: .appLanguage),
                systemImage: "arrow.up",
                message: String(localized: "Aucun changement de direction au-dessus du seuil configuré (Réglages > Roadbook) sur cette trace.", bundle: .appLanguage)
            )
        } else if settings.roadbookReadingMode == .gpsAssisted {
            // Fix "roadbook-focused-next-turn" (it23ter, retour terrain : "il faudrait
            // clairement afficher le prochain virage, au moins la moitié de l'écran... la
            // map doit être un aperçu, 15% de l'écran max") — mode Assisté GPS uniquement,
            // "prochain virage" n'a de sens qu'avec une position réelle à comparer. Le mode
            // Classique garde la table complète ci-dessous (aucune notion de "position
            // actuelle" à mettre en avant dans ce mode).
            // Mini-carte RETIRÉE (jalon it28, demande explicite) : la vue focus occupe tout
            // l'espace, portrait comme paysage — aucune réservation de place à droite du hero.
            RoadbookFocusedView(
                entries: entries,
                currentEntryIndex: liveEntry?.index,
                distanceRemainingMeters: liveEntry?.distanceRemainingMeters,
                currentCumulativeDistanceMeters: liveCumulativeDistanceMeters,
                unit: settings.roadbookPDFOptions.distanceUnit,
                hasLocationFix: locationManager.currentLocation != nil,
                landmarks: landmarks,
                offTrack: offTrack
            )
        } else {
            RoadbookTableView(
                maneuvers: maneuvers,
                landmarkCheckpoints: landmarkSelection.standalone,
                unit: settings.roadbookPDFOptions.distanceUnit,
                currentIndex: nil,
                liveDistanceRemainingMeters: nil,
                landmarks: landmarks
            )
        }
    }

    /// `.compact` = paysage sur iPhone (seul device family ciblé, `TARGETED_DEVICE_FAMILY "1"`).
    @Environment(\.verticalSizeClass) private var verticalSizeClass
}

/// Trace affichée par le Road Book (it29) : la trace ACTIVE de la Bibliothèque, dans son sens de
/// parcours — jamais une autre, jamais un repli sur "la première trace" : sans trace active, le
/// Road Book invite à en choisir une dans la Bibliothèque. Seule source, pas d'état local.
enum RoadbookTrackSource {
    @MainActor
    static func displayedTrack(library: LibraryStore, trackRideSettings: TrackRideSettingsStore) -> GPXTrack? {
        library.activeTrack.map { $0.reordered(using: trackRideSettings.settings(for: $0.id)) }
    }
}

/// Raccourci en haut à gauche du Road Book : icône Bibliothèque + nom de la trace active, en
/// lecture seule. Un tap mène à la Bibliothèque — aucune liste de traces sur place.
struct RoadbookLibraryShortcut: View {
    let trackName: String?
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Image(systemName: "books.vertical")
                Text(trackName ?? "Bibliothèque")
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .frame(maxWidth: 190, alignment: .leading)
            }
        }
        .accessibilityLabel(trackName.map { String(localized: "Trace active : \($0). Ouvrir la Bibliothèque pour en changer", bundle: .appLanguage) } ?? "Ouvrir la Bibliothèque")
    }
}

/// Badge discret du service de routage actif (spec "roadbook-ui-redesign", it25, point 4) —
/// même donnée que `ValhallaSettingsView` (Réglages > Avancé), affichée en plus ICI pour que la
/// fiabilité route-aware du Road Book (it24) soit visible sans changer d'écran. "Valhalla" (vert)
/// / "OSRM" (orange, repli — précision route-aware non garantie) / "—" (gris, aucune requête).
private struct RoutingServiceBadge: View {
    @ObservedObject private var monitor = RoutingActivityMonitor.shared

    var body: some View {
        HStack(spacing: 4) {
            Circle().fill(color).frame(width: 7, height: 7)
            Text(label).font(.caption2.bold())
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .background(color.opacity(0.15), in: Capsule())
        .foregroundStyle(color)
        .fixedSize()
        .longPressTooltip(tooltip)
        .accessibilityLabel(String(localized: "Service de routage : \(label)", bundle: .appLanguage))
    }

    private var label: String {
        switch monitor.lastEvent?.provider {
        case .valhalla: return "Valhalla"
        case .osrm: return "OSRM"
        case nil: return "—"
        }
    }

    private var color: Color {
        switch monitor.lastEvent?.provider {
        case .valhalla: return .green
        case .osrm: return .orange
        case nil: return .secondary
        }
    }

    private var tooltip: String {
        switch monitor.lastEvent?.provider {
        case .valhalla: return String(localized: "Détection route-aware active via Valhalla", bundle: .appLanguage)
        case .osrm: return String(localized: "Repli OSRM — la précision route-aware (rond-points/fourches) n'est pas garantie", bundle: .appLanguage)
        case nil: return String(localized: "Aucune requête de routage récente", bundle: .appLanguage)
        }
    }
}

/// Table dense en colonnes façon roadbook papier de rallye (spec "roadbook-mode", it23bis/
/// it23quater ; refonte hiérarchie visuelle "roadbook-ui-redesign", it25, point 3 — retour
/// terrain : "texte petit uniforme, aucune hiérarchie... premier élément au moins 3× plus
/// grand"). Jamais un `List` SwiftUI standard (ses insets/fonds par défaut cassent l'effet
/// "tableau imprimé" recherché).
private struct RoadbookTableView: View {
    let maneuvers: [RoadbookManeuver]
    /// Repères visibles en ligne dédiée, intercalés dans l'ordre de progression — la numérotation
    /// des manœuvres, elle, reste celle des seuls changements de direction.
    let landmarkCheckpoints: [RoadbookLandmarkCheckpoint]
    let unit: DistanceUnit
    let currentIndex: Int?
    let liveDistanceRemainingMeters: Double?
    let landmarks: [UUID: RoadbookLandmarkInfo?]

    @Environment(\.roadbookPaletteColors) private var palette

    // Fractions de la largeur totale — le bloc "info" absorbe le reste, jamais une largeur
    // fixe qui laisserait un grand vide à droite sur un écran de téléphone.
    private static let distanceColumnFraction: CGFloat = 0.26
    private static let headingColumnFraction: CGFloat = 0.20

    var body: some View {
        GeometryReader { geometry in
            let distanceWidth = geometry.size.width * Self.distanceColumnFraction
            let headingWidth = geometry.size.width * Self.headingColumnFraction
            let infoWidth = geometry.size.width - distanceWidth - headingWidth

            ScrollViewReader { proxy in
                ScrollView {
                    VStack(spacing: 0) {
                        headerRow(distanceWidth: distanceWidth, headingWidth: headingWidth, infoWidth: infoWidth)
                        Divider().background(palette.rule)

                        ForEach(RoadbookEntry.merge(maneuvers: maneuvers, landmarks: landmarkCheckpoints)) { entry in
                            switch entry {
                            case .maneuver(let maneuver, let index) where index == 0:
                                // Première MANŒUVRE = HERO (spec it25, point 3 : "au moins 3× plus
                                // grand, doit sauter aux yeux comme ce qui arrive maintenant") —
                                // même esprit visuel que la carte du mode Assisté GPS, données
                                // INCHANGÉES (partielle/cumulée/cap), juste réorganisées.
                                RoadbookHeroRow(
                                    maneuver: maneuver,
                                    unit: unit,
                                    isCurrent: currentIndex == 0,
                                    liveDistanceRemainingMeters: currentIndex == 0 ? liveDistanceRemainingMeters : nil,
                                    landmark: landmarks[maneuver.id] ?? nil
                                )
                                .id(0)
                                .background(palette.surface)
                            case .maneuver(let maneuver, let index):
                                RoadbookTableRow(
                                    maneuver: maneuver,
                                    index: index,
                                    unit: unit,
                                    isCurrent: currentIndex == index,
                                    liveDistanceRemainingMeters: currentIndex == index ? liveDistanceRemainingMeters : nil,
                                    landmark: landmarks[maneuver.id] ?? nil,
                                    distanceColumnWidth: distanceWidth,
                                    headingColumnWidth: headingWidth,
                                    infoColumnWidth: infoWidth,
                                    ruleColor: palette.rule
                                )
                                .id(index)
                            case .landmark(let landmark):
                                RoadbookLandmarkTableRow(
                                    landmark: landmark,
                                    unit: unit,
                                    distanceColumnWidth: distanceWidth,
                                    headingColumnWidth: headingWidth,
                                    infoColumnWidth: infoWidth,
                                    ruleColor: palette.rule
                                )
                            }
                            Divider().background(palette.rule)
                        }
                    }
                }
                // Fait défiler automatiquement jusqu'à la manœuvre courante en mode Assisté
                // GPS — un roadbook papier n'a pas besoin de ça (tout est déjà sous les yeux),
                // mais sur un écran qui peut dépasser la hauteur visible, c'est le filet de
                // sécurité attendu.
                .onChange(of: currentIndex) { newIndex in
                    guard let newIndex else { return }
                    withAnimation { proxy.scrollTo(newIndex, anchor: .center) }
                }
            }
        }
    }

    private func headerRow(distanceWidth: CGFloat, headingWidth: CGFloat, infoWidth: CGFloat) -> some View {
        HStack(spacing: 0) {
            columnHeader(String(localized: "Distances", bundle: .appLanguage), width: distanceWidth)
            verticalRule
            columnHeader(String(localized: "Cap", bundle: .appLanguage), width: headingWidth)
            verticalRule
            columnHeader(String(localized: "Info", bundle: .appLanguage), width: infoWidth)
        }
        .padding(.vertical, 6)
        .background(Color.primary.opacity(0.04))
    }

    private func columnHeader(_ title: String, width: CGFloat) -> some View {
        Text(title)
            .font(.caption.bold())
            .foregroundStyle(.secondary)
            .frame(width: width)
    }

    private var verticalRule: some View {
        Rectangle().fill(palette.rule).frame(width: 1)
    }
}

/// Ligne HERO — première manœuvre de la liste, esprit "carte" plutôt que ligne de tableau (spec
/// it25, point 3). Garde les 3 données existantes (partielle/cumulée/cap) mais la partielle (le
/// "combien avant CE virage", l'info la plus actionnable) devient le gros chiffre dominant —
/// même rôle que la distance restante dans `RoadbookBigManeuverCard` (mode Assisté GPS).
private struct RoadbookHeroRow: View {
    let maneuver: RoadbookManeuver
    let unit: DistanceUnit
    let isCurrent: Bool
    let liveDistanceRemainingMeters: Double?
    let landmark: RoadbookLandmarkInfo?

    /// Fix "roadbook-classic-landscape-hero-overflow" (it25, retour terrain avec capture :
    /// "Virage prononcé"/"Cap" passaient SOUS la tab bar en mode Liste paysage) — la disposition
    /// verticale portrait (icône, puis distance, puis palier, puis cap/cumulé empilés) est bien
    /// trop haute pour un écran deux fois moins haut en paysage ; même bug de fond que la carte
    /// hero du mode Assisté GPS, jamais corrigé ici puisque `RoadbookHeroRow` n'avait reçu aucune
    /// variante paysage jusqu'ici.
    @Environment(\.verticalSizeClass) private var verticalSizeClass
    /// Spec "roadbook-jump-to-map" — retour terrain : "clic sur un virage dans la liste... aller
    /// dans l'onglet Ride pour voir de quel virage on parle". Jamais un accès à
    /// `RideSessionManager` depuis ce module (invariant "découplé de l'état de Ride actif") —
    /// `AppNavigationState.focusRideMap(on:)` est le SEUL point de passage.
    @EnvironmentObject private var navigationState: AppNavigationState

    var body: some View {
        Button {
            navigationState.focusRideMap(on: maneuver.checkpoint.coordinate)
        } label: {
            Group {
                if verticalSizeClass == .compact {
                    landscapeBody
                } else {
                    portraitBody
                }
            }
        }
        .buttonStyle(.plain)
    }

    private var portraitBody: some View {
        VStack(spacing: 12) {
            HStack(alignment: .center, spacing: 12) {
                RoadbookManeuverIcon(checkpoint: maneuver.checkpoint, size: 84)
                    .foregroundStyle(isCurrent ? Color.accentColor : Color.accentColor.opacity(0.9))
                if let landmark {
                    Text(landmark.category.emoji)
                        .font(.system(size: 46))
                }
            }
            Text(unit.displayString(fromMeters: liveDistanceRemainingMeters ?? maneuver.partialDistanceMeters))
                .font(.system(size: 52, weight: .heavy, design: .rounded))
                .monospacedDigit()
                .minimumScaleFactor(0.6)
                .lineLimit(1)
            Text(maneuver.checkpoint.tier.label)
                .font(.title2.bold())
            HStack(spacing: 8) {
                Text("Cap \(Int(maneuver.headingDegrees.rounded()))°")
                Text("· Cumulé \(unit.displayString(fromMeters: maneuver.cumulativeDistanceMeters))")
            }
            .font(.subheadline.monospacedDigit())
            .foregroundStyle(.secondary)
            if let landmark {
                Text(landmark.displayLabel)
                    .font(.headline)
                    .foregroundStyle(.orange)
                    .multilineTextAlignment(.center)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 28)
        .padding(.horizontal, 20)
    }

    /// Horizontal et compact — même esprit que `RoadbookBigManeuverCardLandscape` (mode Assisté
    /// GPS) : icône à gauche, distance bien visible, palier/cap/cumulé/repère empilés à droite en
    /// petit, jamais plus haut qu'une seule ligne de contrôles.
    private var landscapeBody: some View {
        HStack(spacing: 20) {
            VStack(spacing: 4) {
                RoadbookManeuverIcon(checkpoint: maneuver.checkpoint, size: 84)
                    .foregroundStyle(isCurrent ? Color.accentColor : Color.accentColor.opacity(0.9))
                if let landmark {
                    Text(landmark.category.emoji)
                        .font(.system(size: 30))
                }
            }

            Text(unit.displayString(fromMeters: liveDistanceRemainingMeters ?? maneuver.partialDistanceMeters))
                .font(.system(size: 44, weight: .heavy, design: .rounded))
                .monospacedDigit()
                .minimumScaleFactor(0.6)
                .lineLimit(1)

            VStack(alignment: .leading, spacing: 3) {
                Text(maneuver.checkpoint.tier.label)
                    .font(.headline)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                Text("Cap \(Int(maneuver.headingDegrees.rounded()))° · Cumulé \(unit.displayString(fromMeters: maneuver.cumulativeDistanceMeters))")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                if let landmark {
                    Text(landmark.displayLabel)
                        .font(.caption.bold())
                        .foregroundStyle(.orange)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                }
            }

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 16)
    }
}

private struct RoadbookTableRow: View {
    let maneuver: RoadbookManeuver
    let index: Int
    let unit: DistanceUnit
    let isCurrent: Bool
    let liveDistanceRemainingMeters: Double?
    /// `nil` = pas encore résolu OU résolu sans résultat — les deux cas produisent le même
    /// affichage (rien)
    /// pour éviter de réinterroger un point déjà négatif.
    let landmark: RoadbookLandmarkInfo?
    let distanceColumnWidth: CGFloat
    let headingColumnWidth: CGFloat
    let infoColumnWidth: CGFloat
    let ruleColor: Color

    /// Spec "roadbook-jump-to-map" — voir `RoadbookHeroRow` pour le détail du pourquoi
    /// (`AppNavigationState` reste le seul point de passage vers l'onglet Ride).
    @EnvironmentObject private var navigationState: AppNavigationState

    var body: some View {
        Button {
            navigationState.focusRideMap(on: maneuver.checkpoint.coordinate)
        } label: {
            rowContent
        }
        .buttonStyle(.plain)
    }

    private var rowContent: some View {
        HStack(spacing: 0) {
            // Bloc distances : cumulée en grand (ce qu'on lit sur son compteur), partielle en
            // dessous dans un badge avec le n° de manœuvre — même hiérarchie visuelle que la
            // référence rallye (gros chiffre + petit chiffre encadré). Polices agrandies (it25,
            // point 3 : "priorité à la lisibilité — gants, plein soleil, coup d'œil rapide").
            VStack(spacing: 5) {
                Text(unit.displayString(fromMeters: maneuver.cumulativeDistanceMeters))
                    .font(.title3.monospacedDigit().bold())
                HStack(spacing: 5) {
                    Text("\(index + 1)")
                        .font(.caption.bold())
                        .foregroundStyle(.white)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(isCurrent ? Color.accentColor : Color.secondary, in: Capsule())
                    // Partielle : la distance restante LIVE remplace la distance partielle fixe
                    // pour la manœuvre courante en mode Assisté GPS (même donnée, présentation
                    // différente selon le mode — voir RoadbookLiveProgress).
                    Text(unit.displayString(fromMeters: liveDistanceRemainingMeters ?? maneuver.partialDistanceMeters))
                        .font(.subheadline.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
            }
            .frame(width: distanceColumnWidth)

            verticalRule

            VStack(spacing: 4) {
                // Pictogramme RÉEL du palier (rond-point/fourche/fusion/demi-tour, it24) à côté
                // de l'emoji de repère OSM (it23sexies) — HStack plutôt qu'un badge superposé,
                // plus lisible dans une colonne déjà étroite.
                HStack(spacing: 5) {
                    RoadbookManeuverIcon(checkpoint: maneuver.checkpoint, size: 30)
                        .foregroundStyle(isCurrent ? Color.accentColor : .primary)
                    if let landmark {
                        Text(landmark.category.emoji)
                            .font(.system(size: 26))
                    }
                }
                Text("\(Int(maneuver.headingDegrees.rounded()))°")
                    .font(.caption.bold().monospacedDigit())
                    .foregroundStyle(.secondary)
            }
            .frame(width: headingColumnWidth)

            verticalRule

            VStack(alignment: .leading, spacing: 3) {
                Text(maneuver.checkpoint.tier.label)
                    .font(.headline)
                if let landmark {
                    Text(landmark.displayLabel)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
            }
            .frame(width: infoColumnWidth, alignment: .leading)
            .padding(.leading, 10)
        }
        .padding(.vertical, 14)
        .background(isCurrent ? Color.accentColor.opacity(0.12) : Color.clear)
    }

    private var verticalRule: some View {
        Rectangle().fill(ruleColor).frame(width: 1)
    }
}

/// Ligne "repère visible" (itération "repères = uniquement ce que le conducteur voit") — mêmes
/// colonnes que `RoadbookTableRow` pour rester alignée, mais visuellement distincte d'un
/// changement de direction : pictogramme de la catégorie au lieu d'une flèche, pas de numéro de
/// manœuvre, fond teinté. Distance CUMULÉE (ce qu'on vérifie sur son compteur), nom puis
/// catégorie et côté.
private struct RoadbookLandmarkTableRow: View {
    let landmark: RoadbookLandmarkCheckpoint
    let unit: DistanceUnit
    let distanceColumnWidth: CGFloat
    let headingColumnWidth: CGFloat
    let infoColumnWidth: CGFloat
    let ruleColor: Color

    @EnvironmentObject private var navigationState: AppNavigationState

    var body: some View {
        Button {
            navigationState.focusRideMap(on: landmark.coordinate)
        } label: {
            HStack(spacing: 0) {
                Text(unit.displayString(fromMeters: landmark.cumulativeDistanceMeters))
                    .font(.title3.monospacedDigit().bold())
                    .frame(width: distanceColumnWidth)
                Rectangle().fill(ruleColor).frame(width: 1)
                RoadbookLandmarkIcon(category: landmark.info.category, size: 24)
                    .frame(width: headingColumnWidth)
                Rectangle().fill(ruleColor).frame(width: 1)
                VStack(alignment: .leading, spacing: 2) {
                    Text(landmark.info.localizedLabel)
                        .font(.headline)
                        .lineLimit(2)
                    Text(RoadbookLandmarkRowText.detail(landmark.info))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .frame(width: infoColumnWidth, alignment: .leading)
                .padding(.leading, 10)
            }
            .padding(.vertical, 10)
            .background(Color.accentColor.opacity(0.06))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(String(localized: "Repère : \(landmark.info.displayLabel), \(unit.displayString(fromMeters: landmark.cumulativeDistanceMeters))", bundle: .appLanguage))
    }
}

/// Deuxième ligne d'un repère : catégorie (si le nom affiché n'est pas déjà le libellé
/// générique) et côté — "Entrée d'agglomération · à droite".
enum RoadbookLandmarkRowText {
    static func detail(_ info: RoadbookLandmarkInfo) -> String {
        let category = info.label == info.category.genericLabel ? nil : info.category.localizedGenericLabel
        return [category, info.sideDescription].compactMap { $0 }.joined(separator: " · ").ifEmpty(info.category.localizedGenericLabel)
    }
}

private extension String {
    func ifEmpty(_ fallback: String) -> String { isEmpty ? fallback : self }
}

/// État vide maison — `ContentUnavailableView` (SwiftUI natif) est iOS 17+, incompatible avec
/// la cible 16.0 du projet. Même patron visuel que `LibraryView.emptyState`.
private struct RoadBookEmptyState: View {
    let title: String
    let systemImage: String
    let message: String

    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: systemImage)
                .font(.system(size: 48))
                .foregroundStyle(.secondary)
            Text(title)
                .font(.title2.bold())
            Text(message)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
