import SwiftUI
import CoreLocation

/// Nouvel écran Réglages > Adresses favoris (spec "home-work-favorites", it13) — terrain :
/// "le ride search suggère déjà Domicile/Travail mais nulle part où configurer ces deux
/// adresses." NavFavoritesStore.setHome/setWork existaient déjà (depuis quelle itération ?
/// aucun appelant avant ce bloc) — cet écran est le chaînon manquant, pas une nouvelle donnée.
///
/// Deux méthodes de saisie volontairement simples : recherche d'adresse (Nominatim, même
/// service que la recherche Ride) et position actuelle. Pas de sélection "pan sur la carte"
/// dans cette itération — décision de scope assumée, voir TODO.md.
struct FavoriteAddressesView: View {
    @EnvironmentObject private var favorites: NavFavoritesStore
    @State private var editingTarget: EditingTarget?

    private struct EditingTarget: Identifiable {
        let id = UUID()
        let slot: NavFavorite.Slot
    }

    var body: some View {
        List {
            Section {
                row(title: "Domicile", systemImage: "house.fill", favorite: favorites.home, slot: .home)
                row(title: "Travail", systemImage: "briefcase.fill", favorite: favorites.work, slot: .work)
            } footer: {
                Text("Ces adresses alimentent les suggestions rapides de la recherche \"Aller à\" en Ride.")
            }
        }
        .navigationTitle("Adresses favoris")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(item: $editingTarget) { target in
            FavoriteAddressPickerView(slot: target.slot)
        }
    }

    private func row(title: String, systemImage: String, favorite: NavFavorite?, slot: NavFavorite.Slot) -> some View {
        Button {
            editingTarget = EditingTarget(slot: slot)
        } label: {
            HStack {
                Image(systemName: systemImage)
                    .foregroundStyle(favorite != nil ? Color.accentColor : Color.secondary)
                    .frame(width: 28)
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .foregroundStyle(.primary)
                    Text(favorite?.label ?? "Non défini — touche pour configurer")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
        }
        .buttonStyle(.plain)
    }
}

/// Choix d'une adresse pour un slot donné (Domicile/Travail) — recherche Nominatim (même
/// patron que NavDestinationSearchView, gardé séparé volontairement : contenu et actions
/// différents — favoris à écrire, pas de profil de guidage à choisir) ou position actuelle.
private struct FavoriteAddressPickerView: View {
    let slot: NavFavorite.Slot

    @EnvironmentObject private var favorites: NavFavoritesStore
    @StateObject private var locationManager = LocationManager()
    @Environment(\.dismiss) private var dismiss

    @State private var query = ""
    @State private var results: [GeocodingResult] = []
    @State private var isSearching = false
    @State private var errorMessage: String?
    @State private var searchTask: Task<Void, Never>?

    private var title: String { slot == .work ? "Travail" : "Domicile" }
    private var existing: NavFavorite? { slot == .work ? favorites.work : favorites.home }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Button {
                        guard let coordinate = locationManager.currentLocation?.coordinate else { return }
                        apply(coordinate: coordinate, label: nil)
                    } label: {
                        Label("Utiliser ma position actuelle", systemImage: "location.fill")
                    }
                    .disabled(locationManager.currentLocation == nil)
                }

                if let existing {
                    Section {
                        Button(role: .destructive) {
                            favorites.delete(existing)
                            dismiss()
                        } label: {
                            Label("Retirer cette adresse favorite", systemImage: "trash")
                        }
                    }
                }

                Section {
                    if isSearching {
                        ProgressView()
                    } else if let errorMessage {
                        Text(errorMessage).foregroundStyle(.secondary)
                    }
                    ForEach(results) { result in
                        Button {
                            apply(coordinate: result.coordinate, label: result.displayName)
                        } label: {
                            // Fix "icon-text-consistency" (it19, étude UX) : la ligne "Position
                            // actuelle" juste au-dessus a déjà une icône (location.fill) — les
                            // résultats de recherche restaient en texte seul, incohérent dans la
                            // même liste.
                            Label {
                                Text(result.displayName)
                                    .multilineTextAlignment(.leading)
                                    .lineLimit(2)
                                    .foregroundStyle(.primary)
                            } icon: {
                                Image(systemName: "mappin.and.ellipse")
                            }
                        }
                    }
                }
            }
            .searchable(text: $query, prompt: "Adresse ou lieu")
            .onChange(of: query) { newValue in
                scheduleSearch(for: newValue)
            }
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Fermer") { dismiss() }
                }
            }
            .onAppear {
                locationManager.requestAuthorization()
                locationManager.startUpdating()
            }
            .onDisappear {
                locationManager.stopUpdating()
            }
        }
    }

    private func apply(coordinate: CLLocationCoordinate2D, label: String?) {
        switch slot {
        case .home: favorites.setHome(coordinate, label: label ?? "Domicile")
        case .work: favorites.setWork(coordinate, label: label ?? "Travail")
        case .other: break
        }
        dismiss()
    }

    private func scheduleSearch(for text: String) {
        searchTask?.cancel()
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count >= 3 else {
            results = []
            errorMessage = nil
            return
        }
        searchTask = Task {
            isSearching = true
            errorMessage = nil
            try? await Task.sleep(nanoseconds: 400_000_000)
            guard !Task.isCancelled else { return }
            do {
                let found = try await NominatimGeocodingService.shared.search(query: trimmed)
                guard !Task.isCancelled else { return }
                results = found
            } catch {
                guard !Task.isCancelled else { return }
                results = []
                errorMessage = (error as? LocalizedError)?.errorDescription ?? "Recherche impossible."
            }
            isSearching = false
        }
    }
}
