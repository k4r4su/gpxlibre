import Foundation
import CoreLocation

/// Cache local du résultat de map matching PAR TRACE (spec
/// "valhalla-map-matching-direction-change", it20, "cache local... pour éviter de refaire
/// l'appel réseau à chaque chargement") — clé = `GPXTrack.id`, valeur = les manœuvres de
/// changement de direction RETENUES par `ValhallaMapMatchingService.matchRoute` (filtrage
/// route-aware, spec it24, point 1). Même patron que `UnsavedRideStore`/`NavSearchHistoryStore` :
/// persistance JSON simple dans un dossier dédié (`Documents/RoadbookMapMatchCache/`),
/// `directoryOverride` comme seam de test pour ne JAMAIS écrire dans le vrai Documents pendant
/// un test.
///
/// AUCUNE invalidation temporelle : une trace GPX ne change pas une fois importée (voir
/// `GPXTrack`, `let points`) — le résultat de map matching pour un `id` donné reste valide tant
/// que la trace existe. Une trace supprimée puis réimportée obtient un nouvel `id` (UUID généré
/// à l'import, voir `LibraryStore.addTrack`), donc jamais de collision avec un cache périmé.
///
/// Format de cache CHANGÉ en it24 (ajout `type`/`roundaboutExitCount`, nécessaires au pictogramme
/// enrichi du point 2) — un ancien fichier `index.json` (format it20, `coordinates` seul) échoue
/// simplement à décoder : dégradation propre, pas un crash (`try?` ci-dessous), le prochain accès
/// se comporte comme un cache vide et relance l'appel réseau en tâche de fond. Aucune migration
/// nécessaire — un cache est par nature un dérivé recalculable, jamais une donnée source.
///
/// Clé CHANGÉE en it26 (fix "mapmatch-cache-direction-aware") : `GPXTrack.traversalKey` au lieu de
/// `GPXTrack.id`. Les types de manœuvre Valhalla dépendent du SENS de parcours (un "tourner à
/// droite" A→B est un "tourner à gauche" B→A, le rang de sortie d'un rond-point change aussi) —
/// indexé par `id` seul, un trajet déjà map-matché dans un sens réutilisait ces manœuvres telles
/// quelles dans l'autre sens. Ancien format (`trackID`) : même dégradation propre qu'en it24.
struct CachedMapMatchedManeuver: Codable {
    let coordinate: CLLocationCoordinate2DCodable
    let maneuverTypeRawValue: Int
    let roundaboutExitCount: Int?
}

struct CachedMapMatch: Codable {
    let traversalKey: String
    let maneuvers: [CachedMapMatchedManeuver]
}

@MainActor
final class RoadbookMapMatchCache {
    private var entries: [String: [CachedMapMatchedManeuver]] = [:]

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

    func maneuvers(for track: GPXTrack) -> [MapMatchedManeuver]? {
        entries[track.traversalKey]?.map {
            MapMatchedManeuver(
                coordinate: $0.coordinate.coordinate,
                type: ValhallaManeuverType(rawValue: $0.maneuverTypeRawValue) ?? .none,
                roundaboutExitCount: $0.roundaboutExitCount
            )
        }
    }

    func store(traversalKey: String, maneuvers: [MapMatchedManeuver]) {
        entries[traversalKey] = maneuvers.map {
            CachedMapMatchedManeuver(
                coordinate: CLLocationCoordinate2DCodable($0.coordinate),
                maneuverTypeRawValue: $0.type.rawValue,
                roundaboutExitCount: $0.roundaboutExitCount
            )
        }
        saveIndex()
    }

    private func loadIndex() {
        guard let data = try? Data(contentsOf: indexFileURL),
              let decoded = try? JSONDecoder().decode([CachedMapMatch].self, from: data) else { return }
        entries = Dictionary(decoded.map { ($0.traversalKey, $0.maneuvers) }, uniquingKeysWith: { _, latest in latest })
    }

    private func saveIndex() {
        let encoded = entries.map { CachedMapMatch(traversalKey: $0.key, maneuvers: $0.value) }
        guard let data = try? JSONEncoder().encode(encoded) else { return }
        try? data.write(to: indexFileURL)
    }
}
