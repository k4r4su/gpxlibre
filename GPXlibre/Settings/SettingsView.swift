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
                Section("Zoom automatique") {
                    Picker("Preset", selection: $settings.zoomPreset) {
                        ForEach(ZoomPreset.allCases) { preset in
                            Text(preset.displayName).tag(preset)
                        }
                    }
                    .pickerStyle(.segmented)
                }

                Section("Roadbook") {
                    Picker("Seuil de virage", selection: $settings.turnThresholdDegrees) {
                        ForEach(RideConstants.turnThresholdDegreesOptions, id: \.self) { value in
                            Text("\(Int(value))°").tag(value)
                        }
                    }
                    Picker("Alerte checkpoint", selection: $settings.checkpointAlertDistanceMeters) {
                        ForEach(RideConstants.alertDistanceOptions, id: \.self) { value in
                            Text("\(Int(value)) m").tag(value)
                        }
                    }
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
                }

                Section("Carte") {
                    Picker("Orientation", selection: $settings.mapOrientationNorthUp) {
                        Text("Cap en haut").tag(false)
                        Text("Nord en haut").tag(true)
                    }
                    Picker("Thème", selection: $settings.mapThemePreset) {
                        ForEach(MapThemePreset.allCases) { preset in
                            Text(preset.label).tag(preset)
                        }
                    }
                    Picker("Unité de vitesse", selection: $settings.speedUnit) {
                        ForEach(SpeedUnit.allCases) { unit in
                            Text(unit.label).tag(unit)
                        }
                    }
                }

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
                }

                Section("Trace") {
                    Picker("Épaisseur", selection: $settings.traceWidthPreset) {
                        ForEach(TraceWidthPreset.allCases) { preset in
                            Text(preset.label).tag(preset)
                        }
                    }
                    .pickerStyle(.segmented)

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
                }

                Section("Écran") {
                    Toggle("Empêcher la mise en veille en Ride", isOn: $settings.keepScreenAwakeInRide)
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
                }

                Section {
                    Button("Revoir le didacticiel") {
                        showOnboarding = true
                    }
                }
            }
            .navigationTitle("Réglages")
        }
        .fullScreenCover(isPresented: $showOnboarding) {
            OnboardingView(isPresented: $showOnboarding)
        }
    }
}
