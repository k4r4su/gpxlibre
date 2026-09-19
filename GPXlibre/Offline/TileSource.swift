import Foundation

/// Deux sources de tuiles raster coexistent dans le cache (jamais la même case z/x/y —
/// chacune a son propre sous-dossier, voir `cacheFolderName`). "Relief" = thème carte #4
/// (Standard/Clair/Sombre/Relief) — Option A de la spec : tuiles OpenTopoMap toutes prêtes,
/// pas de source DEM séparée (Option B) — voir TODO.md pour le compromis assumé.
enum TileSource: String, Codable, CaseIterable {
    case osmStandard
    case openTopoMap
    /// Spec "satellite-sentinel2" (it22) — imagerie Sentinel-2 cloudless (EOX IT Services GmbH,
    /// mosaïque annuelle sans nuages), SEULE source satellite trouvée gratuite ET réutilisable
    /// hors-ligne (décision documentée en it18-bis, TODO.md : Esri/Google/Bing World Imagery
    /// interdisent la redistribution/mise en cache dans leurs CGU gratuites — incompatible avec
    /// le cache PMTiles/raster auto-hébergé de cette app). Contrepartie assumée, choisie
    /// explicitement par le propriétaire face à l'alternative payante (Maxar/Mapbox Satellite,
    /// nécessite un compte + une clé que l'app ne peut pas provisionner) : résolution nettement
    /// inférieure à un satellite commercial (~10 m/pixel natif, mosaïque annuelle — pas
    /// d'imagerie récente), largement suffisant pour se repérer, PAS pour distinguer un sentier
    /// étroit.
    case satellite

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
        case .satellite:
            // Ordre de chemin INHABITUEL, vérifié contre la vraie WMTSCapabilities.xml du
            // service (pas deviné) : le ResourceURL officiel est
            // ".../default/{TileMatrixSet}/{TileMatrix}/{TileRow}/{TileCol}.jpg", soit
            // z/y/x — PAS z/x/y comme la plupart des sources XYZ. Les jetons `{z}`/`{x}`/`{y}`
            // sont substitués PAR NOM (jamais par position) aussi bien côté MapLibre
            // (spec TileJSON) que côté `TileDownloadQueue.tileURL` (replacingOccurrences) — leur
            // ordre dans la chaîne peut donc être différent de la convention habituelle sans
            // rien casser, à condition d'écrire le bon ordre ICI (sinon des tuiles x/y
            // interverties silencieusement, jamais une erreur visible).
            return ["https://tiles.maps.eox.at/wmts/1.0.0/s2cloudless-2024_3857/default/g/{z}/{y}/{x}.jpg"]
        }
    }

    /// Hôtes à intercepter pour le cache disque (TileCacheURLProtocol).
    var hosts: [String] {
        switch self {
        case .osmStandard: return ["tile.openstreetmap.org"]
        case .openTopoMap: return ["a.tile.opentopomap.org", "b.tile.opentopomap.org", "c.tile.opentopomap.org"]
        case .satellite: return ["tiles.maps.eox.at"]
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
        // Résolution native Sentinel-2 ≈ 10 m/pixel — au-delà du zoom 16, les tuiles servies
        // sont un simple suréchantillonnage (aucun détail réel supplémentaire), pas la peine de
        // les mettre en cache hors-ligne (le service en sert jusqu'à 21, vérifié dans sa
        // WMTSCapabilities.xml, mais ce serait du stockage gaspillé pour du flou).
        case .satellite: return 16
        }
    }

    var attributionHTML: String {
        switch self {
        case .osmStandard: return MapEngineConstants.osmAttributionHTML
        case .openTopoMap:
            return "Kartendaten: © OpenStreetMap-Mitwirkende, SRTM | Style: © OpenTopoMap (CC-BY-SA)"
        case .satellite:
            return "Sentinel-2 cloudless by <a href=\"https://eox.at\">EOX IT Services GmbH</a> (Contains modified Copernicus Sentinel data 2024), <a href=\"https://creativecommons.org/licenses/by-nc-sa/4.0/\">CC BY-NC-SA 4.0</a>"
        }
    }

    var attributionPlainText: String {
        switch self {
        case .osmStandard: return MapEngineConstants.osmAttributionPlainText
        case .openTopoMap: return "© OpenStreetMap contributors, SRTM · © OpenTopoMap (CC-BY-SA)"
        // Attribution EXACTE requise par EOX (vérifiée dans la WMTSCapabilities.xml officielle
        // du service, pas devinée/recopiée d'un blog tiers) — licence CC BY-NC-SA 4.0
        // (NonCommercial inclus : compatible avec GPXlibre, gratuit et sans abonnement).
        case .satellite: return "Sentinel-2 cloudless by EOX IT Services GmbH (Copernicus Sentinel data 2024) · CC BY-NC-SA 4.0"
        }
    }

    /// Sous-dossier de cache disque — jamais partagé entre sources pour éviter toute collision
    /// z/x/y entre deux jeux de tuiles différents.
    var cacheFolderName: String {
        switch self {
        case .osmStandard: return "osm"
        case .openTopoMap: return "opentopo"
        case .satellite: return "satellite"
        }
    }

    /// Extension réelle du format d'image servi — PAS toujours ".png" (fix "satellite-black-map",
    /// it22bis : EOX sert du JPEG, `TileCacheURLProtocol.parseTile` supposait ".png" en dur et
    /// échouait silencieusement sur CHAQUE tuile satellite, d'où l'écran totalement noir).
    var tileFileExtension: String {
        switch self {
        case .osmStandard, .openTopoMap: return "png"
        case .satellite: return "jpg"
        }
    }

    static func active(for theme: MapThemePreset) -> TileSource {
        switch theme {
        case .relief: return .openTopoMap
        case .satellite: return .satellite
        case .standard, .hauteContraste, .terreux: return .osmStandard
        }
    }
}
