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
            .padding()

            Text(settings.roadbookReadingMode.description)
                .font(.caption)
                .foregroundStyle(.secondary)
                .padding(.horizontal)
                .padding(.bottom, 8)

            if settings.roadbookMiniMapEnabled {
                RoadbookMiniMapView(track: track, currentLocation: settings.roadbookReadingMode == .gpsAssisted ? locationManager.currentLocation?.coordinate : nil)
                    .frame(height: 140)
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                    .padding(.horizontal)
                    .padding(.bottom, 8)
            }

            if maneuvers.isEmpty {
                RoadBookEmptyState(
                    title: "Aucune manœuvre détectée",
                    systemImage: "arrow.up",
                    message: "Aucun changement de direction au-dessus du seuil configuré (Réglages > Roadbook) sur cette trace."
                )
            } else {
                List {
                    ForEach(Array(maneuvers.enumerated()), id: \.element.id) { index, maneuver in
                        RoadbookManeuverRow(
                            maneuver: maneuver,
                            index: index,
                            unit: settings.roadbookPDFOptions.distanceUnit,
                            isCurrent: liveProgress?.index == index,
                            liveDistanceRemainingMeters: liveProgress?.index == index ? liveProgress?.distanceRemainingMeters : nil
                        )
                    }
                }
                .listStyle(.plain)
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

private struct RoadbookManeuverRow: View {
    let maneuver: RoadbookManeuver
    let index: Int
    let unit: DistanceUnit
    let isCurrent: Bool
    let liveDistanceRemainingMeters: Double?

    var body: some View {
        HStack(spacing: 14) {
            Text("\(index + 1)")
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)
                .frame(width: 24, alignment: .trailing)

            Image(systemName: maneuver.checkpoint.tier.systemImageName(direction: maneuver.checkpoint.direction))
                .font(.system(size: 20, weight: .bold))
                .foregroundStyle(isCurrent ? Color.accentColor : .primary)
                .frame(width: 30)

            VStack(alignment: .leading, spacing: 2) {
                Text(maneuver.checkpoint.tier.label)
                    .font(.subheadline.bold())
                if let liveDistanceRemainingMeters {
                    Text("Dans \(unit.displayString(fromMeters: liveDistanceRemainingMeters))")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    Text("Partiel \(unit.displayString(fromMeters: maneuver.partialDistanceMeters))")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Spacer()

            Text(unit.displayString(fromMeters: maneuver.cumulativeDistanceMeters))
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 4)
        .listRowBackground(isCurrent ? Color.accentColor.opacity(0.12) : Color.clear)
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
