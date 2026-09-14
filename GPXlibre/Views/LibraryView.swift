import SwiftUI
import UniformTypeIdentifiers

struct LibraryView: View {
    @EnvironmentObject private var library: LibraryStore
    @EnvironmentObject private var downloadedRegions: DownloadedRegionStore
    @EnvironmentObject private var settings: RideSettingsStore
    @State private var isImporting = false
    @State private var renamingTrack: GPXTrack?
    @State private var renameText = ""
    @State private var trackToConfigure: GPXTrack?
    /// Fiche complète (spec "biblio-track-fullsheet", it13) — tap sur une ligne, voir
    /// TrackFullSheetView.
    @State private var trackForFullSheet: GPXTrack?

    private static let gpxType = UTType(filenameExtension: "gpx") ?? .xml

    var body: some View {
        NavigationStack {
            Group {
                if library.tracks.isEmpty {
                    emptyState
                } else {
                    trackList
                }
            }
            .navigationTitle("Bibliothèque")
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    NavigationLink {
                        RegionDownloadView()
                    } label: {
                        Image(systemName: "arrow.down.circle")
                    }
                    .longPressTooltip("Cartes hors-ligne")
                }
                ToolbarItem(placement: .navigationBarLeading) {
                    NavigationLink {
                        VectorPackagesView()
                    } label: {
                        Image(systemName: "square.stack.3d.up")
                    }
                    .longPressTooltip("Paquets vectoriels")
                }
                ToolbarItem(placement: .primaryAction) {
                    Menu {
                        Button {
                            isImporting = true
                        } label: {
                            Label("Importer un fichier GPX", systemImage: "square.and.arrow.down")
                        }
                        Button {
                            library.loadSample()
                        } label: {
                            Label("Charger la trace d'exemple", systemImage: "wand.and.stars")
                        }
                    } label: {
                        Image(systemName: "plus")
                    }
                    .longPressTooltip("Ajouter une trace")
                }
            }
            .fileImporter(
                isPresented: $isImporting,
                allowedContentTypes: [Self.gpxType, .xml],
                allowsMultipleSelection: false
            ) { result in
                switch result {
                case .success(let urls):
                    urls.forEach(library.importTrack(from:))
                case .failure(let error):
                    library.lastError = error.localizedDescription
                }
            }
            .alert(
                "Erreur",
                isPresented: Binding(
                    get: { library.lastError != nil },
                    set: { if !$0 { library.lastError = nil } }
                )
            ) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(library.lastError ?? "")
            }
            .alert(
                "Renommer la trace",
                isPresented: Binding(
                    get: { renamingTrack != nil },
                    set: { if !$0 { renamingTrack = nil } }
                )
            ) {
                TextField("Nom", text: $renameText)
                Button("Annuler", role: .cancel) { renamingTrack = nil }
                Button("Enregistrer") {
                    if let track = renamingTrack {
                        library.rename(track, to: renameText)
                    }
                    renamingTrack = nil
                }
            }
        }
    }

    private var emptyState: some View {
        VStack(spacing: 16) {
            Image(systemName: "map")
                .font(.system(size: 48))
                .foregroundStyle(.secondary)
            Text("Aucune trace")
                .font(.title2.bold())
            Text("Importez un fichier GPX depuis Fichiers, Mail ou Safari, ou chargez la trace d'exemple pour commencer.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
            Button("Charger la trace d'exemple") {
                library.loadSample()
            }
            .buttonStyle(.borderedProminent)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var trackList: some View {
        List {
            ForEach(library.tracks) { track in
                // Fix "biblio-track-fullsheet" (it13, terrain : "Tap sur une ligne trace = fiche
                // complète") — le tap n'ouvre plus TrackDetailView (carte + "Utiliser pour le
                // Ride" avec précache) mais une fiche de gestion légère (nom/longueur/infos +
                // Supprimer/Renommer/Paramètres). Décision de scope assumée : TrackDetailView
                // reste intact mais n'a plus de point d'entrée depuis cette liste (voir
                // TODO.md) — "Utiliser pour le Ride" reste accessible via le check-mark de
                // ligne et via TrackSettingsView, "voir la trace" via l'aperçu dans Paramètres.
                Button {
                    trackForFullSheet = track
                } label: {
                    TrackRow(
                        track: track,
                        isFullyOffline: downloadedRegions.isTrackFullyOffline(track.id, source: TileSource.active(for: settings.mapThemePreset)),
                        isActive: library.activeTrackID == track.id,
                        onToggleActive: {
                            if library.activeTrackID == track.id {
                                library.setDisplayed(track.id, false)
                            } else {
                                library.setActive(track.id)
                            }
                        }
                    )
                }
                .buttonStyle(.plain)
                .swipeActions(edge: .trailing) {
                    Button(role: .destructive) {
                        library.delete(track)
                    } label: {
                        Label("Supprimer", systemImage: "trash")
                    }
                    Button {
                        renameText = track.name
                        renamingTrack = track
                    } label: {
                        Label("Renommer", systemImage: "pencil")
                    }
                    .tint(.orange)
                }
                // Swipe à DROITE (edge .leading, spec "per-track-settings") : accès direct au
                // panneau "Paramétrer la trace" — sens, départ personnalisé, apparence, chevrons.
                .swipeActions(edge: .leading) {
                    Button {
                        trackToConfigure = track
                    } label: {
                        Label("Paramétrer", systemImage: "slider.horizontal.3")
                    }
                    .tint(.blue)
                }
            }
        }
        .sheet(item: $trackToConfigure) { track in
            TrackSettingsView(track: track)
        }
        .sheet(item: $trackForFullSheet) { track in
            TrackFullSheetView(
                track: track,
                isFullyOffline: downloadedRegions.isTrackFullyOffline(track.id, source: TileSource.active(for: settings.mapThemePreset)),
                isActive: library.activeTrackID == track.id,
                onDelete: {
                    library.delete(track)
                    trackForFullSheet = nil
                },
                onRename: {
                    renameText = track.name
                    renamingTrack = track
                    trackForFullSheet = nil
                },
                onConfigure: {
                    trackForFullSheet = nil
                    trackToConfigure = track
                }
            )
        }
    }
}

private struct TrackRow: View {
    let track: GPXTrack
    let isFullyOffline: Bool
    /// Fix "single-source-active-track" (Bloc 1, itération 10) : un seul indicateur, la
    /// trace active pour le Ride — coché vert. Bascule explicite en tête de ligne, second
    /// point d'entrée identique dans TrackSettingsView (swipe it8).
    let isActive: Bool
    let onToggleActive: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Button(action: onToggleActive) {
                Image(systemName: isActive ? "checkmark.circle.fill" : "circle")
                    .font(.title3)
                    .foregroundStyle(isActive ? .green : .secondary)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(isActive ? "Trace active pour le Ride, toucher pour désactiver" : "Rendre cette trace active pour le Ride")

            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Text(track.name)
                        .font(.headline)
                    if isFullyOffline {
                        Label("100% hors-ligne", systemImage: "checkmark.seal.fill")
                            .labelStyle(.iconOnly)
                            .foregroundStyle(.green)
                            .accessibilityLabel("Carte 100% hors-ligne")
                    }
                }
                // Spec "biblio-date-display" (it15, Bloc 1) : sobre, gris secondaire, sous le
                // nom — masquable entièrement via LibraryConstants.dateDisplayEnabled.
                if LibraryConstants.dateDisplayEnabled {
                    Text(track.displayDateLabel)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                HStack(spacing: 12) {
                    Label(String(format: "%.1f km", track.totalDistanceKm), systemImage: "ruler")
                    Label("\(track.pointCount) pts", systemImage: "point.topleft.down.curvedto.point.bottomright.up")
                    if track.elevationGainMeters > 0 {
                        Label(String(format: "+%.0f m", track.elevationGainMeters), systemImage: "arrow.up.right")
                    }
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 4)
    }
}
