import SwiftUI

/// Panneau de mise en forme avant export PDF (spec "roadbook-mode", it23, point 2 : "panneau
/// avant export, pas juste un bouton Exporter"). Génère depuis la MÊME liste `[RoadbookManeuver]`
/// que l'écran Road Book (passée par l'appelant, jamais recalculée séparément) — une seule
/// source de vérité, aucune divergence possible entre affichage et export.
struct RoadbookExportOptionsView: View {
    let trackName: String
    let maneuvers: [RoadbookManeuver]
    @Binding var options: RoadbookPDFOptions
    var landmarks: [UUID: String?] = [:]

    @Environment(\.dismiss) private var dismiss
    @State private var exportedPDFURL: URL?

    var body: some View {
        NavigationStack {
            Form {
                Section("Mise en page") {
                    Picker("Orientation", selection: $options.orientation) {
                        ForEach(PDFOrientation.allCases) { Text($0.label).tag($0) }
                    }
                    Picker("Densité", selection: $options.density) {
                        ForEach(PDFDensity.allCases) { Text($0.label).tag($0) }
                    }
                    Picker("Taille de police", selection: $options.fontSize) {
                        ForEach(PDFFontSize.allCases) { Text($0.label).tag($0) }
                    }
                }

                Section("Colonnes") {
                    Toggle("Distance cumulée", isOn: $options.showCumulativeDistance)
                    Toggle("Colonne note", isOn: $options.showNoteColumn)
                    Picker("Cap", selection: $options.headingStyle) {
                        ForEach(PDFHeadingStyle.allCases) { Text($0.label).tag($0) }
                    }
                }

                Section("Unité") {
                    Picker("Distance", selection: $options.distanceUnit) {
                        ForEach(DistanceUnit.allCases) { Text($0.label).tag($0) }
                    }
                }

                Section {
                    Text("\(maneuvers.count) manœuvre(s) détectée(s) sur « \(trackName) ».")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .navigationTitle("Export PDF")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Fermer") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    if let exportedPDFURL {
                        ShareLink(item: exportedPDFURL) {
                            Label("Partager", systemImage: "square.and.arrow.up")
                        }
                    } else {
                        Button("Générer") { generate() }
                    }
                }
            }
            .onChange(of: options) { _ in
                // Toute modification d'option invalide le PDF déjà généré — évite de partager
                // un fichier qui ne reflète plus les options actuellement affichées.
                exportedPDFURL = nil
            }
        }
    }

    private func generate() {
        let data = RoadbookPDFExporter.generate(trackName: trackName, maneuvers: maneuvers, options: options, landmarks: landmarks)
        let sanitizedName = trackName
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .joined(separator: "_")
        let destination = FileManager.default.temporaryDirectory.appendingPathComponent("RoadBook_\(sanitizedName.isEmpty ? "trace" : sanitizedName).pdf")
        do {
            if FileManager.default.fileExists(atPath: destination.path) {
                try FileManager.default.removeItem(at: destination)
            }
            try data.write(to: destination)
            exportedPDFURL = destination
        } catch {
            exportedPDFURL = nil
        }
    }
}
