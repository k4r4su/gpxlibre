# CLAUDE.md — GPXlibre/Nav

Chargé automatiquement quand une session travaille sous `GPXlibre/Nav/`. Le reste du
contexte projet (philosophie, règles absolues, conventions) reste dans le CLAUDE.md
racine — ce fichier ne documente que ce qui est spécifique à ce dossier.

## Reconstruction du guidage classique (spec "nav-classic-rebuild", it21)

Contexte : le "Mode Nav" (guidage A→B turn-by-turn, `RideMode.nav`) existe dans le codebase
depuis it5, mais `RideModeSegmentedControl` — seul moyen de faire passer
`RideModeStore.mode` de `.trace` à `.nav` — n'est plus appelé depuis it12 (spec "hide-nav-tab").
Conséquence directe, non détectée avant it21 faute de tests sur cette zone : **tout le guidage
classique (`startNav`/`navRoute`/`NavGuidancePanelView`/`updateNavProgress`) était
COMPLÈTEMENT INERTE en usage réel** — `modeStore.mode` valant toujours `.trace`, aucune des
branches `case .nav:` (dans `RideView.hasDirectionPanel`/`activeBanner`/`directionPanelLayer`
ET dans `RideSessionManager.handle(location:)`, qui décidait d'appeler `updateNavProgress` OU
`updateRoadbookProgress` selon CE MÊME mode) ne s'exécutait jamais. Trouvé en écrivant
`NavProgressTests`/`NavAutoRecomputeTests` (it21) : les premières assertions échouaient
silencieusement (`currentManeuverIndex` ne bougeait jamais) jusqu'à remonter la cause exacte —
`updateNavProgress(from:etaSpeedKmh:)` n'était appelée QUE dans la branche `case .nav` du
switch sur `modeStore.mode`, jamais atteinte.

**Fix de fond, dans les DEUX fichiers concernés** — remplace `switch modeStore.mode` par une
condition réellement atteignable :
- `RideSessionManager.handle(location:)` : `if navDestinationCoordinate != nil { updateNavProgress(...) } else { updateRoadbookProgress/updateAutoRecompute/updateRoadbookBanner/updateRideStats(...) }`
  — les deux restent MUTUELLEMENT EXCLUSIFS (pas simplement ajoutés côte à côte) parce qu'ils
  écrivent les MÊMES propriétés partagées (`distanceRemainingMeters`/`percentComplete`/
  `estimatedArrivalDate`, lues par `RideStatsPanel` quel que soit le mode) — les faire tourner
  toutes les deux sur le même fix ferait gagner arbitrairement celle exécutée en dernier.
  `GoToGuidance` (`updateGoToGuidance`, propriétés dédiées `goToDistanceRemainingMeters`, jamais
  partagées) reste totalement indépendant de ce choix — déjà correctement "parallèle" avant
  it21, aucun changement nécessaire là.
- `RideView.hasDirectionPanel`/`.activeBanner`/`.directionPanelLayer` : vérifient désormais
  `session.navRoute != nil`/`session.isRoutingInProgress`/`session.navRoutingError`
  directement, plus `modeStore.mode == .nav`.
- `DestinationSearchTabView`/l'ancien sheet dupliqué dans `RideView` (retiré, voir plus bas) :
  le déclenchement devient `if profile == .route, session.isRichNavAvailable { startNav } else
  { startGoTo }` — remplace `if modeStore.mode == .nav, profile == .route`.

`RideModeStore`/`RideMode`/`RideModeSegmentedControl` restent INTACTS (fichier non supprimé,
toujours `.trace` par défaut, plus aucun moyen de le changer depuis l'UI — inchangé depuis
it12) : ce n'est plus le mécanisme d'activation du guidage classique, mais rien n'empêche de le
réutiliser dans une itération future si un besoin de bascule explicite Trace/Nav revient.

**Duplication supprimée** (pas orpheline, réellement retirée) : `RideView` avait un second
sheet de recherche de destination (`showDestinationSearch`, déclenché par le bouton
`.navChooseDestination`, lui-même seulement atteignable via le `modeStore.mode == .nav` mort) —
strict doublon de `DestinationSearchTabView` (spec "search-as-tab", it19) déjà déclaré comme LE
point d'entrée. Retiré entièrement (`BannerKind.navChooseDestination` + son rendu + l'état +
le sheet) plutôt qu'orphelin : le garder aurait perpétué exactement le bug ci-dessus si
quelqu'un l'avait un jour rebranché.

## Branchement Valhalla (dépendance dure, spec explicite)

Le guidage classique riche a besoin des manœuvres détaillées de Valhalla (`/route`,
`trip.legs[].maneuvers[]`) — OSRM public (`NavRoutingService`/`NavManeuver`, NavRoute.swift,
it5) n'a pas un niveau de détail équivalent (pas de verbal 3-temps, pas de nombre de sortie de
rond-point, instructions non localisées). `RideSessionManager.isRichNavAvailable` (`internal`,
lu par `DestinationSearchTabView`) vaut `currentValhallaConfiguration != nil` : si Valhalla est
désactivé ou mal configuré, le profil "Itinéraire" d'Aller à retombe simplement sur
`startGoTo` (pointillés + ETA, comportement historique) — jamais un guidage riche à moitié
construit avec des données insuffisantes.

