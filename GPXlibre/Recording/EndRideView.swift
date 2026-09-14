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
    @EnvironmentObject private var session: RideSessionManager
    @State private var trackName = ""
    @State private var comment = ""
    @State private var exportURL: URL?

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
                            .disabled(points.count < 2 || trackName.trimmingCharacters(in: .whitespaces).isEmpty)
                    }
                }
            }
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
        library.importTrack(from: url)
        session.resetRecording()
        exportURL = url
    }
}
