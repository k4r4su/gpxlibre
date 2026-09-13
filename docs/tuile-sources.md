# Sources de tuiles vectorielles — GPXlibre (it11, "vector-pmtiles")

Ce document répertorie les sources vectorielles évaluées pour l'étape 1 (validation du
style/de l'UX vectorielle avec une source hébergée, sans compte), et pourquoi **OpenFreeMap**
a été retenu. L'étape 2 (self-host PMTiles régional) est documentée séparément dans
`docs/generation-tuiles-regionales.md`.

## Choisi : OpenFreeMap

- **URL du style utilisé** : `https://tiles.openfreemap.org/styles/liberty` (récupéré une
  fois et embarqué, patché, dans `GPXlibre/Resources/vector-style-liberty.json` — voir
  ci-dessous "Pourquoi embarqué plutôt que re-téléchargé").
- **Source de tuiles réelle** (celle que l'app mute pour basculer hébergé/local) :
  `https://tiles.openfreemap.org/planet`, source `"type": "vector"` identifiée
  `openmaptiles` dans le style (schéma OpenMapTiles).
- **Aucune clé, aucun compte, aucune limite annoncée** sur l'instance publique — exactement
  le besoin de l'étape 1 ("propose une source sans clé usage-modéré permise").
- **Licence/attribution exigée** : `© OpenFreeMap · © OpenMapTiles · © OpenStreetMap
  contributors` — affichée en permanence via `OSMAttributionView` (mutée selon la source
  active, voir `MapEngineConstants.vectorHostedAttributionPlainText`).
- **Auto-hébergeable** si besoin un jour (le projet publie un script de déploiement complet
  côté serveur) — cohérent avec l'esprit "hors-ligne capable, sans dépendance à vie à un
  tiers" de l'app, même si l'étape 2 de GPXlibre passe par PMTiles régional plutôt que par un
  clone complet d'OpenFreeMap.

### Pourquoi le style est embarqué plutôt que re-téléchargé à chaque lancement

Le style JSON complet (~110 couches) est récupéré UNE fois pendant le développement, patché
(voir "Patch moto-trail" ci-dessous), puis committé dans `GPXlibre/Resources/
vector-style-liberty.json`. Au runtime, seul le champ `sources.openmaptiles.url` est modifié
(`https://tiles.openfreemap.org/planet` pour l'étape 1, `pmtiles://file://...` pour l'étape
2) — jamais tout le style. Avantages :

- Contrôle total du patch moto-trail (pas de risque qu'une mise à jour du style amont écrase
  silencieusement les couches modifiées).
- Pas de dépendance à la disponibilité du endpoint `/styles/liberty` au lancement de l'app —
  seule la disponibilité de la source de TUILES compte, avec le raster en repli si elle est
  injoignable (voir `MapSourceResolver`).
- Cohérent avec la discipline déjà en place pour le style raster
  (`MapEngineConstants.buildInitialStyleJSON`, construit par `JSONSerialization`, jamais par
  interpolation de string).

### Patch moto-trail appliqué

Le schéma OpenMapTiles ne distingue pas finement `track`/`bridleway`/`footway` au niveau
`class` (tout est `path` ou `track`/`service` combinés) — les couches suivantes ont été
rendues plus prominentes (couleur brun/orange distincte, largeur augmentée) sans changer leur
`minzoom` d'origine (on ne prétend pas que la donnée existe dans les tuiles à un zoom où elle
n'existe pas réellement) :

| Couche (id réel du style) | Classe OSM couverte | Changement |
|---|---|---|
| `road_service_track_casing` / `road_service_track` | `service`, `track` | Couleur brun `#6b4a2f` (casing) / orange `#e2a24d` (trait), largeur augmentée, tirets |
| `road_path_pedestrian` | `path`, `pedestrian` | Couleur brune `#a8703f`, tirets resserrés, largeur augmentée |

## Alternatives documentées (non retenues pour l'étape 1)

### Protomaps (clé requise)

Free tier généreux et projet solide (aussi l'auteur du format PMTiles utilisé pour l'étape 2
self-host), mais nécessite un compte + une clé API générée par le propriétaire — ne collait
pas à la contrainte explicite "sans compte" de l'étape 1. Documenté ici pour une bascule
future si besoin : générer une clé sur `protomaps.com`, remplacer
`MapEngineConstants.vectorHostedTilesURL` par l'URL fournie (avec la clé en paramètre), et
mettre à jour l'attribution en conséquence.

### VersaTiles

Projet FLOSS (générateur + tuiles + styles clair/sombre prêts à l'emploi), également
sans clé annoncée. Pas retenu pour l'étape 1 par manque de vérification directe de l'URL
publique exacte du endpoint de tuiles au moment de cette itération — à évaluer via
`versatiles.org`/leur organisation GitHub si OpenFreeMap devait un jour devenir indisponible.
Son atout principal : builds de style clair ET sombre déjà fournis, ce qui comblerait la
limite de scope actuelle de GPXlibre (le fond vectoriel n'a qu'une variante claire pour
l'instant, voir `RideMapLibreView.updateNightMode`).

## Ce qui reste vrai quel que soit le choix

- Attribution OpenStreetMap (et dérivés) toujours visible — non désactivable, voir
  `OSMAttributionView`.
- Le raster existant (OSM standard / OpenTopoMap) n'est jamais retiré : c'est le fallback
  mode avion sans paquet vectoriel préparé (voir `MapSourceResolver`).
