# CLAUDE.md — GPXlibre/RoadBook

Chargé automatiquement quand une session travaille sous `GPXlibre/RoadBook/`. Le reste du
contexte projet (philosophie, règles absolues, conventions) reste dans le CLAUDE.md racine —
ce fichier ne documente que ce qui est spécifique à ce dossier.

## Mode Road Book (spec "roadbook-mode", it23)

Nouvel onglet, feature différenciante ("esprit roadbook papier de rallye, pas une redite du
GPS") — lecture d'une trace en liste de directions pures, sans carte principale.

**Découplage total du Ride actif, non négociable** : ce module ne référence JAMAIS
`RideSessionManager`, ne lit ni n'écrit `LibraryStore.activeTrackID`/`displayedTrackIDs`
(invariant trace unique, it10) ni `GuidanceTarget` (it22). `RoadBookTabView.selectedTrackID`
est un `@State` PUREMENT LOCAL à cet écran — choisir une trace ici n'affiche/ne pilote rien
côté Ride, exactement l'inverse de `LibraryView`/`RideView` qui, eux, mutent
`LibraryStore.activeTrackID` intentionnellement. `RoadbookExtractor`/`RoadbookLiveProgress`
(logique pure) n'ont même pas accès à ces objets — l'invariant est garanti par CONSTRUCTION,
pas seulement par convention de code.

**Pas de nouvelle logique de détection de virage** (demande explicite de la fiche) :
`RoadbookExtractor.maneuvers(for:...)` réutilise TEL QUEL
`RoadbookAnalyzer.buildRoadbookEvents` (paliers 30/45/90/135°, it14) et
`TrackProjector.cumulativeDistances` — il ne fait qu'assembler les distances partielle/cumulée
autour de la liste de `Checkpoint` déjà produite ailleurs. Les seuils/fenêtre utilisés sont les
MÊMES réglages Roadbook que Ride (`RideSettingsStore.roadbookWindowBeforeMeters` etc.) — aucun
réglage de détection dupliqué pour cet onglet. Le map matching Valhalla (it20,
`mapMatchedDirectionChangeCoordinates`) n'est PAS branché ici — délibérément, pour rester
découplé de tout appel réseau/cache lié à une session Ride ; scope potentiel d'une itération
future si le besoin se confirme.

**Deux modes de lecture, une seule liste de données** (`RoadbookReadingMode`) :
- `.classic` : affiche directement `[RoadbookManeuver]` telle quelle (distances fixes).
- `.gpsAssisted` : calcule un index/une distance restante EN PLUS via
  `RoadbookLiveProgress.nextManeuver` (fonction pure, prend une distance cumulée déjà projetée)
  — NE MUTE JAMAIS la liste `[RoadbookManeuver]` elle-même. C'est cette séparation qui garantit
  qu'aucun état parasite ne fuit entre les deux modes (test dédié,
  `RoadbookLiveProgressTests`) : basculer de mode ne fait qu'activer/désactiver l'appel à cette
  fonction, jamais une resynchronisation d'état à gérer.
- GPS assisté utilise sa PROPRE instance `LocationManager()` locale à `RoadBookTabView`
  (`@StateObject`, même patron que `FavoriteAddressesView`/`RegionDownloadView` — "instance
  locale, pas d'injection globale") — jamais le GPS de `RideSessionManager`.

## UI façon roadbook papier + pictogrammes cohérents (retour terrain it23bis)

Deux corrections après le premier retour terrain sur it23 : "niveau UI c'est pas ça du tout...
regarde ce qui se fait en affichage roadbook, et copie la même chose" (référence choisie par le
propriétaire : "roadbook papier de rallye classique") + "tu utilises des flèches bizarres,
parfois on dirait qu'il faut faire un retour arrière".

**UI** : `RoadbookTableView`/`RoadbookTableRow` remplacent l'ancien `List` SwiftUI générique par
une vraie table dense en colonnes (N°/Cap/Partiel/Cumulé, traits fins verticaux ET horizontaux,
chiffres `monospacedDigit`) — mêmes colonnes/terminologie que l'export PDF, jamais un `List`
standard (ses insets/fonds par défaut cassent l'effet "tableau imprimé"). Largeurs de colonnes
PROPORTIONNELLES à la largeur d'écran disponible (`GeometryReader`, pas des largeurs fixes) —
un vrai roadbook papier est une bande étroite, mais sur un écran de téléphone une bande étroite
avec un grand vide à droite aurait l'air cassé, pas "fidèle au papier".

**Pictogrammes (bug réel, capture d'écran à l'appui)** : `RoadbookTier` choisissait un nom de SF
Symbol DIFFÉRENT par palier (`.hard` → `arrow.turn.down.left/right`) sans vérifier que tous les
paliers partagent la même convention visuelle — `.light`/`.marked` pointent globalement vers le
HAUT (lu comme "tout droit"), `.hard` pointait vers le BAS (lu comme "fais demi-tour"),
incohérence jamais remarquée avant que le Road Book ne l'affiche en grand ("Virage fort" avec
une flèche qui semblait indiquer un retour en arrière). Corrigé À LA SOURCE
(`RoadbookTier.baseSystemImageName`/`rotationDegrees(direction:)`) : UN SEUL glyphe de base
("arrow.up"), tourné d'un angle STANDARDISÉ par palier (30°/65°/105°/180°, jamais l'angle
géométrique brut mesuré sur la trace — trop bruité pour un pictogramme stable, et une rotation
proportionnelle continue aurait fini par pointer vers le bas pour les virages francs, exactement
le bug d'origine). Répercuté sur les TROIS call sites qui utilisaient déjà `systemImageName` :
`LateralCapBannerView` (bannière Ride, `.rotationEffect`), pins carte
(`RideMapLibreView.annotationView`, nouveau paramètre `rotationDegrees:` →
`CGAffineTransform`), et `RoadbookPDFExporter.drawPictogram` (réécrit pour réutiliser
`RoadbookTier.rotationDegrees` au lieu de sa propre rotation continue — écran et PDF partagent
désormais EXACTEMENT la même convention visuelle). `.lightDirectionChange` (panneau de
signalisation map matching) est le SEUL cas non concerné — il n'a jamais été une flèche tournée,
voir son commentaire dédié.

