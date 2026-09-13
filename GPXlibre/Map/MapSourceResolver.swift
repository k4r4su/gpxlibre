import Foundation

/// Résolution PURE de la source de carte effective (spec "vector-pmtiles", it11) — testable
/// sans UIKit ni réseau réel, aucun état mutable. Priorité explicite de la spec :
///
/// 1. Un paquet vectoriel local actif ET dont le fichier existe encore sur disque →
///    `.vectorLocal` (fonctionne intégralement en mode avion — c'est tout le but du
///    self-host PMTiles).
/// 2. Sinon, si le réseau est joignable → `.vectorHosted` (OpenFreeMap, étape 1).
/// 3. Sinon (pas de paquet local utilisable, pas de réseau — mode avion sans rien préparé)
///    → comportement RASTER actuel, inchangé. Le raster ne part pas.
enum MapSourceResolver {
    static func resolve(
        activeVectorPackageFileURL: URL?,
        isNetworkReachable: Bool,
        themePreset: MapThemePreset,
        fileExists: (URL) -> Bool = { FileManager.default.fileExists(atPath: $0.path) }
    ) -> MapSourceSelection {
        if let fileURL = activeVectorPackageFileURL, fileExists(fileURL) {
            return .vectorLocal(fileURL: fileURL)
        }
        if isNetworkReachable {
            return .vectorHosted
        }
        return .raster(TileSource.active(for: themePreset))
    }
}
