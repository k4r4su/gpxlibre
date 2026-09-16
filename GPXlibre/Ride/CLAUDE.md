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
  phase `.active`
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

