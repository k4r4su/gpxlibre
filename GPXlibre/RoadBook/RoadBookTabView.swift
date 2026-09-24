import SwiftUI
import CoreLocation

/// Onglet Road Book (spec "roadbook-mode", it23, point 1 ; refonte UI/UX "roadbook-ui-redesign",
/// it25) — lecture d'une trace en mode liste de directions pures, esprit roadbook papier de
/// rallye. TOTALEMENT DÉCOUPLÉ de l'état de Ride actif : lit une trace en entrée (celle affichée
/// dans Ride, ou une autre choisie ici depuis la Bibliothèque), ne pilote RIEN — jamais un accès
/// à `RideSessionManager`, jamais une écriture dans `LibraryStore.activeTrackID`/
/// `displayedTrackIDs` (invariant it10). La sélection de trace ici est un `@State` PUREMENT
/// LOCAL à cet écran.
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

    @State private var selectedTrackID: UUID?
    @State private var showExportOptions = false
    @State private var showTrackPicker = false
    @StateObject private var locationManager = LocationManager()
    /// Repères OSM à proximité de chaque manœuvre (spec "roadbook-mode", it23quater) — clé
    /// ABSENTE = pas encore résolu (en cours ou pas commencé), valeur `nil` = résolu, rien
    /// trouvé à proximité, valeur non-nil = repère trouvé. Rempli progressivement par
    /// `loadLandmarksIfNeeded()` (voir `.task(id:)` ci-dessous) — best-effort, ne bloque JAMAIS
    /// l'affichage des manœuvres elles-mêmes.
    @State private var landmarks: [UUID: RoadbookLandmarkInfo?] = [:]
    @State private var landmarkCache = RoadbookLandmarkCache()

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

    /// Trace CANONIQUE (ordre d'origine du fichier GPX) — utilisée uniquement pour la sélection
    /// (comparaison d'id dans le picker) ; jamais passée directement à l'extraction de
    /// manœuvres/la projection GPS, voir `selectedTrack` ci-dessous.
    private var rawSelectedTrack: GPXTrack? {
        if let selectedTrackID, let track = library.tracks.first(where: { $0.id == selectedTrackID }) {
            return track
        }
        return library.activeTrack ?? library.tracks.first
    }

    /// Trace dans le sens RÉELLEMENT affiché/parcouru (fix "roadbook-reversed-direction-broken")
    /// — même patron que `RideView.rideContent` : `reordered(using:)` préserve `id` (voir
    /// `GPXTrack.reordered`), donc le cache map matching (`RoadbookMapMatchCache`, clé =
    /// `track.id`) reste valide quel que soit le sens choisi. TOUJOURS utiliser CETTE propriété
    /// (jamais `rawSelectedTrack`) pour tout calcul de distance cumulée/manœuvre/projection GPS.
    private var selectedTrack: GPXTrack? {
        rawSelectedTrack.map { $0.reordered(using: trackRideSettings.settings(for: $0.id)) }
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
            uTurnThresholdDegrees: settings.roadbookUTurnThresholdDegrees,
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

    /// `nil` tant que le mode Assisté GPS n'a pas de position exploitable — l'affichage retombe
    /// alors silencieusement sur les distances fixes (repli honnête, jamais un crash).
    private var liveProgress: (index: Int, distanceRemainingMeters: Double)? {
        guard settings.roadbookReadingMode == .gpsAssisted,
              let track = selectedTrack, let location = locationManager.currentLocation,
              !maneuvers.isEmpty
        else { return nil }
        let cumulativeDistances = TrackProjector.cumulativeDistances(for: track.points)
        guard let projection = TrackProjector.project(location.coordinate, onto: track.points, cumulativeDistances: cumulativeDistances) else { return nil }
        return RoadbookLiveProgress.nextManeuver(maneuvers: maneuvers, currentCumulativeDistanceMeters: projection.cumulativeDistanceMeters)
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
                    RoadBookEmptyState(
                        title: "Aucune trace",
                        systemImage: "list.bullet.rectangle",
                        message: "Importe ou charge une trace dans la Bibliothèque pour générer un Road Book."
                    )
                }
            }
            .navigationTitle("Road Book")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        showTrackPicker = true
                    } label: {
                        Image(systemName: "map")
                    }
                    .disabled(library.tracks.isEmpty)
                    .accessibilityLabel("Choisir une trace")
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
            .sheet(isPresented: $showTrackPicker) {
                trackPickerSheet
            }
            .sheet(isPresented: $showExportOptions) {
                if let track = selectedTrack {
                    RoadbookExportOptionsView(trackName: track.name, maneuvers: maneuvers, options: $settings.roadbookPDFOptions, landmarks: landmarks)
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
        .onChange(of: locationManager.currentLocation?.coordinate.latitude) { _ in updateResolvedPalette() }
        .onReceive(Timer.publish(every: RoadBookConstants.paletteReevaluationIntervalSeconds, on: .main, in: .common).autoconnect()) { _ in
            updateResolvedPalette()
        }
        // `.task(id:)` annule/relance automatiquement si la trace sélectionnée OU son sens de
        // parcours change (`traversalKey`, fix "mapmatch-cache-direction-aware" — le sens peut
        // changer depuis Réglages de trace pendant que cet onglet reste vivant dans le TabView,
        // sans que `id` ne change) — jamais besoin de gérer l'annulation à la main (voir
        // RoadBook/CLAUDE.md pour le détail du fonctionnement best-effort, point par point).
        .task(id: selectedTrack?.traversalKey) {
            // `Checkpoint.id` est dérivé de `sourcePointIndex` SEUL (fix
            // "roadbook-landmark-id-stability") — deux traces/sens différents peuvent partager le
            // même index, donc jamais réutiliser les entrées d'un parcours précédent ici.
            landmarks = [:]
            if let track = selectedTrack {
                triggerMapMatchingIfNeeded(for: track)
            } else {
                mapMatchedManeuvers = []
            }
            await loadLandmarksIfNeeded()
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
            }
        }
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

    /// Résout les repères OSM manquants un par un (jamais en rafale concurrente — bonne conduite
    /// vis-à-vis d'Overpass, service public gratuit partagé). Un point déjà en cache (positif OU
    /// négatif, voir `RoadbookLandmarkLookup`) ne déclenche jamais de nouvel appel réseau.
    private func loadLandmarksIfNeeded() async {
        for maneuver in maneuvers {
            guard !Task.isCancelled else { return }
            guard landmarks[maneuver.id] == nil else { continue }
            switch landmarkCache.lookup(for: maneuver.checkpoint.coordinate) {
            case .cached(let info):
                landmarks[maneuver.id] = info
            case .notCached:
                let info = await RoadbookLandmarkService.shared.nearbyLandmark(at: maneuver.checkpoint.coordinate)
                guard !Task.isCancelled else { return }
                landmarkCache.store(info: info, for: maneuver.checkpoint.coordinate)
                landmarks[maneuver.id] = info
            }
        }
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
                mainArea(track: track)
                    .frame(maxWidth: .infinity)
                landscapeModeColumn
            }
        } else {
            VStack(spacing: 0) {
                modePickerRow
                mainArea(track: track)
            }
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
            landscapeModeButton(.classic, systemImage: "list.bullet", shortLabel: "Liste")
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
                title: "Aucune manœuvre détectée",
                systemImage: "arrow.up",
                message: "Aucun changement de direction au-dessus du seuil configuré (Réglages > Roadbook) sur cette trace."
            )
        } else if settings.roadbookReadingMode == .gpsAssisted {
            // Fix "roadbook-focused-next-turn" (it23ter, retour terrain : "il faudrait
            // clairement afficher le prochain virage, au moins la moitié de l'écran... la
            // map doit être un aperçu, 15% de l'écran max") — mode Assisté GPS uniquement,
            // "prochain virage" n'a de sens qu'avec une position réelle à comparer. Le mode
            // Classique garde la table complète ci-dessous (aucune notion de "position
            // actuelle" à mettre en avant dans ce mode).
            GeometryReader { geometry in
                ZStack {
                    RoadbookFocusedView(
                        maneuvers: maneuvers,
                        currentIndex: liveProgress?.index,
                        distanceRemainingMeters: liveProgress?.distanceRemainingMeters,
                        unit: settings.roadbookPDFOptions.distanceUnit,
                        hasLocationFix: locationManager.currentLocation != nil,
                        landmarks: landmarks,
                        landscapeMiniMapReservedWidth: showsLandscapeMiniMap(containerSize: geometry.size)
                            ? RoadBookConstants.miniMapLandscapeWidth + 24 : 0
                    )

                    if settings.roadbookMiniMapEnabled, let coordinate = locationManager.currentLocation?.coordinate {
                        miniMap(track: track, coordinate: coordinate, containerSize: geometry.size)
                    }
                }
            }
        } else {
            RoadbookTableView(
                maneuvers: maneuvers,
                unit: settings.roadbookPDFOptions.distanceUnit,
                currentIndex: nil,
                liveDistanceRemainingMeters: nil,
                landmarks: landmarks
            )
        }
    }

    /// Bascule PORTRAIT (glisser/zoomer, `RoadbookDraggableMiniMap`, inchangé depuis it23quinquies
    /// — "ça marche" confirmé par retour terrain) / PAYSAGE (`RoadbookLandscapeMiniMap`, coin
    /// fixe, spec it25 point 2). `verticalSizeClass == .compact` = paysage sur iPhone (seul
    /// device family ciblé, `TARGETED_DEVICE_FAMILY "1"`).
    @Environment(\.verticalSizeClass) private var verticalSizeClass

    /// `true` si la mini-carte paysage sera RÉELLEMENT affichée (mêmes conditions que `miniMap`
    /// ci-dessous) — calculé une seule fois et réutilisé pour réserver la place correspondante
    /// dans le layout du hero (`RoadbookFocusedView.landscapeMiniMapReservedWidth`), jamais
    /// dupliqué/désynchronisé entre les deux (fix "roadbook-landscape-minimap-overlap", it25,
    /// retour terrain avec capture : la mini-carte chevauchait le texte de distance ET la
    /// première ligne de la liste).
    private func showsLandscapeMiniMap(containerSize: CGSize) -> Bool {
        verticalSizeClass == .compact
            && settings.roadbookMiniMapEnabled
            && locationManager.currentLocation != nil
            && containerSize.height >= RoadBookConstants.miniMapLandscapeMinContainerHeight
    }

    @ViewBuilder
    private func miniMap(track: GPXTrack, coordinate: CLLocationCoordinate2D, containerSize: CGSize) -> some View {
        if verticalSizeClass == .compact {
            // "Masquée en paysage si le format ne permet pas un rendu propre" — demande
            // explicite, jamais un compromis à moitié cassé.
            if showsLandscapeMiniMap(containerSize: containerSize) {
                // CONFINÉE à la bande du hero (`.topTrailing`, jamais `.bottomTrailing` sur tout
                // l'écran) — root cause du chevauchement : ancrée sur la hauteur TOTALE (hero +
                // liste), elle débordait dans la zone de la liste en dessous.
                RoadbookLandscapeMiniMap(track: track, currentLocation: coordinate, spanMeters: settings.roadbookMiniMapSpanMeters)
                    .frame(maxWidth: .infinity, alignment: .trailing)
                    .padding(.trailing, 14)
                    .padding(.top, max((RoadBookConstants.focusedHeroLandscapeHeight - RoadBookConstants.miniMapLandscapeHeight) / 2, 8))
                    .frame(maxHeight: .infinity, alignment: .top)
            }
        } else {
            RoadbookDraggableMiniMap(
                track: track,
                currentLocation: coordinate,
                containerSize: containerSize,
                spanMeters: $settings.roadbookMiniMapSpanMeters,
                positionXFraction: $settings.roadbookMiniMapPositionXFraction,
                positionYFraction: $settings.roadbookMiniMapPositionYFraction
            )
        }
    }

    private var trackPickerSheet: some View {
        NavigationStack {
            List {
                ForEach(library.tracks) { track in
                    trackPickerRow(track)
                }
            }
            .navigationTitle("Choisir une trace")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Fermer") { showTrackPicker = false }
                }
            }
        }
    }

    /// Extrait en fonction séparée (piège Swift déjà rencontré ailleurs dans le projet, voir
    /// Offline/CLAUDE.md : un type-checker peut échouer à résoudre une closure de ligne trop
    /// dense mêlant `Button`/`HStack`/comparaison optionnelle, avec des erreurs qui pointent
    /// à tort vers l'appel `List(...)` lui-même plutôt que la vraie ligne en cause).
    @ViewBuilder
    private func trackPickerRow(_ track: GPXTrack) -> some View {
        let isSelected = track.id == selectedTrack?.id
        Button {
            selectedTrackID = track.id
            showTrackPicker = false
        } label: {
            HStack {
                Text(track.name)
                Spacer()
                if isSelected {
                    Image(systemName: "checkmark").foregroundStyle(Color.accentColor)
                }
            }
        }
        .buttonStyle(.plain)
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
        .accessibilityLabel("Service de routage : \(label)")
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
        case .valhalla: return "Détection route-aware active via Valhalla"
        case .osrm: return "Repli OSRM — la précision route-aware (rond-points/fourches) n'est pas garantie"
        case nil: return "Aucune requête de routage récente"
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

                        // Premier élément = HERO (spec it25, point 3 : "au moins 3× plus grand,
                        // doit sauter aux yeux comme ce qui arrive maintenant") — même esprit
                        // visuel que la carte du mode Assisté GPS, données INCHANGÉES (partielle/
                        // cumulée/cap), juste réorganisées autour de cette hiérarchie.
                        if let first = maneuvers.first {
                            RoadbookHeroRow(
                                maneuver: first,
                                unit: unit,
                                isCurrent: currentIndex == 0,
                                liveDistanceRemainingMeters: currentIndex == 0 ? liveDistanceRemainingMeters : nil,
                                landmark: landmarks[first.id] ?? nil
                            )
                            .id(0)
                            .background(palette.surface)
                            Divider().background(palette.rule)
                        }

                        ForEach(Array(maneuvers.enumerated().dropFirst()), id: \.element.id) { index, maneuver in
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
            columnHeader("Distances", width: distanceWidth)
            verticalRule
            columnHeader("Cap", width: headingWidth)
            verticalRule
            columnHeader("Info", width: infoWidth)
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
                Text(landmark.label)
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
                    Text(landmark.label)
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
    /// affichage (rien), la distinction ne sert qu'à `RoadBookTabView.loadLandmarksIfNeeded`
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
                    Text(landmark.label)
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
