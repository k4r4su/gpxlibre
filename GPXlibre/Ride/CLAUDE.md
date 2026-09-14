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

