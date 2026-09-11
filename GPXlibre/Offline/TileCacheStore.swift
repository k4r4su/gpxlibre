import Foundation

/// Cache disque des tuiles raster, structuré `MapTiles/{z}/{x}/{y}.png`. Sert de vérité
/// locale : une tuile déjà présente n'est jamais re-téléchargée (pas de round-trip réseau).
final class TileCacheStore {
    static let shared = TileCacheStore()

    private let fileManager = FileManager.default
    private let queue = DispatchQueue(label: "GPXlibre.TileCacheStore", attributes: .concurrent)

    private lazy var baseDirectory: URL = {
        let caches = fileManager.urls(for: .cachesDirectory, in: .userDomainMask)[0]
        let dir = caches.appendingPathComponent(OfflineConstants.cacheDirectoryName, isDirectory: true)
        if !fileManager.fileExists(atPath: dir.path) {
            try? fileManager.createDirectory(at: dir, withIntermediateDirectories: true)
        }
        return dir
    }()

    private init() {}

    func fileURL(for tile: TileCoordinate) -> URL {
        baseDirectory
            .appendingPathComponent("\(tile.z)", isDirectory: true)
            .appendingPathComponent("\(tile.x)", isDirectory: true)
            .appendingPathComponent("\(tile.y).png")
    }

    func hasTile(_ tile: TileCoordinate) -> Bool {
        queue.sync { fileManager.fileExists(atPath: fileURL(for: tile).path) }
    }

    func read(_ tile: TileCoordinate) -> Data? {
        queue.sync { try? Data(contentsOf: fileURL(for: tile)) }
    }

    func write(_ data: Data, for tile: TileCoordinate) {
        queue.sync(flags: .barrier) {
            let url = fileURL(for: tile)
            let dir = url.deletingLastPathComponent()
            if !fileManager.fileExists(atPath: dir.path) {
                try? fileManager.createDirectory(at: dir, withIntermediateDirectories: true)
            }
            try? data.write(to: url)
        }
    }

    func delete(_ tiles: [TileCoordinate]) {
        queue.sync(flags: .barrier) {
            for tile in tiles {
                try? fileManager.removeItem(at: fileURL(for: tile))
            }
        }
    }

    func totalDiskUsageBytes() -> Int64 {
        queue.sync {
            guard let enumerator = fileManager.enumerator(
                at: baseDirectory,
                includingPropertiesForKeys: [.fileSizeKey],
                options: [.skipsHiddenFiles]
            ) else { return 0 }

            var total: Int64 = 0
            for case let url as URL in enumerator {
                if let size = try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize {
                    total += Int64(size)
                }
            }
            return total
        }
    }

    func clearAll() {
        queue.sync(flags: .barrier) {
            try? fileManager.removeItem(at: baseDirectory)
            try? fileManager.createDirectory(at: baseDirectory, withIntermediateDirectories: true)
        }
    }
}
