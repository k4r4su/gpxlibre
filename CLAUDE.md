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
  Models/         GPXPoint, GPXTrack (struct value type, reordered() pur — voir Trace sacrée ;
                   `contentDate: Date?` depuis it15, voir section horodatage Biblio ci-dessous)
  Services/       GPXParser (XMLParser maison), LibraryStore (source de vérité des traces,
                   voir section dédiée), LocationManager, NetworkMonitor
  Ride/           Le cœur du produit — RideView (orchestrateur SwiftUI de l'onglet Ride),
                   RideSessionManager (state machine GPS/roadbook/détour/resume, @MainActor),
                   RideOverlayLayout (grille figée des zones d'overlay, SEULE source de
                   vérité layout), RoadbookAnalyzer/TrackProjector/Checkpoint/RoadbookTier
                   (géométrie pure), DetourRoutingService (OSRM), ResumeGuidance* (feat it10 ;
                   `isAutomatic` depuis it18 — voir Ride/CLAUDE.md), OffTrackChipView/
                   RejoinGuidanceBannerView (it18, colonne latérale, voir Ride/CLAUDE.md),
                   RidePanelStyle (styles partagés), RideConstants (constantes Ride hors
                   roadbook), DebugReplayDriver (#if DEBUG, voir plus bas).
                   RoadbookPanelView (bandeau "hors trace" plein-largeur) ORPHELINE depuis it18
                   (spec "offtrack-compact-chip" — remplacée par OffTrackChipView, colonne
                   latérale) : fichier intact, même patron que TrackDetailView/
                   TrackThumbnailView ci-dessous.
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
                   vectorHosted(flavor:)/vectorLocal(fileURL:flavor:) depuis it19),
                   MapSourceResolver (pur, priorité de la source de carte effective — voir
                   section dédiée, it11), MapColorFlavor/ColorFlavorPatcher (it19 : palettes de
                   couleur "maison" appliquées au style vectoriel Liberty, voir section dédiée
                   Map/CLAUDE.md — remplace la demande "Flavors Protomaps", incompatible avec
                   le schéma OpenMapTiles déjà en place, voir TODO.md)
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
                   régionaux (import/téléchargement, un seul actif à la fois). Voir section
                   "Compter avant d'énumérer" (bbox de tuiles) plus bas — piège vécu, it16.
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
                   CameraPreviewMapView), MapThemePreset (it19 : standard/hauteContraste/
                   terreux/relief — "sombre" retiré, voir Map/CLAUDE.md), MapThemePickerView
                   (it18-bis : vignettes plutôt qu'un Picker texte), ControlsSide,
                   DebugReplaySection (#if DEBUG, dans Réglages > Avancé).
  Views/          LibraryView (Biblio — tap sur une ligne ouvre TrackFullSheetView depuis
                   it13, spec "biblio-track-fullsheet" : fiche nom/stats + Supprimer/
                   Renommer/Paramètres ; PLUS TrackDetailView, qui n'a donc plus de point
                   d'entrée UI mais reste intact, voir TODO.md), TrackDetailView,
                   TrackSettingsView (réglages par trace — sélecteur de départ personnalisé
                   RETIRÉ it14, spec "remove-start-choice", redondant avec le sens A→B/it12 ;
                   `TrackRideSettings.customStartPointIndex` reste dans le modèle/persistance
                   pour ne pas casser une valeur héritée, juste plus d'UI pour en DÉFINIR une
                   nouvelle), TrackFicheMapView (it17, Bloc 5 : carte unique MapLibre —
                   trace + chevrons agrandis taille fixe + repères A/B, cadrage auto sur
                   l'emprise — remplace dans TrackSettingsView le duo TrackMapView/
                   TrackThumbnailView), TrackMapView (simplifié it14 ; reste utilisé par
                   TrackDetailView UNIQUEMENT depuis it17, ne plus l'appeler depuis
                   TrackSettingsView), RootView (TabView)
  Rendering/      TraceAppearance (couleur/épaisseur, override par trace possible) ;
                   SlopeAnalyzer (it19 : détection NATIVE de pente forte le long d'une trace —
                   décision tranchée avec le propriétaire plutôt que le package tiers GPXKit,
                   voir TODO.md et Ride/CLAUDE.md — symboles ponctuels, jamais un dégradé
                   continu) ;
                   TrackThumbnailGeometry/TrackThumbnailView (it11) — miniature Canvas pure,
                   ORPHELINE depuis it17 (plus de point d'entrée UI, remplacée par
                   TrackFicheMapView dans TrackSettingsView) mais fichier intact, même patron
                   que TrackDetailView/RideModeSegmentedControl (voir TODO.md) ; algorithme
                   d'échantillonnage équitable des chevrons (`capChevrons`) généralisé en
                   coordonnées réelles dans `DirectionChevronComputer.evenlySpacedSubset`
                   (it17) plutôt que réutilisé tel quel (types différents)
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

Déplacé dans `GPXlibre/Map/CLAUDE.md` (chargé automatiquement quand une session travaille
sous ce dossier) — 2D-only, fond vectoriel PMTiles, priorité MapSourceResolver, découverte
`pmtiles://` native.

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

## Vitesse affichée, `isGuidanceStopped`, hors-trace

Déplacé dans `GPXlibre/Ride/CLAUDE.md` (chargé automatiquement quand une session travaille
sous ce dossier) — vitesse affichée vs utilisée (raw-speed-1hz), `isGuidanceStopped` vs
`isRecordingPaused` (Pause/Stop défini), seuil hors-trace à hystérésis.

## Réglages stagés, sheets translucides

Déplacé dans `GPXlibre/Settings/CLAUDE.md` (chargé automatiquement quand une session
travaille sous ce dossier) — exception "réglages stagés (non live)", fond translucide des
sheets à aperçu carte live.

## Horodatage Biblio (spec "biblio-date-display", it15, Bloc 1)

`GPXTrack.contentDate: Date?` — DISTINCT d'`importDate` (préexistant, toujours défini) :
priorité `<metadata><time>` du GPX (parsé par `GPXParser`, distinct du `<time>` par point,
attention aux deux éléments XML homonymes) > date de création du fichier `.gpx` écrit sur
disque à l'import (`LibraryStore.addTrack`) > `nil` si aucun des deux. `GPXTrack.displayDate`
fait le repli sur `importDate` si `contentDate` est `nil` ; `displayDateLabel` choisit le
préfixe ("Tracée le" si `contentDate` connue, "Importée le" sinon). `LibraryStore.sortTracks()`
trie par `displayDate` décroissante puis alpha en repli, appelé après import/renommage/
chargement — piloté par `LibraryConstants.sortKey`/`dateDisplayEnabled`
(BIBLIO_SORT_KEY/BIBLIO_DATE_DISPLAY, toggles de code, pas de réglage UI).

## Compter avant d'énumérer : bbox de tuiles

Déplacé dans `GPXlibre/Offline/CLAUDE.md` (chargé automatiquement quand une session
travaille sous ce dossier) — piège vécu du crash "region-picker-huge-bbox-crash" (it16) et
la règle à appliquer partout où une bbox arbitraire pilote une énumération de tuiles.

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

**Mettre à jour `README.md`** (demande explicite du propriétaire, it17) si une nouvelle
feature utilisateur clé a été ajoutée/changée — c'est la vitrine du dépôt sur GitHub, pas un
pense-bête interne comme CLAUDE.md : rester simple, agréable à lire, fidèle à la philosophie
propriétaire citée en tête de ce fichier. Ne pas y mettre de détail technique/implémentation.
