import Foundation

/// Dossier de la Bibliothèque (it31).
struct TrackFolder: Codable, Identifiable, Equatable, Hashable {
    let id: UUID
    var name: String
}

/// Dossiers de la Bibliothèque (it31) — PUREMENT ORGANISATIONNELS :
/// - n'ont AUCUN effet sur la trace active/affichée (invariant it10, `setActive`/`setDisplayed`
///   restent les seuls points d'écriture) ni sur l'export/partage d'une trace (it19) ;
/// - persistés à part (`Tracks/folders.json` : dossiers + affectation trace → dossier), sans
///   toucher au modèle `GPXTrack` ni à `index.json`. Une trace sans affectation est dans le
///   dossier par défaut "Non classé" (virtuel, jamais stocké, jamais supprimable). Migration :
///   les traces existantes n'ont aucune affectation → toutes dans "Non classé", aucune orpheline ;
/// - supprimer un dossier ne supprime JAMAIS ses traces : elles retournent dans "Non classé".
@MainActor
extension LibraryStore {
    private struct FolderState: Codable {
        var folders: [TrackFolder]
        var assignments: [UUID: UUID]
    }

    private var foldersFileURL: URL { tracksDirectoryURL.appendingPathComponent("folders.json") }

    /// Dossiers triés par nom (ordre d'affichage).
    var sortedFolders: [TrackFolder] {
        folders.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    /// Dossier d'une trace — `nil` = "Non classé".
    func folderID(of trackID: UUID) -> UUID? {
        folderAssignments[trackID].flatMap { id in folders.contains { $0.id == id } ? id : nil }
    }

    /// Traces d'un dossier, dans l'ordre de la Bibliothèque — `nil` = "Non classé".
    func tracks(inFolder folderID: UUID?) -> [GPXTrack] {
        tracks.filter { self.folderID(of: $0.id) == folderID }
    }

    /// `nil` si le nom est vide ou déjà pris (sans tenir compte de la casse).
    @discardableResult
    func createFolder(named name: String) -> TrackFolder? {
        guard let cleaned = validFolderName(name, excluding: nil) else { return nil }
        let folder = TrackFolder(id: UUID(), name: cleaned)
        folders.append(folder)
        saveFolders()
        return folder
    }

    @discardableResult
    func renameFolder(_ id: UUID, to name: String) -> Bool {
        guard let index = folders.firstIndex(where: { $0.id == id }), let cleaned = validFolderName(name, excluding: id) else { return false }
        folders[index].name = cleaned
        saveFolders()
        return true
    }

    /// Les traces du dossier ne sont JAMAIS supprimées : elles retournent dans "Non classé".
    func deleteFolder(_ id: UUID) {
        folders.removeAll { $0.id == id }
        folderAssignments = folderAssignments.filter { $0.value != id }
        saveFolders()
    }

    /// `folderID == nil` : vers "Non classé".
    func move(trackID: UUID, toFolder folderID: UUID?) {
        guard tracks.contains(where: { $0.id == trackID }) else { return }
        if let folderID {
            guard folders.contains(where: { $0.id == folderID }) else { return }
            folderAssignments[trackID] = folderID
        } else {
            folderAssignments.removeValue(forKey: trackID)
        }
        saveFolders()
    }

    func forgetFolderAssignment(of trackID: UUID) {
        guard folderAssignments.removeValue(forKey: trackID) != nil else { return }
        saveFolders()
    }

    /// Au lancement : lit `folders.json` (absent = aucun dossier, toutes les traces "Non classé")
    /// et oublie les affectations vers une trace ou un dossier disparus.
    func loadFolders() {
        guard let data = try? Data(contentsOf: foldersFileURL),
              let state = try? JSONDecoder().decode(FolderState.self, from: data)
        else { return }
        folders = state.folders
        let trackIDs = Set(tracks.map(\.id))
        let folderIDs = Set(state.folders.map(\.id))
        folderAssignments = state.assignments.filter { trackIDs.contains($0.key) && folderIDs.contains($0.value) }
        if folderAssignments.count != state.assignments.count { saveFolders() }
    }

    private func saveFolders() {
        guard let data = try? JSONEncoder().encode(FolderState(folders: folders, assignments: folderAssignments)) else { return }
        try? data.write(to: foldersFileURL)
    }

    private func validFolderName(_ name: String, excluding id: UUID?) -> String? {
        let cleaned = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleaned.isEmpty,
              !folders.contains(where: { $0.id != id && $0.name.caseInsensitiveCompare(cleaned) == .orderedSame })
        else { return nil }
        return cleaned
    }
}
