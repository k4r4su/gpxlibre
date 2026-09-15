import SwiftUI

/// Affiché avant de démarrer le Ride sur une trace : estimation du corridor hors-ligne
/// (±1 km, zoom 10-15) et choix Wi-Fi uniquement (défaut) / inclure les données mobiles.
struct PrecacheConfirmationView: View {
    let track: GPXTrack
    let onFinished: () -> Void

    @EnvironmentObject private var networkMonitor: NetworkMonitor
    @EnvironmentObject private var downloadedRegions: DownloadedRegionStore
    @EnvironmentObject private var settings: RideSettingsStore
    @StateObject private var queue = TileDownloadQueue()
    @Environment(\.dismiss) private var dismiss

    @State private var estimate: PrecacheEstimate?
    @State private var wifiOnly = true

    /// Le corridor pré-caché DOIT suivre le thème carte actif (#10), Relief inclus.
    private var activeSource: TileSource { TileSource.active(for: settings.mapThemePreset) }

    var body: some View {
        NavigationStack {
            VStack(spacing: 24) {
                if downloadedRegions.isTrackFullyOffline(track.id, source: activeSource) {
                    Label("Corridor déjà 100% hors-ligne", systemImage: "checkmark.seal.fill")
                        .foregroundStyle(.green)
                        .font(.headline)
                } else if let estimate {
                    VStack(spacing: 8) {
                        Text("Télécharger la carte hors-ligne de ce parcours ?")
                            .font(.headline)
                            .multilineTextAlignment(.center)
                        Text("Corridor ±1 km · \(estimate.tileCount) tuiles · \(estimate.formattedSize) · \(estimate.formattedDuration)")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                    }

                    if queue.isRunning {
                        ProgressView(value: queue.progress)
                            .padding(.horizontal, 32)
                        Text("\(queue.completedCount)/\(queue.totalCount) tuiles")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    } else {
                        Toggle("Wi-Fi uniquement", isOn: $wifiOnly)
                            .padding(.horizontal, 32)

                        VStack(spacing: 12) {
                            Button {
                                startDownload()
                            } label: {
                                Label(wifiOnly ? "OK en Wi-Fi only" : "Inclure la connexion mobile", systemImage: wifiOnly ? "wifi" : "antenna.radiowaves.left.and.right")
                            }
                            .buttonStyle(.borderedProminent)

                            Button {
                                onFinished()
                            } label: {
                                Label("Plus tard", systemImage: "clock")
                            }
                            .buttonStyle(.bordered)
                        }
                    }
                } else {
                    ProgressView("Estimation…")
                }
            }
            .padding()
            .navigationTitle("Carte hors-ligne")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Fermer") { onFinished() }
                }
            }
        }
        .onAppear {
            if estimate == nil {
                estimate = CorridorPrecacheEstimator.estimate(for: track, source: activeSource)
            }
        }
        .onChange(of: settings.mapThemePreset) { _ in
            // Le thème a changé pendant que la feuille est ouverte : ré-estimer pour la
            // nouvelle source plutôt que de proposer un téléchargement obsolète.
            estimate = CorridorPrecacheEstimator.estimate(for: track, source: activeSource)
        }
    }

    private func startDownload() {
        guard let estimate else { return }
        queue.download(tiles: estimate.tiles, wifiOnly: wifiOnly, networkMonitor: networkMonitor) { success in
            let region = DownloadedRegion(
                id: downloadedRegions.region(forTrackID: track.id, source: activeSource)?.id ?? UUID(),
                name: track.name,
                kind: .trackCorridor,
                trackID: track.id,
                tiles: estimate.tiles.map(DownloadedRegion.TileKey.init),
                createdAt: Date(),
                isComplete: success,
                source: activeSource
            )
            downloadedRegions.upsert(region)
            onFinished()
        }
    }
}