## Export PDF (spec "roadbook-mode", it23, point 2)

`RoadbookPDFExporter.generate(trackName:maneuvers:options:)` — génération CÔTÉ APP
(`UIGraphicsPDFRenderer`, natif iOS), aucun service externe. Lit la MÊME liste
`[RoadbookManeuver]` que l'écran (passée par l'appelant `RoadBookTabView` à
`RoadbookExportOptionsView`) — une seule source de vérité, jamais de recalcul séparé qui
pourrait diverger de l'affichage à l'écran.

- `columnLayout(options:contentRect:)` (pur, testé séparément) répartit la largeur disponible
  entre les colonnes ACTIVÉES seulement — masquer "cumulée"/"note" rend leur place aux autres
  colonnes plutôt que de laisser un blanc.
- Pagination par CALCUL de la hauteur réelle disponible (`contentRect.height / rowHeight`),
  jamais un nombre de lignes fixe codé en dur qui se désynchroniserait si la police/densité
  changent — voir `RoadBookConstants.pdfRowHeightCompact/Comfortable`.
- Pictogrammes : flèche vectorielle dessinée (`UIBezierPath`, jamais une image rasterisée),
  tournée selon `Checkpoint.direction`/`turnAngleDegrees` — teinte d'accent orange/rouge
  (`RoadBookConstants.pdfAccentColorRGB`, clin d'œil à l'identité visuelle du logo) en couleur
  PLEINE, jamais un dégradé par glyphe (resterait lisible imprimé en niveaux de gris, demande
  explicite de la fiche : "pas nécessairement en fond de page pour rester imprimable").
- Trace vide ou sans manœuvre détectée → une page avec un message explicite, jamais un crash
  ni une page blanche muette (`RoadbookPDFExporterTests.
  testGenerateNeverCrashesOnEmptyManeuverList`).
- Colonne "Note" : vierge et lignée (esprit roadbook papier, l'utilisateur l'annote à la main)
  — aucune donnée de note n'existe dans l'app, ce n'est pas un oubli.
- Partage via `ShareLink` (même mécanisme que l'export GPX de l'it19, voir
  `LibraryStore.exportURL`) — le PDF est écrit dans `FileManager.default.temporaryDirectory`,
  jamais dans `Documents/` (fichier éphémère, régénéré à chaque export).

## Unité de distance (`DistanceUnit`, km/mi)

Introduite PAR cette feature, scopée au Road Book — DISTINCTE de `SpeedUnit` (vitesses
uniquement). Aucune unité de distance globale n'existait ailleurs dans l'app avant it23
(`RideStatsPanel` etc. restent en km, explicitement hors périmètre de `SpeedUnit`, voir son
commentaire de tête) : ce choix n'étend PAS cette unité à un autre écran, ne change rien à
l'affichage des distances existant ailleurs.

## Réglages persistés (`RideSettingsStore`)

`roadbookReadingMode`/`roadbookMiniMapEnabled` : un champ UserDefaults chacun, même patron que
le reste du store. `roadbookPDFOptions` (`RoadbookPDFOptions`, `Codable`) : persisté en UNE
seule clé JSON (`JSONEncoder`/`JSONDecoder`) plutôt qu'un champ par option — ses 7 champs n'ont
de sens qu'ensemble (toujours lus/écrits groupés par `RoadbookExportOptionsView`), contrairement
aux réglages Roadbook de détection ci-dessus qui ont chacun un usage indépendant côté Ride.
Seul exemple de ce patron JSON dans le store actuellement — si un futur réglage a le même besoin
(struct multi-champs cohérente), le réutiliser plutôt que d'inventer un 2e patron.

## Mini-carte (`RoadbookMiniMapView`)

MapKit léger (comme `CameraPreviewMapView`, Settings/), fichier SÉPARÉ plutôt qu'un paramètre
ajouté à `CameraPreviewMapView` — celle-ci est déjà partagée par 3 écrans Réglages avec un
contrat fixe (spec "translucent-settings-preview-sheets", it15), et ce mini-map a un besoin
légèrement différent (position live optionnelle, mode Assisté GPS uniquement). Toggle
`roadbookMiniMapEnabled` : "utile en debug de fiabilité de la feature et comme filet de
sécurité visuel" (spec) — jamais affiché en mode Roadbook classique (pas de position live à
montrer dans ce mode).
