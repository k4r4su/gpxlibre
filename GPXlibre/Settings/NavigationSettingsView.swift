import SwiftUI

/// Réglages > Navigation (spec it14, Blocs 1/6/7) — regroupe les réglages caméra/zoom qui ont
/// besoin d'un aperçu carte en direct, remplace l'ancienne section "Zoom automatique" à plat
/// en tête de Réglages (déplacée ici, voir SettingsView).
struct NavigationSettingsView: View {
    @EnvironmentObject private var settings: RideSettingsStore
    @EnvironmentObject private var library: LibraryStore

    private var previewTrack: GPXTrack {
        library.activeTrack ?? library.tracks.first ?? CameraPreviewMapView.sampleTrack
    }

    var body: some View {
        List {
            Section {
                NavigationLink {
                    RideAnchorSettingsView(track: previewTrack)
                } label: {
                    Label("Position point bleu", systemImage: "location.circle.fill")
                }
            } header: {
                Text("Caméra")
            } footer: {
                Text("Où la position s'ancre à l'écran en mode suivi cap-en-haut — plus bas laisse plus de trace visible devant soi.")
            }
        }
        .navigationTitle("Navigation")
        .navigationBarTitleDisplayMode(.inline)
    }
}

/// Bloc 1 "ride-anchor-lowered-setting" — slider LIVE (pas de bouton Sauvegarder : chaque
/// mouvement s'applique immédiatement à `settings.rideAnchorYFraction`, cohérent avec tous les
/// autres réglages de l'app). L'aperçu carte derrière le slider n'est qu'un repère visuel
/// (voir AnchorFractionOverlay) — la vraie ancre exacte reste calculée par
/// `RideOverlayLayout.computeMapInsets`, inchangé.
private struct RideAnchorSettingsView: View {
    let track: GPXTrack
    @EnvironmentObject private var settings: RideSettingsStore

    var body: some View {
        ZStack(alignment: .bottom) {
            CameraPreviewMapView(track: track, spanMeters: 900)
                .overlay { AnchorFractionOverlay(fraction: settings.rideAnchorYFraction) }
                .ignoresSafeArea(edges: .top)

            VStack(alignment: .leading, spacing: 12) {
                Text("Position point bleu")
                    .font(.headline)
                Text("En mode suivi cap-en-haut, laisse plus ou moins de trace visible devant toi. Nord-en-haut n'est pas concerné (reste centré).")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                HStack {
                    Text("Haut")
                    Slider(value: $settings.rideAnchorYFraction, in: RideConstants.rideAnchorYFractionRange)
                    Text("Bas")
                }
                Text("\(Int(settings.rideAnchorYFraction * 100)) % depuis le haut")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
            .padding()
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
            .padding()
        }
        .navigationTitle("Position point bleu")
        .navigationBarTitleDisplayMode(.inline)
    }
}
