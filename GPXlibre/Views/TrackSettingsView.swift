import SwiftUI

/// Panneau "Paramétrer la trace" (spec "per-track-settings") — accessible par swipe à droite
/// sur une ligne de la Bibliothèque. N'écrit JAMAIS le fichier GPX source : sens de parcours,
/// départ personnalisé, override couleur/épaisseur et espacement des chevrons sont des
/// réglages purement applicatifs, persistés séparément (TrackRideSettingsStore).
struct TrackSettingsView: View {
    let track: GPXTrack

    @EnvironmentObject private var trackRideSettings: TrackRideSettingsStore
    @EnvironmentObject private var settings: RideSettingsStore
    @EnvironmentObject private var library: LibraryStore
    @Environment(\.dismiss) private var dismiss

    @State private var localSettings = TrackRideSettings.default
    @State private var isPickingStart = false

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TrackMapView(
                        track: track,
                        currentLocation: nil,
                        traceAppearance: previewAppearance,
                        onPickStartIndex: isPickingStart ? { index in
                            localSettings.customStartPointIndex = index
                            isPickingStart = false
                        } : nil,
                        startIndexToHighlight: localSettings.customStartPointIndex
                    )
                    .frame(height: 220)
                    .listRowInsets(EdgeInsets())
                    .overlay(alignment: .bottom) {
                        if isPickingStart {
                            Text("Touche un point de la trace pour le définir comme départ")
                                .font(.caption.bold())
                                .foregroundStyle(.white)
                                .padding(.horizontal, 12)
                                .padding(.vertical, 6)
                                .background(.black.opacity(0.7))
                                .clipShape(Capsule())
                                .padding(.bottom, 8)
                        }
                    }
                }

                Section {
                    // Fix "single-source-active-track" (Bloc 1, it10) : second point d'entrée
                    // pour le même état que l'icône de la ligne Biblio — jamais un état
                    // parallèle, toujours library.setActive/setDisplayed.
                    Button {
                        if library.activeTrackID == track.id {
                            library.setDisplayed(track.id, false)
                        } else {
                            library.setActive(track.id)
                        }
                    } label: {
                        Label(
                            library.activeTrackID == track.id ? "Trace active pour le Ride" : "Rendre active pour le Ride",
                            systemImage: library.activeTrackID == track.id ? "checkmark.circle.fill" : "circle"
                        )
                        .foregroundStyle(library.activeTrackID == track.id ? .green : .primary)
                    }
                }

                Section {
                    if track.isLoop {
                        Label("Boucle détectée — ordre du fichier conservé par défaut", systemImage: "arrow.triangle.2.circlepath")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Picker("Sens", selection: $localSettings.isReversed) {
                        Text("A → B (ordre du fichier)").tag(false)
                        Text("B → A (inversé)").tag(true)
                    }
                    .pickerStyle(.segmented)
                } header: {
                    Text("Sens de parcours")
                } footer: {
                    Text("Ne modifie jamais le fichier GPX — un paramètre d'affichage et de navigation uniquement.")
                }

                Section("Départ") {
                    Button(isPickingStart ? "Choix en cours… touche la carte ci-dessus" : "Choisir le début") {
                        isPickingStart.toggle()
                    }
                    if localSettings.hasCustomStart {
                        Button("Revenir au début d'origine") {
                            localSettings.customStartPointIndex = nil
                            isPickingStart = false
                        }
                        .foregroundStyle(.red)
                    }
                }

                Section {
                    Picker("Couleur", selection: Binding(
                        get: { localSettings.colorOverride ?? settings.traceColorPreset },
                        set: { localSettings.colorOverride = $0 }
                    )) {
                        ForEach(TraceColorPreset.allCases) { preset in
                            Label {
                                Text(preset.label)
                            } icon: {
                                Circle().fill(Color(preset.color)).frame(width: 14, height: 14)
                            }
                            .tag(preset)
                        }
                    }
                    Picker("Épaisseur", selection: Binding(
                        get: { localSettings.widthOverride ?? settings.traceWidthPreset },
                        set: { localSettings.widthOverride = $0 }
                    )) {
                        ForEach(TraceWidthPreset.allCases) { preset in
                            Text(preset.label).tag(preset)
                        }
                    }
                    .pickerStyle(.segmented)
                    if localSettings.colorOverride != nil || localSettings.widthOverride != nil {
                        Button("Revenir à l'apparence globale") {
                            localSettings.colorOverride = nil
                            localSettings.widthOverride = nil
                        }
                        .font(.caption)
                    }
                } header: {
                    Text("Apparence (cette trace)")
                } footer: {
                    Text("Les réglages globaux (Réglages) restent le défaut tant qu'aucun override n'est choisi ici.")
                }

                Section {
                    Picker("Espacement", selection: $localSettings.chevronSpacingMeters) {
                        ForEach(RideConstants.directionArrowSpacingMetersOptions, id: \.self) { value in
                            Text(value >= 1000 ? "\(Int(value / 1000)) km" : "\(Int(value)) m").tag(value)
                        }
                    }
                } header: {
                    Text("Chevrons de direction")
                } footer: {
                    Text("Petites flèches le long de la trace, orientées selon le sens actif — visibles à partir du zoom 14.")
                }
            }
            .navigationTitle("Paramétrer la trace")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Annuler") { dismiss() }
                }
                ToolbarItem(placement: .primaryAction) {
                    Button("Enregistrer") {
                        trackRideSettings.setSettings(localSettings, for: track.id)
                        dismiss()
                    }
                    .fontWeight(.bold)
                }
            }
            .onAppear {
                localSettings = trackRideSettings.settings(for: track.id)
            }
        }
    }

    private var previewAppearance: TraceAppearance {
        TraceAppearance(
            widthPreset: localSettings.widthOverride ?? settings.traceWidthPreset,
            colorPreset: localSettings.colorOverride ?? settings.traceColorPreset,
            isNightMode: false
        )
    }
}
