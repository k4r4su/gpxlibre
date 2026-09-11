import Foundation
import CoreLocation

struct NavFavorite: Codable, Identifiable {
    enum Slot: String, Codable {
        case home, work, other
    }

    let id: UUID
    var label: String
    let slot: Slot
    let coordinate: CLLocationCoordinate2DCodable

    init(label: String, slot: Slot, coordinate: CLLocationCoordinate2D) {
        self.id = UUID()
        self.label = label
        self.slot = slot
        self.coordinate = CLLocationCoordinate2DCodable(coordinate)
    }
}

/// Domicile/Travail en 1 tap, plus quelques favoris libres. Persistance simple, locale.
@MainActor
final class NavFavoritesStore: ObservableObject {
    @Published private(set) var favorites: [NavFavorite] = []

    private var fileURL: URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("nav-favorites.json")
    }

    var home: NavFavorite? { favorites.first { $0.slot == .home } }
    var work: NavFavorite? { favorites.first { $0.slot == .work } }

    init() { load() }

    func setHome(_ coordinate: CLLocationCoordinate2D, label: String = "Domicile") {
        set(slot: .home, label: label, coordinate: coordinate)
    }

    func setWork(_ coordinate: CLLocationCoordinate2D, label: String = "Travail") {
        set(slot: .work, label: label, coordinate: coordinate)
    }

    func addOther(_ coordinate: CLLocationCoordinate2D, label: String) {
        guard favorites.filter({ $0.slot == .other }).count < NavConstants.maxSavedFavorites else { return }
        favorites.append(NavFavorite(label: label, slot: .other, coordinate: coordinate))
        save()
    }

    func delete(_ favorite: NavFavorite) {
        favorites.removeAll { $0.id == favorite.id }
        save()
    }

    private func set(slot: NavFavorite.Slot, label: String, coordinate: CLLocationCoordinate2D) {
        favorites.removeAll { $0.slot == slot }
        favorites.append(NavFavorite(label: label, slot: slot, coordinate: coordinate))
        save()
    }

    private func load() {
        guard let data = try? Data(contentsOf: fileURL),
              let decoded = try? JSONDecoder().decode([NavFavorite].self, from: data) else { return }
        favorites = decoded
    }

    private func save() {
        guard let data = try? JSONEncoder().encode(favorites) else { return }
        try? data.write(to: fileURL)
    }
}
