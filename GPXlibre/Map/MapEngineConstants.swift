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
    static func buildInitialStyleJSON() -> String {
        let style: [String: Any] = [
            "version": 8,
            "sources": [
                rasterSourceIdentifier: [
                    "type": "raster",
                    "tiles": [osmTileURLTemplate],
                    "tileSize": 256,
                    "minzoom": Int(minZoomLevel),
                    "maxzoom": Int(maxZoomLevel),
                    "attribution": osmAttributionHTML,
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
