import Foundation

/// Résolution PURE de la source de carte effective (spec "vector-pmtiles", it11 ; flavors de
/// couleur, it19) — testable sans UIKit ni réseau réel, aucun état mutable. Priorité explicite
/// de la spec :
///
/// 0. Fix "map-theme-binding" (it13) — Relief n'a PAS de variante vectorielle (le style embarqué
///    "Liberty" n'a qu'un rendu clair patché par flavor, voir CLAUDE.md "Fond vectoriel
///    PMTiles") : avant ce fix, Relief était purement décoratif dès que le réseau était
///    joignable (le cas normal), car seule la branche 3 ci-dessous lisait `themePreset` —
///    jamais atteinte en pratique. Relief force donc désormais le raster correspondant, AVANT
///    même de regarder un paquet vectoriel local ou le réseau. (Le thème "Sombre", qui avait le
///    même traitement, a été retiré en it19 — plus aucun thème raster-only hors Relief.)
/// 1. Sinon, un paquet vectoriel local actif ET dont le fichier existe encore sur disque →
///    `.vectorLocal` (fonctionne intégralement en mode avion — c'est tout le but du
///    self-host PMTiles), avec la palette de couleur du thème choisi.
/// 2. Sinon, si le réseau est joignable → `.vectorHosted` (OpenFreeMap, étape 1), avec la même
///    palette — flavors fonctionnent identiquement hébergé/local, aucune limitation hors-ligne.
/// 3. Sinon (pas de paquet local utilisable, pas de réseau — mode avion sans rien préparé)
///    → comportement RASTER actuel, inchangé, SANS palette (image pré-rendue, pas de couleur
///    applicable). Le raster ne part pas.
enum MapSourceResolver {
    static func resolve(
        activeVectorPackageFileURL: URL?,
        isNetworkReachable: Bool,
        themePreset: MapThemePreset,
        fileExists: (URL) -> Bool = { FileManager.default.fileExists(atPath: $0.path) }
    ) -> MapSourceSelection {
        guard let flavor = themePreset.colorFlavor else {
            return .raster(TileSource.active(for: themePreset))
        }
        if let fileURL = activeVectorPackageFileURL, fileExists(fileURL) {
            return .vectorLocal(fileURL: fileURL, flavor: flavor)
        }
        if isNetworkReachable {
            return .vectorHosted(flavor: flavor)
        }
        return .raster(TileSource.active(for: themePreset))
    }
}
