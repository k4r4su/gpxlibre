import SwiftUI

/// Réglages > Repères du Road Book (jalon it28) — un interrupteur par catégorie du catalogue
/// (`RoadbookLandmarkCategory`), regroupées par famille. Effet immédiat : le Road Book refiltre
/// ses repères sans rien retélécharger ; une catégorie activée pour la première fois est
/// téléchargée seule (complément) à la prochaine ouverture du Road Book — voir
/// `RoadbookLandmarkLoader`.
struct RoadbookLandmarkSettingsView: View {
    @EnvironmentObject private var settings: RideSettingsStore

    var body: some View {
        Form {
            Section {
                Button("Réinitialiser aux valeurs par défaut") { settings.resetRoadbookLandmarkCategoriesToDefaults() }
                Button("Tout activer") { settings.roadbookLandmarkCategories = Set(RoadbookLandmarkCategory.allCases) }
                Button("Tout désactiver") { settings.roadbookLandmarkCategories = [] }
            } footer: {
                Text("Seul ce qui se voit depuis la route est proposé. Les ronds-points restent toujours affichés comme des changements de direction.")
            }

            ForEach(RoadbookLandmarkCategory.Group.allCases) { group in
                Section(group.label) {
                    ForEach(group.categories) { category in
                        Toggle(isOn: binding(for: category)) {
                            Label {
                                Text(category.localizedGenericLabel)
                            } icon: {
                                Text(category.emoji)
                            }
                        }
                    }
                }
            }
        }
        .navigationTitle("Repères du Road Book")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func binding(for category: RoadbookLandmarkCategory) -> Binding<Bool> {
        Binding(
            get: { settings.roadbookLandmarkCategories.contains(category) },
            set: { isOn in
                if isOn {
                    settings.roadbookLandmarkCategories.insert(category)
                } else {
                    settings.roadbookLandmarkCategories.remove(category)
                }
            }
        )
    }
}
