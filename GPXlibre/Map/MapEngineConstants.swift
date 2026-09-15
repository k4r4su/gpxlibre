import Foundation
import UIKit

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
    static let navRouteCasingLayerIdentifier = "nav-route-layer-casing"

    /// Couleur de la route Nav (spec fix "nav-route-overlay") : DISTINCTE de la trace GPX
    /// (couleur choisie par l'utilisateur) et du guidage "Aller à" (cyan pointillé) — un bleu
    /// "route", plein, comme la plupart des apps de navigation. Bleu nuit profond sur fond
    /// clair (Standard/Clair/Relief), bleu plus clair sur fond sombre pour rester lisible.
    static func navRouteColor(isNightMode: Bool) -> UIColor {
        isNightMode
            ? UIColor(red: 0.40, green: 0.80, blue: 1.0, alpha: 1)
            : UIColor(red: 0.05, green: 0.16, blue: 0.55, alpha: 1)
    }
    static let goToSourceIdentifier = "goto-source"
    static let goToLayerIdentifier = "goto-layer"
    static let resumeRouteSourceIdentifier = "resume-route-source"
    static let resumeRouteLayerIdentifier = "resume-route-layer"
    static let resumeRouteCasingLayerIdentifier = "resume-route-layer-casing"
    static let resumePinSourceIdentifier = "resume-pin-source"
    static let resumePinLayerIdentifier = "resume-pin-layer"

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

    /// Chevrons de direction par trace (spec "per-track-settings") — un MLNSymbolStyleLayer
    /// unique, données mises à jour par diff (voir RideMapLibreView.updateChevronShape),
    /// jamais reconstruit par frame. `bearing`, propriété par feature, pilote la rotation
    /// (icon-rotate data-driven). Densité adaptative au zoom depuis it17 (Bloc 3, voir
    /// `DirectionChevronComputer.zoomSpacingTable`) — plus de seuil `minimumZoomLevel` fixe ici.
    static let chevronSourceIdentifier = "direction-chevron-source"
    static let chevronLayerIdentifier = "direction-chevron-layer"
    static let chevronIconName = "direction-chevron-icon"

    // MARK: - Avertissement de pente (spec "slope-warning-native", it19)

    static let slopeWarningSourceIdentifier = "slope-warning-source"
    static let slopeWarningLayerIdentifier = "slope-warning-layer"
    static let slopeWarningClimbIconName = "slope-warning-climb-icon"
    static let slopeWarningDescentIconName = "slope-warning-descent-icon"

    // MARK: - Fond vectoriel PMTiles (spec "vector-pmtiles", it11)

    /// Style embarqué en bundle (GPXlibre/Resources/) — dérivé du style "Liberty" d'OpenFreeMap
    /// (proche OSM Americana/Positron), patché pour la prominence moto/piste (voir
    /// docs/tuile-sources.md pour la liste des couches modifiées). Embarqué plutôt que
    /// re-téléchargé à chaque lancement : contrôle total, pas de dépendance à la disponibilité
    /// du endpoint de style JSON — seule la source de TUILES (`vectorSourceIdentifier` ci-
    /// dessous) reste distante (étape 1) ou locale (étape 2).
    static let vectorStyleResourceName = "vector-style-liberty"

    /// Identifiant EXACT de la source vectorielle dans le style embarqué (schéma OpenMapTiles)
    /// — c'est la clé qu'on mute pour basculer hébergé/local, jamais une reconstruction du
    /// style entier.
    static let vectorSourceIdentifier = "openmaptiles"

    /// Étape 1 — CDN vectoriel ouvert, sans clé, sans compte (voir docs/tuile-sources.md pour
    /// les alternatives documentées). `url` (TileJSON), PAS `tiles` : laisse MapLibre lire les
    /// bornes zoom réelles depuis l'en-tête plutôt que de supposer maxzoom 22 par défaut.
    static let vectorHostedTilesURL = "https://tiles.openfreemap.org/planet"
    static let vectorHostedAttributionPlainText = "© OpenFreeMap · © OpenMapTiles · © OpenStreetMap contributors"

    enum VectorStyleSource: Equatable {
        case hosted
        case local(fileURL: URL)
    }

    /// Construit le style vectoriel en repartant du JSON embarqué et en mutant UNIQUEMENT le
    /// champ `url` de la source `vectorSourceIdentifier` — jamais par interpolation de string
    /// (même discipline que `buildInitialStyleJSON`). `.local` utilise le schéma `pmtiles://`
    /// supporté nativement par MapLibre Native depuis 6.10 (confirmé dans les headers vendored
    /// de la version épinglée 6.31.0) : `pmtiles://` + l'URL `file://` du `.pmtiles` régional.
    /// En cas d'échec (ressource manquante/invalide — ne devrait jamais arriver, embarquée au
    /// build), retombe sur le raster standard plutôt que sur un écran noir muet.
    ///
    /// `flavor` (spec "map-color-flavors", it19) : palette de couleur appliquée à CHAQUE calque
    /// avant patch de rotation — ordre volontaire, les deux patches opèrent sur des clés
    /// disjointes (`paint` vs `layout`) donc totalement indépendants l'un de l'autre.
    static func buildVectorStyleJSON(source: VectorStyleSource, flavor: MapColorFlavor) -> String {
        guard let resourceURL = Bundle.main.url(forResource: vectorStyleResourceName, withExtension: "json"),
              let data = try? Data(contentsOf: resourceURL),
              var style = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              var sources = style["sources"] as? [String: Any],
              var vectorSource = sources[vectorSourceIdentifier] as? [String: Any]
        else {
            assertionFailure("buildVectorStyleJSON: \(vectorStyleResourceName).json introuvable/invalide dans le bundle")
            return buildInitialStyleJSON()
        }

        switch source {
        case .hosted:
            vectorSource["url"] = vectorHostedTilesURL
        case .local(let fileURL):
            vectorSource["url"] = "pmtiles://" + fileURL.absoluteString
        }
        sources[vectorSourceIdentifier] = vectorSource
        style["sources"] = sources

        if var layers = style["layers"] as? [[String: Any]] {
            layers = ColorFlavorPatcher.apply(flavor, toLayers: layers)
            if symbolsCapUpMode {
                layers = layers.map(patchedSymbolLayerForCapUp)
            }
            style["layers"] = layers
        }

        guard let patchedData = try? JSONSerialization.data(withJSONObject: style),
              let json = String(data: patchedData, encoding: .utf8)
        else {
            assertionFailure("buildVectorStyleJSON: échec de sérialisation, ne devrait jamais arriver")
            return buildInitialStyleJSON()
        }
        return json
    }

    /// SYMBOLS_CAP_UP_MODE (spec "rotating-symbols-cap-up", it18, Bloc 7 ; précisé it18-bis,
    /// retour propriétaire "cap au nord → OK, cap-en-haut → les textes doivent suivre") — DEUX
    /// familles de symboles, comportement voulu DISTINCT pour chacune, jamais le même réglage
    /// partout :
    /// - Placement POINT (labels de lieu/POI, villes) → `viewport` : le texte reste DROIT À
    ///   L'ÉCRAN quel que soit le cap, jamais tourné avec la caméra — sinon illisible dès qu'on
    ///   ne roule pas plein nord (bug d'origine : "nord-locked... illisible"). Comportement
    ///   standard du marché (Google/Apple/Waze en mode conduite : les noms de ville ne tournent
    ///   jamais).
    /// - Placement LINE/LINE-CENTER (noms de route/rivière, flèches de sens unique) → `map` :
    ///   le texte DOIT suivre la ligne/la carte (littéralement "les textes doivent suivre"),
    ///   donc tourner avec la caméra en cap-en-haut — comportement standard du marché pour un
    ///   nom de route (imprimé LE LONG de la route, peut apparaître de travers/inversé dans un
    ///   virage serré, c'est normal et volontaire, jamais lié à un bug).
    /// Vérifié dans les headers vendored (`MLNSymbolStyleLayer.h`) : `text`/`icon-rotation-
    /// alignment` valent `auto` par défaut quand omis, qui DEVRAIT déjà résoudre exactement ainsi
    /// (viewport pour point, map pour line) — mais plutôt que de compter sur cette résolution
    /// implicite (risque de bug de la version épinglée du SDK, non vérifiable sans device
    /// physique), les DEUX valeurs sont désormais rendues EXPLICITES pour CHAQUE calque symbol du
    /// style, sans aucune exception qui resterait sur l'implicite. `true` par défaut, appliqué au
    /// chargement du style (pas de mutation live nécessaire : correct quel que soit le mode
    /// d'orientation, y compris nord-en-haut où bearing=0 rend les deux alignements équivalents
    /// visuellement).
    static let symbolsCapUpMode = true

    /// `internal` plutôt que `private` uniquement pour la testabilité (même patron que
    /// `DetourRoutingService.route`) — jamais appelée hors `buildVectorStyleJSON` en production.
    static func patchedSymbolLayerForCapUp(_ layer: [String: Any]) -> [String: Any] {
        guard layer["type"] as? String == "symbol", var layout = layer["layout"] as? [String: Any] else { return layer }
        // Une valeur d'expression zoom-dépendante (ex. "highway-shield-*", tableau
        // ["step", ["zoom"], "point", 11, "line"]) n'est jamais un simple `"line"` fixe — traitée
        // comme point (déjà explicitement "viewport" dans le style source pour ces calques
        // précis : des badges numéro de route doivent rester lisibles à l'écran, jamais collés à
        // la ligne comme un nom de route).
        let placementString = layout["symbol-placement"] as? String
        let isLinePlacement = placementString == "line" || placementString == "line-center"
        let alignment = isLinePlacement ? "map" : "viewport"
        var patched = layer
        if layout["text-field"] != nil { layout["text-rotation-alignment"] = alignment }
        if layout["icon-image"] != nil { layout["icon-rotation-alignment"] = alignment }
        patched["layout"] = layout
        return patched
    }

    /// Point d'entrée unique de construction de style, quel que soit le fond choisi — voir
    /// `MapSourceResolver` pour la logique qui décide LEQUEL utiliser.
    static func buildStyleJSON(for mapSource: MapSourceSelection) -> String {
        switch mapSource {
        case .raster(let tileSource):
            return buildInitialStyleJSON(source: tileSource)
        case .vectorHosted(let flavor):
            return buildVectorStyleJSON(source: .hosted, flavor: flavor)
        case .vectorLocal(let fileURL, let flavor):
            return buildVectorStyleJSON(source: .local(fileURL: fileURL), flavor: flavor)
        }
    }

    /// Identifiant du calque de fond du style vectoriel embarqué (premier calque, id
    /// "background" dans le style Liberty/OpenMapTiles) — sert d'ancre pour insérer le
    /// hillshade juste au-dessus, avant tout landuse/route, même esprit que l'ancrage sur
    /// `rasterLayerIdentifier` côté raster.
    static let vectorBackgroundLayerIdentifier = "background"

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
