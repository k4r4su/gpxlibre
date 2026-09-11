import SwiftUI
import UniformTypeIdentifiers

struct LibraryView: View {
    @EnvironmentObject private var library: LibraryStore
    @EnvironmentObject private var downloadedRegions: DownloadedRegionStore
    @State private var isImporting = false
    @State private var renamingTrack: GPXTrack?
    @State private var renameText = ""

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
                    .accessibilityLabel("Cartes hors-ligne")
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
                NavigationLink(value: track) {
                    TrackRow(track: track, isFullyOffline: downloadedRegions.isTrackFullyOffline(track.id))
                }
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
            }
        }
        .navigationDestination(for: GPXTrack.self) { track in
            TrackDetailView(track: track)
        }
    }
}

private struct TrackRow: View {
    let track: GPXTrack
    let isFullyOffline: Bool

    var body: some View {
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
        .padding(.vertical, 4)
    }
}
