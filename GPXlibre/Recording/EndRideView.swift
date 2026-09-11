import SwiftUI

/// Terminer la sortie : commentaire d'une ligne (optionnel), enregistrement de la trace
/// roulée dans la Bibliothèque, puis partage du .gpx via le share sheet système.
struct EndRideView: View {
    let trackName: String
    let points: [GPXPoint]
    let waypoints: [RollingWaypoint]
    let onFinished: () -> Void

    @EnvironmentObject private var library: LibraryStore
    @EnvironmentObject private var session: RideSessionManager
    @State private var comment = ""
    @State private var exportURL: URL?

    var body: some View {
        NavigationStack {
            Form {
                Section("Commentaire de fin de sortie") {
                    TextField("Une ligne, optionnel", text: $comment)
                }
                Section {
                    Text("\(points.count) points enregistrés · \(waypoints.count) point(s) d'intérêt")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                if exportURL != nil {
                    Section {
                        Label("Enregistrée dans la Bibliothèque", systemImage: "checkmark.seal.fill")
                            .foregroundStyle(.green)
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
                            .disabled(points.count < 2)
                    }
                }
            }
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
        library.importTrack(from: url)
        session.resetRecording()
        exportURL = url
    }
}
