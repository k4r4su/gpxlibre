import Foundation

/// Cache disque des checkpoints d'entrée de commune (spec "roadbook-locality-checkpoints", it26
/// point 3) — clé `GPXTrack.traversalKey` : "par trace ET par sens" (demande explicite), les
/// entrées de commune d'un sens étant aux limites opposées, dans l'ordre inverse. Un résultat
/// VIDE est mis en cache (trace qui ne quitte jamais sa commune : rien à réinterroger) ; un
/// ÉCHEC réseau ne l'est jamais (voir `RoadBookTabView`), pour réessayer à la prochaine ouverture.
/// `directoryOverride` : seam de test, jamais le vrai `Documents/` pendant un test.
@MainActor
final class RoadbookLocalityCache {
    private struct Entry: Codable {
        let traversalKey: String
        let checkpoints: [RoadbookLocalityCheckpoint]
    }

    private var entries: [String: [RoadbookLocalityCheckpoint]] = [:]
    private let fileManager = FileManager.default
    private let directoryOverride: URL?

    private var directory: URL {
        let dir = directoryOverride
            ?? fileManager.urls(for: .documentDirectory, in: .userDomainMask)[0].appendingPathComponent("RoadbookLocalityCache", isDirectory: true)
        if !fileManager.fileExists(atPath: dir.path) {
            try? fileManager.createDirectory(at: dir, withIntermediateDirectories: true)
        }
        return dir
    }

    private var indexFileURL: URL { directory.appendingPathComponent("index.json") }

    init(directoryOverride: URL? = nil) {
        self.directoryOverride = directoryOverride
        if let data = try? Data(contentsOf: indexFileURL),
           let decoded = try? JSONDecoder().decode([Entry].self, from: data) {
            entries = Dictionary(decoded.map { ($0.traversalKey, $0.checkpoints) }, uniquingKeysWith: { _, latest in latest })
        }
    }

    func checkpoints(for track: GPXTrack) -> [RoadbookLocalityCheckpoint]? {
        entries[track.traversalKey]
    }

    func store(_ checkpoints: [RoadbookLocalityCheckpoint], traversalKey: String) {
        entries[traversalKey] = checkpoints
        let encoded = entries.map { Entry(traversalKey: $0.key, checkpoints: $0.value) }
        guard let data = try? JSONEncoder().encode(encoded) else { return }
        try? data.write(to: indexFileURL)
    }
}
