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

    /// Palette jour/nuit RÉSOLUE (spec "roadbook-ui-redesign", it25, point 0) — recalculée à
    /// l'apparition, à chaque mise à jour de position, à chaque changement du réglage manuel, ET
    /// périodiquement (`paletteReevaluationIntervalSeconds`) pendant que l'écran reste ouvert :
    /// sans ce filet, un Road Book ouvert à cheval sur le coucher du soleil resterait figé sur la
    /// palette du moment de l'ouverture.
    @State private var resolvedPalette: RoadbookPalette = .paper

    private var selectedTrack: GPXTrack? {
        if let selectedTrackID, let track = library.tracks.first(where: { $0.id == selectedTrackID }) {
            return track
        }
        return library.activeTrack ?? library.tracks.first
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
            mergeMinDistanceMeters: settings.turnMergeMinDistanceMeters
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
        // `.task(id:)` annule/relance automatiquement si la trace sélectionnée change — jamais
        // besoin de gérer l'annulation à la main (voir RoadBook/CLAUDE.md pour le détail du
        // fonctionnement best-effort, point par point, sans jamais bloquer l'affichage).
        .task(id: selectedTrack?.id) {
            await loadLandmarksIfNeeded()
        }
    }

    private func updateResolvedPalette() {
        resolvedPalette = RoadbookPaletteResolver.resolve(
            override: settings.roadbookPaletteSetting.overrideValue,
            coordinate: locationManager.currentLocation?.coordinate
        )
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

    @ViewBuilder
    private func content(track: GPXTrack) -> some View {
        VStack(spacing: 0) {
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
                            landmarks: landmarks
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
    }

    /// Bascule PORTRAIT (glisser/zoomer, `RoadbookDraggableMiniMap`, inchangé depuis it23quinquies
    /// — "ça marche" confirmé par retour terrain) / PAYSAGE (`RoadbookLandscapeMiniMap`, coin
    /// fixe, spec it25 point 2). `verticalSizeClass == .compact` = paysage sur iPhone (seul
    /// device family ciblé, `TARGETED_DEVICE_FAMILY "1"`).
    @Environment(\.verticalSizeClass) private var verticalSizeClass

    @ViewBuilder
    private func miniMap(track: GPXTrack, coordinate: CLLocationCoordinate2D, containerSize: CGSize) -> some View {
        if verticalSizeClass == .compact {
            // "Masquée en paysage si le format ne permet pas un rendu propre" — demande
            // explicite, jamais un compromis à moitié cassé.
            if containerSize.height >= RoadBookConstants.miniMapLandscapeMinContainerHeight {
                RoadbookLandscapeMiniMap(track: track, currentLocation: coordinate, spanMeters: settings.roadbookMiniMapSpanMeters)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
                    .padding(10)
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

    var body: some View {
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

    var body: some View {
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
