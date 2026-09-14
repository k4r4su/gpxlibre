# CLAUDE.md — mémoire de travail GPXlibre

Ce fichier n'est pas une doc utilisateur : c'est un pense-bête pour la prochaine session
Claude Code sur ce dépôt. Le lire en entier avant de toucher au code.

## Philosophie propriétaire (mot pour mot, ne pas dévier)

> « Le but de l'app c'est d'afficher une trace de façon simple, pouvoir la suivre, la
> reprendre plus loin si besoin. »

Toute feature qui ne sert pas cette phrase est candidate à la suppression, pas à l'ajout.
Vu en pratique à l'itération 10 : suppression nette du POI rapide ("ça ne sert à rien")
plutôt que de le garder derrière un flag. En cas de doute sur une nouvelle idée pendant une
itération, la noter dans `TODO.md` plutôt que l'implémenter hors périmètre demandé.

Spec fonctionnelle d'origine (contexte historique, partiellement dépassée depuis — Mode Nav
avec recalcul a été ajouté malgré le "hors périmètre MVP" d'origine) : `spec_app_gpx.md`.

## Architecture — où vit quoi

```
GPXlibre/
  App/            AppNavigationState (onglet actif), GPXlibreApp (racine, injecte tous
                   les @StateObject en @EnvironmentObject)
  Config/         NavigationConstants.swift (it14) — constantes du roadbook rebuilt from
                   scratch UNIQUEMENT (fenêtre, paliers d'angle, flash, debug replay), demandé
                   explicitement à cet emplacement plutôt que RideConstants.swift. Ajouté à
                   `sources:` dans project.yml — si ce dossier disparaît d'un futur `xcodegen
                   generate`, vérifier que project.yml le liste toujours.
  Models/         GPXPoint, GPXTrack (struct value type, reordered() pur — voir Trace sacrée)
  Services/       GPXParser (XMLParser maison), LibraryStore (source de vérité des traces,
                   voir section dédiée), LocationManager, NetworkMonitor
  Ride/           Le cœur du produit — RideView (orchestrateur SwiftUI de l'onglet Ride),
                   RideSessionManager (state machine GPS/roadbook/détour/resume, @MainActor),
                   RideOverlayLayout (grille figée des zones d'overlay, SEULE source de
                   vérité layout), RoadbookAnalyzer/TrackProjector/Checkpoint/RoadbookTier
                   (géométrie pure), DetourRoutingService (OSRM), ResumeGuidance* (feat it10),
                   RidePanelStyle (styles partagés), RideConstants (constantes Ride hors
                   roadbook), DebugReplayDriver (#if DEBUG, voir plus bas).
                   Roadbook REBUILT FROM SCRATCH (spec "roadbook-angle-buckets-replay", it14,
                   Bloc 4 — "aujourd'hui aucun déclenchement réel en roulage") :
                   RoadbookAnalyzer.buildRoadbookEvents REMPLACE les deux anciens détecteurs
                   séparés (buildCheckpoints seuil ponctuel ±20 m ; buildInflectionPoints
                   fenêtre glissante forward-only it12) par UN SEUL algorithme, source unique
                   pour les épingles carte (`checkpoints`) ET la bannière latérale
                   (`inflectionPoints`) — CE SONT LA MÊME LISTE depuis it14 (deux propriétés
                   @Published distinctes uniquement pour ne pas renommer le paramètre
                   `checkpoints:` déjà consommé par RideMapLibreView/RideMapView). Mesure la
                   somme des deltas de cap segment à segment sur une fenêtre AVANT/APRÈS
                   chaque point (`RideSettingsStore.roadbookWindowBeforeMeters/AfterMeters`,
                   défauts dans Config/NavigationConstants.swift), classée en 5 paliers
                   (RoadbookTier : light/marked/hard/uTurn, seuils réglables Réglages >
                   Roadbook) — icône DISTINCTE par palier, cohérente épingles/bannière. PLUS
                   D'INDEX à avancer/resynchroniser (currentCheckpointIndex et
                   resyncCheckpointIndex supprimés it14) : le flash (100 derniers mètres,
                   `NavigationConstants.roadbookFlashMeters`) et la bannière sont tous les
                   deux SANS ÉTAT, recalculés à chaque fix GPS comme "prochain événement dont
                   la distance cumulée dépasse la position actuelle" — s'auto-corrigent seuls
                   après hors-trace/reprise, aucune synchronisation à maintenir. Countdown
                   BANNER_* (RideConstants, 600→0 m) INCHANGÉ, ne pilote QUE l'affichage.
                   RoadbookPanelView ne gère toujours QUE l'alerte "hors trace" (EN HAUT,
                   pleine largeur, it12) — la bannière latérale vit maintenant DANS la colonne
                   de contrôles (voir "Colonne de contrôles" plus bas), pas dans un calque à
                   part comme avant it14.
  Map/            RideMapLibreView (moteur actif, voir ci-dessous), MapProvider (protocole
                   commun), MapEngineConstants (identifiants sources/couches + couleurs +
                   construction des styles raster ET vectoriel), MapSourceSelection (raster/
                   vectorHosted/vectorLocal), MapSourceResolver (pur, priorité de la source
                   de carte effective — voir section dédiée, it11)
                   ⚠️ SUSPICION NON RÉSOLUE (it13) : les chevrons de direction
                   (`direction-chevron-layer`, `MLNSymbolStyleLayer`+`MLNShapeSource`)
                   pourraient ne JAMAIS s'afficher visuellement sur la vraie carte Ride —
                   trouvé en vérifiant le fix "chevrons-live-refresh" par simulateur (couche
                   présente/visible, zoom largement suffisant, image enregistrée, source
                   peuplée avec succès, mais rien ne rend à l'écran sur 6 captures). Cause
                   NON identifiée (zoom/thème/mémoïsation/icône/rotation tous écartés) — voir
                   le détail complet et les pistes à creuser dans TODO.md avant de faire
                   confiance à ce mécanisme. Les checkpoints/waypoints (annotations
                   MLNPointAnnotation, mécanisme différent) ne sont PAS concernés par cette
                   suspicion.
  Nav/            Mode Nav (guidage A→B, recalcul automatique) — RideMode/RideModeStore
                   (Trace vs Nav), NavRoutingService, GoToGuidance ("Aller à" parallèle —
                   `.offroad` route réellement en hors-route depuis it13, spec "offroad-
                   routing-preference", via DetourRoutingService.route(profile: .offroad)
                   réutilisé, PLUS une ligne droite ; `.mixed` termine aussi en hors-route
                   routé plutôt qu'à vol d'oiseau), NavFavoritesStore (Domicile/Travail,
                   configurables depuis it13 via Settings/FavoriteAddressesView),
                   NavReportButton ("Signaler" — indépendant du POI supprimé en it10).
                   RideModeSegmentedControl n'est plus appelé depuis it12 (spec
                   "hide-nav-tab", Trace seul visible/actif) — fichier intact, tout le code
                   Nav reste en place tel quel, ne PAS le supprimer : sera relancé dans une
                   itération future, après la trace door-to-door.
  Offline/        Téléchargement de tuiles raster par région, cache, précalcul de taille ;
                   VectorPackageStore/VectorPackagesView (it11) — paquets `.pmtiles`
                   régionaux (import/téléchargement, un seul actif à la fois)
  Waypoints/      RollingWaypoint(Store) — sert uniquement à "Signaler" (Nav) depuis it10 ;
                   le bouton "Point" (POI rapide Essence/Eau/Bivouac) a été supprimé pour de
                   vrai (chore "remove-poi"), ne pas le réintroduire à moitié
  Sync/           SharedBlockage* — base partagée anonyme des points bloqués signalés
  Recording/      Enregistrement GPS pendant le Ride + export GPX
  Settings/       RideSettingsStore (réglages globaux persistés — SAUF exception explicite,
                   voir "Réglages stagés" plus bas), SettingsView, FavoriteAddressesView
                   (Domicile/Travail, it13), NavigationSettingsView (it14 : Réglages >
                   Navigation, regroupe Position point bleu/Zoom par défaut/Zoom automatique
                   — les 3 réglages qui ont besoin d'un aperçu carte en direct,
                   CameraPreviewMapView), ControlsSide, DebugReplaySection (#if DEBUG, dans
                   Réglages > Avancé).
  Views/          LibraryView (Biblio — tap sur une ligne ouvre TrackFullSheetView depuis
                   it13, spec "biblio-track-fullsheet" : fiche nom/stats + Supprimer/
                   Renommer/Paramètres ; PLUS TrackDetailView, qui n'a donc plus de point
                   d'entrée UI mais reste intact, voir TODO.md), TrackDetailView,
                   TrackSettingsView (réglages par trace — sélecteur de départ personnalisé
                   RETIRÉ it14, spec "remove-start-choice", redondant avec le sens A→B/it12 ;
                   `TrackRideSettings.customStartPointIndex` reste dans le modèle/persistance
                   pour ne pas casser une valeur héritée, juste plus d'UI pour en DÉFINIR une
                   nouvelle), TrackMapView (simplifié it14, plus de tap-to-pick, juste un
                   aperçu), RootView (TabView)
  Rendering/      TraceAppearance (couleur/épaisseur, override par trace possible) ;
                   TrackThumbnailGeometry/TrackThumbnailView (it11) — miniature Canvas pure
                   de la trace avec chevrons + pastille de sens, aucune carte interactive.
                   Gotcha (fix "biblio-direction-live-refresh", it12) : un `Canvas` dans une
                   `Form`/`List` peut rester visuellement figé après un changement de state
                   tant qu'aucun scroll/layout ne force le redessin de la cellule hôte — voir
                   `.id(...)` sur TrackThumbnailView dans TrackSettingsView, contournement
                   standard, pas une correction de la logique d'état (qui était déjà correcte)
  Onboarding/     Écran d'accueil première ouverture
GPXlibreTests/    XCTest, @MainActor, @testable import GPXlibre — voir conventions plus bas
server/           Backend FastAPI+SQLite pour SharedBlockage (Docker, `docker compose up`)
docs/             Docs livrables pour le propriétaire (pas du pense-bête interne) :
                   tuile-sources.md (sources vectorielles évaluées), generation-tuiles-
                   regionales.md (manuel Planetiler/osmium à exécuter sur le NAS)
```

