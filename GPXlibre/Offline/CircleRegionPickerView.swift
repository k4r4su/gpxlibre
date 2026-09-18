import SwiftUI
import CoreLocation

/// Remplace `PlaceRegionPickerView` (recherche par nom de lieu, it21) — retour terrain : "pas
/// ultra fan de ça, je pense qu'il faudrait juste avoir une carte, avec un cercle qu'on peut
/// augmenter ou diminuer et cliquer sur télécharger. Simple efficace avec toujours la taille que
/// ça va prendre." Plus besoin de taper un nom de lieu : juste centrer la carte (pan libre) et
/// redimensionner un cercle — plus simple, aucune dépendance à Nominatim.
///
/// "Possibilité de supprimer si ça prend trop de place" : déjà couvert par la section "Zones
/// téléchargées" (swipe pour supprimer) de `RegionDownloadView`, l'écran parent — rien à
/// dupliquer ici.
///
/// Body factorisé en sous-vues distinctes dès le départ (leçon retenue de
/// `PlaceRegionPickerView`, voir Offline/CLAUDE.md "piège Swift") — un seul `List` avec toute
/// cette logique en ligne peut dépasser ce que le type-checker Swift résout en temps
/// raisonnable.
struct CircleRegionPickerView: View {
    @EnvironmentObject private var downloadedRegions: DownloadedRegionStore
    @EnvironmentObject private var networkMonitor: NetworkMonitor
    @EnvironmentObject private var settings: RideSettingsStore
    @Environment(\.dismiss) private var dismiss
    @StateObject private var queue = TileDownloadQueue()
    @StateObject private var locationManager = LocationManager()

    @State private var centerCoordinate: CLLocationCoordinate2D?
    @State private var radiusKm: Double = OfflineConstants.circleRegionDefaultRadiusKm
    @State private var maxZoom: Double = Double(OfflineConstants.regionMaxZoomSliderValue)
    @State private var estimate: PrecacheEstimate?
    @State private var isZoneTooLarge = false
    @State private var wifiOnly = true

    private var activeSource: TileSource { TileSource.active(for: settings.mapThemePreset) }
    private var initialCenter: CLLocationCoordinate2D {
        locationManager.currentLocation?.coordinate ?? OfflineConstants.franceCenterCoordinate
    }

    var body: some View {
        NavigationStack {
            List {
                mapSection
                radiusSection
                zoomSection
                estimateAndDownloadSection
            }
            .navigationTitle("Zone circulaire")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Fermer") { dismiss() }
                }
            }
            .onAppear {
                locationManager.requestAuthorization()
                locationManager.startUpdating()
            }
            .onDisappear {
                locationManager.stopUpdating()
            }
            .onChange(of: radiusKm) { _ in updateEstimate() }
            .onChange(of: maxZoom) { _ in updateEstimate() }
        }
    }

    @ViewBuilder
    private var mapSection: some View {
        Section {
            Text("Thème actif : \(settings.mapThemePreset.label)")
                .font(.caption)
                .foregroundStyle(.secondary)
            // `CLLocationCoordinate2D` n'est pas `Equatable` — pas de `.onChange(of:
            // centerCoordinate)` possible. Binding personnalisé qui déclenche directement
            // `updateEstimate()` à chaque écriture, plutôt qu'un wrapper Equatable dédié pour
            // cette seule utilisation.
            CircleRegionPickerMapView(
                centerCoordinate: Binding(
                    get: { centerCoordinate },
                    set: { newValue in
                        centerCoordinate = newValue
                        updateEstimate()
                    }
                ),
                radiusMeters: radiusKm * 1000,
                downloadedRegions: downloadedRegions.regions,
                initialCenterCoordinate: initialCenter
            )
            .frame(height: 260)
            .listRowInsets(EdgeInsets())
        }
    }

    private var radiusSection: some View {
        Section {
            VStack(alignment: .leading) {
                Text("Rayon : \(Int(radiusKm)) km")
                Slider(value: $radiusKm, in: OfflineConstants.circleRegionRadiusRangeKm, step: 1)
            }
        }
    }

    private var zoomSection: some View {
        Section {
            VStack(alignment: .leading) {
                Text("Zoom max : \(Int(maxZoom))")
                Slider(
                    value: $maxZoom,
                    in: Double(OfflineConstants.regionMinZoomSliderValue)...Double(OfflineConstants.regionMaxZoomSliderValue),
                    step: 1
                )
            }
        }
    }

    @ViewBuilder
    private var estimateAndDownloadSection: some View {
        Section {
            if let estimate {
                Text("\(estimate.tileCount) tuiles · \(estimate.formattedSize) · \(estimate.formattedDuration)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else if isZoneTooLarge {
                Text("Zone trop grande pour ce zoom — réduis le rayon ou baisse le zoom max.")
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
                Button {
                    startDownload()
                } label: {
                    Label("Télécharger cette zone", systemImage: "arrow.down.circle.fill")
                }
                .disabled(estimate == nil)
            }
        }
    }

    private func currentBounds() -> (minLat: Double, maxLat: Double, minLon: Double, maxLon: Double)? {
        guard let center = centerCoordinate ?? Optional(initialCenter) else { return nil }
        return TileCoordinate.boundingBox(around: center, radiusMeters: radiusKm * 1000)
    }

    private func updateEstimate() {
        isZoneTooLarge = false
        guard let bounds = currentBounds() else {
            estimate = nil
            return
        }
        let cappedMaxZoom = min(Int(maxZoom), activeSource.maxZoomLevel)
        guard cappedMaxZoom >= OfflineConstants.regionMinZoomSliderValue else {
            estimate = nil
            return
        }
        switch OfflineTileEstimator.estimate(
            minLat: bounds.minLat, maxLat: bounds.maxLat, minLon: bounds.minLon, maxLon: bounds.maxLon,
            minZoom: OfflineConstants.regionMinZoomSliderValue, maxZoom: cappedMaxZoom, source: activeSource
        ) {
        case .empty:
            estimate = nil
        case .tooLarge:
            estimate = nil
            isZoneTooLarge = true
        case .estimate(let result):
            estimate = result
        }
    }

    private func startDownload() {
        guard let estimate, let center = centerCoordinate ?? Optional(initialCenter) else { return }
        queue.download(tiles: estimate.tiles, wifiOnly: wifiOnly, networkMonitor: networkMonitor) { success in
            let region = DownloadedRegion(
                id: UUID(),
                name: "Zone circulaire ±\(Int(radiusKm)) km (\(settings.mapThemePreset.label))",
                kind: .customArea,
                trackID: nil,
                tiles: estimate.tiles.map(DownloadedRegion.TileKey.init),
                createdAt: Date(),
                isComplete: success,
                source: activeSource
            )
            downloadedRegions.upsert(region)
            dismiss()
        }
    }
}
