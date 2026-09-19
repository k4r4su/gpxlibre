import SwiftUI
import CoreLocation

/// Recherche d'adresse (Nominatim), favoris Domicile/Travail en 1 tap, historique des dernières
/// recherches (spec "search-history", it19), et point choisi directement sur la carte
/// (long-press, voir RideView).
struct NavDestinationSearchView: View {
    let onSelect: (CLLocationCoordinate2D, String, GoToProfile) -> Void

    @EnvironmentObject private var favorites: NavFavoritesStore
    @EnvironmentObject private var searchHistory: NavSearchHistoryStore
    /// Spec "poi-search-nominatim" (it22) — position actuelle utilisée pour biaiser une
    /// recherche générique ("pharmacie", "supermarché") vers les résultats proches, voir
    /// `NominatimGeocodingService.search(nearCoordinate:)`.
    @EnvironmentObject private var session: RideSessionManager
    @Environment(\.dismiss) private var dismiss

    @State private var query = ""
    @State private var results: [GeocodingResult] = []
    @State private var isSearching = false
    @State private var errorMessage: String?
    @State private var searchTask: Task<Void, Never>?

    var body: some View {
        NavigationStack {
            List {
                Section {
                    HStack(spacing: 12) {
                        favoriteButton(title: "Domicile", systemImage: "house.fill", favorite: favorites.home)
                        favoriteButton(title: "Travail", systemImage: "briefcase.fill", favorite: favorites.work)
                    }
                    .padding(.vertical, 4)
                }

                // Spec "search-history" (it19, retour terrain : "le menu est un peu vide
                // sinon") — visible uniquement avant de taper quoi que ce soit, comme les
                // résultats de recherche eux-mêmes qu'il remplace le temps qu'on tape.
                if query.isEmpty, !searchHistory.entries.isEmpty {
                    Section("Recherches récentes") {
                        ForEach(searchHistory.entries) { entry in
                            destinationRow(label: entry.label, coordinate: entry.coordinate.coordinate)
                        }
                        .onDelete { offsets in
                            for index in offsets { searchHistory.remove(searchHistory.entries[index]) }
                        }
                    }
                }

                if isSearching {
                    ProgressView()
                } else if let errorMessage {
                    Text(errorMessage).foregroundStyle(.secondary)
                }

                ForEach(results) { result in
                    destinationRow(label: result.displayName, coordinate: result.coordinate)
                }
            }
            // Fix "search-bar-requires-pull-down" (it21, retour terrain : "pour afficher la
            // barre de recherche dans Aller à il faut faire un petit swipe down") — placement
            // par défaut de `.searchable` se réduit/masque tant que le contenu n'a pas été
            // tiré vers le bas, quirk connu de SwiftUI particulièrement visible ici depuis que
            // cette vue vit comme ONGLET permanent (spec "search-as-tab", it19) plutôt que
            // poussée dans une pile de navigation. `.navigationBarDrawer(displayMode: .always)`
            // force la barre à rester visible en permanence, sans geste requis.
            .searchable(text: $query, placement: .navigationBarDrawer(displayMode: .always), prompt: "Adresse ou lieu")
            .onChange(of: query) { newValue in
                scheduleSearch(for: newValue)
            }
            .navigationTitle("Destination")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Fermer") { dismiss() }
                }
            }
        }
    }

    /// Ligne réutilisée pour un résultat de recherche ET une entrée d'historique — même
    /// libellé + chips de profil (Bloc 4 : Route / Offroad / Mixte), seule la source diffère.
    private func destinationRow(label: String, coordinate: CLLocationCoordinate2D) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            // Fix "icon-text-consistency" (it19, étude UX) : les favoris Domicile/Travail juste
            // au-dessus ont déjà une icône — même incohérence que FavoriteAddressesView,
            // corrigée à l'identique (mappin.and.ellipse).
            Label {
                Text(label)
                    .multilineTextAlignment(.leading)
                    .lineLimit(2)
            } icon: {
                Image(systemName: "mappin.and.ellipse")
            }
            HStack(spacing: 8) {
                ForEach(GoToProfile.allCases) { profile in
                    Button {
                        searchHistory.record(coordinate: coordinate, label: label)
                        onSelect(coordinate, label, profile)
                        dismiss()
                    } label: {
                        Label(profile.label, systemImage: profile.systemImageName)
                            .font(.caption2.bold())
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(Color.accentColor.opacity(0.15))
                            .clipShape(Capsule())
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .padding(.vertical, 2)
    }

    private func favoriteButton(title: String, systemImage: String, favorite: NavFavorite?) -> some View {
        Button {
            guard let favorite else { return }
            onSelect(favorite.coordinate.coordinate, favorite.label, .route)
            dismiss()
        } label: {
            VStack(spacing: 6) {
                Image(systemName: systemImage)
                    .font(.title2)
                Text(title)
                    .font(.caption)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 10)
            .background(favorite != nil ? Color.accentColor.opacity(0.15) : Color(.systemGray5))
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
        .disabled(favorite == nil)
        .buttonStyle(.plain)
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
                let found = try await NominatimGeocodingService.shared.search(query: trimmed, nearCoordinate: session.currentLocation?.coordinate)
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
