import SwiftUI
import UniformTypeIdentifiers

/// Didacticiel 3 écrans, affiché une seule fois au premier lancement (voir GPXlibreApp),
/// réactivable depuis Réglages. Max 2 lignes de texte par écran.
struct OnboardingView: View {
    @EnvironmentObject private var library: LibraryStore
    @EnvironmentObject private var settings: RideSettingsStore
    @Binding var isPresented: Bool

    @State private var page = 0
    @State private var isImporting = false

    private static let gpxType = UTType(filenameExtension: "gpx") ?? .xml

    var body: some View {
        TabView(selection: $page) {
            OnboardingPage(
                title: "Importe ta première trace",
                message: "Depuis Mail, Fichiers ou Safari — ou choisis un fichier ici."
            ) {
                Button("Importer un fichier GPX") { isImporting = true }
                    .buttonStyle(.borderedProminent)
            }
            .tag(0)

            OnboardingPage(
                title: "Une trace d'exemple est incluse",
                message: "Teste l'app tout de suite, sans rien importer."
            ) {
                Button("Charger la trace d'exemple") {
                    library.loadSample()
                    finish()
                }
                .buttonStyle(.borderedProminent)
            }
            .tag(1)

            OnboardingPage(
                title: "L'alerte checkpoint flashe 200 m avant les virages",
                message: "Regarde autour de toi quand même : c'est toi qui pilotes."
            ) {
                Button("C'est parti") { finish() }
                    .buttonStyle(.borderedProminent)
            }
            .tag(2)
        }
        .tabViewStyle(.page(indexDisplayMode: .always))
        .indexViewStyle(.page(backgroundDisplayMode: .always))
        .background(Color(.systemBackground))
        .fileImporter(
            isPresented: $isImporting,
            allowedContentTypes: [Self.gpxType, .xml],
            allowsMultipleSelection: false
        ) { result in
            if case .success(let urls) = result {
                urls.forEach(library.importTrack(from:))
            }
            finish()
        }
    }

    private func finish() {
        settings.hasSeenOnboarding = true
        isPresented = false
    }
}

private struct OnboardingPage<Action: View>: View {
    let title: String
    let message: String
    @ViewBuilder let action: () -> Action

    var body: some View {
        VStack(spacing: 20) {
            Spacer()
            Text(title)
                .font(.title.bold())
                .multilineTextAlignment(.center)
            Text(message)
                .font(.body)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .lineLimit(2)
            action()
            Spacer()
        }
        .padding(32)
    }
}
