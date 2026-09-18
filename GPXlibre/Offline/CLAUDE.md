# CLAUDE.md — GPXlibre/Offline

Chargé automatiquement quand une session travaille sous `GPXlibre/Offline/`. Le reste
du contexte projet (philosophie, règles absolues, conventions) reste dans le CLAUDE.md
racine — ce fichier ne documente que ce qui est spécifique à ce dossier.

## Compter avant d'énumérer : bbox de tuiles (fix "region-picker-huge-bbox-crash", it16)

Piège vécu (crash terrain réel, pas théorique) : `RegionPickerMapView` (MLNMapView) démarre
SANS caméra initiale — MapLibre part alors en vue "monde" (zoom ~0), et le tout premier
`visibleCoordinateBounds` rapporté peut couvrir la planète entière AVANT que l'utilisateur
n'ait pu cadrer sa vraie zone. `RegionDownloadView.updateEstimate()` énumérait directement
cette zone jusqu'au zoom max (`TileCoordinate.tiles`, deux boucles imbriquées) sur le thread
principal — pour une bbox quasi mondiale, ça représente des milliards d'éléments, thread
bloqué jusqu'à ce que le watchdog iOS tue l'app (~10 s d'absence de réponse).

Règle à appliquer PARTOUT où une bbox géographique arbitraire (pas une bbox déjà bornée par un
tracé réel, comme `CorridorPrecacheEstimator`) pilote une énumération de tuiles : calculer
D'ABORD le COMPTE en O(1) (`TileCoordinate.tileCount`, arithmétique de plage sur
topLeft/bottomRight, jamais de boucle) et comparer à un plafond dur
(`OfflineConstants.regionTileCountHardCap`) AVANT d'appeler `tiles(...)` qui matérialise la
liste réelle. Donner une caméra initiale raisonnable à une carte de sélection est un confort,
PAS une protection suffisante — un utilisateur peut toujours pincer manuellement jusqu'au zoom
monde, le garde-fou de compte reste la seule protection qui couvre tous les cas.

## Prévisualisation centrée (fix "region-picker-atlantic-ocean-default", it21)

