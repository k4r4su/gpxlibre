# TODO

## Bloc 4 — Trafic (TomTom) : sauté proprement, activation documentée

**Statut** : non activé. Bloqué par une clé API TomTom que l'agent ne peut pas provisionner
(inscription développeur requise, humaine). Toute l'infrastructure autour (réglage Trafic
on/off #11, point d'accroche `TrafficService`) est en place et prête.

### Pourquoi ce n'est pas fait

TomTom Traffic API (free tier) nécessite un compte développeur + une clé API générée sur
[developer.tomtom.com](https://developer.tomtom.com). C'est une étape humaine (inscription,
acceptation des conditions) que je ne peux pas faire à ta place.

### Comment l'activer

1. Créer un compte gratuit sur https://developer.tomtom.com/user/register
2. Créer une clé API ("API Keys" → "Add new key")
3. Ouvrir `GPXlibre/Nav/TrafficService.swift`, renseigner `apiKey` :
   ```swift
   static let apiKey = "TA_CLE_TOMTOM"
   ```
4. Implémenter l'appel réel dans `trafficSummary(for:networkMonitor:)` — endpoint
   [Traffic Flow Segment Data](https://developer.tomtom.com/traffic-api/documentation/traffic-flow/flow-segment-data)
   (`GET /traffic/services/4/flowSegmentData/absolute/10/json?key=...&point={lat},{lon}`)
   sur quelques points le long de `route.coordinates`, agréger `currentSpeed` vs
   `freeFlowSpeed` pour estimer un retard en minutes.
5. Overlay carte : styler la portion de route concernée en une couleur distincte
   (vert/orange/rouge selon le ratio vitesse actuelle/vitesse fluide) — MapLibre : découper
   la géométrie de route Nav en segments avec `NSExpression` conditionnelle sur `lineColor` ;
   MapKit : plusieurs `MKPolyline` (un par tronçon coloré).
6. UI : afficher `TrafficSummary.extraDelayMinutes` dans `NavGuidancePanelView`
   ("+12 min trafic"), silencieux si `nil` — c'est déjà le comportement du service.
7. Hors ligne : la fonction retourne déjà `nil` si `networkMonitor.isReachable == false` —
   comportement "section grisée honnête" déjà respecté, rien à changer.
8. Pas de reroutage automatique lié au trafic (demandé explicitement en v1) — ne pas
   brancher `trafficSummary` sur `RideSessionManager.requestNavRoute()`.

### Repli si quota/clé pose problème plus tard

Le free tier TomTom a un quota mensuel de requêtes. Si dépassé : le service échoue
silencieusement (à coder de la même façon que l'absence de clé — `catch { return nil }`),
jamais d'erreur visible pour une fonctionnalité annexe.