`project.yml` (xcodegen) est la source de vérité du projet Xcode. **Après tout ajout ou
suppression de fichier Swift, lancer `xcodegen generate`** avant de builder — ne jamais
éditer `GPXlibre.xcodeproj` à la main.

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

## Source de vérité des états (fix "single-source-active-track", it10)

`LibraryStore` (Services/) est la SEULE source de vérité pour quelle trace est chargée :

- `activeTrackID: UUID?` (persisté UserDefaults `library.activeTrackID`) — la trace qui
  alimente `RideSessionManager`. Une seule à la fois.
- `displayedTrackIDs: Set<UUID>` (persisté UserDefaults, JSON) — bookkeeping pur ; une trace
  importée pendant qu'une autre est active reste "affichée" sans voler l'état actif.
- **Invariant fort, appliqué dans TOUTES les mutations (jamais dans les vues) : active ⟹
  affichée.** `setActive(id)`/`setDisplayed(id:_:)` sont les SEULS points d'écriture.
- Le rendu (RideMapLibreView/RideMapView) ne reçoit toujours qu'UNE trace (`activeTrack`) —
  pas de rendu multi-trace, décision de scope assumée (voir philosophie ci-dessus).
- `RideSessionManager.stop()` purge explicitement (checkpoints, index, track, détour,
  resume) — ne jamais compter sur un futur `start()` pour nettoyer un état fantôme.
