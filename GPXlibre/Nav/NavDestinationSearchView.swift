import SwiftUI
import CoreLocation

/// Recherche d'adresse (Nominatim), favoris Domicile/Travail en 1 tap, et point choisi
/// directement sur la carte (long-press, voir RideView).
struct NavDestinationSearchView: View {
    let onSelect: (CLLocationCoordinate2D, String, GoToProfile) -> Void

    @EnvironmentObject private var favorites: NavFavoritesStore
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

                if isSearching {
                    ProgressView()
                } else if let errorMessage {
                    Text(errorMessage).foregroundStyle(.secondary)
                }

                ForEach(results) { result in
                    VStack(alignment: .leading, spacing: 6) {
                        Text(result.displayName)
                            .multilineTextAlignment(.leading)
                            .lineLimit(2)
                        // Chip de profil (Bloc 4) : Route / Offroad / Mixte, sur chaque résultat.
                        HStack(spacing: 8) {
                            ForEach(GoToProfile.allCases) { profile in
                                Button {
                                    onSelect(result.coordinate, result.displayName, profile)
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
            }
            .searchable(text: $query, prompt: "Adresse ou lieu")
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
