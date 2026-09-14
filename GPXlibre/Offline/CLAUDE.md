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

