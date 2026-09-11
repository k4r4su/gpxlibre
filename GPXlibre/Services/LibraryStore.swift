import Foundation

@MainActor
final class LibraryStore: ObservableObject {
    @Published private(set) var tracks: [GPXTrack] = []
    @Published var lastError: String?
    @Published var selectedTrackID: UUID? {
        didSet { UserDefaults.standard.set(selectedTrackID?.uuidString, forKey: "library.selectedTrackID") }
    }

    /// Trace actuellement choisie pour le mode Ride (onglet 1). Ne modifie en rien
    /// le fonctionnement de l'écran Bibliothèque lui-même.
    var selectedTrack: GPXTrack? {
        guard let id = selectedTrackID else { return nil }
        return tracks.first { $0.id == id }
    }

    private let fileManager = FileManager.default

    private var tracksDirectory: URL {
        let docs = fileManager.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let dir = docs.appendingPathComponent("Tracks", isDirectory: true)
        if !fileManager.fileExists(atPath: dir.path) {
            try? fileManager.createDirectory(at: dir, withIntermediateDirectories: true)
        }
        return dir
    }

    private var indexFileURL: URL {
        tracksDirectory.appendingPathComponent("index.json")
    }

    init() {
        loadIndex()
        if let stored = UserDefaults.standard.string(forKey: "library.selectedTrackID") {
            selectedTrackID = UUID(uuidString: stored)
        }
    }

    /// Import déclenché depuis le partage système iOS (Mail/Safari/Fichiers → "Ouvrir dans GPXlibre")
    /// ou depuis le sélecteur de fichiers manuel.
    func importTrack(from url: URL) {
        let accessing = url.startAccessingSecurityScopedResource()
        defer { if accessing { url.stopAccessingSecurityScopedResource() } }
        do {
            let data = try Data(contentsOf: url)
            try addTrack(named: url.deletingPathExtension().lastPathComponent, data: data)
        } catch {
            lastError = "Import impossible : \(error.localizedDescription)"
        }
    }

    func loadSample() {
        guard let sampleURL = Bundle.main.url(forResource: "sample-trail", withExtension: "gpx") else {
            lastError = "Fichier d'exemple introuvable dans le bundle."
            return
        }
        do {
            let data = try Data(contentsOf: sampleURL)
            try addTrack(named: "Exemple – Col de la Croix", data: data)
        } catch {
            lastError = "Chargement de l'exemple impossible : \(error.localizedDescription)"
        }
    }

    func rename(_ track: GPXTrack, to newName: String) {
        let trimmed = newName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, let index = tracks.firstIndex(where: { $0.id == track.id }) else { return }
        tracks[index].name = trimmed
        saveIndex()
    }

    func delete(_ track: GPXTrack) {
        let fileURL = tracksDirectory.appendingPathComponent(track.fileName)
        try? fileManager.removeItem(at: fileURL)
        tracks.removeAll { $0.id == track.id }
        if selectedTrackID == track.id { selectedTrackID = nil }
        saveIndex()
    }

    private func addTrack(named suggestedName: String, data: Data) throws {
        let parsed = try GPXParser.parse(data: data)
        let fileName = "\(UUID().uuidString).gpx"
        let destination = tracksDirectory.appendingPathComponent(fileName)
        try data.write(to: destination)
        let track = GPXTrack(
            id: UUID(),
            name: parsed.name ?? suggestedName,
            fileName: fileName,
            importDate: Date(),
            points: parsed.points,
            waypoints: parsed.waypoints
        )
        tracks.insert(track, at: 0)
        if selectedTrackID == nil {
            selectedTrackID = track.id
        }
        saveIndex()
    }

    private func loadIndex() {
        guard let data = try? Data(contentsOf: indexFileURL),
              let decoded = try? JSONDecoder().decode([GPXTrack].self, from: data) else { return }
        tracks = decoded
    }

    private func saveIndex() {
        guard let data = try? JSONEncoder().encode(tracks) else { return }
        try? data.write(to: indexFileURL)
    }
}
