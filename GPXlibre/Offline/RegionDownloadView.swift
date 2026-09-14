import SwiftUI

/// Écran dédié (depuis le menu Bibliothèque) : cadrer une zone par pan/zoom, choisir le
/// zoom max, estimer, télécharger — et gérer les zones déjà téléchargées (usage disque,
/// suppression).
struct RegionDownloadView: View {
    @EnvironmentObject private var downloadedRegions: DownloadedRegionStore
    @EnvironmentObject private var networkMonitor: NetworkMonitor
    @EnvironmentObject private var settings: RideSettingsStore
    @StateObject private var queue = TileDownloadQueue()

    @State private var visibleBounds: SimpleBounds?
    @State private var maxZoom: Double = Double(OfflineConstants.regionMaxZoomSliderValue)
    @State private var wifiOnly = true
    @State private var estimate: PrecacheEstimate?
    /// Fix "region-picker-huge-bbox-crash" (bug terrain, it16) — voir OfflineConstants.
    @State private var isZoneTooLarge = false
    /// Spec "tiles-zoom-explainer" (it17, Bloc 2) — replié par défaut, pas besoin d'imposer le
    /// texte à qui sait déjà ce qu'est un niveau de zoom.
    @State private var isExplainerExpanded = false

    /// La zone téléchargée suit toujours le thème carte actif (#10), Relief inclus.
    private var activeSource: TileSource { TileSource.active(for: settings.mapThemePreset) }

    var body: some View {
        List {
            Section("Nouvelle zone") {
                Text("Thème actif : \(settings.mapThemePreset.label)")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                // Spec "offline-zones-outline" (it17, Bloc 1) : contour des zones DÉJÀ
                // téléchargées visible en cadrant une nouvelle zone, pour voir la couverture
                // existante d'un coup d'œil.
                RegionPickerMapView(bounds: $visibleBounds, downloadedRegions: downloadedRegions.regions)
                    .frame(height: 220)
                    .listRowInsets(EdgeInsets())

                // Spec "tiles-zoom-explainer" (it17, Bloc 2) : "l'utilisateur final ne
                // comprend pas 'zoom max 12/13'" — encart pédagogique repliable juste
                // au-dessus du sélecteur concerné, pas une page d'aide séparée qu'il faudrait
                // aller chercher.
                DisclosureGroup(isExpanded: $isExplainerExpanded) {
                    Text(OfflineExplainerText.body)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.top, 4)
                } label: {
                    Label(OfflineExplainerText.title, systemImage: "info.circle")
                        .font(.subheadline)
                }

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
                } else if isZoneTooLarge {
                    Text("Zone trop grande pour ce zoom — pince pour réduire la zone visible ou baisse le zoom max.")
                        .font(.caption)
                        .foregroundStyle(.orange)
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
                        Text("\(region.source == .openTopoMap ? "Relief" : "Standard") · \(region.tileCount) tuiles · \(ByteCountFormatter.string(fromByteCount: region.estimatedBytes, countStyle: .file))")
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
        .onChange(of: settings.mapThemePreset) { _ in updateEstimate() }
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
        isZoneTooLarge = false
        guard let bounds = visibleBounds else {
            estimate = nil
            return
        }
        let cappedMaxZoom = min(Int(maxZoom), activeSource.maxZoomLevel)
        guard cappedMaxZoom >= OfflineConstants.regionMinZoomSliderValue else {
            estimate = nil
            return
        }
        // Fix "region-picker-huge-bbox-crash" (bug terrain, it16) : compte D'ABORD en O(1) —
        // une zone "monde" (caméra initiale non cadrée, ou pincement manuel jusqu'au zoom
        // monde) énumérée directement jusqu'au zoom 16 gèle le thread principal (watchdog ~10 s).
        var projectedTileCount = 0
        for zoom in OfflineConstants.regionMinZoomSliderValue...cappedMaxZoom {
            projectedTileCount += TileCoordinate.tileCount(
                minLat: bounds.minLat, maxLat: bounds.maxLat, minLon: bounds.minLon, maxLon: bounds.maxLon, zoom: zoom, source: activeSource
            )
            if projectedTileCount > OfflineConstants.regionTileCountHardCap {
                estimate = nil
                isZoneTooLarge = true
                return
            }
        }
        var tileSet = Set<TileCoordinate>()
        for zoom in OfflineConstants.regionMinZoomSliderValue...cappedMaxZoom {
            let tiles = TileCoordinate.tiles(
                minLat: bounds.minLat, maxLat: bounds.maxLat, minLon: bounds.minLon, maxLon: bounds.maxLon, zoom: zoom, source: activeSource
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
                name: "Zone personnalisée (\(settings.mapThemePreset.label))",
                kind: .customArea,
                trackID: nil,
                tiles: estimate.tiles.map(DownloadedRegion.TileKey.init),
                createdAt: Date(),
                isComplete: success,
                source: activeSource
            )
            downloadedRegions.upsert(region)
        }
    }
}
