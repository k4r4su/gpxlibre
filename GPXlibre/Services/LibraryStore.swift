import Foundation

/// Source de vérité unique pour l'état "active"/"affichée" des traces (fix
/// "single-source-active-track", itération 10) — avant ce fix, `selectedTrackID` était un
/// simple UUID optionnel manipulé indépendamment par `delete()`, l'import et
/// `TrackDetailView`, sans invariant centralisé : c'était la cause des états fantômes
/// remontés du terrain (trace supprimée toujours active, trace importée qui n'apparaît pas).
///
/// Deux états désormais, avec un seul invariant fort : **active ⟹ affichée** (jamais une
/// trace active qui ne serait pas affichée). Le pipeline de rendu (RideMapLibreView/
/// RideMapView) ne reçoit toujours qu'UNE SEULE trace (`activeTrack`) — `displayedTrackIDs`
/// existe pour le bookkeeping (ex : une trace importée pendant qu'une autre est active reste
/// "affichée" sans voler l'état actif), jamais pour un rendu multi-trace simultané, hors
/// périmètre de l'app ("afficher une trace", pas plusieurs).
@MainActor
final class LibraryStore: ObservableObject {
    @Published private(set) var tracks: [GPXTrack] = []
    @Published var lastError: String?
    @Published private(set) var activeTrackID: UUID?
    @Published private(set) var displayedTrackIDs: Set<UUID> = []

    private static let activeTrackKey = "library.activeTrackID"
    private static let displayedTrackIDsKey = "library.displayedTrackIDs"
    private static let legacySelectedTrackKey = "library.selectedTrackID"

    /// Trace actuellement chargée pour le mode Ride (onglet 1). Ne modifie en rien le
    /// fonctionnement de l'écran Bibliothèque lui-même.
    var activeTrack: GPXTrack? {
        guard let id = activeTrackID else { return nil }
        return tracks.first { $0.id == id }
    }

    func isDisplayed(_ id: UUID) -> Bool { displayedTrackIDs.contains(id) }

    /// Bascule "affichée" (œil/check vert dans la ligne Biblio). Invariant "active ⟹
    /// affichée" appliqué dans les deux sens : afficher une trace sans active existante la
    /// promeut automatiquement ; masquer la trace active fait tomber l'état actif avec elle
    /// (une trace non affichée ne peut jamais rester active).
    func setDisplayed(_ id: UUID, _ displayed: Bool) {
        guard tracks.contains(where: { $0.id == id }) else { return }
        if displayed {
            displayedTrackIDs.insert(id)
            if activeTrackID == nil { activeTrackID = id }
        } else {
            displayedTrackIDs.remove(id)
            if activeTrackID == id { activeTrackID = nil }
        }
        persistActiveState()
    }

    /// Rend une trace explicitement active ("Utiliser pour le Ride", panneau réglages par
    /// trace) — l'affiche automatiquement si besoin (invariant).
    func setActive(_ id: UUID) {
        guard tracks.contains(where: { $0.id == id }) else { return }
        displayedTrackIDs.insert(id)
        activeTrackID = id
        persistActiveState()
    }

    private let fileManager = FileManager.default
    private let tracksDirectoryOverride: URL?
    private let defaults: UserDefaults

