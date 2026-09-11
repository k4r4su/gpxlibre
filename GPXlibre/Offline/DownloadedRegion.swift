import Foundation

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

    struct TileKey: Codable, Hashable {
        let z: Int, x: Int, y: Int
        var coordinate: TileCoordinate { TileCoordinate(z: z, x: x, y: y) }
        init(_ tile: TileCoordinate) { z = tile.z; x = tile.x; y = tile.y }
    }

    var tileCount: Int { tiles.count }
    var estimatedBytes: Int64 { Int64(tiles.count) * OfflineConstants.averageTileSizeBytes }
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

    func region(forTrackID trackID: UUID) -> DownloadedRegion? {
        regions.first { $0.trackID == trackID && $0.kind == .trackCorridor }
    }

    func isTrackFullyOffline(_ trackID: UUID) -> Bool {
        region(forTrackID: trackID)?.isComplete ?? false
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
