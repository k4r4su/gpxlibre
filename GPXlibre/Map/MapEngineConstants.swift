import Foundation

enum MapEngineConstants {
    /// Moteur de carte actif dans l'app. MapKit reste compilable et intact (comparaison),
    /// mais n'est pas instancié tant que ceci vaut `.mapLibre`.
    static let active: MapEngine = .mapLibre

    /// Tuiles raster OSM standard. Respecte la politique d'usage OSM : User-Agent identifiant
    /// l'app (voir MapLibreBootstrap), pas de téléchargement en masse hors du corridor pré-caché
    /// (axe suivant), attribution visible en permanence (voir OSMAttributionView).
    static let osmTileURLTemplate = "https://tile.openstreetmap.org/{z}/{x}/{y}.png"
    static let osmAttributionHTML = "© <a href=\"https://www.openstreetmap.org/copyright\">OpenStreetMap</a> contributors"
    static let osmAttributionPlainText = "© OpenStreetMap contributors"

    static let minZoomLevel: Double = 0
    static let maxZoomLevel: Double = 19

    /// Identifie explicitement l'app auprès de tile.openstreetmap.org (politique d'usage OSM :
    /// un User-Agent générique/absent peut être throttled ou bloqué par les serveurs OSM).
    static let userAgent = "GPXlibre/0.3 (contact: oliv.zim@gmail.com)"

    static let rasterSourceIdentifier = "osm-raster-source"
    static let rasterLayerIdentifier = "osm-raster-layer"
    static let trackSourceIdentifier = "track-source"
    static let trackLayerIdentifier = "track-layer"
    static let detourSourceIdentifier = "detour-source"
    static let detourLayerIdentifier = "detour-layer"
    static let navRouteSourceIdentifier = "nav-route-source"
    static let navRouteLayerIdentifier = "nav-route-layer"
    static let goToSourceIdentifier = "goto-source"
    static let goToLayerIdentifier = "goto-layer"
    /// Halo de contraste derrière le point de position natif (spec "fab-contrast") — même
    /// idée que le casing de la trace : un disque qui ressort sur fond clair ET sur fond
    /// sombre, indépendant du point natif lui-même (qui reste géré par MapLibre).
    static let userLocationHaloSourceIdentifier = "user-location-halo-source"
    static let userLocationHaloLayerIdentifier = "user-location-halo-layer"

    /// Relief GPU (spec "hillshade-clean") : tuiles DEM Terrarium, gratuites et sans clé
    /// (AWS Open Data). Ajouté UNE fois au chargement du style (didFinishLoading), jamais
    /// reconstruit en réponse au zoom/à la position — sous le raster OSM standard uniquement
    /// (OpenTopoMap a déjà son propre ombrage intégré, l'ajouter dessous serait redondant/
    /// terne). OpenTopoMap (thème "papier") reste inchangé.
    static let hillshadeDEMTileURLTemplate = "https://s3.amazonaws.com/elevation-tiles-prod/terrarium/{z}/{x}/{y}.png"
    static let hillshadeSourceIdentifier = "hillshade-dem-source"
    static let hillshadeLayerIdentifier = "hillshade-layer"
    /// Compromis assumé (spec) : zoom max réduit sur le DEM, cohérent avec le cache hors-ligne.
    static let hillshadeMaxZoomLevel = 13
    static let hillshadeExaggerationDefault: Double = 0.4

    /// Nom du fichier de style de secours embarqué dans le bundle (GPXlibre/Resources/),
    /// utilisé si le style principal échoue à charger (JSON invalide, timeout) — l'utilisateur
    /// doit toujours voir un fond de carte, même dégradé.
    static let fallbackStyleResourceName = "fallback-style"

    /// Délai au-delà duquel, si le style n'a pas fini de charger, on bascule sur le style
    /// de secours et on affiche un bandeau d'erreur visible.
    static let styleLoadTimeoutSeconds: Double = 5

    /// Style initial : fond raster OSM (tileSize 256 — pas exposé par l'API Swift
    /// `MLNRasterTileSource(tileURLTemplates:options:)`, donc défini directement dans le
    /// JSON de style, conforme au spec Mapbox/MapLibre). La trace et le détour sont ajoutés
    /// par code une fois ce style chargé (voir RideMapLibreView) — pas de style externe hébergé.
    ///
    /// Construit via JSONSerialization (jamais par interpolation de string) : l'attribution
    /// contient du HTML avec des guillemets, et un ancien template en string interpolé
    /// produisait un JSON invalide (guillemets non échappés) qui faisait échouer tout le
    /// chargement du style, silencieusement — c'était la cause du fond noir muet.
    ///
    /// `source` détermine le fond raster (OSM standard ou OpenTopoMap pour le thème Relief) —
    /// changer de thème recharge entièrement le style (`mapView.styleJSON = ...`), voir
    /// RideMapLibreView. Les identifiants source/layer restent stables d'un thème à l'autre.
    static func buildInitialStyleJSON(source: TileSource = .osmStandard) -> String {
        let style: [String: Any] = [
            "version": 8,
            "sources": [
                rasterSourceIdentifier: [
                    "type": "raster",
                    "tiles": source.tileURLTemplates,
                    "tileSize": 256,
                    "minzoom": Int(minZoomLevel),
                    "maxzoom": source.maxZoomLevel,
                    "attribution": source.attributionHTML,
                ] as [String: Any],
            ],
            "layers": [
                [
                    "id": rasterLayerIdentifier,
                    "type": "raster",
                    "source": rasterSourceIdentifier,
                ] as [String: Any],
            ],
        ]

        guard let data = try? JSONSerialization.data(withJSONObject: style),
              let json = String(data: data, encoding: .utf8) else {
            assertionFailure("buildInitialStyleJSON: échec de sérialisation, ne devrait jamais arriver")
            return "{\"version\":8,\"sources\":{},\"layers\":[]}"
        }
        return json
    }
}
