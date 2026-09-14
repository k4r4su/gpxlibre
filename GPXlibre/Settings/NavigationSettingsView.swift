import SwiftUI

/// Fond translucide pour les sheets à aperçu carte live (spec "translucent-settings-preview-
/// sheets", it15, Bloc 2) — remplace le `.regularMaterial` opaque qui masquait la carte
/// derrière. Teinte sombre légère + `ultraThinMaterial` (le blur seul se fait parfois "laver"
/// par un fond de carte très clair, illisible en plein soleil) ; force `colorScheme` à `.dark`
/// sur la carte pour que `.primary`/`.secondary` restent clairs dessus quel que soit le mode
/// système — même patron que RideStatsBadge/Panel pour les calques posés sur la carte.
/// Réservé aux 3 sheets à aperçu live ci-dessous ; ne PAS généraliser aux réglages
/// administratifs classiques (nom/version...), qui restent en sheet opaque standard.
private extension View {
    func translucentPreviewBackground() -> some View {
        background(
            ZStack {
                Color.black.opacity(0.45)
                Rectangle().fill(.ultraThinMaterial)
            }
            .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        )
        .environment(\.colorScheme, .dark)
    }
}

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

            Section {
                NavigationLink {
                    DefaultRideZoomSettingsView(track: previewTrack)
                } label: {
                    Label("Zoom par défaut", systemImage: "arrow.up.left.and.arrow.down.right")
                }
                NavigationLink {
                    AutoZoomSettingsView(track: previewTrack)
                } label: {
                    Label("Zoom automatique", systemImage: "speedometer")
                }
            } header: {
                Text("Zoom")
            } footer: {
                Text("Zoom par défaut : niveau de départ avant le premier mouvement. Zoom automatique : la courbe qui ajuste ensuite le zoom selon la vitesse.")
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
            .translucentPreviewBackground()
            .padding()
        }
        .navigationTitle("Position point bleu")
        .navigationBarTitleDisplayMode(.inline)
    }
}

/// Bloc 6 "default-zoom-preview" — slider STAGÉ (spec explicite : "Sauvegarder = applique") :
/// contrairement à la Position point bleu (live), ici le réglage réel ne change qu'au tap sur
/// Sauvegarder — la valeur locale pilote juste l'aperçu pendant qu'on ajuste.
private struct DefaultRideZoomSettingsView: View {
    let track: GPXTrack
    @EnvironmentObject private var settings: RideSettingsStore
    @Environment(\.dismiss) private var dismiss
    @State private var localValue: Double = 0
    @State private var hasSaved = false

    var body: some View {
        ZStack(alignment: .bottom) {
            CameraPreviewMapView(track: track, spanMeters: localValue)
                .ignoresSafeArea(edges: .top)

            VStack(alignment: .leading, spacing: 12) {
                Text("Zoom par défaut")
                    .font(.headline)
                Text("Niveau de zoom au tout début d'un Ride, avant le premier mouvement — le zoom automatique (vitesse) prend ensuite le relais.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Slider(
                    value: $localValue,
                    in: RideConstants.defaultRideZoomRange,
                    step: 50
                )
                Text(spanText)
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
                Button(hasSaved ? "Sauvegardé" : "Sauvegarder") {
                    settings.defaultRideZoomCameraMeters = localValue
                    hasSaved = true
                }
                .buttonStyle(.borderedProminent)
                .disabled(localValue == settings.defaultRideZoomCameraMeters)
            }
            .padding()
            .translucentPreviewBackground()
            .padding()
        }
        .navigationTitle("Zoom par défaut")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear { localValue = settings.defaultRideZoomCameraMeters }
        .onChange(of: localValue) { _ in hasSaved = false }
    }

    private var spanText: String {
        localValue < 1000 ? "\(Int(localValue)) m" : String(format: "%.1f km", localValue / 1000)
    }
}

/// Bloc 7 "auto-zoom-speed-curve" — TOUT stagé jusqu'à "Valider" (spec explicite : "non
/// persistant tant que non validé"). Preview animée : transition automatique du zoom serré
/// (min, vitesse faible) au zoom large (max, vitesse haute) sur ~6 s à chaque changement de
/// preset/bornes — "skippable au tap" en sautant directement à l'état large.
private struct AutoZoomSettingsView: View {
    let track: GPXTrack
    @EnvironmentObject private var settings: RideSettingsStore
    @State private var localEnabled = true
    @State private var localPreset: ZoomPreset = .normal
    @State private var localMin: Double = RideConstants.autoZoomMinMetersDefault
    @State private var localMax: Double = RideConstants.autoZoomMaxMetersDefault
    @State private var previewSpan: Double = RideConstants.autoZoomMinMetersDefault
    @State private var hasChanges = false

    var body: some View {
        ZStack(alignment: .bottom) {
            CameraPreviewMapView(track: track, spanMeters: previewSpan)
                .ignoresSafeArea(edges: .top)
                .onTapGesture { skipPreview() }

            VStack(alignment: .leading, spacing: 10) {
                Text("Zoom automatique")
                    .font(.headline)
                Toggle("Activé", isOn: $localEnabled)
                if localEnabled {
                    Picker("Preset", selection: $localPreset) {
                        ForEach(ZoomPreset.allCases) { preset in
                            Text(preset.displayName).tag(preset)
                        }
                    }
                    .pickerStyle(.segmented)
                    Text("Serré (vitesse faible)").font(.caption2).foregroundStyle(.secondary)
                    Slider(value: $localMin, in: RideConstants.autoZoomBoundsRange, step: 50)
                    Text("Large (vitesse haute)").font(.caption2).foregroundStyle(.secondary)
                    Slider(value: $localMax, in: RideConstants.autoZoomBoundsRange, step: 50)
                    Text("Touche l'aperçu pour passer directement au niveau large.")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                Button("Valider") {
                    settings.autoZoomEnabled = localEnabled
                    settings.zoomPreset = localPreset
                    settings.autoZoomMinMeters = min(localMin, localMax)
                    settings.autoZoomMaxMeters = max(localMin, localMax)
                    hasChanges = false
                }
                .buttonStyle(.borderedProminent)
                .disabled(!hasChanges)
            }
            .padding()
            .translucentPreviewBackground()
            .padding()
        }
        .navigationTitle("Zoom automatique")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            localEnabled = settings.autoZoomEnabled
            localPreset = settings.zoomPreset
            localMin = settings.autoZoomMinMeters
            localMax = settings.autoZoomMaxMeters
            playPreview()
        }
        .onChange(of: localMin) { _ in hasChanges = true; playPreview() }
        .onChange(of: localMax) { _ in hasChanges = true; playPreview() }
        .onChange(of: localPreset) { _ in hasChanges = true; playPreview() }
        .onChange(of: localEnabled) { _ in hasChanges = true }
    }

    private func playPreview() {
        previewSpan = min(localMin, localMax)
        withAnimation(.easeInOut(duration: 6)) {
            previewSpan = max(localMin, localMax)
        }
    }

    private func skipPreview() {
        withAnimation(.easeInOut(duration: 0.3)) {
            previewSpan = max(localMin, localMax)
        }
    }
}
