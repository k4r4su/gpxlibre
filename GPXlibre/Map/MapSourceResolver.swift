import Foundation

/// Résolution PURE de la source de carte effective (spec "vector-pmtiles", it11) — testable
/// sans UIKit ni réseau réel, aucun état mutable. Priorité explicite de la spec :
///
/// 0. Fix "map-theme-binding" (it13, bug terrain : "Choisir Clair/Sombre/Relief n'a aucun
///    effet") — Relief et Sombre n'ont PAS de variante vectorielle (le style embarqué "Liberty"
///    n'a qu'un rendu clair, voir CLAUDE.md "Fond vectoriel PMTiles") : avant ce fix, ces deux
///    thèmes étaient purement décoratifs dès que le réseau était joignable (le cas normal), car
///    seule la branche 3 ci-dessous lisait `themePreset` — jamais atteinte en pratique. Relief/
///    Sombre forcent donc désormais le raster correspondant, AVANT même de regarder un paquet
///    vectoriel local ou le réseau (qui n'ont, de toute façon, pas ce qu'il faut pour ces deux
///    thèmes).
/// 1. Sinon, un paquet vectoriel local actif ET dont le fichier existe encore sur disque →
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
        if themePreset == .relief || themePreset == .sombre {
            return .raster(TileSource.active(for: themePreset))
        }
        if let fileURL = activeVectorPackageFileURL, fileExists(fileURL) {
            return .vectorLocal(fileURL: fileURL)
        }
        if isNetworkReachable {
            return .vectorHosted
        }
        return .raster(TileSource.active(for: themePreset))
    }
}
