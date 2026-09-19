import SwiftUI

/// Page unique, liste plate, aucune navigation en sous-menu — conforme à la philosophie
/// "simplicité radicale" de l'app (guidon, gants, soleil). 14 réglages max au complet
/// (itération Nav, Bloc 5) ; épaisseur/couleur de trace ajoutés ici (Bloc 3, #13/#14).
struct SettingsView: View {
    @EnvironmentObject private var settings: RideSettingsStore
    @State private var showOnboarding = false

    var body: some View {
        NavigationStack {
            Form {
                // Spec it14 (Blocs 1/6/7) : l'ancienne section "Zoom automatique" à plat
                // déménage dans ce nouvel écran, avec Position point bleu et Zoom par défaut —
                // les trois ont besoin d'un aperçu carte en direct, impossible à faire
                // proprement dans une simple ligne de Form.
                Section {
                    NavigationLink {
                        NavigationSettingsView()
                    } label: {
                        Label("Navigation", systemImage: "location.north.line.fill")
                    }
                }

                // Renouvelée intégralement (spec "roadbook-settings-wired", it14, Bloc 5 :
                // "L'ancien panneau Réglages > Roadbook existant n'agit pas") — chaque contrôle
                // ci-dessous pilote directement RoadbookAnalyzer.buildRoadbookEvents via
                // RideSessionManager.rebuildCheckpoints, appelé par le .onChange en bas de
                // RideView pour chacun de ces réglages (bascule live, sans kill app).
                Section {
                    Toggle("Activé", isOn: $settings.roadbookEnabled)
                    if settings.roadbookEnabled {
                        Toggle("Flash (100 derniers mètres)", isOn: $settings.roadbookFlashEnabled)
                        Picker("Nombre de flashs", selection: $settings.flashCount) {
                            ForEach(RideConstants.flashCountOptions, id: \.self) { value in
                                Text("\(value)").tag(value)
                            }
                        }
                        Picker("Fusion des virages rapprochés", selection: $settings.turnMergeMinDistanceMeters) {
                            ForEach(RideConstants.turnMergeMinDistanceMetersOptions, id: \.self) { value in
                                Text("\(Int(value)) m").tag(value)
                            }
                        }
                        .longPressTooltip("Deux virages détectés à moins de cette distance sont fusionnés en un seul — utile sur piste qui zigzague")

                        VStack(alignment: .leading, spacing: 6) {
                            Text("Fenêtre de mesure : \(Int(settings.roadbookWindowBeforeMeters)) m avant / \(Int(settings.roadbookWindowAfterMeters)) m après")
                                .font(.subheadline)
                            Text("Avant").font(.caption).foregroundStyle(.secondary)
                            Slider(value: $settings.roadbookWindowBeforeMeters, in: NavigationConstants.roadbookWindowRange, step: 5)
                            Text("Après").font(.caption).foregroundStyle(.secondary)
                            Slider(value: $settings.roadbookWindowAfterMeters, in: NavigationConstants.roadbookWindowRange, step: 5)
                        }
                        .longPressTooltip("Distance avant/après chaque point de la trace sur laquelle l'angle est mesuré (±40-80 m)")

                        Toggle("Seuils personnalisés", isOn: Binding(
                            get: { settings.roadbookUseCustomThresholds },
                            set: { isCustom in
                                settings.roadbookUseCustomThresholds = isCustom
                                if !isCustom { settings.resetRoadbookThresholdsToDefaults() }
                            }
                        ))
                        if settings.roadbookUseCustomThresholds {
                            roadbookThresholdStepper("Léger dès", value: $settings.roadbookLightThresholdDegrees)
                            roadbookThresholdStepper("Prononcé dès", value: $settings.roadbookMarkedThresholdDegrees)
                            roadbookThresholdStepper("Fort dès", value: $settings.roadbookHardThresholdDegrees)
                            roadbookThresholdStepper("Demi-tour dès", value: $settings.roadbookUTurnThresholdDegrees)
                        } else {
                            Text("Standard : léger 30° · prononcé 45° · fort 90° · demi-tour 135°")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                } header: {
                    Text("Roadbook")
                } footer: {
                    Text("Mesure l'angle de la trace autour de chaque point (fenêtre avant/après) et le classe en 4 paliers — léger, prononcé, fort, demi-tour.")
                }

                Section {
                    Picker("Orientation", selection: $settings.mapOrientationNorthUp) {
                        Text("Cap en haut").tag(false)
                        Text("Nord en haut").tag(true)
                    }
                    // Spec "map-style-visual-picker" (it18-bis) : vignettes plutôt qu'une liste
                    // de texte — standard du marché pour un choix de fond de carte.
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Thème").font(.subheadline)
                        MapThemePickerView(selection: $settings.mapThemePreset)
                    }
                    Picker("Unité de vitesse", selection: $settings.speedUnit) {
                        ForEach(SpeedUnit.allCases) { unit in
                            Text(unit.label).tag(unit)
                        }
                    }
                } header: {
                    Text("Carte")
                } footer: {
                    // Fix "map-style-rotation-consistency" (it22, retour terrain : "certains
                    // styles affichent les labels à l'envers ou statiques quand on tourne la
                    // carte") — diagnostiqué : ce n'est PAS un bug de rotation (vérifié, le
                    // patch cap-en-haut s'applique de façon identique aux 3 palettes
                    // vectorielles), ce sont les thèmes RASTER (image pré-rendue, aucune
                    // rotation de texte possible par nature) qui ne suivent jamais la rotation,
                    // contrairement aux thèmes vectoriels. Documenté ici plutôt que "corrigé" —
                    // rien à corriger dans le mécanisme de rotation lui-même. Satellite
                    // (Sentinel-2, it22) est raster au même titre que Relief — même limitation.
                    if settings.mapThemePreset == .relief || settings.mapThemePreset == .satellite {
                        Text("\(settings.mapThemePreset.label) est une carte pré-dessinée (raster) : les noms de rue ne pivotent pas avec la boussole en cap-en-haut, contrairement aux thèmes vectoriels.")
                    }
                }

                // Spec "slope-warning-native" (it19) : nouvelle option d'apparence — symboles
                // ponctuels aux endroits de forte pente, jamais un dégradé continu sur la trace.
                Section {
                    Toggle("Avertissements de pente", isOn: $settings.slopeWarningsEnabled)
                    if settings.slopeWarningsEnabled {
                        Picker("Seuil de déclenchement", selection: $settings.slopeWarningThresholdPercent) {
                            ForEach(RideConstants.slopeWarningThresholdPercentOptions, id: \.self) { value in
                                Text("\(Int(value)) %").tag(value)
                            }
                        }
                    }
                } header: {
                    Text("Pente")
                } footer: {
                    Text("Un triangle apparaît sur la carte quand la pente dépasse le seuil choisi, en montée comme en descente.")
                }
                // Spec "map-color-flavors" (it19) : le thème Sombre (seul à avoir un accroc
                // hors-ligne, documenté en it18-bis) a été retiré — les 3 palettes restantes
                // fonctionnent identiquement hébergé/hors-ligne (paquet local), Relief a toujours
                // eu le même comportement raster-only qu'avant (rien de nouveau à signaler) :
                // plus besoin de footer d'avertissement ici.

                Section("Mode Nav") {
                    Picker("Seuil dépassement vitesse", selection: $settings.speedLimitAlertThresholdKmh) {
                        ForEach(NavConstants.speedLimitAlertThresholdOptionsKmh, id: \.self) { value in
                            Text("+\(value) km/h").tag(value)
                        }
                    }
                    Toggle("Guidage vocal", isOn: $settings.voiceGuidanceEnabled)
                    if settings.voiceGuidanceEnabled {
                        VStack(alignment: .leading) {
                            Text("Volume")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Slider(value: $settings.voiceGuidanceVolume, in: 0...1)
                        }
                    }
                    Toggle("Trafic", isOn: $settings.trafficEnabled)
                    // Nouvel écran (spec "home-work-favorites", it13) : "Domicile"/"Travail"
                    // étaient déjà suggérés par la recherche Ride, sans nulle part où les
                    // définir — voir FavoriteAddressesView.
                    NavigationLink {
                        FavoriteAddressesView()
                    } label: {
                        Label("Adresses favoris", systemImage: "house.and.flag.fill")
                    }
                }

                // Renommée "Trace" → "Apparence" (spec "controls-side-setting", it14, Bloc 2 :
                // "Réglages > Apparence > Position contrôles") — regroupe désormais aussi le
                // côté de la colonne de contrôles Ride, pas seulement le rendu de la trace.
                Section("Apparence") {
                    // Fix "settings-segmented-picker-missing-title" (bug terrain, it16) :
                    // .pickerStyle(.segmented) masque le titre du Picker par défaut (contrairement
                    // au style menu utilisé pour "Couleur" juste en dessous) — sans Text explicite
                    // au-dessus, impossible de deviner à quoi correspondent les segments.
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Épaisseur").font(.subheadline)
                        Picker("Épaisseur", selection: $settings.traceWidthPreset) {
                            ForEach(TraceWidthPreset.allCases) { preset in
                                Text(preset.label).tag(preset)
                            }
                        }
                        .pickerStyle(.segmented)
                        .labelsHidden()
                    }

                    Picker("Couleur", selection: $settings.traceColorPreset) {
                        ForEach(TraceColorPreset.allCases) { preset in
                            Label {
                                Text(preset.label)
                            } icon: {
                                Circle().fill(Color(preset.color)).frame(width: 14, height: 14)
                            }
                            .tag(preset)
                        }
                    }

                    VStack(alignment: .leading, spacing: 4) {
                        Text("Position contrôles").font(.subheadline)
                        Picker("Position contrôles", selection: $settings.controlsSide) {
                            ForEach(ControlsSide.allCases) { side in
                                Text(side.label).tag(side)
                            }
                        }
                        .pickerStyle(.segmented)
                        .labelsHidden()
                        .longPressTooltip("Colonne +/−/Stop/Bloqué et bannière roadbook, du côté choisi — le badge vitesse passe automatiquement de l'autre côté")
                    }
                }

                Section("Écran") {
                    Toggle("Empêcher la mise en veille en Ride", isOn: $settings.keepScreenAwakeInRide)
                }

                // Spec "recording-density-setting" (it19, retour terrain "alléger le fichier
                // GPX final") — `précis` (défaut) reproduit exactement le comportement d'avant
                // ce réglage, live comme le reste (pas de bouton Sauvegarder).
                Section {
                    Picker("Densité d'enregistrement", selection: $settings.recordingDensityPreset) {
                        ForEach(RecordingDensityPreset.allCases) { preset in
                            Text(preset.label).tag(preset)
                        }
                    }
                } header: {
                    Text("Enregistrement de la sortie")
                } footer: {
                    Text("\(settings.recordingDensityPreset.detail). Un enregistrement plus léger produit un fichier GPX exporté plus petit, mais moins fidèle au tracé réel.")
                }

                // Spec "unsaved-ride-recovery" (it19, retour terrain "cleanup au bout de 10 ou
                // 20 traces, réglable") — nombre de sauvegardes de secours conservées dans
                // Biblio > "Sorties non enregistrées" avant purge automatique des plus anciennes.
                Section {
                    Picker("Sauvegardes de secours conservées", selection: $settings.unsavedRideRetentionLimit) {
                        ForEach(RideConstants.unsavedRideRetentionLimitOptions, id: \.self) { count in
                            Text("\(count)").tag(count)
                        }
                    }
                } footer: {
                    Text("Pendant l'enregistrement, une copie de secours de la sortie en cours est sauvegardée automatiquement — récupérable dans Biblio si tu oublies de faire \"Terminer la sortie\". Les plus anciennes au-delà de ce nombre sont supprimées automatiquement.")
                }

                Section {
                    Toggle("Partager mes signalements anonymement", isOn: $settings.shareBlockagesAnonymously)
                        .longPressTooltip("Envoie uniquement un point GPS, une date et une note optionnelle — aucune donnée nominative, aucun compte")
                } header: {
                    Text("Communauté")
                } footer: {
                    Text("Un chemin bloqué que tu signales est ajouté à une base partagée anonyme, pour alerter les autres utilisateurs qui passent par là.")
                }

                // Section repliée par défaut (Bloc 5, "cachée avancé") : URL du serveur
                // auto-hébergé des points bloqués partagés — vide par défaut (voir
                // SharedBlockageConstants, server/README.md).
                DisclosureGroup("Avancé") {
                    TextField("URL du serveur (points bloqués)", text: $settings.sharedBlockageServerURLString)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .keyboardType(.URL)
                    Text("Laisser vide désactive toute tentative réseau vers cette fonctionnalité.")
                        .font(.caption2)
                        .foregroundStyle(.secondary)

                    NavigationLink {
                        ValhallaSettingsView()
                    } label: {
                        Label("Routage Valhalla (bêta)", systemImage: "point.topleft.down.curvedto.point.bottomright.up")
                    }

                    #if DEBUG
                    DebugReplaySection()
                    #endif
                }

                Section {
                    Button {
                        showOnboarding = true
                    } label: {
                        Label("Revoir le didacticiel", systemImage: "graduationcap.fill")
                    }
                }
            }
            .navigationTitle("Réglages")
        }
        .fullScreenCover(isPresented: $showOnboarding) {
            OnboardingView(isPresented: $showOnboarding)
        }
    }

    /// Un seuil personnalisé = un `Stepper` degré par degré, borné [10°, 179°] (au-delà l'ordre
    /// light < marked < hard < uTurn n'est plus garanti — pas de validation croisée ici, le
    /// propriétaire reste libre de l'ordre exact qu'il veut tester).
    private func roadbookThresholdStepper(_ title: String, value: Binding<Double>) -> some View {
        Stepper(value: value, in: 10...179, step: 1) {
            HStack {
                Text(title)
                Spacer()
                Text("\(Int(value.wrappedValue))°").foregroundStyle(.secondary).monospacedDigit()
            }
        }
    }
}
