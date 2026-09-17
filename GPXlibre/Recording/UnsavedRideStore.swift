import Foundation

/// Spec "unsaved-ride-recovery" (it19, retour terrain : "quand on allume l'app, ça enregistre
/// direct, puis il faut manuellement l'enregistrer à la fin — créer dans Biblio une catégorie
/// 'non-enregistré' qui récupère les traces non enregistrées, avec un cleanup au bout de 10-20
/// traces, réglable") — filet de secours si l'utilisateur oublie "Terminer la sortie" (ou que
/// l'app plante/est tuée en arrière-plan) : `RideSessionManager` réécrit périodiquement un GPX
/// de la trace enregistrée EN COURS dans un dossier dédié, DISTINCT de `LibraryStore`
/// (`Documents/Tracks/`) — jamais mélangé aux vraies traces de la Bibliothèque tant qu'une
/// sauvegarde n'a pas été explicitement "récupérée".
struct UnsavedRide: Codable, Identifiable, Equatable {
    let id: UUID
    let fileName: String
    let startedAt: Date
    var pointCount: Int
}

@MainActor
final class UnsavedRideStore: ObservableObject {
    @Published private(set) var rides: [UnsavedRide] = []

    private let fileManager = FileManager.default
    /// Seam de test (même patron que `LibraryStore.tracksDirectoryOverride`) — jamais le vrai
    /// `Documents/UnsavedRides` de l'app pendant un test.
    private let directoryOverride: URL?

    private var directory: URL {
        let dir: URL
        if let directoryOverride {
            dir = directoryOverride
        } else {
            let docs = fileManager.urls(for: .documentDirectory, in: .userDomainMask)[0]
            dir = docs.appendingPathComponent("UnsavedRides", isDirectory: true)
        }
        if !fileManager.fileExists(atPath: dir.path) {
            try? fileManager.createDirectory(at: dir, withIntermediateDirectories: true)
        }
        return dir
    }

    private var indexFileURL: URL { directory.appendingPathComponent("index.json") }

    init(directoryOverride: URL? = nil) {
        self.directoryOverride = directoryOverride
        loadIndex()
    }

    func fileURL(for ride: UnsavedRide) -> URL {
        directory.appendingPathComponent(ride.fileName)
    }

    /// Écrit/écrase le fichier de secours de la session `sessionID` — appelé PÉRIODIQUEMENT par
    /// RideSessionManager pendant l'enregistrement (pas à chaque point, coût I/O), jamais par
    /// une autre source. `maxRetained` vient de RideSettingsStore (réglable par l'utilisateur) :
    /// purge les sauvegardes les plus anciennes au-delà de cette limite.
    func checkpoint(sessionID: UUID, startedAt: Date, gpxData: Data, pointCount: Int, maxRetained: Int) {
        let fileName = "\(sessionID.uuidString).gpx"
        guard (try? gpxData.write(to: directory.appendingPathComponent(fileName))) != nil else { return }

        if let index = rides.firstIndex(where: { $0.id == sessionID }) {
            rides[index].pointCount = pointCount
        } else {
            rides.append(UnsavedRide(id: sessionID, fileName: fileName, startedAt: startedAt, pointCount: pointCount))
        }
        saveIndex()
        enforceRetentionLimit(maxRetained: maxRetained)
    }

    /// Appelé quand la sortie correspondante vient d'être proprement enregistrée (EndRideView) —
    /// le filet de secours n'a plus lieu d'être pour CETTE session.
    func discard(sessionID: UUID) {
        guard let ride = rides.first(where: { $0.id == sessionID }) else { return }
        delete(ride)
    }

    func delete(_ ride: UnsavedRide) {
        try? fileManager.removeItem(at: fileURL(for: ride))
        rides.removeAll { $0.id == ride.id }
        saveIndex()
    }

    /// Recharge depuis le disque — appelé par la Biblio à l'apparition pour refléter les
    /// sauvegardes écrites entre-temps par une autre instance (RideSessionManager en possède
    /// sa propre référence privée, même patron que BlockageLogStore).
    func reload() { loadIndex() }

    private func enforceRetentionLimit(maxRetained: Int) {
        guard rides.count > maxRetained else { return }
        let oldestFirst = rides.sorted { $0.startedAt < $1.startedAt }
        for ride in oldestFirst.prefix(rides.count - maxRetained) {
            delete(ride)
        }
    }

    private func loadIndex() {
        guard let data = try? Data(contentsOf: indexFileURL),
              let decoded = try? JSONDecoder().decode([UnsavedRide].self, from: data) else { return }
        rides = decoded
    }

    private func saveIndex() {
        guard let data = try? JSONEncoder().encode(rides) else { return }
        try? data.write(to: indexFileURL)
    }
}
