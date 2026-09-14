# CLAUDE.md — GPXlibre/Settings

Chargé automatiquement quand une session travaille sous `GPXlibre/Settings/`. Le reste
du contexte projet (philosophie, règles absolues, conventions) reste dans le CLAUDE.md
racine — ce fichier ne documente que ce qui est spécifique à ce dossier.

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


## Sheets à aperçu carte live : fond translucide (spec "translucent-settings-preview-sheets",
## it15, Bloc 2)

Les 3 sheets Réglages > Navigation qui montrent une carte en direct derrière un slider
(Position point bleu, Zoom par défaut, Zoom automatique) utilisent
`translucentPreviewBackground()` (View extension privée, `NavigationSettingsView.swift`) —
teinte noire 0.45 + `.ultraThinMaterial` (le blur seul peut se faire "laver" par un fond de
carte très clair, illisible en plein soleil) + `.environment(\.colorScheme, .dark)` forcé sur
la carte pour que `.primary`/`.secondary` restent clairs dessus quel que soit le mode système
— même patron que RideStatsBadge/Panel pour un calque posé sur la carte. Réservé à CES 3
sheets précisément ; un réglage administratif classique (nom/version...) reste en sheet opaque
standard — ne pas généraliser sans qu'une spec future le demande.