- Ne JAMAIS réintroduire un `selectedTrackID` parallèle dans une vue ou un autre store.

Même patron appliqué à `VectorPackageStore` (Offline/, it11) : `activePackageID: UUID?`, un
seul paquet vectoriel actif à la fois, `setActive(_:)` seul point d'écriture — pas de fusion
multi-région, pas d'état parallèle dans `VectorPackagesView`.

## Vitesse affichée vs vitesse utilisée (spec "raw-speed-1hz", it12)

`RideSessionManager` expose DEUX valeurs de vitesse, jamais interchangeables :
`smoothedSpeedKmh` (moyenne glissante `speedSmoothingWindowSeconds`, 10 s) reste la SEULE
source pour tout ce qui doit rester stable — zoom auto (`updateZoomBucket`), contexte route
rapide/piste (`updateRideContext`), dépassement de limite de vitesse (`isOverSpeedLimit`).
`rawSpeedKmh` (`location.speed` brut, throttlé à 1 Hz au moment du PUBLISHED uniquement — le
GPS continue d'être consommé à la cadence normale) alimente UNIQUEMENT le speedo
(RideStatsBadge/RideStatsPanel). Demande terrain explicite pour le speedo seul ("m'enfou que
ça oscille") : ne jamais brancher `rawSpeedKmh` sur une décision automatique.

## `isGuidanceStopped` vs `isRecordingPaused` (spec "stop-guidance-semantics", it14)

DEUX états distincts sur `RideSessionManager`, ne jamais les confondre :
`isRecordingPaused` (préexistant) suspend l'ENREGISTREMENT de la session (le tracé parcouru
n'avance plus), typiquement via le bouton pause de l'écran d'enregistrement libre.
`isGuidanceStopped` (nouveau, bouton Stop de la colonne de contrôles) arrête uniquement le
GUIDAGE actif : la trace chargée reste affichée, le roadbook/bannières latérales se rétractent
(`hasDirectionPanel`/`isLateralBannerVisible` passent à `false` tant que `isGuidanceStopped`),
la vitesse continue d'être affichée, on reste sur l'écran Ride — la session de suivi/
enregistrement, elle, N'EST PAS arrêtée. Haptic + toast "Guidage arrêté" au moment du Stop
(`.rideToast`). Reprise : soit un tap sur une nouvelle trace, soit le bouton recentrer/cibler
(`recenterCamera()`), soit le nouveau bouton discret "play" de la colonne
(`resumeGuidanceAfterStop()`) si une trace reste sélectionnée — dans les trois cas
`isGuidanceStopped` repasse à `false` et le roadbook/bannière réapparaissent naturellement
(aucun état d'index à resynchroniser, voir section roadbook ci-dessus).

## Seuil hors-trace à hystérésis (spec "offtrace-threshold-hysteresis", it14, Bloc 8)

Bug terrain observé par photo (bannière "Hors trace – Reprise à 16,3 km" restée affichée alors
que le trajet était proche de la trace) : un seuil unique oscillait autour de sa valeur.
Remplacé par un DOUBLE seuil avec hystérésis, porté par `RideConstants.horsTraceEnterMeters`
(30 m — au-delà, `isOffTrackPaused` passe à `true`) et `RideConstants.horsTraceExitMeters`
(25 m — en-deçà, repasse à `false`) ; les anciennes constantes `resyncHysteresisSeconds`/
`resyncMinConsecutiveStableFixes` ont été retirées, ce mécanisme de resync par temps/fixes
consécutifs n'existe plus, remplacé par cette comparaison directe de distance dans
`updateRoadbookProgress`. Comme avant, cet état reste NON bloquant : la trace reste visible,
rien d'autre ne change. Se valide via le mode replay debug (voir section roadbook ci-dessus),
pas besoin de sortir en voiture pour reproduire un franchissement de seuil.

## Réglages stagés (non live) — exception documentée

Convention par défaut de l'app : tout réglage s'applique EN DIRECT dès qu'on le touche, jamais
besoin de bouton Sauvegarder. Deux réglages dérogent explicitement à cette règle depuis it14,
parce que le prompt d'itération le demandait noir sur blanc (Bloc 6 : "Sauvegarder = applique"
; Bloc 7 : "non persistant tant que non validé") : Réglages > Navigation > **Zoom par défaut**
(`DefaultRideZoomSettingsView`, bouton "Sauvegarder") et **Zoom automatique**
(`AutoZoomSettingsView`, bouton "Valider"). Dans les deux cas, un `@State` local pilote
l'aperçu carte pendant l'ajustement (`CameraPreviewMapView`) et seul le tap sur le bouton
écrit dans `RideSettingsStore` (`settings.defaultRideZoomCameraMeters`/`settings.autoZoomEnabled`
etc.). Ne pas généraliser ce patron à un nouveau réglage sans qu'une spec future le demande
explicitement — c'est une exception, pas le nouveau défaut.

## Règles absolues (non négociables, violées = régression critique)

1. **Trace sacrée** — en Mode Trace, la trace GPX chargée n'est JAMAIS recalculée ni
   modifiée. `GPXTrack.reordered(using:)` retourne une NOUVELLE valeur, ne touche jamais le
   fichier source. Tout guidage parallèle (détour, "Aller à", "Reprendre ici") se dessine
   À CÔTÉ, jamais en remplacement, et reste annulable sans laisser de trace.
2. **Caméra stable aux bascules** — changer de mode (Trace↔Nav), revenir d'un autre onglet,
   ou changer d'écran (Biblio→Ride) ne doit JAMAIS provoquer de saut de zoom/recentrage
   implicite. Utiliser `switchMode(track:)` (préserve tout l'état caméra/vitesse/stats),
   jamais `start(track:)` (reset complet, réservé aux vrais démarrages) pour ces cas.
3. **Zone tab bar sacrée** — rien d'autre que la tab bar native n'entre jamais dans cette
   zone. Voir `RideOverlayLayout` pour la grille complète (segmented → bannière → panneau de
   direction en haut ; colonne contrôles + badge vitesse en bas, au-dessus de la tab bar).
   Depuis it14 (spec "controls-side-setting"), la colonne de contrôles (+/-/Stop/Bloqué + la
   bannière latérale du roadbook, empilée au-dessus) est à DROITE ou à GAUCHE selon
   `settings.controlsSide` (Réglages > Apparence > Position contrôles, live) — mais reste,
   dans les deux cas, la SEULE chose à occuper cette zone verticale ; à gauche, elle doit
   toujours éviter le compteur km/h (à droite, inchangé).
4. **Position ancrée à ~63 % par défaut, overridable en mode suivi** —
   `RideConstants.rideAnchorYFractionDefault` (0.625) reste la valeur par défaut, mais depuis
   it14 (spec "ride-anchor-lowered-setting") l'ancre réelle utilisée en mode suivi cap-en-haut
   est `settings.rideAnchorYFraction` (réglable via Réglages > Navigation > Position point
   bleu, live, plage `RideConstants.rideAnchorYFractionRange`) — PAS la constante brute. Le
   calcul EXACT sur `contentInset` (`RideOverlayLayout.computeMapInsets`) reste inchangé,
   seule l'entrée qu'on lui passe est désormais dynamique ; nord-en-haut n'est pas concerné
   (reste centré, sans notion d'ancre). Recalculé à CHAQUE apparition/disparition de
   panneau/bannière ET à chaque changement du réglage.
5. **Zéro overlap d'overlays** — un overlay qui apparaît (bannière, panneau, carte "Reprendre
   ici") ne doit JAMAIS déplacer un contrôle existant. Tout nouvel overlay custom : calque
   isolé, position fixe, jamais un sibling dans une VStack qui grandit avec son contenu (voir
   la règle documentée en tête de `RideOverlayLayout.swift`, fix "overlay-never-pushes").
   Préférer réutiliser le mécanisme de bannière déjà isolé plutôt qu'inventer une zone.

## Conventions de commit

- Un commit par bug/feature/bloc logique, tag exact demandé dans le prompt d'itération en
  préfixe du message : `fix:"nom-du-fix"`, `feat:"nom-feature"`, `chore:"nom"`,
  `style:"nom"`, `docs:"nom"`. Le tag fait partie du sujet du commit, pas juste du corps.
- Message détaillé : quoi, pourquoi (symptôme terrain / spec), comment (fichiers clés,
  patron réutilisé), et honnêteté explicite sur les décisions de scope ou les limites
  (root cause non isolée, test non fiable dans cet environnement, etc.) — jamais caché.
- **Push sur `origin main` après CHAQUE commit**, pas seulement en fin de session/itération
  (consigne permanente du propriétaire).
- Toujours terminer par les lignes d'attribution `Co-Authored-By`/`Claude-Session` fournies
  par le système au moment du commit (elles changent d'une session à l'autre).
- Ne jamais utiliser `git commit --amend` ni de destructif sans demande explicite.

## Device de référence et validation

- **iPhone 13 Pro, portrait** — device de référence pour toutes les captures de validation.
- Simulateur utilisé cette session : UDID `EB5320F4-608F-45C1-83E0-114274683620` (vérifier
  qu'il existe toujours via `xcrun simctl list devices` ; en créer un nouveau sinon).
- Avant le premier lancement d'une session de test : `xcrun simctl privacy <udid> grant all
  <bundle-id>` (permissions loc) — sinon `xcrun simctl location set` est silencieusement
  ignoré. Parfois `simctl location set` doit être appelé deux fois (coordonnées différentes)
  pour forcer un vrai `didUpdateLocations`. `simctl location start --speed=N` avec plusieurs
  points est plus fiable pour simuler un trajet continu.
- Pas d'automatisation tactile (AppleScript/Accessibility) disponible dans cet environnement
  — impossible de taper à travers l'UI. Vérification honnête : soit forcer un état via une
  modification de code TEMPORAIRE (annulée juste après, jamais commitée), soit documenter la
  limite plutôt que prétendre avoir vérifié visuellement quelque chose qui ne l'a pas été.
- Build : `xcodebuild -project GPXlibre.xcodeproj -scheme GPXlibre -destination
  'platform=iOS Simulator,id=<udid>' build` (simulateur) et `-destination
  'generic/platform=iOS' build CODE_SIGNING_ALLOWED=NO` (device, compile-only). Les deux
  doivent être verts avant tout commit.
- Tests : `xcodebuild test -project GPXlibre.xcodeproj -scheme GPXlibre -destination
  'platform=iOS Simulator,id=<udid>'`. `GPXlibreTests/` — XCTest, `@MainActor`,
  `@testable import GPXlibre`. Stores testés avec des seams d'injection (`tracksDirectoryOverride`,
  `defaults: UserDefaults`) pour ne JAMAIS toucher les vraies données de l'app pendant un
  test — toujours vérifier qu'un nouveau test ne lit/écrit pas `Documents/` ou
  `UserDefaults.standard` réels sans isolation.

## À la fin de chaque itération

**Relire ce fichier et le mettre à jour** si l'architecture, les règles absolues, ou les
conventions ont changé — nouveau dossier, nouvelle règle absolue introduite par le
propriétaire, nouveau device/UDID de référence, nouveau pattern de test, etc. Ce fichier
doit toujours refléter l'état RÉEL du dépôt, jamais un instantané figé d'une itération
passée. Un fichier CLAUDE.md obsolète est pire qu'utile : il fait perdre du temps à la
prochaine session à démêler ce qui a changé.
