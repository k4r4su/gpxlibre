import Foundation
import CoreLocation

struct DownloadedRegion: Codable, Identifiable {
    enum Kind: String, Codable {
        case trackCorridor
        case customArea
    }

    let id: UUID
    var name: String
    let kind: Kind
    /// ID de la trace associée si `kind == .trackCorridor`.
    let trackID: UUID?
    let tiles: [TileKey]
    let createdAt: Date
    var isComplete: Bool
    /// Thème/source au moment du téléchargement (#10) — un corridor OSM standard ne compte
    /// jamais comme "Relief déjà téléchargé", et vice versa (dossiers de cache distincts).
    var source: TileSource = .osmStandard

    struct TileKey: Codable, Hashable {
        let z: Int, x: Int, y: Int
        var source: TileSource = .osmStandard
        var coordinate: TileCoordinate { TileCoordinate(z: z, x: x, y: y, source: source) }
        init(_ tile: TileCoordinate) { z = tile.z; x = tile.x; y = tile.y; source = tile.source }
    }

    var tileCount: Int { tiles.count }
    var estimatedBytes: Int64 { Int64(tiles.count) * OfflineConstants.averageTileSizeBytes }

    /// Rectangle englobant (spec "offline-zones-outline", it17, Bloc 1) : "contour fin ambré
    /// ... ou rectangle englobant si la géométrie exacte n'est pas accessible" — le modèle ne
    /// stocke que la liste de tuiles (`tiles`), jamais la bbox/le polygone d'origine, donc
    /// systématiquement le repli bbox explicitement autorisé par le prompt, y compris pour un
    /// corridor de trace (non rectangulaire en réalité — approximation assumée, documentée).
    /// Dérivée SEULEMENT des tuiles du zoom le PLUS BAS présent (le moins nombreuses, un
    /// corridor à 6 niveaux de zoom peut compter des dizaines de milliers de tuiles au zoom
    /// max — inutile de toutes les parcourir pour une simple bbox).
    var boundingBox: (minLat: Double, maxLat: Double, minLon: Double, maxLon: Double)? {
        guard let minZ = tiles.map(\.z).min() else { return nil }
        let tilesAtMinZoom = tiles.filter { $0.z == minZ }
        guard let minX = tilesAtMinZoom.map(\.x).min(), let maxX = tilesAtMinZoom.map(\.x).max(),
              let minY = tilesAtMinZoom.map(\.y).min(), let maxY = tilesAtMinZoom.map(\.y).max()
        else { return nil }
        let northWest = TileCoordinate.northWestCorner(z: minZ, x: minX, y: minY)
        let southEast = TileCoordinate.northWestCorner(z: minZ, x: maxX + 1, y: maxY + 1)
        return (minLat: southEast.latitude, maxLat: northWest.latitude, minLon: northWest.longitude, maxLon: southEast.longitude)
    }
}

/// Persiste la liste des zones téléchargées (corridors de traces + zones manuelles), pour
/// l'écran de gestion (usage disque, suppression) et le badge "100% hors-ligne".
@MainActor
final class DownloadedRegionStore: ObservableObject {
    @Published private(set) var regions: [DownloadedRegion] = []

    private let fileManager = FileManager.default
    private var fileURL: URL {
        let docs = fileManager.urls(for: .documentDirectory, in: .userDomainMask)[0]
        return docs.appendingPathComponent("downloaded-regions.json")
    }

    init() {
        load()
    }

    func region(forTrackID trackID: UUID, source: TileSource) -> DownloadedRegion? {
        regions.first { $0.trackID == trackID && $0.kind == .trackCorridor && $0.source == source }
    }

    func isTrackFullyOffline(_ trackID: UUID, source: TileSource) -> Bool {
        region(forTrackID: trackID, source: source)?.isComplete ?? false
    }

    func upsert(_ region: DownloadedRegion) {
        if let index = regions.firstIndex(where: { $0.id == region.id }) {
            regions[index] = region
        } else {
            regions.append(region)
        }
        save()
    }

    func delete(_ region: DownloadedRegion) {
        TileCacheStore.shared.delete(region.tiles.map(\.coordinate))
        regions.removeAll { $0.id == region.id }
        save()
    }

    private func load() {
        guard let data = try? Data(contentsOf: fileURL),
              let decoded = try? JSONDecoder().decode([DownloadedRegion].self, from: data) else { return }
        regions = decoded
    }

    private func save() {
        guard let data = try? JSONEncoder().encode(regions) else { return }
        try? data.write(to: fileURL)
    }
}
