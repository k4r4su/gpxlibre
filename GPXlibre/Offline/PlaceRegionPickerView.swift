import SwiftUI
import CoreLocation

/// Spec "region-download-by-place" (it21) : "Pays → pays entier ; Région → région + 50 km ;
/// Ville → ville + 100 km" — 3 types de lieu, chacun avec un comportement/rayon par défaut
/// distinct, modifiable ensuite par l'utilisateur.
enum PlaceKind: String, CaseIterable, Identifiable {
    case country, region, city

    var id: String { rawValue }

    var label: String {
        switch self {
        case .country: return "Pays"
        case .region: return "Région"
        case .city: return "Ville"
        }
    }

    /// Valeur `featureType` Nominatim la plus proche — pas de valeur "region" dédiée côté
    /// Nominatim, "state" est l'équivalent le plus proche d'une région administrative.
    var nominatimFeatureType: String {
        switch self {
        case .country: return "country"
        case .region: return "state"
        case .city: return "city"
        }
    }

    /// `nil` pour `.country` : l'emprise RÉELLE du pays (bounding box Nominatim) est utilisée
    /// directement — un rayon fixe autour d'un centroïde n'aurait aucun sens pour un pays de
    /// forme irrégulière (voir `PlaceRegionPickerView.currentBounds()`).
    var defaultRadiusKm: Double? {
        switch self {
        case .country: return nil
        case .region: return OfflineConstants.placeRegionDefaultRadiusKmRegion
        case .city: return OfflineConstants.placeRegionDefaultRadiusKmCity
        }
    }
}

/// Alternative au cadrage manuel pan/zoom de `RegionDownloadView` — recherche un lieu nommé
/// (Nominatim, même service que "Aller à"/Domicile-Travail) et calcule une zone à télécharger
/// depuis son type (pays entier, ou région/ville + rayon réglable). Réutilise
/// `OfflineTileEstimator` (même garde-fou "compter avant d'énumérer" que le cadrage manuel) et
/// `TileDownloadQueue`/`DownloadedRegionStore` à l'identique.
struct PlaceRegionPickerView: View {
    @EnvironmentObject private var downloadedRegions: DownloadedRegionStore
    @EnvironmentObject private var networkMonitor: NetworkMonitor
    @EnvironmentObject private var settings: RideSettingsStore
    @Environment(\.dismiss) private var dismiss
    @StateObject private var queue = TileDownloadQueue()

    @State private var placeKind: PlaceKind = .city
    @State private var query = ""
    @State private var searchResults: [GeocodingResult] = []
    @State private var isSearching = false
    @State private var searchError: String?
    @State private var selectedResult: GeocodingResult?
    @State private var radiusKm: Double = OfflineConstants.placeRegionDefaultRadiusKmCity
    @State private var maxZoom: Double = Double(OfflineConstants.regionMaxZoomSliderValue)
    @State private var estimate: PrecacheEstimate?
    @State private var isZoneTooLarge = false
    @State private var wifiOnly = true

    private var activeSource: TileSource { TileSource.active(for: settings.mapThemePreset) }

