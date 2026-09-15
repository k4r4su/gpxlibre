import Foundation

/// Source de fond de carte effective (spec "vector-pmtiles", it11) — remplace `TileSource`
/// comme paramètre passé aux `MapProvider` : le fond peut être vectoriel (hébergé OpenFreeMap,
/// étape 1 ; ou local via un `.pmtiles` importé/téléchargé, étape 2 self-host) ou rester
/// raster (comportement historique, jamais retiré — c'est le fallback mode avion sans paquet).
///
/// Résolue par `MapSourceResolver` (pur, testable), jamais construite à la main dans une vue.
enum MapSourceSelection: Equatable {
    case raster(TileSource)
    /// Étape 1 — CDN vectoriel ouvert sans clé (OpenFreeMap), pour valider le style/l'UX.
    /// `flavor` (spec "map-color-flavors", it19) : palette de couleur appliquée au style —
    /// fonctionne identiquement en hébergé ET en local, aucune limitation hors-ligne
    /// (contrairement à l'ancien thème Sombre, raster uniquement).
    case vectorHosted(flavor: MapColorFlavor)
    /// Étape 2 — fichier `.pmtiles` régional local (`Documents/VectorPackages/`), lu
    /// nativement par MapLibre via le schéma `pmtiles://file://...` (support intégré depuis
    /// MapLibre Native 6.10, confirmé dans les headers vendored de la version épinglée
    /// 6.31.0 — aucune dépendance supplémentaire). Fonctionne intégralement hors-ligne.
    case vectorLocal(fileURL: URL, flavor: MapColorFlavor)

    var isVector: Bool {
        switch self {
        case .raster: return false
        case .vectorHosted, .vectorLocal: return true
        }
    }
}
