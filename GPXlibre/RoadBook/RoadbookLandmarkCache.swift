import Foundation
import CoreLocation

/// Cache disque des repères OSM déjà résolus (spec "roadbook-mode", it23quater) — clé =
/// coordonnée arrondie (5 décimales, ~1 m de précision), PAS le couple trace+index comme
/// `RoadbookMapMatchCache` : un repère est une propriété du LIEU, pas de la trace — deux traces
/// qui repassent par le même carrefour profitent du même résultat déjà connu, et un changement
/// de seuils roadbook (qui peut changer QUELLES coordonnées deviennent des manœuvres) n'invalide
/// jamais un résultat déjà acquis pour un point donné.
///
/// `CachedEntry.info == nil` est un résultat NÉGATIF mis en cache (déjà interrogé, rien trouvé
/// à proximité) — distingué d'une absence d'entrée (jamais encore interrogé) via
/// `lookup(for:)`, qui renvoie `RoadbookLandmarkLookup.notCached` dans ce dernier cas. Sans
/// cette distinction, un point sans repère serait réinterrogé à chaque ouverture de l'écran.
enum RoadbookLandmarkLookup: Equatable {
    case notCached
    case cached(RoadbookLandmarkInfo?)
}

private struct CachedEntry: Codable {
    let key: String
    let info: RoadbookLandmarkInfo?
}

@MainActor
final class RoadbookLandmarkCache {
    private var entries: [String: RoadbookLandmarkInfo?] = [:]

    private let fileManager = FileManager.default
    private let directoryOverride: URL?

    private var directory: URL {
        let dir: URL
        if let directoryOverride {
            dir = directoryOverride
        } else {
            let docs = fileManager.urls(for: .documentDirectory, in: .userDomainMask)[0]
            dir = docs.appendingPathComponent("RoadbookLandmarkCache", isDirectory: true)
        }
        if !fileManager.fileExists(atPath: dir.path) {
            try? fileManager.createDirectory(at: dir, withIntermediateDirectories: true)
        }
        return dir
    }

    private var indexFileURL: URL { directory.appendingPathComponent("index.json") }

    init(directoryOverride: URL? = nil) {
        self.directoryOverride = directoryOverride
        loadIndex()
    }

    func lookup(for coordinate: CLLocationCoordinate2D) -> RoadbookLandmarkLookup {
        let key = Self.key(for: coordinate)
        guard let value = entries[key] else { return .notCached }
        return .cached(value)
    }

    func store(info: RoadbookLandmarkInfo?, for coordinate: CLLocationCoordinate2D) {
        entries[Self.key(for: coordinate)] = info
        saveIndex()
    }

    static func key(for coordinate: CLLocationCoordinate2D) -> String {
        String(format: "%.5f,%.5f", coordinate.latitude, coordinate.longitude)
    }

    private func loadIndex() {
        guard let data = try? Data(contentsOf: indexFileURL),
              let decoded = try? JSONDecoder().decode([CachedEntry].self, from: data) else { return }
        entries = Dictionary(uniqueKeysWithValues: decoded.map { ($0.key, $0.info) })
    }

    private func saveIndex() {
        let encoded = entries.map { CachedEntry(key: $0.key, info: $0.value) }
        guard let data = try? JSONEncoder().encode(encoded) else { return }
        try? data.write(to: indexFileURL)
    }
}
