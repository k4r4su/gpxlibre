import Foundation

/// Cache disque des repères candidats d'une trace — clé `GPXTrack.id` : les candidats ne dépendent
/// que de la GÉOMÉTRIE (une trace importée ne change jamais), la sélection selon le sens de
/// parcours et les catégories activées est refaite localement (`RoadbookLandmarkSelector`) —
/// inverser le sens ou désactiver une catégorie ne coûte aucune requête. `fetchedCategories` de
/// chaque entrée dit ce qui a déjà été téléchargé (complément seulement pour le reste). Un résultat
/// vide est mis en cache ; un échec réseau jamais (voir `RoadbookLandmarkLoader`).
/// `directoryOverride` : seam de test.
@MainActor
final class RoadbookLandmarkDataCache {
    private struct Entry: Codable {
        let trackID: UUID
        let data: RoadbookLandmarkData
    }

    private var entries: [UUID: RoadbookLandmarkData] = [:]
    private let fileManager = FileManager.default
    private let directoryOverride: URL?

    private var directory: URL {
        let dir = directoryOverride
            ?? fileManager.urls(for: .documentDirectory, in: .userDomainMask)[0].appendingPathComponent("RoadbookLandmarkDataCache", isDirectory: true)
        if !fileManager.fileExists(atPath: dir.path) {
            try? fileManager.createDirectory(at: dir, withIntermediateDirectories: true)
        }
        return dir
    }

    /// v2 (jalon it28) : catégories téléchargées par trace + identifiants OSM. L'ancien
    /// `index.json` (catalogue it27, sans ces informations) est supprimé : il se reconstruit.
    private var indexFileURL: URL { directory.appendingPathComponent("index-v2.json") }

    init(directoryOverride: URL? = nil) {
        self.directoryOverride = directoryOverride
        try? fileManager.removeItem(at: directory.appendingPathComponent("index.json"))
        if let data = try? Data(contentsOf: indexFileURL),
           let decoded = try? JSONDecoder().decode([Entry].self, from: data) {
            entries = Dictionary(decoded.map { ($0.trackID, $0.data) }, uniquingKeysWith: { _, latest in latest })
        }
    }

    func data(for trackID: UUID) -> RoadbookLandmarkData? {
        entries[trackID]
    }

    func store(_ data: RoadbookLandmarkData, for trackID: UUID) {
        entries[trackID] = data
        let encoded = entries.map { Entry(trackID: $0.key, data: $0.value) }
        guard let json = try? JSONEncoder().encode(encoded) else { return }
        try? json.write(to: indexFileURL)
    }
}
