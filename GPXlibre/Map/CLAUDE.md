# CLAUDE.md — GPXlibre/Map

Chargé automatiquement quand une session travaille sous `GPXlibre/Map/`. Le reste du
contexte projet (philosophie, règles absolues, conventions) reste dans le CLAUDE.md
racine — ce fichier ne documente que ce qui est spécifique à ce dossier.

## Moteur de carte

`MapEngineConstants.active` = `.mapLibre` (MapLibre Native iOS, hors-ligne). `RideMapView`
(MapKit) est conservé **intact pour comparaison**, conforme au même protocole `MapProvider`
— ne jamais le supprimer, mais ne pas se sentir obligé de lui donner une parité parfaite sur
les features avancées (chevrons, fond vectoriel : retombe sur raster OSM standard côté
MapKit, documenté comme tel). Toujours vérifier les signatures MapLibre contre les headers
vendored réels avant utilisation (jamais deviner une API) :
`~/Library/Developer/Xcode/DerivedData/.../MapLibre.framework/Headers/`.

**2D uniquement (spec "2d-only", it11)** — la vue caméra en perspective (pitch) a été
abandonnée définitivement, partout, y compris en Ride cap-en-haut : `RideConstants.
cameraPitchDegrees` a été supprimé, `pitch: 0` est câblé en dur côté MapLibre ET MapKit, et
`mapView.isPitchEnabled = false` désactive aussi le geste natif à deux doigts. Le toggle
`is2DNorthUp` (cap-en-haut ↔ nord-en-haut) reste, mais n'a plus rien à voir avec le pitch —
c'est une bascule d'orientation pure. Ne JAMAIS réintroduire un pitch non-nul, même
conditionnel.

**Fond vectoriel PMTiles (spec "vector-pmtiles", it11)** — le raster (OSM standard/
OpenTopoMap) reste le moteur historique intact, mais n'est plus la seule option :
`MapSourceSelection` (`.raster`/`.vectorHosted`/`.vectorLocal`) remplace `TileSource` comme
paramètre de `MapProvider`. `MapSourceResolver.resolve(...)` (pur, testé) décide LEQUEL
utiliser, dans cet ordre de priorité STRICT :
0. Fix "map-theme-binding" (it13) : thème Relief OU Sombre choisi → **raster forcé**
   (respectivement OpenTopoMap et OSM standard + filtre nuit) AVANT toute autre règle,
   paquet local actif inclus — ces deux thèmes n'ont pas de variante vectorielle (le style
   "Liberty" embarqué n'a qu'un rendu clair). Sans cette branche, le thème choisi n'avait
   AUCUN effet dès que le réseau était joignable (bug terrain corrigé it13).
1. Sinon, paquet vectoriel local actif (`VectorPackageStore.activeFileURL`) ET présent sur
   disque → vectoriel local, fonctionne intégralement en mode avion.
2. Sinon, réseau joignable (`NetworkMonitor.isReachable`) → vectoriel hébergé (OpenFreeMap,
   voir `docs/tuile-sources.md`).
3. Sinon → **raster existant, inchangé**. Le raster ne part JAMAIS, c'est le filet de sécurité
   mode avion sans paquet préparé.

Découverte clé (vérifiée dans les headers vendored, pas devinée) : MapLibre Native supporte
NATIVEMENT le schéma d'URL `pmtiles://` (local `pmtiles://file://...` et distant
`pmtiles://https://...`) depuis la version 6.10, bien avant la version épinglée du projet
(6.31.0) — **zéro dépendance SPM supplémentaire** n'a donc été ajoutée pour lire des
`.pmtiles`, contrairement à ce qu'un premier coup d'œil au besoin aurait suggéré. Le style
vectoriel est un JSON embarqué en bundle (`GPXlibre/Resources/vector-style-liberty.json`,
dérivé du style "Liberty" d'OpenFreeMap, patché pour la prominence moto/piste), dont on ne
mute QUE le champ `sources.openmaptiles.url` selon la source (voir
`MapEngineConstants.buildVectorStyleJSON`) — jamais tout le style, jamais par interpolation
de string. Un paquet `.pmtiles` régional pour ce style DOIT respecter le schéma OpenMapTiles
(généré via Planetiler, profil par défaut — voir `docs/generation-tuiles-regionales.md`),
sinon les noms de couches ne correspondent à rien et le fond reste vide.

Décision de scope assumée : le dimming nuit (filtre luminosité/saturation) ne s'applique
qu'au raster OSM standard — le fond vectoriel n'a qu'une variante claire pour l'instant (voir
`docs/tuile-sources.md` pour une piste future, VersaTiles fournit déjà clair+sombre).

## Symboles cap-en-haut lisibles (spec "rotating-symbols-cap-up", it18, Bloc 7)

Uniquement pertinent côté fond VECTORIEL (le raster n'a aucun label). `MapEngineConstants.
buildVectorStyleJSON` patche désormais chaque calque `symbol` à placement POINT (labels de
lieu/POI — absence de `symbol-placement` ou valeur littérale `"point"`) pour forcer
`text`/`icon-rotation-alignment` à `"viewport"` explicitement (`symbolsCapUpMode`, flag) —
robuste à un éventuel bug de résolution de la valeur implicite `"auto"` du spec sur la version
épinglée du SDK (vérifié dans les headers vendored `MLNSymbolStyleLayer.h` : `auto` DEVRAIT déjà
résoudre en `viewport` pour un placement point). Les calques à placement LINE (noms de route/
rivière, flèches de sens unique `road_one_way_arrow*`) ne sont JAMAIS touchés — ils doivent
continuer à suivre la géométrie de la ligne, comportement standard du marché. Logique pure
testable via `MapEngineConstants.patchedSymbolLayerForCapUp(_:)` (internal, voir
`SymbolCapUpAlignmentTests`) — ne pas confondre avec `chevronLayer.iconRotationAlignment = "map"`
(chevrons de direction, calque ajouté par code après le chargement du style, intentionnellement
non concerné par ce patch : il DOIT suivre la trace, pas rester upright à l'écran).

## Chevrons : densité adaptative au zoom (fix "chevrons-zoom-adaptive", it17, Bloc 3)

Bug corrigé : les chevrons disparaissaient totalement en dessous d'un zoom donné —
`chevronLayer.minimumZoomLevel` (coupure binaire sur la couche). Root cause du principe même :
le rendering distance-driven ne peut pas dépendre du zoom natif d'une couche, seulement des
FEATURES qui existent dans la source. Fix : plus de `minimumZoomLevel` sur
`direction-chevron-layer` — la densité est pilotée par `RideMapLibreView.updateChevronShape`,
qui recombine l'espacement CONFIGURÉ par trace (it11, jamais perdu) avec un palier dérivé du
zoom courant via `DirectionChevronComputer.adaptiveSpacingMeters` (le plus GRAND des deux —
jamais resserré par la table, seulement élargi). Recalculé en continu pendant un geste via le
delegate `regionIsChangingWith` (vérifié contre le header vendored MLNMapViewDelegate.h) pour
un rendu "sans saut" ; le dedup déjà existant sur l'espacement effectif limite le vrai
recalcul aux seules transitions de palier (~6 valeurs), pas à chaque frame.

