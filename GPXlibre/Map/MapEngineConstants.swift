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

    static let userAgent = "GPXlibre/1.0 (iOS; usage app moto offroad; contact via App Store)"

    static let rasterSourceIdentifier = "osm-raster-source"
    static let rasterLayerIdentifier = "osm-raster-layer"
    static let trackSourceIdentifier = "track-source"
    static let trackLayerIdentifier = "track-layer"
    static let detourSourceIdentifier = "detour-source"
    static let detourLayerIdentifier = "detour-layer"

    /// Style initial : fond raster OSM (tileSize 256 — pas exposé par l'API Swift
    /// `MLNRasterTileSource(tileURLTemplates:options:)`, donc défini directement dans le
    /// JSON de style, conforme au spec Mapbox/MapLibre). La trace et le détour sont ajoutés
    /// par code une fois ce style chargé (voir RideMapLibreView) — pas de style externe hébergé.
    static let initialStyleJSON = """
    {
      "version": 8,
      "sources": {
        "\(rasterSourceIdentifier)": {
          "type": "raster",
          "tiles": ["\(osmTileURLTemplate)"],
          "tileSize": 256,
          "minzoom": \(Int(minZoomLevel)),
          "maxzoom": \(Int(maxZoomLevel)),
          "attribution": "\(osmAttributionHTML)"
        }
      },
      "layers": [
        {
          "id": "\(rasterLayerIdentifier)",
          "type": "raster",
          "source": "\(rasterSourceIdentifier)"
        }
      ]
    }
    """
}
