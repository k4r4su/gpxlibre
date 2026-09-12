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
  Models/         GPXPoint, GPXTrack (struct value type, reordered() pur — voir Trace sacrée)
  Services/       GPXParser (XMLParser maison), LibraryStore (source de vérité des traces,
                   voir section dédiée), LocationManager, NetworkMonitor
  Ride/           Le cœur du produit — RideView (orchestrateur SwiftUI de l'onglet Ride),
                   RideSessionManager (state machine GPS/roadbook/détour/resume, @MainActor),
                   RideOverlayLayout (grille figée des zones d'overlay, SEULE source de
                   vérité layout), RoadbookAnalyzer/TrackProjector/Checkpoint (géométrie
                   pure), DetourRoutingService (OSRM), ResumeGuidance* (feat it10),
                   RidePanelStyle (styles partagés), RideConstants (toutes les constantes
                   tunables du module Ride)
  Map/            RideMapLibreView (moteur actif, voir ci-dessous), MapProvider (protocole
                   commun), MapEngineConstants (identifiants sources/couches + couleurs)
  Nav/            Mode Nav (guidage A→B, recalcul automatique) — RideMode/RideModeStore
                   (Trace vs Nav), NavRoutingService, GoToGuidance ("Aller à" parallèle),
                   NavReportButton ("Signaler" — indépendant du POI supprimé en it10)
  Offline/        Téléchargement de tuiles par région, cache, précalcul de taille
  Waypoints/      RollingWaypoint(Store) — sert uniquement à "Signaler" (Nav) depuis it10 ;
                   le bouton "Point" (POI rapide Essence/Eau/Bivouac) a été supprimé pour de
                   vrai (chore "remove-poi"), ne pas le réintroduire à moitié
  Sync/           SharedBlockage* — base partagée anonyme des points bloqués signalés
  Recording/      Enregistrement GPS pendant le Ride + export GPX
  Settings/       RideSettingsStore (réglages globaux persistés), SettingsView
  Views/          LibraryView (Biblio), TrackDetailView, TrackSettingsView (réglages par
                   trace), TrackMapView, RootView (TabView)
  Rendering/      TraceAppearance (couleur/épaisseur, override par trace possible)
  Onboarding/     Écran d'accueil première ouverture
GPXlibreTests/    XCTest, @MainActor, @testable import GPXlibre — voir conventions plus bas
server/           Backend FastAPI+SQLite pour SharedBlockage (Docker, `docker compose up`)
```

`project.yml` (xcodegen) est la source de vérité du projet Xcode. **Après tout ajout ou
suppression de fichier Swift, lancer `xcodegen generate`** avant de builder — ne jamais
éditer `GPXlibre.xcodeproj` à la main.

## Moteur de carte

`MapEngineConstants.active` = `.mapLibre` (MapLibre Native iOS, tuiles OSM raster,
hors-ligne). `RideMapView` (MapKit) est conservé **intact pour comparaison**, conforme au
même protocole `MapProvider` — ne jamais le supprimer, mais ne pas se sentir obligé de lui
donner une parité parfaite sur les features avancées (ex : chevrons de direction non
implémentés côté MapKit, documenté comme tel). Toujours vérifier les signatures MapLibre
contre les headers vendored réels avant utilisation (jamais deviner une API) :
`~/Library/Developer/Xcode/DerivedData/.../MapLibre.framework/Headers/`.

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
   direction en haut ; colonne droite/badge vitesse en bas, au-dessus de la tab bar).
4. **Position ancrée à ~63 %** — `RideConstants.positionAnchorRatio` (0.625) depuis le haut
   de la zone libre (hors panneaux/tab bar), via un calcul EXACT sur `contentInset`
   (`RideOverlayLayout.computeMapInsets`), jamais une heuristique de décalage géographique
   côté MapLibre. Recalculé à CHAQUE apparition/disparition de panneau/bannière.
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
