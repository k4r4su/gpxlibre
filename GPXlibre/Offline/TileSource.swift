import Foundation

/// Deux sources de tuiles raster coexistent dans le cache (jamais la même case z/x/y —
/// chacune a son propre sous-dossier, voir `cacheFolderName`). "Relief" = thème carte #4
/// (Standard/Clair/Sombre/Relief) — Option A de la spec : tuiles OpenTopoMap toutes prêtes,
/// pas de source DEM séparée (Option B) — voir TODO.md pour le compromis assumé.
///
/// Un 3e cas, `satellite` (Sentinel-2 cloudless via EOX, spec "satellite-sentinel2", it22), a
/// existé brièvement puis a été RETIRÉ (chore "remove-satellite", it22bis, retour terrain
/// immédiat : "vraiment pixelisé et inutilisable") — la résolution native ~10 m/pixel du
/// service, déjà documentée comme contrepartie assumée au moment du choix, s'est avérée
/// rédhibitoire en usage réel (bien plus grossière qu'un satellite commercial). Backlog
/// re-documenté dans TODO.md ; ne pas réintroduire cette même source sans un changement de
/// fournisseur (résolution) en amont.
enum TileSource: String, Codable, CaseIterable {
    case osmStandard
    case openTopoMap

    /// MapLibre round-robine automatiquement entre plusieurs gabarits d'URL fournis dans le
    /// style JSON — c'est notre substitut à la syntaxe `{s}` (non supportée telle quelle).
    var tileURLTemplates: [String] {
        switch self {
        case .osmStandard:
            return [MapEngineConstants.osmTileURLTemplate]
        case .openTopoMap:
            return [
                "https://a.tile.opentopomap.org/{z}/{x}/{y}.png",
                "https://b.tile.opentopomap.org/{z}/{x}/{y}.png",
                "https://c.tile.opentopomap.org/{z}/{x}/{y}.png",
            ]
        }
    }

    /// Hôtes à intercepter pour le cache disque (TileCacheURLProtocol).
    var hosts: [String] {
        switch self {
        case .osmStandard: return ["tile.openstreetmap.org"]
        case .openTopoMap: return ["a.tile.opentopomap.org", "b.tile.opentopomap.org", "c.tile.opentopomap.org"]
        }
    }

    static func matching(host: String) -> TileSource? {
        allCases.first { $0.hosts.contains(host) }
    }

    var maxZoomLevel: Int {
        switch self {
        case .osmStandard: return Int(MapEngineConstants.maxZoomLevel)
        // OpenTopoMap ne sert officiellement des tuiles qu'jusqu'au zoom 17.
        case .openTopoMap: return 17
        }
    }

    var attributionHTML: String {
        switch self {
        case .osmStandard: return MapEngineConstants.osmAttributionHTML
        case .openTopoMap:
            return "Kartendaten: © OpenStreetMap-Mitwirkende, SRTM | Style: © OpenTopoMap (CC-BY-SA)"
        }
    }

    var attributionPlainText: String {
        switch self {
        case .osmStandard: return MapEngineConstants.osmAttributionPlainText
        case .openTopoMap: return "© OpenStreetMap contributors, SRTM · © OpenTopoMap (CC-BY-SA)"
        }
    }

    /// Sous-dossier de cache disque — jamais partagé entre sources pour éviter toute collision
    /// z/x/y entre deux jeux de tuiles différents.
    var cacheFolderName: String {
        switch self {
        case .osmStandard: return "osm"
        case .openTopoMap: return "opentopo"
        }
    }

    static func active(for theme: MapThemePreset) -> TileSource {
        theme == .relief ? .openTopoMap : .osmStandard
    }
}
