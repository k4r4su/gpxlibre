# CLAUDE.md — GPXlibre/Ride

Chargé automatiquement quand une session travaille sous `GPXlibre/Ride/`. Le reste du
contexte projet (philosophie, règles absolues, conventions) reste dans le CLAUDE.md
racine — ce fichier ne documente que ce qui est spécifique à ce dossier.

## Vitesse affichée vs vitesse utilisée (spec "raw-speed-1hz", it12)

`RideSessionManager` expose DEUX valeurs de vitesse, jamais interchangeables :
`smoothedSpeedKmh` (moyenne glissante `speedSmoothingWindowSeconds`, 10 s) reste la SEULE
source pour tout ce qui doit rester stable — zoom auto (`updateZoomBucket`), contexte route
rapide/piste (`updateRideContext`), dépassement de limite de vitesse (`isOverSpeedLimit`).
`rawSpeedKmh` (`location.speed` brut, throttlé à 1 Hz au moment du PUBLISHED uniquement — le
GPS continue d'être consommé à la cadence normale) alimente UNIQUEMENT le speedo
(RideStatsBadge/RideStatsPanel). Demande terrain explicite pour le speedo seul ("m'enfou que
ça oscille") : ne jamais brancher `rawSpeedKmh` sur une décision automatique.

## `isGuidanceStopped` vs `isRecordingPaused` (spec "stop-guidance-semantics", it14 ; bouton
## toggle Pause/Play, "guidance-toggle-stop-pause-play", it15, Bloc 3)

DEUX états distincts sur `RideSessionManager`, ne jamais les confondre :
`isRecordingPaused` (préexistant) suspend l'ENREGISTREMENT de la session (le tracé parcouru
n'avance plus), typiquement via le bouton pause de l'écran d'enregistrement libre.
`isGuidanceStopped` (bouton toggle de la colonne de contrôles) arrête uniquement le GUIDAGE
actif : la trace chargée reste affichée, le roadbook/bannières latérales se rétractent
(`hasDirectionPanel`/`isLateralBannerVisible` passent à `false` tant que `isGuidanceStopped`),
la vitesse continue d'être affichée, on reste sur l'écran Ride — la session de suivi/
enregistrement, elle, N'EST PAS arrêtée.

Deux façons d'atteindre CE MÊME état depuis it15, mutation factorisée dans
`haltActiveGuidance()` (stopNav/stopGoTo/cancelDetour/`isGuidanceStopped = true`), seule la
présentation diffère :
- **Pause** (`pauseGuidance()`, tap court sur `RideGuidanceToggleButton`) : haptique LÉGÈRE
  (`UIImpactFeedbackGenerator .light`), PAS de toast — une pause de routine.
- **Stop défini** (`stopGuidance()`, item destructif du menu contextuel du même bouton, appui
  long) : haptique FORTE (`UINotificationFeedbackGenerator`), toast "Guidage arrêté"
  (`.rideToast`, déclenché côté RideView, pas dans le manager).

Pourquoi un menu contextuel plutôt qu'un second geste sur le bouton : l'appui long est déjà,
dans toute l'app, la convention de `longPressTooltip` (infobulle explicative + haptique légère)
sur tout bouton à icône SEULE — réutiliser ce même geste pour déclencher un arrêt aurait cassé
ce réflexe partout ailleurs. `RideGuidanceToggleButton` garde un label texte permanent
(Pause/Reprendre), il n'a donc jamais fait partie de cette convention, d'où l'absence de
conflit à y poser un `.contextMenu`. Décision tranchée avec le propriétaire avant codage
(prompt it15 la laissait explicitement ouverte).

Reprise (`resumeGuidanceAfterStop()`, identique dans les deux cas) : tap sur le bouton toggle
quand il affiche Play, tap sur une nouvelle trace, ou recentrage (`recenterCamera()`) —
`isGuidanceStopped` repasse à `false` et le roadbook/bannière réapparaissent naturellement
(aucun état d'index à resynchroniser, voir section roadbook ci-dessus).

`RideConstants.guidanceButtonMode` (`GUIDANCE_BUTTON_MODE`, défaut `.toggle`) : l'ancien
comportement it14 à 2 boutons empilés (Stop + icône Play séparée, avec
`confirmationDialog`) est conservé intact derrière `.twoButtons` — filet de secours si le
bouton unique s'avère mal compris sur le terrain, pas du code mort à supprimer sans y penser.

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

## Guidage de reprise manuel vs automatique (spec "link-recompute-on-divergence" /
## "rejoin-trace-guidance-banner", it18, Blocs 3/5)

`ResumeGuidance.isAutomatic` distingue DEUX origines du même mécanisme "Reprendre la trace ici"
(feat it10, `RideSessionManager.requestResume`/`ResumeGuidance`), jamais deux moteurs séparés :

- **Manuel** (`isAutomatic = false`, défaut) : tap sur la trace (`RideView.handleTrackTap`).
  Démarre en phase `.previewing` (vol d'oiseau visible, itinéraire en cours), confirmation
  explicite requise (`confirmResume()`) — bannière DU HAUT (`ResumeGuidanceCardView`), inchangée
  depuis it10.
- **Automatique** (`isAutomatic = true`) : `RideSessionManager.updateAutoRecompute`, appelé à
  CHAQUE fix en Mode Trace, déclenche `requestResume(..., isAutomatic: true)` dès que la
  divergence à la trace dépasse `RideConstants.recomputeDivergenceThresholdMeters` (100 m) en
  continu pendant `recomputeDivergenceDurationSeconds` (2 s) — cible (spec "rejoin-nearest-by-
  air", it19, remplace l'ancien "point suivant + `detourAheadMinMeters`") :
  `TrackProjector.nearestPointByAirDistance`, le point de la trace le plus proche à VOL D'OISEAU
  parmi TOUS ses points, pas seulement le suivant dans l'ordre chronologique — bug terrain
  corrigé où une trace en boucle faisait cibler un point à 15 km par la route alors qu'un autre
  point, plus loin dans l'ordre de la trace, n'était qu'à 2 km à vol d'oiseau.
  `updateOffTrackResumeTarget` (affichage informatif du chip hors-trace, voir plus bas) utilise
  la MÊME fonction, pour rester cohérent avec la cible réellement routée. Démarre DIRECTEMENT en
  phase `.active`. Réévalué PÉRIODIQUEMENT tant qu'actif ET hors-trace (spec "auto-recompute-
  periodic-reevaluation", it19, retour terrain "la logique est trop random") :
  `RideConstants.autoRecomputeReevaluationIntervalSeconds` (60 s) — sans ça, la cible restait
  figée à la position du rider au moment du déclenchement, jamais réajustée s'il continuait à
  s'éloigner ou se rapprochait d'un autre point de la trace entre-temps. Re-routage déclenché
  seulement si le nouveau point le plus proche diffère de l'ancien de plus de
  `autoRecomputeRetargetMinDistanceMeters` (10 m) — évite un aller-retour réseau (OSRM/Valhalla)
  inutile quand la cible n'a, dans les faits, pas changé (gigue GPS)
  (auto-confirmé, jamais de preview à valider) — jamais déclenché si un guidage de reprise
  (manuel ou automatique) existe déjà (`resumeGuidance == nil` gardé en tête de fonction).
  Présentation DISTINCTE : pas de bannière du haut (`RideView.activeBanner` filtre
  `!resume.isAutomatic`), juste un toast bref "Recalcul"
  (`autoRecomputeToastToken`/`.onChange` côté RideView) + une bannière LATÉRALE dédiée
  (`RejoinGuidanceBannerView`, indigo-lite, même colonne que `LateralCapBannerView`/
  `OffTrackChipView`, prioritaire sur les deux tant qu'active — feature-flag
  `RideConstants.rejoindreGuidanceBannerEnabled`).

`RideSessionManager.resumeGuidanceLiveDistanceMeters` (distance au pin, recalculée à CHAQUE fix
tant que `resumeGuidance != nil`) alimente cette bannière — jamais stale, contrairement à un
calcul figé au moment du déclenchement. Le tracé pointillé bleu sur la carte
(`RideMapLibreView.updateResumeShape`) et la fin du guidage (jonction atteinte < 30 m, ou retour
naturel sur trace) sont EXACTEMENT les mêmes pour les deux origines — seule la présentation
diffère.

## `start(track:)` vs `switchMode(track:)` — ne jamais les confondre dans RideView

`RideSessionManager` expose deux façons de (re)donner une trace à la session, jamais
interchangeables : `start(track:)` est un VRAI nouveau départ (réinitialise `rideStartDate`,
`averageSpeedKmh`/`maxSpeedKmh`/`totalDistanceTraveledMeters`, `currentBucketIndex`,
`speedSamples`, `isGuidanceStopped`...) ; `switchMode(track:)` reconstruit uniquement ce qui
dépend de la trace (checkpoints, distance cumulée, état hors-trace) sans toucher aux stats en
cours ni au zoom/historique de vitesse — pensé pour un retour d'onglet ou Trace↔Nav (spec
"camera-mode-stability").

Fix "ride-restarts-from-zero-on-tab-return" (it19, retour terrain : "si je switch d'onglet et
reviens sur Ride, ça repart de zéro") — `RideView.onAppear` appelait INCONDITIONNELLEMENT
`start(track:)`, or `.onAppear`/`.onDisappear` se déclenchent à CHAQUE changement de visibilité
dans un `TabView` (pas seulement au montage initial) : chaque aller-retour Ride→Biblio→Ride
remettait donc les stats de la sortie à zéro, alors même que `recordedPoints` (l'enregistrement
GPS lui-même) survivait déjà correctement grâce au garde `recordingTrackID != track.id`.
`RideView.hasStartedRideSession` (`@State`, non persisté) distingue désormais le VRAI premier
lancement (`start`) de tout retour ultérieur (`switchMode`) — `.onChange(of:
navigationState.selectedTab)` continue d'appeler `switchMode(track:)` séparément au retour
d'onglet (double appel harmless, même patron déjà en place pour `stop()` via `.onDisappear` +
la branche `else`) : ne pas essayer de dédupliquer ces deux déclencheurs, ils réagissent à des
signaux différents (visibilité de vue vs changement d'onglet) et coexistaient déjà pour `stop()`
avant ce fix.

## Avertissement de pente natif (spec "slope-warning-native", it19)

Remplace la demande initiale "utiliser GPXKit" — `GPXKit` (mmllr/GPXKit) existe bien et
conviendrait techniquement, mais c'est un VRAI package tiers, contraire à la règle explicite du
projet ("MapLibre est la SEULE dépendance tierce autorisée", `project.yml`). Décision tranchée
avec le propriétaire : détection NATIVE, `GPXPoint.elevation` est déjà disponible (déjà utilisée
pour `GPXTrack.elevationGainMeters`).

`SlopeAnalyzer.steepGradeWarnings` (Rendering/, logique pure) découpe la trace en fenêtres non
chevauchantes d'au moins `RideConstants.slopeWarningMinSegmentMeters` (100 m — évite les pentes
aberrantes sur un segment de quelques mètres, bruit GPS/altimétrique), pose un symbole PONCTUEL
(jamais un dégradé continu, demande explicite) si la pente moyenne de la fenêtre dépasse
`slopeWarningThresholdPercent` (défaut 10 %, réglable 8/10/12/15 %), espacés d'au moins
`slopeWarningMinMarkerSpacingMeters` (300 m) pour ne jamais empiler des triangles sur une longue
pente régulière. Rendu côté `RideMapLibreView` : triangle jaune/noir façon panneau routier
(`slopeWarningImage(isClimbing:)`, deux variantes dessinées selon le signe de la pente),
`icon-rotation-alignment: viewport` (reste lisible à l'écran, ne suit pas la rotation cap-en-
haut — contrairement aux chevrons qui, eux, DOIVENT suivre la trace). Activation/seuil passés
par `.environment(...)` (voir `slopeWarningsEnabled`/`slopeWarningThresholdPercent` sur
`EnvironmentValues`), même contrainte `MapProvider` (init à signature fixe) que le marqueur
replay debug ci-dessous.

## Exclusivité mutuelle des guidages (spec "manual-point-guidance-exclusivity", it22)

Constat : taper un point manuel sur la carte pendant un Ride en Trace (ou choisir une
destination via "Aller à") ne mettait auparavant JAMAIS en pause le guidage de trace
(roadbook + reprise) — les deux tournaient en parallèle, contradictoire avec "un seul guidage
actif à la fois".

`GuidanceTarget` (Ride/GuidanceTarget.swift, `.trace`/`.manualPoint(CLLocationCoordinate2D)`/
`.none`) — délibérément un type CALCULÉ (`RideSessionManager.guidanceTarget`), jamais un
second état stocké à resynchroniser : dérivé de `navDestinationCoordinate`/`goToGuidance`/
`track`, déjà les sources de vérité existantes. DISTINCT de l'état de trace unique
(`LibraryStore.activeTrackID`/`displayedTrackIDs`, invariant it10) — la trace reste AFFICHÉE
même quand `guidanceTarget == .manualPoint`, seul son GUIDAGE se met en pause.

- `startNav`/`startGoTo` appellent désormais `cancelResume()` (en plus de leur exclusion
  mutuelle réciproque déjà en place depuis it21, `stopGoTo()`/`stopNav()`) — met en pause la
  reprise de trace (manuelle ou automatique) sans jamais toucher `track`.
- `RideSessionManager.handle(location:)` : le `switch guidanceTarget` (remplace l'ancien
  `if navDestinationCoordinate != nil` d'it21, qui ne couvrait QUE le guidage riche) suspend
  tout le pipeline trace (`updateRoadbookProgress`/`updateAutoRecompute`/`updateRoadbookBanner`/
  `updateRideStats`) dès que `guidanceTarget != .trace` — un guidage SIMPLE (`startGoTo`,
  profil Piste/Mixte, ou Valhalla indisponible) est désormais couvert aussi, pas seulement le
  riche.
- `RideView.bottomControlsColumn` : toute la colonne latérale (RejoinGuidanceBannerView/
  OffTrackChipView/LateralCapBannerView) est gardée par `session.guidanceTarget == .trace` —
  sans ce garde explicite, ces vues resteraient sur leur dernière valeur FIGÉE (le calcul
  s'arrête, mais rien ne force `nil`/`false`) plutôt que de disparaître proprement.
- `RideView.handleTrackTap` (tap direct sur la trace) appelle `session.returnToTraceGuidance()`
  avant `requestResume(...)` si un guidage manuel était actif — "taper à nouveau sur la trace...
  réactive le guidage trace et annule la destination manuelle".
- `RideSessionManager.returnToTraceGuidance()` — `stopNav()` + `stopGoTo()`, le bouton "Revenir
  à la trace"/"Arrêter le guidage" de `NavGuidancePanelView` (voir plus bas) l'appelle aussi.
- **Bug manqué en it21, corrigé ici** : `RideView.commitGoTo(profile:)` (tap LONG sur la carte,
  confirmationDialog Route/Piste/Mixte) utilisait encore `modeStore.mode == .nav` — le même
  check mort déjà corrigé dans `DestinationSearchTabView` en it21 (spec "nav-classic-rebuild"),
  mais oublié sur CE second call site. Un point manuel avec le profil "Itinéraire" et Valhalla
  configuré ne déclenchait donc jamais le guidage riche via tap long, seulement via la
  recherche "Aller à". Même fix : `profile == .route && session.isRichNavAvailable`.

## Bannière de guidage "Aller à" : bouton d'arrêt (spec "nav-guidance-stop-button", it22)

`NavGuidancePanelView` n'avait AUCUN contrôle de fermeture propre une fois `session.navRoute
!= nil` (seul `GoToStatusPillView`, le guidage SIMPLE, avait un `xmark.circle.fill`) — ajouté
un bouton identique, `onStop`/`stopLabel` fournis par l'appelant (`RideView.directionPanelLayer`) :
"Revenir à la trace" (→ `returnToTraceGuidance()`) si `library.activeTrack != nil`, "Arrêter
le guidage" (→ `stopNav()`) sinon.

## Icône de reprise de trace dynamique (spec "rejoin-icon-dynamic-bearing", it22)

`RejoinGuidanceBannerView` (bannière indigo, guidage AUTOMATIQUE de reprise) avait une icône
STATIQUE (`arrow.triangle.merge`, jamais tournée) — retour terrain : "elle doit devenir
dynamique et refléter la vraie direction à prendre". Fix : `relativeBearingDegrees: Double?`
+ `.rotationEffect(...)`, EXACTEMENT le même patron que `OffTrackChipView` (rotation continue
d'un seul symbole, pas un jeu d'icônes discret) — calculé côté `RideView` via
`resumeRelativeBearingDegrees(to: resume.pinCoordinate)`, déjà existant (utilisé par
`ResumeGuidanceCardView`), aucun nouveau calcul de bearing nécessaire. `nil` → icône fixe non
tournée (repli honnête, jamais de crash).

## Toggle orientation cap-en-haut/nord-en-haut (`leftMiddleLayer`, RideView.swift)

Fix "orientation-toggle-nav-only-unreachable" (it19, retour terrain : "dans l'onglet Ride,
toujours pas de boussole") — ce bouton (+ `SpeedLimitBadgeView`) vivait dans un bloc restreint
à `modeStore.mode == .nav`, or le Mode Nav est MASQUÉ de l'UI depuis it12 (`RideModeSegmentedControl`
plus appelée, voir CLAUDE.md racine section Nav/) : ce bouton n'a donc jamais été visible en
usage réel avant ce fix. Affiché désormais quel que soit le mode — **ne JAMAIS regater un
contrôle Ride derrière `modeStore.mode == .nav`** sans vérifier d'abord qu'il reste atteignable
(Mode Nav n'a plus de point d'entrée UI). `SpeedLimitBadgeView` reste conditionné à
`session.currentSpeedLimitKmh` (toujours `nil` en Mode Trace, `updateSpeedLimit` n'étant
appelée que par `updateNavProgress`) — invisible tant que ce calcul n'est pas branché sur Mode
Trace, sans risque de régression.

**Fix "ride-landscape-overlap"** (retour terrain : "en mode paysage y a des instructions qui se
chevauchent") — `leftMiddleLayer` se centrait verticalement sur TOUTE la hauteur de l'écran
(`Spacer()`/contenu/`Spacer()` non borné), jamais sur la zone réellement libre entre le haut
(attribution + bannière + `NavGuidancePanelView`) et le bas (marge caméra). Invisible en
portrait (écran assez haut), mais chevauche le panneau de guidage en paysage (écran court)
quand bannière + panneau sont actifs en même temps. `leftMiddleLayer` prend désormais
`insets: RideOverlayLayout.MapInsets` en paramètre (plus une simple `var`) et se borne dans
`insets.uiTop`/`insets.uiBottom` avant de centrer son contenu — LA MÊME zone déjà utilisée pour
cadrer la caméra/le point GPS (`computeMapInsets`), jamais un second calcul indépendant. Si un
futur overlay vertical-centré est ajouté dans `rideContentBody`, lui donner les mêmes bornes
plutôt que le laisser se centrer sur l'écran entier — c'est cette omission qui a causé le bug.
Non vérifié visuellement sur device (pas de repro tactile pour forcer bannière+panneau+paysage
simultanément dans cet environnement) — raisonnement géométrique seulement, à confirmer au
prochain test terrain.

## Routage Valhalla optionnel (spec "valhalla-client-toggle", it19)

Backend de routage ALTERNATIF à OSRM, désactivé par défaut (`RideSettingsStore.valhallaEnabled`) —
endpoint (non sensible, UserDefaults) + identifiants Basic Auth (Keychain,
`ValhallaKeychainStore`, username ET password en champs libres, aucune valeur codée en dur)
configurables dans Réglages > Avancé > "Routage Valhalla" (`ValhallaSettingsView`, bouton
"Tester la connexion" → `/status`).

Portée délibérément limitée à `DetourRoutingService.route(...)` (repli automatique vers OSRM en
cas d'échec Valhalla — réseau/auth/serveur down — jamais de guidage cassé), donc :
- **Concerné** : contournement "Chemin bloqué" (`requestDetour`/`requestDirectDetour`), reprise
  hors-trace (`updateAutoRecompute`/`requestResume`), profil `.offroad` d'"Aller à" (Mode Nav).
- **PAS concerné** : profils `.route`/`.mixed` d'"Aller à" (`NavRoutingService`) — ceux-ci ont
  besoin des manœuvres turn-by-turn détaillées (`NavManeuver`), dont le vocabulaire Valhalla
  diffère trop d'OSRM pour être mappé fidèlement dans le périmètre de cette itération (voir
  TODO.md pour une éventuelle itération future dédiée).

`RideSessionManager.currentValhallaConfiguration` (calculée à la demande, jamais mise en
cache — lit `RideSettingsStore` + `ValhallaKeychainStore` à chaque fois) vaut `nil` tant que le
toggle est désactivé ou l'endpoint vide : dans ce cas, `DetourRoutingService` se comporte À
L'IDENTIQUE d'avant cette feature — désactiver le toggle revient donc instantanément et sans
reste au comportement OSRM historique, aucune donnée/état ne dépend de Valhalla ailleurs dans
l'app. `ValhallaRoutingService.decodePolyline6` décode au facteur de précision 6 (1e6) — PAS 5
(Google Maps/OSRM standard), format propre à Valhalla (`trip.legs[].shape`).

Retour terrain (it19, serveur `valhalla.zim.ovh` derrière Traefik/Basic Auth) : "Tester la
connexion" timeout en 4G alors que curl HTTPS direct réussit (TLS 1.3, cert Let's Encrypt
valide — ATS écarté comme cause, le TLS dépasse largement ses exigences par défaut). Deux
choses vérifiées/corrigées sans pouvoir reproduire le device réel dans cet environnement (pas de
device physique, voir CLAUDE.md racine) :
- `RideConstants.valhallaRequestTimeoutSeconds` (20 s) — DISTINCT de
  `detourRoutingTimeoutSeconds` (12 s, OSRM, inchangé) : un aller-retour vers un reverse-proxy
  auto-hébergé en 4G peut légitimement dépasser le délai prévu pour l'API de démo OSRM.
- `ValhallaRoutingError.network` expose désormais `domain`/`code` de la `NSError` sous-jacente
  (ex. `NSURLErrorDomain -1001`) dans le message affiché — remplace le besoin d'un outil externe
  (Charles/Proxyman) pour un premier diagnostic. Le header `Authorization: Basic` était déjà
  construit PROACTIVEMENT (`applyBasicAuth`, jamais via `URLAuthenticationChallenge`) — pas la
  cause. Si le timeout persiste après ces deux fixs, le code d'erreur affiché est le point de
  départ du prochain diagnostic.

## Branchement réel de Valhalla (spec "valhalla-live-routing", it20)

Avant it20, `DetourRoutingService.route(...)` appelait `ValhallaRoutingService` directement en
dur (tenter Valhalla, repli OSRM inline) — fonctionnellement déjà correct, mais dupliquant la
logique de repli à chaque site d'appel potentiel et sans point de résolution unique testable.
Depuis it20, `RoutingProvider.swift` introduit :

- Un protocole `RoutingProvider` (`route(from:to:profile:) async throws -> [CLLocationCoordinate2D]`)
  que `OSRMRoutingProvider` et `ValhallaProvider` implémentent tous deux — même signature
  d'entrée/sortie qu'avant, AUCUN appelant existant (`ResumeGuidance`/`requestResume`,
  `requestDetour`/`requestDirectDetour`, `startGoTo` profil `.offroad`) n'a changé.
- `RoutingProviderResolver.orderedProviders(valhallaEnabled:configuration:)` — résolution PURE
  (même patron que `MapSourceResolver`, it11) : Valhalla en tête si activé+configuré, OSRM
  TOUJOURS en dernier maillon, jamais désactivable.
- `DetourRoutingService.route(from:to:profile:valhalla:)` (API publique inchangée) délègue à un
  second overload `route(from:to:profile:providers:)`, `internal` uniquement pour la
  testabilité — permet d'injecter des `RoutingProvider` factices (voir `RoutingProviderTests`)
  et de vérifier le repli en chaîne SANS jamais dépendre d'un vrai réseau (ni OSRM, ni Valhalla).

Portée INCHANGÉE depuis it19 (voir section "Routage Valhalla optionnel" ci-dessous) : toujours
`DetourRoutingService.route(...)` uniquement (contournement, reprise hors-trace, offroad
d'Aller à), jamais `NavRoutingService` (profils route/mixte d'Aller à, manœuvres turn-by-turn).
Nouveauté it20 : le costing "auto" Valhalla (profil `.route`) reçoit désormais des
`costing_options` réduisant `use_highways`/`use_tolls` (`RideConstants.valhallaAutoCosting*`) —
même esprit que le profil `.offroad` (costing "bicycle", qui évite déjà l'autoroute
nativement) : "auto" par défaut privilégierait sinon l'autoroute la plus rapide, peu pertinent
pour un contournement/une reprise moto sur petites routes.

## Détection fine de virages via map matching (spec
## "valhalla-map-matching-direction-change", it20 ; filtrage par type de manœuvre, it24 point 1
## — voir RoadBook/CLAUDE.md section "Détection route-aware" pour le détail complet)

Retour terrain : un léger virage (< `roadbookLightThresholdDegrees`, 30° par défaut)
correspondant à un VRAI changement de rue/bifurcation n'était pas signalé — le roadbook ne
regarde QUE l'angle géométrique cumulé de la trace GPX, qui ne distingue pas une simple
courbure d'un vrai changement de segment routier. Résolu par map matching complet (`/trace_route`
Valhalla, "préparé mais non branché" depuis it19), PAS par un simple abaissement du seuil
d'angle (aurait aussi fait ressortir de vraies simples courbures sans rapport avec un
changement de rue) :

- `ValhallaMapMatchingService.matchRoute(coordinates:configuration:)` recale la trace ENTIÈRE
  sur le réseau routier réel via `/trace_route` (`shape_match: "map_snap"`, costing "auto") —
  PAS `/trace_attributes` (endpoint dédié aux attributs d'arête par point, plus riche mais plus
  complexe à interpréter) : chaque élément de `trip.legs[].maneuvers[]` délimite déjà un segment
  de manœuvre distinct (nom de rue/type différent), exactement ce qu'on veut détecter sans
  reconstruire cette segmentation depuis des attributs bas niveau. Première ET dernière manœuvre
  (Départ/Arrivée) toujours exclues (`intermediateManeuvers`, ex-`intermediateManeuverCoordinates`
  avant it24) — seules les manœuvres EN COURS de route sont des candidates, ET (it24 point 1)
  seules celles dont `ValhallaManeuverType.roadbookTier` n'est pas `nil` survivent (écarte
  `.continueStraight`/`.becomes`, présents à chaque changement de nom de rue même sans virage).
  `RideConstants.mapMatchingMaxTracePoints` (2000) : sous-échantillonnage UNIFORME en amont si
  la trace dépasse ce nombre de points (charge utile raisonnable même sur un enregistrement
  dense "précis", 5 s/15 m).
- `RoadbookTier.lightDirectionChange` : palier DISTINCT des 4 paliers d'angle existants
  (light/marked/hard/uTurn) — icône "signpost.left/right" (panneau de signalisation, pas une
  flèche), signale explicitement "pas un virage géométrique classique". Depuis it24, ce n'est
  plus le SEUL palier possible pour un point de map matching — `.roundabout`/`.fork`/`.merge`
  (rond-point/fourche/fusion-bretelle, dérivés du TYPE de manœuvre Valhalla) et même `.uTurn`
  (réutilisé tel quel) peuvent aussi être assignés, voir RoadBook/CLAUDE.md.
- `RoadbookAnalyzer.buildRoadbookEvents(..., mapMatchedManeuvers: [] par défaut, ex-
  `mapMatchedDirectionChangeCoordinates` avant it24)` — respecte l'invariant it14 "source unique
  pour épingles carte ET bannière latérale" : UNE SEULE liste `[Checkpoint]`, enrichie plutôt
  que dupliquée. Une manœuvre à moins de `mergeMinDistanceMeters` d'un événement géométrique
  déjà détecté est ignorée (pas de doublon) ; sinon assignée au point de trace le plus proche à
  vol d'oiseau (`nearestPointIndex`, parcours linéaire — trace de taille raisonnable, pas besoin
  d'index spatial) avec le `tier`/la `direction` dérivés de son TYPE Valhalla (`roadbookTier`/
  `roadbookDirection`, it24 — plus fiable que l'angle géométrique bruité utilisé avant). La
  liste fusionnée est re-triée par
  `sourcePointIndex` (progression le long du trajet) puis renumérotée — l'ordre d'INSERTION
  (géométrique toujours ajouté avant map matching dans le code) ne reflète pas forcément l'ordre
  RÉEL le long du trajet. `windowedTurn(at:...)`, extrait de la boucle principale sans
  changement de comportement, est réutilisé pour donner à ces nouveaux points un angle/une
  direction cohérents à l'affichage (mais jamais gating — un point de map matching est TOUJOURS
  ajouté, quel que soit l'angle mesuré à cet endroit).
- `RoadbookMapMatchCache` (Ride/, `Documents/RoadbookMapMatchCache/`) : cache disque PAR TRACE
  (clé `GPXTrack.id`) — une trace GPX ne change jamais une fois importée (`let points`), donc
  aucune invalidation temporelle nécessaire ; une trace supprimée puis réimportée obtient un
  nouvel `id`, jamais de collision avec un cache périmé.
- `RideSessionManager.triggerMapMatchingIfNeeded(for:)`, appelée depuis `start(track:)` ET
  `switchMode(track:)` juste avant `rebuildCheckpoints()` (garde `mapMatchedTrackID`, même
  patron que `recordingTrackID` pour l'enregistrement — deux préoccupations indépendantes,
  gardes distinctes) : ne se déclenche qu'une fois par trace RÉELLEMENT différente, jamais à
  chaque retour d'onglet. EN TÂCHE DE FOND uniquement (jamais en temps réel pendant le Ride) :
  cache hit → synchrone, lu par le `rebuildCheckpoints()` de l'appelant qui suit immédiatement ;
  cache miss → `Task` réseau, qui appelle `rebuildCheckpoints()` lui-même à la fin (le
  `rebuildCheckpoints()` synchrone de l'appelant a déjà eu lieu SANS ces points). Dégradation
  propre partout : Valhalla désactivé/non configuré → aucun appel réseau, roadbook géométrique
  identique à avant it20 (voir `RoadbookMapMatchingTests.
  testOmittingMapMatchedParameterLeavesGeometricEventsUnchanged`, non-régression explicite) ;
  échec réseau (`try?`) → même résultat, jamais de crash ni de blocage du roadbook existant.
  `RideSessionManager.mapMatchingProvider`/`mapMatchCache`/`mapMatchingTask` sont `internal`
  plutôt que `private`, uniquement pour la testabilité (même patron que `unsavedRideStore`) —
  voir `RideSessionManagerMapMatchingTests` (provider factice, jamais de vrai réseau en test).

## Replay debug v2 (spec "replay-marker-heading-x2", it17, Bloc 4)

Root cause vérifiée avant de coder : le rond bleu NATIF de MapLibre (`showsUserLocation`) ne
suit PAS les positions synthétiques du replay — piloté par le vrai CoreLocation du device,
jamais par `session.handle(location:)`. D'où `RideMapLibreView`'s marqueur blanc dédié
(`MLNPointAnnotation`, seul usage de cette classe concrète sur cette carte).

Sandbox : `RideSessionManager.isDebugReplayActive`/`debugReplayForcesHeadingUp` sont
volontairement SANS `#if DEBUG` (pour ne pas propager la compilation conditionnelle dans
RideView/RideMapLibreView, déjà partagés) mais écrits UNIQUEMENT par `debugSetReplayActive`,
appelé UNIQUEMENT depuis `DebugReplayDriver` (fichier entier `#if DEBUG`, absent des builds
Release) — restent inertes (`false`) en usage normal. Le marqueur lui-même est passé à
`RideMapLibreView` via `.environment(\.isDebugReplayMarkerActive, ...)`, PAS en paramètre
d'init : son init est contractuel (protocole `MapProvider`, signature fixe, voir
`MapProvider.swift`), y ajouter un paramètre casse la conformité (déjà rencontré, corrigé).
`is2DNorthUp` réel de l'utilisateur n'est jamais modifié — `RideView.effectiveIs2DNorthUp`
calcule la valeur AFFICHÉE (force cap-en-haut si `debugReplayForcesHeadingUp`) sans toucher à
l'état persistant.

## Indicateur de service de routage actif (spec "routing-active-service-indicator", it24, point 0)

Retour terrain : "le toggle Valhalla est activé côté Réglages, mais il n'y a aujourd'hui aucun
moyen de confirmer à l'œil quel service répond réellement à un instant donné (Valhalla, ou
repli silencieux vers OSRM)". Vérification technique PRÉALABLE (demandée par la fiche) :
`RoutingProviderResolver` existait DÉJÀ (it20) et est réellement câblé dans
`DetourRoutingService.route(...)` — confirmé par un vrai appel réseau (curl direct vers
`valhalla.zim.ovh/status`/`route`, hors app, pendant cette itération) montrant un serveur
joignable derrière Traefik/Basic Auth (401 attendu sans identifiants) : le chemin réseau
fonctionne de bout en bout, seule l'authentification (Trousseau iOS du propriétaire) reste à
vérifier en conditions réelles via l'indicateur ci-dessous.

`RoutingActivityMonitor` (@MainActor ObservableObject, même patron que `NetworkMonitor`) —
`RoutingActivityEvent(provider: .valhalla/.osrm, date:)`, mis à jour EN LIVE à chaque succès
RÉEL, jamais un statut figé au démarrage, jamais sur un échec (un échec total laisse
l'indicateur sur le dernier succès réel, ou "Aucune requête récente" si aucun n'a encore eu
lieu — volontairement PAS de 4e état "erreur", la fiche n'en demande que 3). DEUX points
d'écriture, les SEULS endroits du code où une requête de routage Valhalla part réellement :
- `RoutingProvider.kind: RoutingActivityProvider` (`.valhalla`/`.osrm`) + `DetourRoutingService.
  route(...providers:activityMonitor:)` enregistre `provider.kind` sur CHAQUE succès de la
  chaîne de repli (contournement/reprise hors-trace/hors-route d'Aller à) — `activityMonitor`
  injectable (défaut `.shared`), une instance FRAÎCHE en test plutôt que le singleton partagé.
- `RideSessionManager.requestNavRoute` enregistre `.valhalla` directement (guidage riche,
  AUCUN repli OSRM — dépendance dure, voir section Nav/CLAUDE.md "Branchement Valhalla").

Affiché dans `ValhallaSettingsView` (Réglages > Avancé > Routage Valhalla), juste sous le
toggle existant — "Valhalla" (vert) / "OSRM (repli)" (orange) / "Aucune requête récente" (gris)
+ heure du dernier appel.

## Pictogrammes de virage cohérents (fix "turn-icon-backward-looking", it23bis)

`RoadbookTier.swift` (ce dossier) a été réécrit : un SEUL glyphe de base ("arrow.up") tourné
d'un angle standardisé par palier, remplace les 4 noms de SF Symbol distincts d'avant (dont
`.hard` pointait vers le BAS — se lisait comme "demi-tour" plutôt que "virage fort", bug
remonté sur le Road Book mais qui affectait aussi `LateralCapBannerView` et les pins carte
`RideMapLibreView`, tous les trois consommateurs de `RoadbookTier.systemImageName`). Détail
complet, root cause et les 3 call sites mis à jour : voir `GPXlibre/RoadBook/CLAUDE.md` section
"Pictogrammes". Si un futur palier est ajouté à `RoadbookTier`, lui donner une rotation dans
`rotationDegrees(direction:)` plutôt qu'un nouveau nom de glyphe — c'est cette règle qui manquait
et a permis au bug d'origine.

## Itération 26 — précision du roadbook et saut carte

Toutes les causes ci-dessous ont été confirmées par lecture de code PUIS en rejouant les
algorithmes sur les traces réelles du propriétaire (test temporaire, jamais commité) — voir
CLAUDE.md racine "Device de référence" pour la méthode.

**Cache map matching par sens (fix "mapmatch-cache-direction-aware")** — `RoadbookMapMatchCache`
et les gardes anti-relance (`mapMatchedTraversalKey`, ici ET dans `RoadBookTabView`) sont indexés
par `GPXTrack.traversalKey`, plus par `id` : les types Valhalla (gauche/droite, fourche/fusion,
rang de sortie de rond-point) dépendent du sens de parcours, et `reordered(using:)` préserve
`id` — une trace map-matchée en A→B réutilisait ces types tels quels en B→A.

**Position du vrai carrefour (fix "roadbook-maneuver-position-from-route", it26 point 1)** —
`begin_shape_index` était correctement lu dans la géométrie Valhalla ; la précision était perdue
dans `RoadbookAnalyzer.mergingMapMatchedDirectionChanges` (`nearestPointIndex` → point GPX le
plus proche, 15-120 m d'erreur selon la densité). Désormais :
- `Checkpoint.trackCumulativeDistanceMeters` (distance INTERPOLÉE sur le segment, renseignée
  aussi pour les événements géométriques) et `Checkpoint.cumulativeDistanceMeters(using:)`, SEUL
  point de lecture (Ride `roadbookEventCumulativeDistanceMeters` ET Road Book). Coordonnée
  affichée = carrefour réel. `Checkpoint.id`/`==` dérivés de cette position (décimètres).
- Choix du PASSAGE de trace (boucle qui traverse deux fois un carrefour, aller-retour) :
  `MapMatchedManeuver.routeProgressFraction` (progression le long de la route recalée, depuis
  `begin_shape_index`, tous tronçons confondus) départage les `TrackProjector.passes` ; repli
  sans cette donnée : projection monotone dans l'ordre des manœuvres.
- Carrefour à plus de `NavigationConstants.roadbookMapMatchMaxOffTrackMeters` (60 m) : ignoré.
- Doublon mesuré LE LONG de la trace (plus à vol d'oiseau).

**Demi-tour = même route (fix "roadbook-no-false-uturn", it26 point 2)** — sources réelles sur
12 traces : palier géométrique à 135° (24 faux demi-tours sur une sortie de 110 km, tous des
lacets ; le seuil de 175° demandé en laissait encore 5, angles cumulés 182-435°), un seul demi-tour
Valhalla (à 20 m du départ : stationnement), bruit GPS de départ, et un téléport GPS enregistré
(voir TODO.md). Règle :
- nouveau palier `RoadbookTier.veryHard` "Virage très serré" AVEC son sens ;
- géométrique : `.uTurn` seulement si angle ≥ `roadbookUTurnMinDegrees` (175°) ET la trace
  repart sur son propre tracé (`roadbookUTurnSamePathMaxMeters`, 12 m, positions interpolées) ;
- Valhalla : `.uTurn` seulement si `MapMatchedManeuver.isSameRoadUTurn` (même `street_names`
  avant/après, désormais décodé) ; sinon `.veryHard` du côté du type ;
- tout demi-tour dans les `roadbookUTurnEndpointGuardMeters` (200 m) du départ/de l'arrivée :
  ignoré (stationnement).
- `veryHardThresholdDegrees` remplace `uTurnThresholdDegrees` partout (réglage "Très serré
  dès", clé persistée `settings.roadbookUTurnThresholdDegrees` INCHANGÉE).

**Saut carte depuis le Road Book (fix "roadbook-jump-to-map-sticky", it26 point 4)** — une seule
cause aux deux symptômes ("une fois sur deux", "revient tout seul sur le GPS") : le saut ne
suspendait le suivi que via la fenêtre de 5 s d'un geste manuel, posée par un `.onChange` APRÈS
le rendu qui applique le saut — le bloc de suivi de `updateUIView` recentrait dans la même passe.
`RideCameraFollowPolicy` (pur, testé) : `roadBookFocusRequest != nil` = mode étape, suivi GPS
suspendu sans minuteur ; la passe qui saute ne recentre jamais ; +/- zoome autour de l'étape.
"Me recentrer" (visible pendant tout le mode) appelle `AppNavigationState.endRoadBookFocus()` +
`recenterCamera()` — seule sortie. Le changement d'onglet ne force jamais la caméra (seuls +/-
et "Me recentrer" changent `cameraCommandToken`), vérifié.

## Itération corrective — fiabilité des checkpoints (angle par cordes)

Retour terrain : "Virage fort" (-90°, 0°) là où la trace va tout droit. Diagnostic sur traces
réelles (dump par checkpoint) : TOUS venaient de la détection géométrique — l'angle était la
SOMME des écarts de cap segment par segment, fenêtre comptée en segments ENTIERS (≥ 2 de chaque
côté, donc des centaines de mètres sur une trace peu dense) et segments de 0 m (points GPX
dupliqués, cap fictif 0°) injectant ±90°. Les "0°/-89°" affichés étaient le CAP du segment
suivant. 316 checkpoints sur 436 avaient un changement de cap réel < 25°.

Règle produit : pas de vrai changement de direction = pas de checkpoint. Désormais :
- `RoadbookAnalyzer.headingChange` : cap MOYEN avant (corde interpolée) vs cap moyen après —
  SEULE mesure d'angle, pour la géométrie ET les manœuvres Valhalla (au vrai carrefour). Ne
  jamais réintroduire une somme d'écarts segment par segment.
- `TierThresholds` : seul endroit où un angle devient un libellé ; sous
  `roadbookLightThresholdDegreesDefault` (25°, seuil minimal) jamais de "virage".
- Valhalla : rond-point, fourche, bretelle/sortie, demi-tour gardés ; un virage seulement si la
  trace tourne ≥ seuil minimal, ou si la route change de nom (`MapMatchedManeuver.
  changesRoadName`, noms avant/après désormais conservés) avec ≥ `roadbookRoadChangeMinTurnDegrees`
  (10°) → "Changement de direction". Libellé et sens toujours issus de la trace.
- Grappes (`roadbookTurnClusterMeters`, 50 m) : un checkpoint au sommet le plus marqué, portant
  le virage NET (approche → sortie ; > 180° géré) ; net sous le seuil = zigzag, ignoré.
- Cap affiché : `RoadbookAnalyzer.outgoingHeading` (cap moyen après, 0-360°).
- Fenêtres par défaut 40 m (Réglages > Roadbook, plage 30-80 m).
- Dump de debug : `RoadbookDebugDump` (build DEBUG, `Logger` catégorie "roadbook").
Tests : `RoadbookCheckpointReliabilityTests` (dont réplique synthétique de la trace du retour
terrain).
