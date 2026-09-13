import Foundation

/// Un paquet vectoriel régional (spec "vector-pmtiles", it11, étape 2 self-host) — un fichier
/// `.pmtiles` importé depuis Fichiers ou téléchargé depuis l'URL configurable (le NAS du
/// propriétaire). Pas d'empreinte région (bbox/zoom) calculée : lire l'en-tête PMTiles
/// nous-mêmes aurait demandé une dépendance supplémentaire pour une valeur ajoutée marginale
/// — décision de scope actée, voir docs/tuile-sources.md.
struct VectorPackage: Codable, Identifiable, Equatable {
    let id: UUID
    var name: String
    /// Nom de fichier réel dans `Documents/VectorPackages/` — distinct de `name` (modifiable
    /// par l'utilisateur) pour ne jamais dépendre d'un nom affiché comme chemin disque.
    let fileName: String
    /// nil si importé depuis Fichiers, sinon l'URL du NAS utilisée pour le téléchargement.
    var sourceURLString: String?
    var sizeBytes: Int64
    let importedAt: Date
}

/// Persiste la liste des paquets vectoriels + lequel est actif (spec "un seul paquet actif à
/// la fois", même patron que `LibraryStore.activeTrackID` — une seule source de vérité, pas
/// de fusion multi-région).
@MainActor
final class VectorPackageStore: ObservableObject {
    @Published private(set) var packages: [VectorPackage] = []
    @Published private(set) var activePackageID: UUID?

    private let fileManager = FileManager.default
    private let defaults: UserDefaults
    private static let activeIDKey = "vectorPackages.activePackageID"

    private var packagesDirectory: URL {
        let docs = fileManager.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let directory = docs.appendingPathComponent("VectorPackages", isDirectory: true)
        if !fileManager.fileExists(atPath: directory.path) {
            try? fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        }
        return directory
    }

    private var metadataFileURL: URL {
        packagesDirectory.appendingPathComponent("packages.json")
    }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        load()
        if let raw = defaults.string(forKey: Self.activeIDKey), let id = UUID(uuidString: raw) {
            activePackageID = id
        }
    }

    var activePackage: VectorPackage? {
        packages.first { $0.id == activePackageID }
    }

    /// Consommé par `MapSourceResolver` — nil si aucun paquet actif, sans jamais supposer que
    /// le fichier existe encore (le resolver vérifie lui-même via `FileManager`).
    var activeFileURL: URL? {
        guard let activePackage else { return nil }
        return packagesDirectory.appendingPathComponent(activePackage.fileName)
    }

    func fileURL(for package: VectorPackage) -> URL {
        packagesDirectory.appendingPathComponent(package.fileName)
    }

    func setActive(_ id: UUID?) {
        activePackageID = id
        if let id {
            defaults.set(id.uuidString, forKey: Self.activeIDKey)
        } else {
            defaults.removeObject(forKey: Self.activeIDKey)
        }
    }

    /// Import depuis Fichiers (spec "importés"). `sourceURL` peut être security-scoped
    /// (document picker) — même précaution que `LibraryStore.importTrack`.
    @discardableResult
    func importPackage(from sourceURL: URL, name: String? = nil) throws -> VectorPackage {
        let needsSecurityScope = sourceURL.startAccessingSecurityScopedResource()
        defer { if needsSecurityScope { sourceURL.stopAccessingSecurityScopedResource() } }

        let destination = packagesDirectory.appendingPathComponent("\(UUID().uuidString).pmtiles")
        try fileManager.copyItem(at: sourceURL, to: destination)
        return registerDownloadedFile(
            at: destination,
            name: name ?? sourceURL.deletingPathExtension().lastPathComponent,
            sourceURLString: nil
        )
    }

    /// Téléchargement depuis l'URL configurable (le NAS du propriétaire, spec "étape 2").
    /// Patron `completion` (pas async/await) pour matcher `TileDownloadQueue`, seul autre
    /// téléchargement du module Offline.
    func downloadPackage(from remoteURL: URL, name: String? = nil, completion: @escaping (Result<VectorPackage, Error>) -> Void) {
        let task = URLSession.shared.downloadTask(with: remoteURL) { [weak self] tempURL, response, error in
            Task { @MainActor in
                guard let self else { return }
                if let error {
                    completion(.failure(error))
                    return
                }
                guard let tempURL, let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
                    completion(.failure(URLError(.badServerResponse)))
                    return
                }
                do {
                    let destination = self.packagesDirectory.appendingPathComponent("\(UUID().uuidString).pmtiles")
                    if self.fileManager.fileExists(atPath: destination.path) {
                        try? self.fileManager.removeItem(at: destination)
                    }
                    try self.fileManager.moveItem(at: tempURL, to: destination)
                    let package = self.registerDownloadedFile(
                        at: destination,
                        name: name ?? remoteURL.deletingPathExtension().lastPathComponent,
                        sourceURLString: remoteURL.absoluteString
                    )
                    completion(.success(package))
                } catch {
                    completion(.failure(error))
                }
            }
        }
        task.resume()
    }

    func delete(_ package: VectorPackage) {
        try? fileManager.removeItem(at: fileURL(for: package))
        packages.removeAll { $0.id == package.id }
        if activePackageID == package.id { setActive(nil) }
        save()
    }

    private func registerDownloadedFile(at destination: URL, name: String, sourceURLString: String?) -> VectorPackage {
        let attributes = try? fileManager.attributesOfItem(atPath: destination.path)
        let sizeBytes = (attributes?[.size] as? NSNumber)?.int64Value ?? 0
        let package = VectorPackage(
            id: UUID(),
            name: name,
            fileName: destination.lastPathComponent,
            sourceURLString: sourceURLString,
            sizeBytes: sizeBytes,
            importedAt: Date()
        )
        packages.append(package)
        save()
        return package
    }

    private func load() {
        guard let data = try? Data(contentsOf: metadataFileURL),
              let decoded = try? JSONDecoder().decode([VectorPackage].self, from: data) else { return }
        packages = decoded
    }

    private func save() {
        guard let data = try? JSONEncoder().encode(packages) else { return }
        try? data.write(to: metadataFileURL)
    }
}