`NavRoutingService`/`NavManeuver`/`NavRoute.maneuvers` (OSRM, it5) restent INTACTS mais
ORPHELINS (plus aucun appelant) — même patron que `TrackDetailView`/`RoadbookPanelView`
ailleurs dans l'app. `NavRoute` lui-même (coordinates/totaux/destinationLabel/computedAt) reste
la structure passée à `MapProvider` (signature contractuelle, jamais modifiée) : désormais
CONSTRUITE depuis un `ValhallaNavRoute` (`maneuvers: []`, volontairement inutilisé) — la liste
RICHE de manœuvres vit à part dans `RideSessionManager.navManeuvers: [ValhallaNavManeuver]`.

### `ValhallaManeuverType` (énumération vérifiée, pas supposée)

Valeurs 0-36 vérifiées contre `valhalla/valhalla-docs` (`turn-by-turn/api-reference.md`,
récupéré via WebFetch/WebSearch pendant cette itération, PAS deviné) — voir
`ValhallaManeuverTypeTests` pour la couverture exhaustive. Deux champs de la fiche de départ
N'EXISTENT PAS dans le schéma réel de `/route` (vérifié activement, pas supposé) :
- `bearing_before`/`bearing_after` : absents des maneuvers Valhalla (existent seulement côté
  `/trace_attributes`, un endpoint différent, non utilisé ici). L'icône est donc orientée par
  CATÉGORIE de type (léger/normal/épingle × gauche/droite/tout-droit/demi-tour/rond-point/
  ferry/arrivée), pas par un angle exact — suffisant pour les catégories demandées par la
  fiche ("tourner droite/gauche, léger/prononcé, épingle, rond-point + sortie, bifurcation,
  arrivée"), sans champ inexistant.
- `mergeLeft`/`mergeRight` n'existent pas non plus : seul `kMerge` (25) existe côté Valhalla,
  sans variante directionnelle — un seul cas `.merge` dans `ValhallaManeuverType`.

### Textes déjà en français, ne rien synthétiser

`ValhallaNavigationService.route(...)` demande `language: "fr-FR"` — `instruction`/
`verbal_transition_alert_instruction`/`verbal_pre_transition_instruction`/
`verbal_post_transition_instruction` sont déjà des phrases françaises complètes composées par
Valhalla lui-même (y compris le numéro de sortie de rond-point dans le texte). Contrairement à
l'ancien `NavManeuver.instructionText` (OSRM, it5) qui synthétisait sa propre phrase française
depuis des champs `type`/`modifier` bruts non localisés, `ValhallaNavManeuver` n'a JAMAIS besoin
de générer de texte — `NavGuidancePanelView` affiche `maneuver.instruction` directement.

Costing volontairement SANS la réduction `use_highways`/`use_tolls` appliquée au détour/à la
reprise hors-trace (`ValhallaRoutingService`/`RideConstants.valhallaAutoCosting*`, it20) : un
"Aller à" classique doit pouvoir emprunter l'autoroute si c'est la route la plus rapide, comme
n'importe quel GPS grand public — DISTINCT du cas d'usage détour/reprise, où éviter l'autoroute
a du sens pour un rider qui veut juste rejoindre sa trace.

## Guidage vocal à 3 temps (P2, déjà en grande partie existant depuis it5)

`NavVoiceAnnouncer` (AVSpeechSynthesizer, français) et le réglage on/off
(`RideSettingsStore.voiceGuidanceEnabled`/`voiceGuidanceVolume`) existaient déjà — non
réécrits. Seule la LOGIQUE de sélection du texte annoncé change
(`RideSessionManager.announceIfNeeded`) : Valhalla fournit un texte DIFFÉRENT pour l'alerte
lointaine (`verbal_transition_alert_instruction`, au seuil le plus grand de
`NavConstants.voiceAnnounceDistancesMeters`) et l'instruction proche
(`verbal_pre_transition_instruction`, seuils suivants) — remplace l'ancien comportement qui
répétait le même `instructionText` aux deux seuils (OSRM n'exposait qu'un seul texte par
manœuvre). `verbal_post_transition_instruction`, s'il existe, est annoncé une fois juste après
avoir franchi le seuil `NavConstants.maneuverPassedRadiusMeters` (voir `updateNavProgress`).

## Bannière secondaire "puis..." (P1)

`NavSecondaryBannerView` (NavGuidancePanelView.swift) — affichée par `RideView.directionPanelLayer`
UNIQUEMENT si `session.currentManeuver?.isMultiCue == true` (Valhalla `verbal_multi_cue`,
enchaînement de manœuvres trop rapproché pour laisser le temps de réagir à la première seule) ;
son contenu est `session.nextManeuver` (`RideSessionManager`, `navManeuvers[currentManeuverIndex + 1]`).

## Tracé de progression parcouru/restant (P1)

`RideSessionManager.navRouteTraveledCoordinateCount` (index de projection + 1 sur
`navRoute.coordinates`, recalculé à chaque fix dans `updateNavProgress`) — passé à
`RideMapLibreView` via `.environment(\.navRouteTraveledCoordinateCount, ...)`, MÊME contrainte
`MapProvider` (signature fixe) que le marqueur replay debug/l'avertissement de pente (it17/it19).
Rendu : DEUX `MLNPolylineFeature` (`traveled: true/false` en attribut) dans la MÊME
`navRouteSource`, filtrées chacune par un `NSPredicate` sur sa propre couche
(`navRouteColorLayer` : `traveled == NO`, restant, bleu ; `navRouteTraveledLayer`, nouvelle
couche : `traveled == YES`, gris atténué `MapEngineConstants.navRouteTraveledColor`) — choix
délibéré face à une expression `NSExpression` data-driven sur la couleur (jamais éprouvée
ailleurs dans ce fichier, contrairement à `.predicate`, déjà bien établi côté MapLibre/
`MLNVectorStyleLayer`). MapKit (`RideMapView`, comparaison) non concerné, comme les autres
features avancées (chevrons, fond vectoriel, pente) — pas d'obligation de parité.

## Recalcul automatique sans boucle infinie (test explicite de la fiche)

`RideSessionManager.updateNavProgress` réutilise le même principe que Trace
(`NavConstants.offRouteDistanceThresholdMeters`/`offRouteToleranceSeconds`, déjà existant it5),
PLUS un cooldown dédié (`NavConstants.navRecomputeCooldownSeconds`, it21) — nécessaire
spécifiquement pour le cas d'un recalcul qui ÉCHOUE : `navOffRouteSinceDate` n'est remis à zéro
QUE sur un recalcul RÉUSSI (voir `requestNavRoute`), donc sans ce cooldown, un serveur Valhalla
devenu injoignable en cours de route redéclencherait un appel réseau à CHAQUE fix suivant (`elapsed
>= offRouteToleranceSeconds` resterait vrai en continu). Voir `NavAutoRecomputeTests` — testé
avec un provider qui réussit une fois puis échoue systématiquement, exactement ce scénario.

## Retours terrain post-livraison (mêmes fixes it21, après premier test réel)

- **`search-bar-requires-pull-down`** : la barre de recherche de `NavDestinationSearchView`
  (`.searchable`) restait masquée tant qu'on ne faisait pas un petit swipe down — quirk connu de
  SwiftUI, amplifié depuis que cette vue vit comme ONGLET permanent (spec "search-as-tab", it19)
  plutôt que poussée dans une pile de navigation. Fix : `.searchable(text:placement:
  .navigationBarDrawer(displayMode: .always), prompt:)` force la barre à rester visible sans
  geste.
- **`nav-banner-too-verbose`** : retour "trop d'info, je veux juste la direction et dans combien
  de mètres, le numéro de sortie si rond-point ; le nom de rue en dessous, pas à la suite" —
  `NavGuidancePanelView` redécoupée en deux zones cloisonnées par un séparateur vertical : GAUCHE
  proéminente (icône + distance + badge sortie), DROITE en retrait, texte plus petit (instruction
  puis nom de rue sur sa PROPRE ligne, jamais accolés).
- **`nav-goto-mutual-exclusion`** (bug réel trouvé via le retour "je vois pas de diff" en testant
  le repli sans Valhalla) : `startNav`/`startGoTo` ne s'excluaient jamais mutuellement — changer
  de destination sans que Valhalla ne soit disponible pouvait démarrer `startGoTo` SANS jamais
  arrêter un `navRoute` resté actif depuis la sélection précédente, donc l'ancienne bannière
  riche restait affichée par-dessus/à la place du nouveau guidage simple censé l'avoir
  remplacée. Fix : `startNav` appelle `stopGoTo()` en tout premier, `startGoTo` appelle
  `stopNav()` en tout premier — les deux systèmes restent séparés dans leur LOGIQUE (voir plus
  haut) mais s'excluent bien mutuellement à l'ACTIVATION. Voir `NavGoToMutualExclusionTests`
  (vérifié au niveau synchrone, avant même la résolution réseau de l'un ou l'autre).

## Testabilité (providers factices, jamais de vrai réseau)

`RideSessionManager.navRoutingProvider: NavRoutingProvider` (`internal`, même patron que
`mapMatchingProvider`/it20) — remplaçable par un provider factice en test.
`RideSessionManager.navRoutingTask: Task<Void, Never>?` (`internal`, même patron que
`mapMatchingTask`) — permet à un test d'attendre `await session.navRoutingTask?.value` la fin
du calcul/recalcul sans `Task.sleep` arbitraire. Voir `NavProgressTests`/`NavAutoRecomputeTests`.

## Non vérifié visuellement (pas de device physique ni de serveur Valhalla réel ici)

Rendu réel de la bannière/l'icône/la bannière secondaire, découpage visuel parcouru/restant sur
la carte, guidage vocal entendu en conditions réelles, ergonomie du badge "Sortie N" en rond-point
— logique couverte par les tests unitaires (`ValhallaManeuverTypeTests`, `NavProgressTests`,
`NavAutoRecomputeTests`), le rendu visuel réel reste à confirmer par le pilote.
