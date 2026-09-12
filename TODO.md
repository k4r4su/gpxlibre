# TODO

## Itération 9 (stabilisation UI) — idées annexes notées, non traitées

Consigne explicite de cette itération : "aucune nouvelle feature, si tenté d'améliorer
autre chose, note-le ici à la place." Voici ce qui a été repéré en marge des 6 bugs
demandés, volontairement laissé de côté :

- **Chrome secondaire sous 56pt** : icône recherche (40×40), bascule 2D/3D (40×40),
  sous-boutons de catégorie du panneau POI (48×48) sont plus petits que les boutons
  critiques (≥56pt, déjà conformes). Le Bug 6 ne visait que les boutons critiques
  ("gants") — uniformiser aussi ce chrome secondaire à 56pt serait un choix de design
  à valider (risque de surcharger l'écran), pas un bug d'affichage.
- **Bug 1 (nav-route-overlay), cause racine non isolée avec certitude** : l'ancien
  rendu suivait déjà le patron du détour (fonctionnel), sans defect structurel trouvé.
  Si le symptôme "route invisible" réapparaît malgré la reconstruction de ce commit, il
  faudrait instrumenter `NavigationCoordinator`/`updateNavRouteShape` avec un compteur
  de features pour confirmer que `source.shape` reçoit bien une géométrie non vide au
  moment du symptôme (piste de debug, pas un fix).
- **Validation paysage non faite cette itération** : toutes les captures de vérification
  (grille, ancrage position) ont été prises en portrait uniquement — pas d'automatisation
  de rotation disponible dans cet environnement. `RideOverlayLayout.landscapeSidePanelWidth`
  existe déjà mais n'a pas été revérifiée visuellement pour cette itération.
- **Overlay POI/paramètres "centré" (validation Bug 5)** : n'a pas pu être capturé en
  simulateur faute d'automatisation tactile pour ouvrir la feuille de recherche/réglages ;
  vérifié uniquement par lecture de code (alignements relatifs, pas d'offset absolu).

## Thème Relief : Option A retenue (raster OpenTopoMap), Option B non tentée

**Choix assumé** : Option A (tuiles raster OpenTopoMap toutes prêtes) est implémentée et
active. Option B (hillshade MapLibre via une source DEM comme les AWS Terrain Tiles /
`elevation-tiles.openstreetmap.fr`) n'a pas été tentée dans cette session.

### Pourquoi Option A plutôt que B

- Option A fonctionne immédiatement avec l'infrastructure déjà en place (même mécanisme
  d'interception/cache que les tuiles OSM standard, juste une deuxième `TileSource`) —
  fiable, zéro nouvelle dépendance, ToS claire (attribution obligatoire, déjà affichée).
- Option B (hillshade sur un fond OSM standard) est visuellement supérieure en théorie
  (relief vectoriel superposable à n'importe quel style) mais demande une source DEM dont
  la fiabilité/gratuité à long terme n'a pas pu être vérifiée dans cette session (la spec
  elle-même anticipait ce risque : "si la source DEM pose un souci de fiabilité/clé →
  fallback Option A"). Plutôt que de livrer un hillshade non testé, l'agent a choisi
  directement le fallback documenté.

### Compromis honnête

- Relief en raster = image pré-rendue : pas de recolorisation possible (contrairement à un
  hillshade vectoriel qui s'adapterait à un thème sombre par exemple). Le thème Relief
  ignore volontairement le mode nuit (`isNightModeActive` retourne `false` pour `.relief`
  dans `RideView`/`TrackDetailView`) plutôt que d'assombrir artificiellement une image qui
  n'a pas été conçue pour ça.
- Zoom plafonné à 17 (`TileSource.openTopoMap.maxZoomLevel`) — OpenTopoMap ne sert pas de
  tuiles au-delà, contrairement à OSM standard (19).
- MapKit (comparaison, non actif) simule Relief via un simple `MKTileOverlay` sur un seul
  sous-domaine (`a.tile.opentopomap.org`) — pas de cache disque partagé avec MapLibre côté
  MapKit, ce chemin n'est pas celui testé/documenté pour l'usage hors-ligne réel.

### Pour tenter Option B plus tard

1. Source DEM candidate : `https://elevation-tiles-prod.s3.amazonaws.com/terrarium/{z}/{x}/{y}.png`
   (AWS Terrain Tiles, terrarium encoding) — vérifier d'abord la disponibilité/CORS/ToS
   actuelles (aucune garantie de pérennité, projet tiers).
2. Ajouter un cas `TileSource` dédié (ex. `.hillshadeDEM`) + une couche
   `MLNHillshadeStyleLayer` (existe côté MapLibre) par-dessus le raster OSM standard, avec
   `hillshadeExaggeration`/`hillshadeShadowColor` réglables.
3. Garder le fallback Option A automatique si le premier fetch DEM échoue (timeout court,
   ne jamais bloquer l'affichage de la carte).

## Bloc 4 — Trafic (TomTom) : sauté proprement, activation documentée

**Statut** : non activé. Bloqué par une clé API TomTom que l'agent ne peut pas provisionner
(inscription développeur requise, humaine). Toute l'infrastructure autour (réglage Trafic
on/off #11, point d'accroche `TrafficService`) est en place et prête.

### Pourquoi ce n'est pas fait

TomTom Traffic API (free tier) nécessite un compte développeur + une clé API générée sur
[developer.tomtom.com](https://developer.tomtom.com). C'est une étape humaine (inscription,
acceptation des conditions) que je ne peux pas faire à ta place.

### Comment l'activer

1. Créer un compte gratuit sur https://developer.tomtom.com/user/register
2. Créer une clé API ("API Keys" → "Add new key")
3. Ouvrir `GPXlibre/Nav/TrafficService.swift`, renseigner `apiKey` :
   ```swift
   static let apiKey = "TA_CLE_TOMTOM"
   ```
4. Implémenter l'appel réel dans `trafficSummary(for:networkMonitor:)` — endpoint
   [Traffic Flow Segment Data](https://developer.tomtom.com/traffic-api/documentation/traffic-flow/flow-segment-data)
   (`GET /traffic/services/4/flowSegmentData/absolute/10/json?key=...&point={lat},{lon}`)
   sur quelques points le long de `route.coordinates`, agréger `currentSpeed` vs
   `freeFlowSpeed` pour estimer un retard en minutes.
5. Overlay carte : styler la portion de route concernée en une couleur distincte
   (vert/orange/rouge selon le ratio vitesse actuelle/vitesse fluide) — MapLibre : découper
   la géométrie de route Nav en segments avec `NSExpression` conditionnelle sur `lineColor` ;
   MapKit : plusieurs `MKPolyline` (un par tronçon coloré).
6. UI : afficher `TrafficSummary.extraDelayMinutes` dans `NavGuidancePanelView`
   ("+12 min trafic"), silencieux si `nil` — c'est déjà le comportement du service.
7. Hors ligne : la fonction retourne déjà `nil` si `networkMonitor.isReachable == false` —
   comportement "section grisée honnête" déjà respecté, rien à changer.
8. Pas de reroutage automatique lié au trafic (demandé explicitement en v1) — ne pas
   brancher `trafficSummary` sur `RideSessionManager.requestNavRoute()`.

### Repli si quota/clé pose problème plus tard

Le free tier TomTom a un quota mensuel de requêtes. Si dépassé : le service échoue
silencieusement (à coder de la même façon que l'absence de clé — `catch { return nil }`),
jamais d'erreur visible pour une fonctionnalité annexe.
