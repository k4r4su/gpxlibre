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

    var body: some View {
        NavigationStack {
            Form {
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
                    // Fiche trace fusionnée (spec "trace-fiche-map-ab-markers", it17, Bloc 5) :
                    // une seule carte (même cartographie vectorielle que la Ride map) avec
                    // chevrons agrandis + repères A/B, remplace l'ancien duo TrackMapView
                    // (aperçu MapKit séparé, retiré ci-dessus) + TrackThumbnailView (diagramme
                    // Canvas séparé, ci-dessous avant ce bloc). `orderedTrack` = `reorderedTrack`
                    // (déjà pur, `GPXTrack.reordered(using:)`) : bascule A→B/B→A = pastilles +
                    // chevrons recalculés instantanément, PAS de rescan GPX.
                    TrackFicheMapView(
                        orderedTrack: reorderedTrack,
                        isReversed: localSettings.isReversed,
                        traceAppearance: previewAppearance
                    )
                    .frame(height: 220)
                    .listRowInsets(EdgeInsets())

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

                // Fix "remove-start-choice" (it14, Bloc 10) : "redondant depuis le toggle
                // A→B/it12 — retire le contrôle et la logique." Le sélecteur tactile de départ
                // a disparu ; seul un bouton de retrait reste, UNIQUEMENT si une trace a déjà
                // une valeur stockée d'avant ce fix — ne
                // casse pas la persistance existante, mais ne propose plus d'en définir une
                // nouvelle (le sens A→B/B→A est désormais la SEULE source pour "où ça commence").
                if localSettings.hasCustomStart {
                    Section {
                        Button(role: .destructive) {
                            localSettings.customStartPointIndex = nil
                        } label: {
                            Label("Revenir au début d'origine (départ personnalisé hérité)", systemImage: "arrow.uturn.backward")
                        }
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
                        Button {
                            localSettings.colorOverride = nil
                            localSettings.widthOverride = nil
                        } label: {
                            Label("Revenir à l'apparence globale", systemImage: "arrow.uturn.backward")
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
                    // Texte mis à jour (it17, Bloc 3, "chevrons-zoom-adaptive") : les chevrons
                    // ne disparaissent plus en dessous d'un zoom donné, l'espacement choisi ici
                    // est juste la référence au zoom le plus serré — plus espacés en dézoomant.
                    Text("Petites flèches le long de la trace, orientées selon le sens actif — cet espacement s'applique au zoom serré, plus espacées en dézoomant.")
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

    /// Réutilisé par la miniature ET, à terme, par tout aperçu qui doit refléter le sens
    /// actif — jamais un nouvel algorithme, juste `GPXTrack.reordered(using:)` (pur, ne
    /// modifie jamais `track`) appliqué aux réglages en cours d'édition (`localSettings`),
    /// pas encore enregistrés.
    private var reorderedTrack: GPXTrack {
        track.reordered(using: localSettings)
    }

    private var previewAppearance: TraceAppearance {
        TraceAppearance(
            widthPreset: localSettings.widthOverride ?? settings.traceWidthPreset,
            colorPreset: localSettings.colorOverride ?? settings.traceColorPreset,
            isNightMode: false
        )
    }
}
