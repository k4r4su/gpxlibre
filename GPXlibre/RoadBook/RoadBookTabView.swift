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
                    RoadbookExportOptionsView(trackName: track.name, maneuvers: maneuvers, options: $settings.roadbookPDFOptions)
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
                    ZStack(alignment: .bottomTrailing) {
                        RoadbookFocusedView(
                            maneuvers: maneuvers,
                            currentIndex: liveProgress?.index,
                            distanceRemainingMeters: liveProgress?.distanceRemainingMeters,
                            unit: settings.roadbookPDFOptions.distanceUnit,
                            hasLocationFix: locationManager.currentLocation != nil
                        )

                        if settings.roadbookMiniMapEnabled, let coordinate = locationManager.currentLocation?.coordinate {
                            RoadbookMiniMapView(track: track, currentLocation: coordinate, spanMeters: RoadBookConstants.miniMapSpanMeters)
                                .frame(width: geometry.size.width * 0.36, height: geometry.size.height * 0.15)
                                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                                .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).stroke(.white.opacity(0.5), lineWidth: 1.5))
                                .shadow(color: .black.opacity(0.3), radius: 6, x: 0, y: 3)
                                .padding(14)
                        }
                    }
                }
            } else {
                RoadbookTableView(
                    maneuvers: maneuvers,
                    unit: settings.roadbookPDFOptions.distanceUnit,
                    currentIndex: nil,
                    liveDistanceRemainingMeters: nil
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

/// Table dense en colonnes façon roadbook papier de rallye (spec "roadbook-mode", it23bis,
/// retour terrain : "niveau UI c'est pas ça du tout... regarde ce qui se fait en affichage
/// roadbook, et copie la même chose" — référence choisie explicitement par le propriétaire :
/// "roadbook papier de rallye classique"). Mêmes colonnes que l'export PDF (N°/Cap/Partiel/
/// Total), grille avec traits fins verticaux ET horizontaux — jamais un `List` SwiftUI standard
/// (ses insets/fonds par défaut cassent justement l'effet "tableau imprimé" recherché).
private struct RoadbookTableView: View {
    let maneuvers: [RoadbookManeuver]
    let unit: DistanceUnit
    let currentIndex: Int?
    let liveDistanceRemainingMeters: Double?

    private static let ruleColor = Color.primary.opacity(0.15)
    // Fractions de la largeur totale — les 2 colonnes de distance se partagent le reste à
    // parts égales, jamais une largeur fixe qui laisserait un grand vide à droite sur un écran
    // de téléphone (contrairement à un vrai roadbook papier, étroit par nature).
    private static let numberColumnFraction: CGFloat = 0.13
    private static let headingColumnFraction: CGFloat = 0.22

    var body: some View {
        GeometryReader { geometry in
            let numberWidth = geometry.size.width * Self.numberColumnFraction
            let headingWidth = geometry.size.width * Self.headingColumnFraction
            let distanceWidth = (geometry.size.width - numberWidth - headingWidth) / 2

            ScrollViewReader { proxy in
                ScrollView {
                    VStack(spacing: 0) {
                        headerRow(numberWidth: numberWidth, headingWidth: headingWidth, distanceWidth: distanceWidth)
                        Divider().background(Self.ruleColor)
                        ForEach(Array(maneuvers.enumerated()), id: \.element.id) { index, maneuver in
                            RoadbookTableRow(
                                maneuver: maneuver,
                                index: index,
                                unit: unit,
                                isCurrent: currentIndex == index,
                                liveDistanceRemainingMeters: currentIndex == index ? liveDistanceRemainingMeters : nil,
                                numberColumnWidth: numberWidth,
                                headingColumnWidth: headingWidth,
                                distanceColumnWidth: distanceWidth,
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

    private func headerRow(numberWidth: CGFloat, headingWidth: CGFloat, distanceWidth: CGFloat) -> some View {
        HStack(spacing: 0) {
            columnHeader("N°", width: numberWidth)
            verticalRule
            columnHeader("Cap", width: headingWidth)
            verticalRule
            columnHeader("Partiel", width: distanceWidth)
            verticalRule
            columnHeader("Cumulé", width: distanceWidth)
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
    let numberColumnWidth: CGFloat
    let headingColumnWidth: CGFloat
    let distanceColumnWidth: CGFloat
    let ruleColor: Color

    var body: some View {
        HStack(spacing: 0) {
            Text("\(index + 1)")
                .font(.footnote.monospacedDigit())
                .foregroundStyle(.secondary)
                .frame(width: numberColumnWidth)

            verticalRule

            Image(systemName: maneuver.checkpoint.tier.systemImageName(direction: maneuver.checkpoint.direction))
                .font(.system(size: 22, weight: .bold))
                .foregroundStyle(isCurrent ? Color.accentColor : .primary)
                .rotationEffect(.degrees(maneuver.checkpoint.tier.rotationDegrees(direction: maneuver.checkpoint.direction) ?? 0))
                .frame(width: headingColumnWidth)

            verticalRule

            // Partiel : la distance restante LIVE remplace la distance partielle fixe pour la
            // manœuvre courante en mode Assisté GPS (même donnée, présentation différente selon
            // le mode — jamais une deuxième valeur stockée séparément, voir RoadbookLiveProgress).
            Text(unit.displayString(fromMeters: liveDistanceRemainingMeters ?? maneuver.partialDistanceMeters))
                .font(.subheadline.monospacedDigit().bold())
                .foregroundStyle(isCurrent ? Color.accentColor : .primary)
                .frame(width: distanceColumnWidth)

            verticalRule

            Text(unit.displayString(fromMeters: maneuver.cumulativeDistanceMeters))
                .font(.subheadline.monospacedDigit())
                .foregroundStyle(.secondary)
                .frame(width: distanceColumnWidth)
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