    var body: some View {
        // Body factorisé en sous-vues distinctes (spec ne le demandait pas, mais nécessaire
        // ici) — un seul `List` avec toute cette logique en ligne dépasse ce que le
        // type-checker Swift peut résoudre en temps raisonnable ("unable to type-check this
        // expression"), rencontré en compilant ce fichier.
        NavigationStack {
            List {
                placeKindSection
                searchSection
                if selectedResult != nil {
                    zoneSection
                }
            }
            .navigationTitle("Zone par lieu")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Fermer") { dismiss() }
                }
            }
        }
    }

    @ViewBuilder
    private var placeKindSection: some View {
        Section("Type de lieu") {
            // Fix "settings-segmented-picker-missing-title" (it16) : `.pickerStyle(.segmented)`
            // masque son propre label — titre affiché séparément.
            Text("Type de lieu").font(.subheadline)
            Picker("Type de lieu", selection: $placeKind) {
                ForEach(PlaceKind.allCases) { kind in
                    Text(kind.label).tag(kind)
                }
            }
            .pickerStyle(.segmented)
            .onChange(of: placeKind) { newValue in
                selectedResult = nil
                estimate = nil
                isZoneTooLarge = false
                if let defaultRadius = newValue.defaultRadiusKm {
                    radiusKm = defaultRadius
                }
            }
        }
    }

    @ViewBuilder
    private var searchSection: some View {
        Section("Rechercher") {
            HStack {
                TextField("Nom du \(placeKind.label.lowercased())...", text: $query)
                    .textInputAutocapitalization(.words)
                    .autocorrectionDisabled()
                    .onSubmit { search() }
                if isSearching {
                    ProgressView()
                }
            }
            if let searchError {
                Text(searchError)
                    .font(.caption)
                    .foregroundStyle(.orange)
            }
            ForEach(searchResults, id: \.id) { result in
                searchResultRow(result)
            }
        }
    }

    private func searchResultRow(_ result: GeocodingResult) -> some View {
        let isSelected = selectedResult?.id == result.id
        return Button {
            select(result)
        } label: {
            HStack {
                Text(result.displayName)
                    .lineLimit(2)
                    .foregroundStyle(.primary)
                Spacer()
                if isSelected {
                    Image(systemName: "checkmark").foregroundStyle(Color.accentColor)
                }
            }
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private var zoneSection: some View {
        Section("Zone") {
            radiusOrCountryExtentRow
            zoomMaxRow
            estimateRow
            Toggle("Wi-Fi uniquement", isOn: $wifiOnly)
            downloadRow
        }
    }

    @ViewBuilder
    private var radiusOrCountryExtentRow: some View {
        if placeKind == .country {
            Text("Emprise du pays entier (limites administratives Nominatim).")
                .font(.caption)
                .foregroundStyle(.secondary)
        } else {
            VStack(alignment: .leading) {
                Text("Rayon autour : \(Int(radiusKm)) km")
                Slider(value: $radiusKm, in: OfflineConstants.placeRegionRadiusRangeKm, step: 5)
                    .onChange(of: radiusKm) { _ in updateEstimate() }
            }
        }
    }

    private var zoomMaxRow: some View {
        VStack(alignment: .leading) {
            Text("Zoom max : \(Int(maxZoom))")
            Slider(
                value: $maxZoom,
                in: Double(OfflineConstants.regionMinZoomSliderValue)...Double(OfflineConstants.regionMaxZoomSliderValue),
                step: 1
            )
            .onChange(of: maxZoom) { _ in updateEstimate() }
        }
    }

    @ViewBuilder
    private var estimateRow: some View {
        if let estimate {
            Text("\(estimate.tileCount) tuiles · \(estimate.formattedSize) · \(estimate.formattedDuration)")
                .font(.caption)
                .foregroundStyle(.secondary)
        } else if isZoneTooLarge {
            Text("Zone trop grande pour ce zoom — réduis le rayon ou baisse le zoom max.")
                .font(.caption)
                .foregroundStyle(.orange)
        }
    }

    @ViewBuilder
    private var downloadRow: some View {
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

    private func search() {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        isSearching = true
        searchError = nil
        searchResults = []
        selectedResult = nil
        estimate = nil
        Task {
            do {
                let results = try await NominatimGeocodingService.shared.search(query: trimmed, featureType: placeKind.nominatimFeatureType)
                await MainActor.run {
                    searchResults = results
                    isSearching = false
                }
            } catch {
                await MainActor.run {
                    searchError = error.localizedDescription
                    isSearching = false
                }
            }
        }
    }

    private func select(_ result: GeocodingResult) {
        selectedResult = result
        updateEstimate()
    }

    private func currentBounds() -> (minLat: Double, maxLat: Double, minLon: Double, maxLon: Double)? {
        guard let result = selectedResult else { return nil }
        // "Pays → pays entier" : emprise réelle Nominatim si fournie, sinon repli sur le même
        // mécanisme rayon que région/ville (rare : Nominatim fournit quasi toujours une bbox
        // pour un résultat de type pays, mais un rayon large reste préférable à un blocage total).
        if placeKind == .country, let box = result.boundingBox {
            return (box.minLat, box.maxLat, box.minLon, box.maxLon)
        }
        return TileCoordinate.boundingBox(around: result.coordinate, radiusMeters: radiusKm * 1000)
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
        guard let estimate, let result = selectedResult else { return }
        let name = placeKind == .country ? result.displayName : "\(result.displayName) +\(Int(radiusKm)) km"
        queue.download(tiles: estimate.tiles, wifiOnly: wifiOnly, networkMonitor: networkMonitor) { success in
            let region = DownloadedRegion(
                id: UUID(),
                name: name,
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
