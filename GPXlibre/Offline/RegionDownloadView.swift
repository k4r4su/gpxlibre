import SwiftUI

/// Écran dédié (depuis le menu Bibliothèque) : cadrer une zone par pan/zoom, choisir le
/// zoom max, estimer, télécharger — et gérer les zones déjà téléchargées (usage disque,
/// suppression).
struct RegionDownloadView: View {
    @EnvironmentObject private var downloadedRegions: DownloadedRegionStore
    @EnvironmentObject private var networkMonitor: NetworkMonitor
    @StateObject private var queue = TileDownloadQueue()

    @State private var visibleBounds: SimpleBounds?
    @State private var maxZoom: Double = Double(OfflineConstants.regionMaxZoomSliderValue)
    @State private var wifiOnly = true
    @State private var estimate: PrecacheEstimate?

    var body: some View {
        List {
            Section("Nouvelle zone") {
                RegionPickerMapView(bounds: $visibleBounds)
                    .frame(height: 220)
                    .listRowInsets(EdgeInsets())

                VStack(alignment: .leading) {
                    Text("Zoom max : \(Int(maxZoom))")
                    Slider(
                        value: $maxZoom,
                        in: Double(OfflineConstants.regionMinZoomSliderValue)...Double(OfflineConstants.regionMaxZoomSliderValue),
                        step: 1
                    )
                }

                if let estimate {
                    Text("\(estimate.tileCount) tuiles · \(estimate.formattedSize) · \(estimate.formattedDuration)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Toggle("Wi-Fi uniquement", isOn: $wifiOnly)

                if queue.isRunning {
                    ProgressView(value: queue.progress)
                    Text("\(queue.completedCount)/\(queue.totalCount) tuiles")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    Button("Télécharger cette zone") { startDownload() }
                        .disabled(visibleBounds == nil)
                }
            }

            Section("Zones téléchargées") {
                if downloadedRegions.regions.isEmpty {
                    Text("Aucune zone téléchargée pour l'instant.")
                        .foregroundStyle(.secondary)
                }
                ForEach(downloadedRegions.regions) { region in
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Text(region.name).font(.headline)
                            if region.isComplete {
                                Image(systemName: "checkmark.seal.fill").foregroundStyle(.green)
                            }
                        }
                        Text("\(region.tileCount) tuiles · \(ByteCountFormatter.string(fromByteCount: region.estimatedBytes, countStyle: .file))")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .swipeActions {
                        Button(role: .destructive) {
                            downloadedRegions.delete(region)
                        } label: {
                            Label("Supprimer", systemImage: "trash")
                        }
                    }
                }

                diskUsageRow
            }
        }
        .navigationTitle("Cartes hors-ligne")
        .onChange(of: visibleBounds) { _ in updateEstimate() }
        .onChange(of: maxZoom) { _ in updateEstimate() }
    }

    private var diskUsageRow: some View {
        let total = TileCacheStore.shared.totalDiskUsageBytes()
        return VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text("Espace utilisé")
                Spacer()
                Text(ByteCountFormatter.string(fromByteCount: total, countStyle: .file))
                    .foregroundStyle(.secondary)
            }
            if total > OfflineConstants.cacheCleanupSuggestionThresholdBytes {
                Text("Le cache dépasse 1 Go — supprime les zones inutilisées ci-dessus si besoin.")
                    .font(.caption)
                    .foregroundStyle(.orange)
            }
        }
    }

    private func updateEstimate() {
        guard let bounds = visibleBounds else {
            estimate = nil
            return
        }
        var tileSet = Set<TileCoordinate>()
        for zoom in OfflineConstants.regionMinZoomSliderValue...Int(maxZoom) {
            let tiles = TileCoordinate.tiles(
                minLat: bounds.minLat, maxLat: bounds.maxLat, minLon: bounds.minLon, maxLon: bounds.maxLon, zoom: zoom
            )
            tileSet.formUnion(tiles)
        }
        estimate = PrecacheEstimate(tiles: Array(tileSet))
    }

    private func startDownload() {
        guard let estimate else { return }
        queue.download(tiles: estimate.tiles, wifiOnly: wifiOnly, networkMonitor: networkMonitor) { success in
            let region = DownloadedRegion(
                id: UUID(),
                name: "Zone personnalisée",
                kind: .customArea,
                trackID: nil,
                tiles: estimate.tiles.map(DownloadedRegion.TileKey.init),
                createdAt: Date(),
                isComplete: success
            )
            downloadedRegions.upsert(region)
        }
    }
}
