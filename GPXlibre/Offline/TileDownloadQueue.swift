import Foundation

@MainActor
final class TileDownloadQueue: ObservableObject {
    @Published private(set) var isRunning = false
    @Published private(set) var completedCount = 0
    @Published private(set) var totalCount = 0
    @Published private(set) var failedCount = 0

    private var task: Task<Void, Never>?
    private let session = URLSession(configuration: .ephemeral)

    var progress: Double {
        totalCount > 0 ? Double(completedCount + failedCount) / Double(totalCount) : 0
    }

    /// Télécharge les tuiles manquantes (celles déjà en cache sont ignorées, pas de
    /// re-téléchargement). `wifiOnly` respecte le choix par défaut de l'utilisateur.
    func download(tiles: [TileCoordinate], wifiOnly: Bool, networkMonitor: NetworkMonitor, completion: @escaping (Bool) -> Void) {
        cancel()
        let missing = tiles.filter { !TileCacheStore.shared.hasTile($0) }
        completedCount = 0
        failedCount = 0
        totalCount = missing.count
        isRunning = true

        guard !missing.isEmpty else {
            isRunning = false
            completion(true)
            return
        }

        task = Task { [weak self] in
            guard let self else { return }
            if wifiOnly, networkMonitor.isExpensiveOrConstrained {
                await MainActor.run {
                    self.isRunning = false
                    completion(false)
                }
                return
            }

            await withTaskGroup(of: Void.self) { group in
                var iterator = missing.makeIterator()
                var activeCount = 0

                func startNext() {
                    guard let tile = iterator.next() else { return }
                    activeCount += 1
                    group.addTask { [weak self] in
                        await self?.fetch(tile: tile)
                    }
                }

                for _ in 0..<min(OfflineConstants.concurrentDownloads, missing.count) {
                    startNext()
                }
                for await _ in group {
                    if Task.isCancelled { break }
                    startNext()
                }
            }

            await MainActor.run {
                self.isRunning = false
                completion(!Task.isCancelled)
            }
        }
    }

    func cancel() {
        task?.cancel()
        task = nil
        isRunning = false
    }

    private func fetch(tile: TileCoordinate) async {
        guard !Task.isCancelled else { return }
        // Chaque tuile porte sa propre source (osm/opentopo) : le pré-cache suit toujours
        // le thème actif au moment de l'estimation, jamais un template unique codé en dur.
        guard let template = tile.source.tileURLTemplates.randomElement() else {
            await MainActor.run { self.failedCount += 1 }
            return
        }
        let urlString = template
            .replacingOccurrences(of: "{z}", with: "\(tile.z)")
            .replacingOccurrences(of: "{x}", with: "\(tile.x)")
            .replacingOccurrences(of: "{y}", with: "\(tile.y)")
        guard let url = URL(string: urlString) else {
            await MainActor.run { self.failedCount += 1 }
            return
        }
        var request = URLRequest(url: url)
        request.setValue(MapEngineConstants.userAgent, forHTTPHeaderField: "User-Agent")

        do {
            let (data, response) = try await session.data(for: request)
            guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
                await MainActor.run { self.failedCount += 1 }
                return
            }
            TileCacheStore.shared.write(data, for: tile)
            await MainActor.run { self.completedCount += 1 }
        } catch {
            await MainActor.run { self.failedCount += 1 }
        }
    }
}
