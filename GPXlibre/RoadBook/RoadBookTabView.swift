import SwiftUI
import CoreLocation

/// Onglet Road Book (spec "roadbook-mode", it23, point 1) — lecture d'une trace en mode liste
/// de directions pures, esprit roadbook papier de rallye. TOTALEMENT DÉCOUPLÉ de l'état de Ride
/// actif : lit une trace en entrée (celle affichée dans Ride, ou une autre choisie ici depuis
/// la Bibliothèque), ne pilote RIEN — jamais un accès à `RideSessionManager`, jamais une
/// écriture dans `LibraryStore.activeTrackID`/`displayedTrackIDs` (invariant it10). La sélection
/// de trace ici est un `@State` PUREMENT LOCAL à cet écran.
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
    @State private var landmarks: [UUID: String?] = [:]
    @State private var landmarkCache = RoadbookLandmarkCache()

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
        .onAppear {
            if settings.roadbookReadingMode == .gpsAssisted {
                locationManager.requestAuthorization()
                locationManager.startUpdating()
            }
        }
        .onDisappear {
            locationManager.stopUpdating()
        }
        .onChange(of: settings.roadbookReadingMode) { mode in
            if mode == .gpsAssisted {
                locationManager.requestAuthorization()
                locationManager.startUpdating()
            } else {
                locationManager.stopUpdating()
            }
        }
        // `.task(id:)` annule/relance automatiquement si la trace sélectionnée change — jamais
        // besoin de gérer l'annulation à la main (voir RoadBook/CLAUDE.md pour le détail du
        // fonctionnement best-effort, point par point, sans jamais bloquer l'affichage).
        .task(id: selectedTrack?.id) {
            await loadLandmarksIfNeeded()
        }
    }

    /// Résout les repères OSM manquants un par un (jamais en rafale concurrente — bonne conduite
    /// vis-à-vis d'Overpass, service public gratuit partagé). Un point déjà en cache (positif OU
    /// négatif, voir `RoadbookLandmarkLookup`) ne déclenche jamais de nouvel appel réseau.
    private func loadLandmarksIfNeeded() async {
        for maneuver in maneuvers {
            guard !Task.isCancelled else { return }
            guard landmarks[maneuver.id] == nil else { continue }
            switch landmarkCache.lookup(for: maneuver.checkpoint.coordinate) {
            case .cached(let label):
                landmarks[maneuver.id] = label
            case .notCached:
                let label = await RoadbookLandmarkService.shared.nearbyLandmark(at: maneuver.checkpoint.coordinate)
                guard !Task.isCancelled else { return }
                landmarkCache.store(label: label, for: maneuver.checkpoint.coordinate)
                landmarks[maneuver.id] = label
            }
        }
    }

    @ViewBuilder
    private func content(track: GPXTrack) -> some View {
        VStack(spacing: 0) {
            Picker("Mode de lecture", selection: $settings.roadbookReadingMode) {
                ForEach(RoadbookReadingMode.allCases) { mode in
                    Text(mode.label).tag(mode)
                }
            }
            .pickerStyle(.segmented)
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
                            RoadbookDraggableMiniMap(
                                track: track,
                                currentLocation: coordinate,
                                containerSize: geometry.size,
                                spanMeters: $settings.roadbookMiniMapSpanMeters,
                                positionXFraction: $settings.roadbookMiniMapPositionXFraction,
                                positionYFraction: $settings.roadbookMiniMapPositionYFraction
                            )
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

/// Table dense en colonnes façon roadbook papier de rallye (spec "roadbook-mode", it23bis/
/// it23quater, retour terrain : "regarde ce qui se fait en affichage roadbook, et copie la
/// même chose" — capture d'un vrai roadbook rallye fournie par le propriétaire, adaptée en 3
/// blocs : distances (cumulée en grand, partielle en dessous), cap (pictogramme + degrés),
/// info (direction + repère OSM à proximité si trouvé). Jamais un `List` SwiftUI standard (ses
/// insets/fonds par défaut cassent l'effet "tableau imprimé" recherché).
private struct RoadbookTableView: View {
    let maneuvers: [RoadbookManeuver]
    let unit: DistanceUnit
    let currentIndex: Int?
    let liveDistanceRemainingMeters: Double?
    let landmarks: [UUID: String?]

    private static let ruleColor = Color.primary.opacity(0.15)
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
                        Divider().background(Self.ruleColor)
                        ForEach(Array(maneuvers.enumerated()), id: \.element.id) { index, maneuver in
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
                                ruleColor: Self.ruleColor
                            )
                            .id(index)
                            Divider().background(Self.ruleColor)
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
            .font(.caption2.bold())
            .foregroundStyle(.secondary)
            .frame(width: width)
    }

    private var verticalRule: some View {
        Rectangle().fill(Self.ruleColor).frame(width: 1)
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
    let landmark: String?
    let distanceColumnWidth: CGFloat
    let headingColumnWidth: CGFloat
    let infoColumnWidth: CGFloat
    let ruleColor: Color

    var body: some View {
        HStack(spacing: 0) {
            // Bloc distances : cumulée en grand (ce qu'on lit sur son compteur), partielle en
            // dessous dans un badge avec le n° de manœuvre — même hiérarchie visuelle que la
            // référence rallye (gros chiffre + petit chiffre encadré).
            VStack(spacing: 4) {
                Text(unit.displayString(fromMeters: maneuver.cumulativeDistanceMeters))
                    .font(.subheadline.monospacedDigit().bold())
                HStack(spacing: 4) {
                    Text("\(index + 1)")
                        .font(.caption2.bold())
                        .foregroundStyle(.white)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 1)
                        .background(isCurrent ? Color.accentColor : Color.secondary, in: Capsule())
                    // Partielle : la distance restante LIVE remplace la distance partielle fixe
                    // pour la manœuvre courante en mode Assisté GPS (même donnée, présentation
                    // différente selon le mode — voir RoadbookLiveProgress).
                    Text(unit.displayString(fromMeters: liveDistanceRemainingMeters ?? maneuver.partialDistanceMeters))
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
            }
            .frame(width: distanceColumnWidth)

            verticalRule

            VStack(spacing: 3) {
                Image(systemName: maneuver.checkpoint.tier.systemImageName(direction: maneuver.checkpoint.direction))
                    .font(.system(size: 22, weight: .bold))
                    .foregroundStyle(isCurrent ? Color.accentColor : .primary)
                    .rotationEffect(.degrees(maneuver.checkpoint.tier.rotationDegrees(direction: maneuver.checkpoint.direction) ?? 0))
                Text("\(Int(maneuver.headingDegrees.rounded()))°")
                    .font(.caption2.bold().monospacedDigit())
                    .foregroundStyle(.secondary)
            }
            .frame(width: headingColumnWidth)

            verticalRule

            VStack(alignment: .leading, spacing: 2) {
                Text(maneuver.checkpoint.tier.label)
                    .font(.subheadline.bold())
                if let landmark {
                    Text(landmark)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
            }
            .frame(width: infoColumnWidth, alignment: .leading)
            .padding(.leading, 10)
        }
        .padding(.vertical, 10)
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