    private var tracksDirectory: URL {
        if let tracksDirectoryOverride {
            if !fileManager.fileExists(atPath: tracksDirectoryOverride.path) {
                try? fileManager.createDirectory(at: tracksDirectoryOverride, withIntermediateDirectories: true)
            }
            return tracksDirectoryOverride
        }
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

    /// `tracksDirectoryOverride`/`defaults` : seams de test (fix "single-source-active-track",
    /// it10) — évite que les tests unitaires ne lisent/écrivent le vrai `Documents/Tracks` ou
    /// le vrai `UserDefaults.standard` de l'app. En production, les deux paramètres restent à
    /// leur valeur par défaut (voir GPXlibreApp).
    init(tracksDirectoryOverride: URL? = nil, defaults: UserDefaults = .standard) {
        self.tracksDirectoryOverride = tracksDirectoryOverride
        self.defaults = defaults
        loadIndex()
        loadActiveState()
    }

    /// Import déclenché depuis le partage système iOS (Mail/Safari/Fichiers → "Ouvrir dans GPXlibre")
    /// ou depuis le sélecteur de fichiers manuel. Retourne l'id de la trace créée (spec
    /// "ride-record-tracks-visible", it18, Bloc 2 — permet à l'appelant, ex. EndRideView, d'agir
    /// sur la trace qu'il vient d'enregistrer, sans avoir à la retrouver par nom/heure) ou `nil`
    /// si l'import échoue (voir `lastError`). `@discardableResult` : la plupart des appelants
    /// (partage système, sélecteur multi-fichiers) ignorent la valeur, comme avant ce changement.
    @discardableResult
    func importTrack(from url: URL) -> UUID? {
        let accessing = url.startAccessingSecurityScopedResource()
        defer { if accessing { url.stopAccessingSecurityScopedResource() } }
        do {
            let data = try Data(contentsOf: url)
            return try addTrack(named: url.deletingPathExtension().lastPathComponent, data: data)
        } catch {
            lastError = "Import impossible : \(error.localizedDescription)"
            return nil
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
        sortTracks()
        saveIndex()
    }

    /// Purge immédiate à la source (fix "single-source-active-track") : si la trace
    /// supprimée était active ou simplement affichée, les deux états tombent AVANT même que
    /// la vue Ride ne réagisse — plus de fenêtre où un état incohérent pourrait être lu.
    func delete(_ track: GPXTrack) {
        let fileURL = tracksDirectory.appendingPathComponent(track.fileName)
        try? fileManager.removeItem(at: fileURL)
        tracks.removeAll { $0.id == track.id }
        displayedTrackIDs.remove(track.id)
        if activeTrackID == track.id { activeTrackID = nil }
        saveIndex()
        persistActiveState()
    }

    @discardableResult
    private func addTrack(named suggestedName: String, data: Data) throws -> UUID {
        let parsed = try GPXParser.parse(data: data)
        let fileName = "\(UUID().uuidString).gpx"
        let destination = tracksDirectory.appendingPathComponent(fileName)
        try data.write(to: destination)
        // Spec "biblio-date-display" (it15, Bloc 1) : priorité metadata GPX > date de création
        // fichier > (repli implicite sur importDate côté GPXTrack.displayDate si les deux sont nil).
        let fileCreationDate = (try? fileManager.attributesOfItem(atPath: destination.path))?[.creationDate] as? Date
        let track = GPXTrack(
            id: UUID(),
            name: parsed.name ?? suggestedName,
            fileName: fileName,
            importDate: Date(),
            contentDate: parsed.metadataDate ?? fileCreationDate,
            points: parsed.points,
            waypoints: parsed.waypoints
        )
        tracks.insert(track, at: 0)
        // Spec "single-source-active-track" : toujours affichée automatiquement ; active
        // seulement si aucune autre trace ne l'est déjà (jamais de vol d'état actif).
        displayedTrackIDs.insert(track.id)
        if activeTrackID == nil {
            activeTrackID = track.id
        }
        sortTracks()
        saveIndex()
        persistActiveState()
        return track.id
    }

    /// Tri Biblio (spec "biblio-date-display", it15, Bloc 1) — appliqué après chaque mutation
    /// qui peut changer l'ordre (import, renommage) et au chargement ; `delete`/`setActive`/
    /// `setDisplayed` ne changent ni date ni nom, pas besoin d'y retrier.
    private func sortTracks() {
        switch LibraryConstants.sortKey {
        case .dateDescending:
            tracks.sort { a, b in
                if a.displayDate != b.displayDate { return a.displayDate > b.displayDate }
                return a.name.localizedCaseInsensitiveCompare(b.name) == .orderedAscending
            }
        case .alphabetical:
            tracks.sort { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        }
    }

    private func loadIndex() {
        guard let data = try? Data(contentsOf: indexFileURL),
              let decoded = try? JSONDecoder().decode([GPXTrack].self, from: data) else { return }
        tracks = decoded
        sortTracks()
    }

    private func saveIndex() {
        guard let data = try? JSONEncoder().encode(tracks) else { return }
        try? data.write(to: indexFileURL)
    }

    private func loadActiveState() {
        if let data = defaults.data(forKey: Self.displayedTrackIDsKey),
           let decoded = try? JSONDecoder().decode(Set<UUID>.self, from: data) {
            displayedTrackIDs = decoded
        }
        if let stored = defaults.string(forKey: Self.activeTrackKey) {
            activeTrackID = UUID(uuidString: stored)
        } else if let legacy = defaults.string(forKey: Self.legacySelectedTrackKey) {
            // Migration silencieuse depuis l'ancien modèle à un seul UUID optionnel — évite
            // de faire perdre son état actif à un utilisateur existant.
            activeTrackID = UUID(uuidString: legacy)
            if let id = activeTrackID { displayedTrackIDs.insert(id) }
            persistActiveState()
        }
    }

    private func persistActiveState() {
        defaults.set(activeTrackID?.uuidString, forKey: Self.activeTrackKey)
        if let data = try? JSONEncoder().encode(displayedTrackIDs) {
            defaults.set(data, forKey: Self.displayedTrackIDsKey)
        }
    }
}
