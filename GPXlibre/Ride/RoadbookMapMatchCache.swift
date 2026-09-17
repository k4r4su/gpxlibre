import Foundation
import CoreLocation

/// Cache local du résultat de map matching PAR TRACE (spec
/// "valhalla-map-matching-direction-change", it20, "cache local... pour éviter de refaire
/// l'appel réseau à chaque chargement") — clé = `GPXTrack.id`, valeur = les coordonnées de
/// changement de manœuvre détectées par `ValhallaMapMatchingService.matchRoute`. Même patron
/// que `UnsavedRideStore`/`NavSearchHistoryStore` : persistance JSON simple dans un dossier
/// dédié (`Documents/RoadbookMapMatchCache/`), `directoryOverride` comme seam de test pour ne
/// JAMAIS écrire dans le vrai Documents pendant un test.
///
/// AUCUNE invalidation temporelle : une trace GPX ne change pas une fois importée (voir
/// `GPXTrack`, `let points`) — le résultat de map matching pour un `id` donné reste valide tant
/// que la trace existe. Une trace supprimée puis réimportée obtient un nouvel `id` (UUID généré
/// à l'import, voir `LibraryStore.addTrack`), donc jamais de collision avec un cache périmé.
struct CachedMapMatch: Codable {
    let trackID: UUID
    let coordinates: [CLLocationCoordinate2DCodable]
}

@MainActor
final class RoadbookMapMatchCache {
    private var entries: [UUID: [CLLocationCoordinate2DCodable]] = [:]

    private let fileManager = FileManager.default
    private let directoryOverride: URL?

    private var directory: URL {
        let dir: URL
        if let directoryOverride {
            dir = directoryOverride
        } else {
            let docs = fileManager.urls(for: .documentDirectory, in: .userDomainMask)[0]
            dir = docs.appendingPathComponent("RoadbookMapMatchCache", isDirectory: true)
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

    func coordinates(for trackID: UUID) -> [CLLocationCoordinate2D]? {
        entries[trackID]?.map(\.coordinate)
    }

    func store(trackID: UUID, coordinates: [CLLocationCoordinate2D]) {
        entries[trackID] = coordinates.map(CLLocationCoordinate2DCodable.init)
        saveIndex()
    }

    private func loadIndex() {
        guard let data = try? Data(contentsOf: indexFileURL),
              let decoded = try? JSONDecoder().decode([CachedMapMatch].self, from: data) else { return }
        entries = Dictionary(uniqueKeysWithValues: decoded.map { ($0.trackID, $0.coordinates) })
    }

    private func saveIndex() {
        let encoded = entries.map { CachedMapMatch(trackID: $0.key, coordinates: $0.value) }
        guard let data = try? JSONEncoder().encode(encoded) else { return }
        try? data.write(to: indexFileURL)
    }
}