Bug terrain : l'écran de sélection de zone s'ouvrait centré au milieu de l'océan Atlantique.
Root cause : `RegionPickerMapView.makeUIView` posait un ZOOM initial (`setZoomLevel(5, ...)`,
fix it16 ci-dessous) mais jamais de COORDONNÉE de centre — une `MLNMapView` sans centre
explicite démarre à (0,0), en plein océan au large de l'Afrique de l'Ouest. Fix :
`RegionPickerMapView.initialCenterCoordinate` (nouveau paramètre, résolu par l'appelant,
appliqué UNE SEULE FOIS dans `makeUIView` via `setCenter(_:zoomLevel:animated:)` — jamais dans
`updateUIView`, qui tournerait à chaque re-render et ferait re-sauter la carte sous
l'utilisateur en train de cadrer sa zone). `RegionDownloadView` résout cette coordonnée par
ordre de préférence : position GPS actuelle (`LocationManager.currentLocation`, même patron que
`FavoriteAddressesView`/`TrackDetailView` — instance locale, pas d'injection globale) → sinon
centre géographique de la France métropolitaine (`OfflineConstants.franceCenterCoordinate`).
"Dernière position connue" (demandée par la spec) obtenue gratuitement en seedant
`LocationManager.currentLocation` avec `manager.location` (cache SYNCHRONE de CoreLocation) dès
`init()`, plutôt qu'une persistance dédiée — si l'autorisation a déjà été accordée par une
session précédente (quasi toujours vrai, la fonctionnalité Ride en dépend), une position est
donc disponible dès l'affichage de l'écran, sans attendre le premier `didUpdateLocations`.

## Zone circulaire (spec "region-download-by-shape", it21, REMPLACE "region-download-by-place")

Retour terrain après livraison de la recherche par nom de lieu (section suivante) : "pas ultra
fan de ça, je pense qu'il faudrait juste avoir une carte, avec un cercle qu'on peut augmenter
ou diminuer et cliquer sur télécharger. Simple efficace avec toujours la taille que ça va
prendre. Possibilité de supprimer si ça prend trop de place." Décision confirmée avec le
propriétaire : REMPLACER entièrement l'écran par lieu (pas coexister) — `PlaceRegionPickerView`/
`PlaceKind`/`PlaceKindTests` supprimés (pas orphelins : un rework de picker jamais réellement
utilisé en conditions réelles, remplacé dans la foulée, contrairement au reste du code
"orphelin mais intact" de ce projet qui a eu un vrai usage passé). `GeocodingBoundingBox`/le
paramètre `featureType` de `NominatimGeocodingService` restent en place (généralement
réutilisables, indépendants de cette UI précise) — voir `GeocodingBoundingBoxTests`.

- `CircleRegionPickerMapView` (nouveau) : carte centrée par pan libre (comme
  `RegionPickerMapView`, mais rapporte `centerCoordinate` au lieu du viewport entier) — dessine
  un cercle de sélection (bleu) au centre, rayon en mètres passé par l'appelant, ET le contour
  des zones déjà téléchargées (ambré, même patron que `RegionPickerMapView`). Cercle dessiné par
  approximation équirectangulaire (36 segments, même formule que `TileCoordinate.boundingBox`)
  — PUREMENT visuel, le calcul réel des tuiles reste basé sur la vraie bounding box géographique
  (`TileCoordinate.boundingBox(around:radiusMeters:)`, inchangé depuis it17).
- `CircleRegionPickerView` : carte + slider rayon (`OfflineConstants.circleRegionRadiusRangeKm`,
  1-200 km) + slider zoom max + estimation (`OfflineTileEstimator`, partagé avec le cadrage
  manuel) + toggle Wi-Fi + bouton télécharger. "Possibilité de supprimer si ça prend trop de
  place" déjà couverte par la section "Zones téléchargées" (swipe) de `RegionDownloadView`,
  l'écran parent — rien à dupliquer ici. Body factorisé en sous-vues `@ViewBuilder` distinctes
  DÈS LE DÉPART (leçon retenue du piège Swift ci-dessous, jamais reproduit).
- Piège rencontré : `CLLocationCoordinate2D` n'est PAS `Equatable` — `.onChange(of:
  centerCoordinate)` ne compile pas pour un `CLLocationCoordinate2D?`. Résolu par un `Binding`
  personnalisé (`get`/`set`) qui appelle directement `updateEstimate()` à chaque écriture,
  plutôt qu'un wrapper Equatable dédié (comme `SimpleBounds` l'est pour les bounds) pour cette
  seule utilisation ponctuelle.

## Zone par lieu nommé + rayon (spec "region-download-by-place", it21, REMPLACÉE ci-dessus)

Section conservée pour l'historique (le code lui-même est supprimé, pas seulement orphelin —
voir section ci-dessus pour les raisons).

Alternative au cadrage manuel pan/zoom : `PlaceRegionPickerView` (sheet, ouverte depuis un
bouton dans `RegionDownloadView`) — Picker Pays/Région/Ville (`PlaceKind`), recherche via
`NominatimGeocodingService` (même service que "Aller à"/Domicile-Travail), rayon par défaut
selon le type ("Pays" → emprise réelle du pays, pas de rayon ; "Région" → +50 km ; "Ville" →
+100 km, `OfflineConstants.placeRegionDefaultRadiusKm*`), modifiable ensuite par
l'utilisateur (slider, `placeRegionRadiusRangeKm`).

- `NominatimGeocodingService.search(query:featureType:)` : nouveau paramètre optionnel
  `featureType` (`"country"`/`"state"`/`"city"`, valeur Nominatim la plus proche de chaque
  `PlaceKind` — pas de valeur "region" dédiée côté Nominatim, "state" est l'équivalent le plus
  proche d'une région administrative française), `nil` par défaut : les appelants existants
  (NavDestinationSearchView, FavoriteAddressesView) sont inchangés.
- `GeocodingResult.boundingBox` (nouveau champ optionnel, `GeocodingBoundingBox`) : décodé
  depuis le champ `boundingbox` de Nominatim (déjà présent dans toute réponse `format=json`,
  aucun paramètre supplémentaire requis) — extrait dans un initialiseur dédié
  (`GeocodingBoundingBox.init?(nominatimStrings:)`) pour rester testable sans JSON brut ni
  réseau réel. Utilisé UNIQUEMENT pour `.country` (l'emprise réelle d'un pays, forme
  irrégulière, n'a aucun sens comme rayon fixe autour d'un centroïde) ; `.region`/`.city`
  utilisent `TileCoordinate.boundingBox(around:radiusMeters:)` (existant depuis it17, corridor
  de trace), jamais testé directement jusqu'ici — couvert par `TileCoordinateTests` depuis
  cette itération.
- `OfflineTileEstimator` (nouveau, `Offline/`) : extrait le patron "compter avant d'énumérer"
  (fix "region-picker-huge-bbox-crash", it16) de `RegionDownloadView.updateEstimate()` pour être
  réutilisé tel quel par `PlaceRegionPickerView` — une bbox "Pays" peut être tout aussi grande
  qu'un pincement manuel jusqu'au zoom monde, même protection nécessaire. `RegionDownloadView`
  a été refactorée pour appeler ce même estimateur (comportement strictement inchangé, non
  duplication).
- `DownloadedRegion.Kind` INCHANGÉ : une zone par lieu est enregistrée comme `.customArea`
  (comme le cadrage manuel), distinguée seulement par son `name` (ex. "Grenoble +100 km") —
  aucun autre code ne discrimine sur le type de provenance d'une zone `.customArea`.
- Piège Swift rencontré en écrivant `PlaceRegionPickerView` : un seul `List` avec toute la
  logique conditionnelle (Picker, recherche, résultats, rayon/pays, zoom, estimation,
  téléchargement) en ligne dépasse ce que le type-checker peut résoudre en temps raisonnable
  ("unable to type-check this expression") — PAS un message d'erreur qui pointe la vraie cause
  au premier essai (le compilateur a d'abord rapporté des erreurs `Binding<...>` totalement
  fantaisistes sur un `ForEach` par ailleurs correct, avant qu'un `id: \.id` explicite ne
  révèle le vrai diagnostic). Corrigé en factorisant le corps en sous-vues distinctes
  (`@ViewBuilder private var` par section/ligne) — à garder en tête pour tout futur écran avec
  plusieurs sections conditionnelles denses dans un seul `List`.

## Contour des zones hors-ligne (spec "offline-zones-outline", it17, Bloc 1)

`DownloadedRegion.boundingBox` dérive un rectangle englobant depuis la liste de tuiles —
UNIQUEMENT celles du zoom le PLUS BAS présent (le moins nombreuses ; un corridor peut compter
des dizaines de milliers de tuiles au zoom max, inutile de toutes les parcourir pour une bbox).
C'est un repli assumé, explicitement autorisé par le prompt ("rectangle englobant si la
géométrie exacte n'est pas accessible") : le modèle ne stocke JAMAIS la bbox/le polygone
d'origine, donc même un corridor de trace (non rectangulaire en réalité) s'affiche comme une
bbox — approximation documentée, pas un bug. `RegionPickerMapView` affiche le contour de
CHAQUE zone déjà téléchargée (trait ambré + remplissage léger, `MLNPolygon` en annotation
legacy) en cadrant une nouvelle zone, diffé par signature (id+nombre de tuiles). Piège vérifié
dans le header vendored : `lineWidthForPolylineAnnotation` ne s'applique PAS à un `MLNPolygon`
(classe distincte de `MLNPolyline`) — pas de contrôle d'épaisseur de contour possible via cette
API legacy, reste au défaut du SDK.

