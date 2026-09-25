import SwiftUI

/// Terminer la sortie : nom + commentaire d'une ligne (optionnel), enregistrement de la trace
/// roulée dans la Bibliothèque, puis partage du .gpx via le share sheet système.
struct EndRideView: View {
    /// Nom de la trace SUIVIE pendant le Ride (référence, jamais modifiée) — sert uniquement
    /// à préremplir `trackName` ci-dessous, jamais écrit tel quel : fix
    /// "end-ride-default-name" (bug terrain, it16) : la trace ENREGISTRÉE reprenait
    /// auparavant ce nom À L'IDENTIQUE, donc indiscernable de la trace d'origine dans Biblio
    /// une fois importée.
    let originalTrackName: String?
    let points: [GPXPoint]
    let waypoints: [RollingWaypoint]
    let onFinished: () -> Void

    @EnvironmentObject private var library: LibraryStore
    @EnvironmentObject private var recorder: RideRecorder
    @EnvironmentObject private var trackRideSettings: TrackRideSettingsStore
    @State private var trackName = ""
    @State private var comment = ""
    @State private var exportURL: URL?
    /// Spec "ride-record-tracks-visible" (it18, Bloc 2) : la trace enregistrée reste seulement
    /// "affichée" en Biblio (décision du propriétaire : ne pas voler l'état actif de la trace
    /// suivie, voir TODO.md) — cet aperçu, réutilisant TrackFicheMapView (même cadrage auto sur
    /// l'emprise que la fiche Biblio), est le seul moyen de "voir la trace sur la carte
    /// immédiatement après validation save" sans y toucher.
    @State private var savedTrack: GPXTrack?
    @State private var confirmDiscard = false

    private static let defaultNameDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "fr_FR")
        formatter.dateFormat = "d MMM yyyy"
        return formatter
    }()

    var body: some View {
        NavigationStack {
            Form {
                Section("Nom de la trace enregistrée") {
                    TextField("Nom", text: $trackName)
                }
                Section("Commentaire de fin de sortie") {
                    TextField("Une ligne, optionnel", text: $comment)
                }
                Section {
                    Text("\(points.count) points enregistrés · \(waypoints.count) point(s) d'intérêt")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                // It30 : terminer SANS enregistrer (sortie de test, oubli) — arrêt propre de
                // l'enregistrement, rien n'est ajouté à la Bibliothèque.
                if exportURL == nil {
                    Section {
                        Button("Supprimer sans enregistrer", role: .destructive) { confirmDiscard = true }
                    }
                }
                if exportURL != nil {
                    Section {
                        Label("Enregistrée dans la Bibliothèque", systemImage: "checkmark.seal.fill")
                            .foregroundStyle(.green)
                    }
                    if let savedTrack {
                        Section {
                            TrackFicheMapView(
                                orderedTrack: savedTrack,
                                isReversed: false,
                                traceAppearance: TraceAppearance(colorPreset: RideConstants.recordedTrackColorPreset)
                            )
                            .frame(height: 220)
                            .listRowInsets(EdgeInsets())
                        } header: {
                            Text("Trace enregistrée")
                        } footer: {
                            Text("Reste \"affichée\" en Bibliothèque sans remplacer la trace suivie active — coche-la depuis la Biblio pour la voir sur la carte du Ride.")
                        }
                    }
                }
            }
            .navigationTitle("Terminer la sortie")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Fermer") { onFinished() }
                }
                ToolbarItem(placement: .primaryAction) {
                    if let exportURL {
                        ShareLink(item: exportURL) {
                            Label("Partager le GPX", systemImage: "square.and.arrow.up")
                        }
                    } else {
                        Button("Enregistrer") { save() }
                            .disabled(points.count < 2 || trackName.trimmingCharacters(in: .whitespaces).isEmpty)
                    }
                }
            }
        }
        .confirmationDialog("Supprimer cette sortie ?", isPresented: $confirmDiscard, titleVisibility: .visible) {
            Button("Supprimer \(points.count) points", role: .destructive) {
                recorder.finish()
                onFinished()
            }
            Button("Annuler", role: .cancel) {}
        } message: {
            Text("L'enregistrement s'arrête et les points sont effacés. Rien n'est ajouté à la Bibliothèque.")
        }
        .onAppear {
            guard trackName.isEmpty else { return }
            let base = originalTrackName ?? "Sortie"
            trackName = "\(base) – \(Self.defaultNameDateFormatter.string(from: Date()))"
        }
    }

    private func save() {
        let data = GPXExporter.export(
            trackName: trackName,
            points: points,
            waypoints: waypoints,
            comment: comment
        )
        let fileName = "\(trackName)-\(Int(Date().timeIntervalSince1970)).gpx"
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(fileName)
        try? data.write(to: url)
        if let newID = library.importTrack(from: url) {
            // RECORDED_TRACK_DISPLAY_COLOR (spec "ride-record-tracks-visible", it18, Bloc 2) :
            // couleur distinctive par défaut, éditable ensuite comme tout override par trace.
            var recordedSettings = trackRideSettings.settings(for: newID)
            recordedSettings.colorOverride = RideConstants.recordedTrackColorPreset
            trackRideSettings.setSettings(recordedSettings, for: newID)
            savedTrack = library.tracks.first { $0.id == newID }
        }
        // La sortie est proprement enregistrée : fin de l'enregistrement (GPS arrière-plan coupé,
        // journal et secours "Sorties non enregistrées" de cette session supprimés, it30).
        recorder.finish()
        exportURL = url
    }
}
