import Foundation
import CoreLocation

/// Spec "search-history" (it19, retour terrain sur l'onglet "Aller à" : "il fonctionne, faudrait
/// garder un historique des 5 dernières recherches, le menu est un peu vide sinon") — les
/// résultats de recherche effectivement CHOISIS (pas Domicile/Travail, déjà leur propre accès
/// direct 1-tap ; pas les simples résultats affichés sans être sélectionnés). Dédoublonné par
/// libellé (un même lieu recherché deux fois remonte en tête plutôt que d'apparaître deux fois).
struct NavSearchHistoryEntry: Codable, Identifiable, Equatable {
    let id: UUID
    let label: String
    let coordinate: CLLocationCoordinate2DCodable
    let searchedAt: Date

    init(label: String, coordinate: CLLocationCoordinate2D) {
        self.id = UUID()
        self.label = label
        self.coordinate = CLLocationCoordinate2DCodable(coordinate)
        self.searchedAt = Date()
    }
}

/// Persistance simple, locale (même patron que NavFavoritesStore) — pas de synchro, pas de compte.
@MainActor
final class NavSearchHistoryStore: ObservableObject {
    @Published private(set) var entries: [NavSearchHistoryEntry] = []

    private var fileURL: URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("nav-search-history.json")
    }

    init() { load() }

    /// Fait remonter le libellé en tête s'il existait déjà (recherche répétée), sinon l'ajoute —
    /// borné à `NavConstants.maxSearchHistoryEntries`, les plus anciens tombent en premier.
    func record(coordinate: CLLocationCoordinate2D, label: String) {
        entries.removeAll { $0.label == label }
        entries.insert(NavSearchHistoryEntry(label: label, coordinate: coordinate), at: 0)
        if entries.count > NavConstants.maxSearchHistoryEntries {
            entries.removeLast(entries.count - NavConstants.maxSearchHistoryEntries)
        }
        save()
    }

    func remove(_ entry: NavSearchHistoryEntry) {
        entries.removeAll { $0.id == entry.id }
        save()
    }

    func clear() {
        entries = []
        save()
    }

    private func load() {
        guard let data = try? Data(contentsOf: fileURL),
              let decoded = try? JSONDecoder().decode([NavSearchHistoryEntry].self, from: data) else { return }
        entries = decoded
    }

    private func save() {
        guard let data = try? JSONEncoder().encode(entries) else { return }
        try? data.write(to: fileURL)
    }
}
