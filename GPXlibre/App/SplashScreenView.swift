import SwiftUI

/// Écran de démarrage (spec "splash-screen", demande explicite du propriétaire) — logo, nom et
/// version de l'app, barre de progression. Affiché systématiquement au lancement, PAS seulement
/// au premier lancement (contrairement à `OnboardingView`, qui reste un écran séparé, réservé à
/// la découverte des fonctionnalités et réactivable depuis Réglages).
///
/// Barre de progression PUREMENT visuelle (temporisée, `splashDurationSeconds`) — l'app n'a rien
/// de long à charger de façon asynchrone au démarrage (`MapLibreBootstrap.configure()` et les
/// stores sont déjà synchrones dans `GPXlibreApp.init()`, terminés avant même le premier
/// rendu) : ce n'est pas un indicateur de progrès réel, seulement une présentation de marque
/// soignée le temps que l'app "s'installe" visuellement, comme le fait la plupart des apps grand
/// public à l'écran de démarrage.
struct SplashScreenView: View {
    let onFinished: () -> Void

    @State private var progress: Double = 0
    @State private var logoOpacity: Double = 0

    private static let splashDurationSeconds: Double = 1.4

    /// Version affichée sous la forme `0.0.<itération>` — convention explicite du propriétaire
    /// tant que l'app est en phase de test ("0.0.21 (itération 21), 0.0.22 (itération 22)...").
    /// Lecture factorisée dans `AppVersion` (it23, "splash-version-robustness") — point UNIQUE
    /// pour que tout futur second affichage de version (écran "À propos", etc.) ne puisse pas
    /// diverger d'une chaîne codée en dur.
    private var versionText: String { AppVersion.displayText() }

    var body: some View {
        ZStack {
            Color(.systemBackground)
                .ignoresSafeArea()

            VStack(spacing: 28) {
                Spacer()

                Image("SplashLogo")
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 140, height: 140)
                    .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
                    .shadow(color: .black.opacity(0.15), radius: 12, x: 0, y: 6)
                    .opacity(logoOpacity)

                VStack(spacing: 6) {
                    Text("GPXlibre")
                        .font(.system(.title, design: .rounded).bold())
                    Text(versionText)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                .opacity(logoOpacity)

                Spacer()

                ProgressView(value: progress)
                    .progressViewStyle(.linear)
                    .tint(.accentColor)
                    .frame(width: 160)
                    .padding(.bottom, 48)
            }
        }
        .onAppear {
            withAnimation(.easeOut(duration: 0.3)) {
                logoOpacity = 1
            }
            withAnimation(.linear(duration: Self.splashDurationSeconds)) {
                progress = 1
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + Self.splashDurationSeconds) {
                onFinished()
            }
        }
    }
}
