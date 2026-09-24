# CLAUDE.md — GPXlibre/RoadBook

Chargé automatiquement quand une session travaille sous `GPXlibre/RoadBook/`. Le reste du
contexte projet (philosophie, règles absolues, conventions) reste dans le CLAUDE.md racine —
ce fichier ne documente que ce qui est spécifique à ce dossier.

## Repères en pictogrammes emoji (spec "roadbook-mode", it23sexies)

⚠️ **Remplacé en it27** ("roadbook-visible-landmarks-only") : le repère par manœuvre et son
cache par coordonnée n'existent plus — voir la section "Repères visibles" en fin de fichier.
Conservé pour l'historique des décisions.

Retour terrain : "pour ces points je ne vois rien. J'aimerais que dans l'espace, à côté de la
flèche il y ait des pictogrammes (je pense que niveau emoji on a ce qu'il faut) afin
d'augmenter l'aide au niveau du prochain virage."

`RoadbookLandmark.bestDescription(for:) -> String?` (it23quater) est devenu
`bestLandmark(for:) -> RoadbookLandmarkInfo?` — retourne désormais une STRUCTURE
(`RoadbookLandmarkCategory` + `label`) plutôt qu'une simple chaîne, pour que l'UI puisse choisir
un emoji SANS reparser le texte. `RoadbookLandmarkCategory.emoji` est la seule source de vérité
du pictogramme (🚧 route non goudronnée, 🚂 passage à niveau, 🌉 pont, 💧 gué, 🔄 rond-point,
⛪ église, ⚡ ligne électrique, 🚦 feux, 🛑 cédez-le-passage/stop, ⛽ station, 🚆 voie ferrée,
🌳 arbre, 🏠 maison isolée, 📍 repli générique) — un emoji Unicode se dessine directement dans
un `Text` SwiftUI ET via `NSString.draw` côté PDF, aucun asset image à maintenir.

Affiché À CÔTÉ du pictogramme de direction (jamais à la place, jamais seulement en dessous en
petit texte comme la version it23quater — retour terrain explicite : le texte seul n'était pas
assez visible) dans les 3 surfaces : `RoadbookTableRow` (HStack flèche+emoji dans la colonne
Cap), `RoadbookBigManeuverCard`/`RoadbookUpcomingRow` (idem, vue focus GPS), et
`RoadbookPDFExporter.drawRow` (emoji dessiné sous le pictogramme/cap de la colonne Heading,
quel que soit le style choisi — pictogramme OU degrés). `RoadbookLandmarkCache`/
`RoadbookLandmarkService` inchangés dans leur fonctionnement, juste leur type de valeur stockée/
retournée (`RoadbookLandmarkInfo?` au lieu de `String?`) — un ancien fichier de cache disque
(format `String?`) ne décode plus et est silencieusement ignoré au premier lancement après cette
mise à jour (repli existant déjà prévu, `try?` sur le decode), le cache se reconstruit tout seul.

## Mini-carte déplaçable + zoom réglable (spec "roadbook-mode", it23quinquies)

⚠️ **Mini-carte SUPPRIMÉE au jalon it28** ("roadbook-remove-minimap", demande explicite) : plus
aucune carte dans le Road Book, portrait comme paysage. Section conservée pour l'historique.

Retour terrain : "zoomé beaucoup plus... qu'on voit les 400 mètres de chaque côté, peut-être
même 300, ou fait que ce paramètre soit changeable. Et cette même map, il faudrait pouvoir la
changer à la volée, comme une fenêtre qui s'affiche par dessus et qu'on peut déplacer".

`RoadbookDraggableMiniMap` (nouveau, enveloppe `RoadbookMiniMapView`) :
- Portée par défaut resserrée à 700 m (`RoadBookConstants.miniMapSpanMetersDefault`, ~350 m de
  chaque côté du point central) — RÉGLABLE par +/- directement sur la mini-carte (jamais un
  réglage caché dans Réglages, ajustement immédiat pendant la lecture), persistée
  (`RideSettingsStore.roadbookMiniMapSpanMeters`, bornée par `miniMapSpanMetersRange`,
  200...1500 m par pas de 100).
- Position déplaçable par glisser (`DragGesture`), persistée en FRACTION (0...1) de la zone
  disponible (`roadbookMiniMapPositionXFraction`/`YFraction`) — JAMAIS en points absolus, pour
  rester cohérente si l'orientation ou la taille d'écran change entre deux sessions. Pendant le
  glisser, un `@State dragTranslation` éphémère pilote la position EN DIRECT
  (`.position(x:y:)`) ; au relâchement, la position finale (clampée pour ne jamais sortir de
  l'écran) est convertie en fraction et écrite dans les réglages persistés, `dragTranslation`
  repart à zéro. Un tap sur les boutons +/- (imbriqués dans la même vue) n'active jamais le
  `DragGesture` par erreur — un `DragGesture` SwiftUI exige un déplacement réel avant de se
  déclencher, un tap sans mouvement ne l'arme jamais.

## Cap en degrés + repères OSM à proximité (spec "roadbook-mode", it23quater)

⚠️ **Remplacé en it27** ("roadbook-visible-landmarks-only") : le repère par manœuvre et son
cache par coordonnée n'existent plus — voir la section "Repères visibles" en fin de fichier.
Conservé pour l'historique des décisions.

Retour terrain avec capture d'un vrai roadbook rallye : "les deux premières colonnes, distance
section et distance cumulée, puis la direction, avec des indications si possible (église,
rond-point...) — est-ce possible d'avoir des infos pertinentes depuis la map ?"

**Cap absolu** (`RoadbookManeuver.headingDegrees`) : bearing du segment SORTANT (juste après le
point de manœuvre), calculé dans `RoadbookExtractor.outgoingHeadingDegrees` — PAS stocké sur
`Checkpoint` lui-même (type partagé avec Ride/`RideMapLibreView`, éviter d'y ajouter un champ
dont ces autres consommateurs n'ont pas besoin). Affiché sous le pictogramme (écran ET PDF, mode
"Degrés" de l'export désormais basé sur ce cap absolu plutôt que sur l'angle RELATIF du virage —
question différente : "quel cap suivre ensuite" plutôt que "de combien tourne-t-on").

**Repères OSM** (`RoadbookLandmark`/`RoadbookLandmarkService`/`RoadbookLandmarkCache`) —
enrichissement BEST-EFFORT, jamais bloquant :
- `RoadbookLandmarkService` interroge Overpass API (OSM public, gratuit, même philosophie que
  `NominatimGeocodingService` déjà utilisé pour la recherche d'adresse — mais Nominatim ne fait
  QUE du géocodage inverse d'adresse, pas une recherche de tags arbitraires à proximité, d'où un
  service Overpass dédié) dans un rayon de `RoadBookConstants.landmarkSearchRadiusMeters` (40 m)
  autour de chaque point de manœuvre. `RoadbookLandmark.bestDescription` (fonction PURE, testée
  sans réseau) choisit le tag le plus pertinent, en 4 paliers : (1) singularités de ROUTE
  (revêtement non goudronné, passage à niveau, pont — information de sécurité/pilotage) ;
  (2) repères visuels FORTS et sans ambiguïté (église, rond-point, ligne électrique, feux) ;
  (3) repères visuels FAIBLES mais utiles pour se diriger à vue (retour terrain : "rajouter des
  maisons, des arbres, des points clés qui permettent de se diriger") — un arbre remarquable
  (`natural=tree`, toujours pertinent, cartographié individuellement dans OSM par nature) ou une
  maison ISOLÉE (`building`, seulement si `RoadbookLandmark.maxBuildingCountForIsolatedHouse`
  bâtiments ou moins trouvés dans le même rayon — au-delà, zone habitée dense, "Maison"
  cesserait d'être un repère distinctif et deviendrait du bruit à chaque virage) ; (4) repli sur
  un nom générique. `RoadBookConstants.landmarkResultLimit` (30) borne le nombre d'éléments
  renvoyés par la requête Overpass elle-même — assez large pour que ce décompte reste fiable
  même si d'autres tags matchent aussi au même endroit.
  Un tag SANS intérêt à aucun palier (`landuse=residential` seul...) n'est jamais retenu.
- `RoadbookLandmarkCache` : cache disque clé PAR COORDONNÉE (arrondie 5 décimales), PAS par
  trace+index comme `RoadbookMapMatchCache` — un repère est une propriété du LIEU, pas de la
  trace ; un changement de seuils roadbook (qui peut changer QUELLES coordonnées deviennent des
  manœuvres) n'invalide jamais un résultat déjà acquis. `RoadbookLandmarkLookup.notCached` vs
  `.cached(nil)` : distingue "jamais interrogé" de "interrogé, rien trouvé" — sans cette
  distinction, un point sans repère serait réinterrogé à chaque ouverture de l'écran.
- `RoadBookTabView.loadLandmarksIfNeeded()` (`.task(id: selectedTrack?.id)`, annulé/relancé
  automatiquement si la trace change) résout les manœuvres SÉQUENTIELLEMENT, jamais en rafale
  concurrente — bonne conduite vis-à-vis d'un service public gratuit partagé, surtout avec
  potentiellement plusieurs dizaines de manœuvres à interroger d'un coup. N'empêche JAMAIS
  l'affichage immédiat des manœuvres elles-mêmes (best-effort, arrive progressivement,
  `landmarks: [UUID: String?]` — clé absente = pas encore résolu).
- Consommé par les 3 surfaces d'affichage (écran table, écran focus GPS, export PDF colonne
  "Note" — remplace la ligne vierge quand un repère est trouvé, la garde en dessous pour une
  note manuscrite complémentaire).

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
réglage de détection dupliqué pour cet onglet. Le map matching Valhalla n'était PAS branché ici
à l'origine (it23) ; il l'est depuis it25 (fix "roadbook-valhalla-route-aware", mécanisme
dupliqué dans `RoadBookTabView` pour rester découplé de `RideSessionManager`, cache disque
partagé avec Ride).

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

## Vue "focus" prochain virage + mini-carte en coin (retour terrain it23ter)

(La mini-carte en coin a été supprimée au jalon it28 ; la vue focus, elle, est inchangée.)

Nouveau retour après it23bis ("le road book est pas mal") : "il faudrait clairement afficher le
prochain virage qui prenne au moins la moitié de l'écran... la map doit être un aperçu, 2 km
autour du point actuel, en bas dans un coin, 15% de l'écran max".

Concerne UNIQUEMENT le mode Assisté GPS — "prochain virage" et "point actuel" n'ont de sens
qu'avec une position réelle à comparer, le mode Classique garde `RoadbookTableView` (table
complète) inchangé, aucune notion de "manœuvre en cours" à mettre en avant dans ce mode-là.

- `RoadbookFocusedView` (nouveau fichier) : la manœuvre EN COURS (`RoadbookBigManeuverCard`,
  pictogramme 120pt + distance 64pt) occupe TOUT l'espace restant une fois les 2 lignes
  suivantes posées (taille intrinsèque, `RoadbookUpcomingRow`) — garantit "au moins la moitié
  de l'écran" sans calcul de fraction explicite, largement plus en pratique. Les 2 manœuvres
  suivantes affichent une distance recalculée DEPUIS LA POSITION ACTUELLE (`cumulativeDistanceMeters`
  de la manœuvre visée moins celle de la manœuvre courante, plus la distance restante live) —
  jamais `partialDistanceMeters` brut, qui donnerait "distance depuis la manœuvre précédente"
  au lieu de "dans combien depuis maintenant". Deux états de repli distincts (jamais le même
  écran vide muet) : pas de position GPS encore acquise vs. trace entièrement parcourue
  (dernière manœuvre déjà dépassée).
- `RoadbookMiniMapView` : nouveau paramètre `spanMeters` (`RoadBookConstants.
  miniMapSpanMeters`, 2000 m) — quand une position live existe, la caméra reste CENTRÉE dessus
  à cette portée fixe (recalculée à chaque position, `updateUIView`), plus jamais la trace
  entière. Sans position (repli), garde l'ancien comportement (cadrer la trace une fois au
  montage) — mieux que rien tant qu'aucun fix n'est connu.
- Positionnement : overlay `ZStack(alignment: .bottomTrailing)` par-dessus `RoadbookFocusedView`
  (jamais un élément de layout qui pousserait le reste, même règle "overlay ne pousse jamais"
  que côté Ride, voir `RideOverlayLayout`), taille `geometry.size.width * 0.36` ×
  `geometry.size.height * 0.15` — le "15% max" demandé est la hauteur, la largeur suit un ratio
  visuellement cohérent (pas un carré strict, une carte est plus lisible en rectangle large).

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

⚠️ **Mini-carte SUPPRIMÉE au jalon it28** ("roadbook-remove-minimap", demande explicite) : plus
aucune carte dans le Road Book, portrait comme paysage. Section conservée pour l'historique.

MapKit léger (comme `CameraPreviewMapView`, Settings/), fichier SÉPARÉ plutôt qu'un paramètre
ajouté à `CameraPreviewMapView` — celle-ci est déjà partagée par 3 écrans Réglages avec un
contrat fixe (spec "translucent-settings-preview-sheets", it15), et ce mini-map a un besoin
légèrement différent (position live optionnelle, mode Assisté GPS uniquement). Toggle
`roadbookMiniMapEnabled` : "utile en debug de fiabilité de la feature et comme filet de
sécurité visuel" (spec) — jamais affiché en mode Roadbook classique (pas de position live à
montrer dans ce mode).

## Détection route-aware + pictogrammes enrichis (spec "roadbook-route-aware-maneuvers", it24)

Retour terrain (point 0) : le toggle Valhalla (Réglages > Avancé) n'avait aucun indicateur de
service RÉELLEMENT utilisé — voir `Ride/CLAUDE.md` section "Indicateur de service de routage
actif" pour `RoutingActivityMonitor`, hors périmètre RoadBook mais découvert/corrigé dans la
même itération.

**Filtrage type de manœuvre (point 1)** — root cause d'un bug terrain ("une courbe progressive
sur le même axe déclenche un événement à tort") : `ValhallaMapMatchingService` (déjà branché
depuis it20) ne regardait QUE `begin_shape_index`, jamais le TYPE de manœuvre — `.continueStraight`/
`.becomes` (la route continue/change de nom SANS virage réel) devenaient donc des événements
roadbook comme n'importe quel vrai virage. Fix : `ValhallaManeuverType.roadbookTier` (Nav/
ValhallaManeuverType.swift — réutilise l'énumération déjà vérifiée contre la doc Valhalla en
it21) filtre EN AMONT (`ValhallaMapMatchingService.intermediateManeuvers`) — `nil` = pas une
vraie décision de conduite, écarté avant même d'atteindre `RoadbookAnalyzer`. `bearing_before`/
`bearing_after` (demandés par la fiche it24) délibérément PAS décodés — vérifiés ABSENTS du
schéma réel des manœuvres Valhalla dès it21 : la direction vient de `roadbookDirection` (dérivée
du TYPE lui-même), plus fiable que l'angle géométrique bruité au point.

**Nouveaux paliers `RoadbookTier`** : `.roundabout`/`.fork`/`.merge` (map matching UNIQUEMENT,
jamais par angle géométrique seul) — `.uTurn` détecté par map matching réutilise le palier
EXISTANT, comme demandé ("à conserver tel quel"). `Checkpoint.roundaboutExitCount: Int?` (champ
séparé, même patron que `direction`) porte le rang Valhalla (`roundabout_exit_count`) pour le
pictogramme. `MapMatchedManeuver` (coordonnée + type + exit count) remplace le simple
`[CLLocationCoordinate2D]` partout (service/cache/analyzer) — format de cache disque CHANGÉ,
dégradation propre (`RoadbookMapMatchCache`, un ancien fichier it20 échoue simplement à décoder,
jamais un crash, recalculé au prochain accès).

**Pictogrammes dédiés (point 2)** — `RoadbookPictogramGeometry.swift` (géométrie PURE,
`roundaboutExitAngleDegrees`/`skippedExitRanks`, 45°/sortie, convention visuelle FIXE car
Valhalla ne fournit que le RANG de sortie jamais la géométrie réelle) + `RoadbookPictograms.swift`
(SwiftUI Canvas — `RoadbookRoundaboutPictogram`/`RoadbookForkPictogram`/`RoadbookMergePictogram`,
teinte d'accent PARTAGÉE avec le PDF via `RoadBookConstants.pdfAccentColorRGB`) +
`RoadbookManeuverIcon` (point d'entrée UNIQUE table/vue focalisée, bascule dessin dédié ou repli
SF Symbol). `RoadbookPDFExporter.drawPictogram` bascule pareil côté Core Graphics
(`drawRoundaboutPictogram`/`drawForkPictogram`/`drawMergePictogram`, MÊME géométrie partagée) —
écran et PDF affichent toujours exactement le même pictogramme pour une manœuvre donnée.
`RoadbookTier.systemImageName` (repli SF Symbol générique) ne sert plus QUE aux pins carte
(`RideMapLibreView`, trop petits pour un pictogramme dessiné).

**Liste de POI étendue à 50 tags OSM (point 3)** — [SUPPRIMÉ en it27, voir "Repères visibles"] `RoadbookLandmarkCategory` passe à
`CaseIterable` (32 catégories), `RoadbookLandmark.bestLandmark` réécrit autour d'une table
déclarative de `Matcher` (tier + catégorie + fonction de correspondance) plutôt que des `if let`
empilés à la main — ajouter un tag revient à ajouter UNE ligne. Priorité INCHANGÉE pour les
catégories déjà existantes (it23quater/it23sexies) ; les nouvelles sont classées par ANALOGIE
avec l'esprit de chaque palier (la fiche donne des groupes THÉMATIQUES, pas un ordre de
priorité — choix assumé, documenté dans `RoadbookLandmark.swift`). `RoadbookLandmarkService` :
la plupart des nouvelles familles de tags sont interrogées EN BLOC côté Overpass
(`["tourism"]`/`["historic"]`/`["natural"]`/`["man_made"]`/`["shop"]`/`["leisure"]`/
`["barrier"]`/`["railway"]`) plutôt que valeur par valeur — un futur ajout ne touchera que
`RoadbookLandmark`, jamais ce fichier. `highway=speed_camera` explicitement HORS PÉRIMÈTRE
(même sujet que les alertes trafic TomTom, à trancher séparément).

Non vérifié en conditions réelles (pas de device physique dans cet environnement) : rendu visuel
des 3 pictogrammes dessinés, pertinence réelle des nouveaux POI sur un vrai trajet, indicateur
de service de routage en conditions de coupure réseau réelle — logique couverte par les tests
unitaires, à confirmer par le pilote (voir checklist manuelle du commit).

## Refonte UI/UX (spec "roadbook-ui-redesign", it25)

Retour terrain avec captures à l'appui : aucun pictogramme visible, liste illisible (texte petit
uniforme), mode paysage cassé (mini-carte en bande illisible, texte "Legal"/distance/palier qui
chevauchent la tab bar). Quatre points, tous scopés à CET écran (jamais la carte Ride/le reste
de l'app).

**Point 0 — Palette jour/nuit** (`RoadbookPalette.swift`) : `RoadbookPalette` (`.paper`/`.night`,
RÉSOLU) DISTINCT de `RoadbookPaletteSetting` (`.automatic`/`.paper`/`.night`, réglage UTILISATEUR,
Réglages > Apparence > "Palette Road Book", persisté `RideSettingsStore.roadbookPaletteSetting`).
`RoadbookPaletteResolver.resolve(override:now:coordinate:calendar:)` — un override explicite
gagne toujours, sinon `SolarTimeCalculator.sunriseSunset(for:coordinate:)` (formule d'équation du
lever de soleil, ±10-15 min, ÉQUATION DU TEMPS IGNORÉE — largement suffisant pour une bascule de
palette visuelle, jamais un usage scientifique) décide selon la position GPS actuelle ; sans
position (permission refusée, pas de fix, ou cas polaire) repli honnête sur une heuristique
horaire simple (`RoadBookConstants.paletteFallbackDayStartHour/EndHour`, 7h-20h). `RoadBookTabView`
recalcule `resolvedPalette` à l'apparition, à chaque changement de position/réglage, ET toutes les
`paletteReevaluationIntervalSeconds` (5 min, `Timer.publish`) — sans ce filet, un Road Book ouvert
à cheval sur le coucher du soleil resterait figé sur la palette de l'ouverture. Appliqué à la
racine SEULEMENT (`NavigationStack` de `RoadBookTabView`) via `.environment(\.colorScheme,...)`
(pilote `.primary`/`.secondary`/les contrôles natifs) + `.environment(\.roadbookPaletteColors,...)`
(nouvel `EnvironmentKey`, teintes crème/surface/filet PROPRES — un `Color(.systemBackground)` en
mode clair standard est blanc pur, pas crème) + `.background(...ignoresSafeArea())` (jamais
`.ignoresSafeArea()` sur le contenu lui-même, qui casserait le respect de la tab bar).

**Point 1 — Liste scrollable complète (mode Assisté GPS)** : `RoadbookFocusedView.upcoming` ne
tronque plus à `.prefix(2)` — TOUTES les manœuvres restantes, dans un `ScrollView`/`LazyVStack`
sous la carte hero (qui garde sa hauteur fixe ~50% de l'écran en portrait, `focusedHeroHeightFraction`).

**Point 2 — Layout paysage dédié** : `@Environment(\.verticalSizeClass)` (`.compact` = paysage
sur iPhone, seul device family ciblé) pilote DEUX bascules indépendantes :
- Hero : `RoadbookBigManeuverCardLandscape` (HStack, pictogramme à gauche/distance à droite,
  polices réduites) remplace le portrait simplement compressé — hauteur FIXE et compacte
  (`focusedHeroLandscapeHeight`, PAS une fraction de l'écran comme en portrait : sur un écran
  deux fois moins haut, la même fraction n'aurait laissé presque rien à la liste). Root cause du
  bug terrain "634 m/Virage prononcé qui chevauchent la tab bar" : les mêmes tailles de police
  qu'en portrait débordaient de l'espace disponible, bien plus court en paysage.
- Mini-carte : `RoadbookLandscapeMiniMap` (taille FIXE en points, ancrée en coin via
  `.overlay(alignment: .bottomTrailing)`) remplace `RoadbookDraggableMiniMap` (glisser/zoomer,
  réservé au portrait où il fonctionne déjà, "ça marche" confirmé it24) — root cause du bug
  "mini-carte réduite à une bande illisible" : `RoadbookDraggableMiniMap.mapSize` est une
  FRACTION de `containerSize` (0.4×largeur, 0.16×hauteur), qui sur une hauteur de conteneur deux
  fois plus petite en paysage produit un bandeau écrasé. Non déplaçable/zoomable en paysage
  (simplicité assumée plutôt qu'étendre le système de glisser à une 2e orientation sans device
  pour vérifier) ; MASQUÉE entièrement si le conteneur est trop court
  (`miniMapLandscapeMinContainerHeight`, ex. clavier ouvert) — demande explicite : "masquée...
  si le format ne permet pas un rendu propre, pas de compromis à moitié cassé".

**Point 3 — Hiérarchie visuelle (Roadbook classique)** : `RoadbookTableView` extrait désormais la
PREMIÈRE manœuvre en `RoadbookHeroRow` (esprit carte, même langage visuel que la carte du mode
Assisté GPS, ~3× plus imposante que les lignes suivantes) — données INCHANGÉES (partielle/
cumulée/cap), juste réorganisées autour de cette hiérarchie (partielle en gros chiffre dominant,
comme la distance restante de `RoadbookBigManeuverCard`). Les lignes suivantes
(`RoadbookTableRow`) gagnent des polices agrandies sur toute la ligne (ex. cumulée `.subheadline`
→ `.title3`, pictogramme 22pt → 30pt, tier label `.subheadline` → `.headline`) — priorité
lisibilité (gants, plein soleil) plutôt que densité. Les pictogrammes RÉELS it24
(`RoadbookManeuverIcon`) étaient déjà branchés depuis it24 (pas un bug de branchement trouvé ici)
— seule leur TAILLE était petite (22pt) ; s'ils continuent à sembler "génériques" sur le terrain,
c'est très probablement que la trace testée n'a déclenché aucun rond-point/fourche/fusion réel
via map matching Valhalla (voir it24 point 1 — un simple virage classique retombe légitimement
sur la flèche générique tournée, ce n'est pas un défaut de rendu).

**Point 4 — Badge service de routage** : `RoutingServiceBadge` (RoadBookTabView.swift, `private`)
réutilise `RoutingActivityMonitor.shared` (it24, point 0) — même donnée que
`ValhallaSettingsView`, affichée en PLUS ici (jamais une 2e source de vérité), à côté du Picker
"Mode de lecture" (même ligne, aucun coût de hauteur supplémentaire — précieux en paysage).

Non vérifié visuellement (pas de device physique dans cet environnement, demande explicite de la
fiche pour cette itération en particulier vu son caractère "purement visuel") : bascule jour/nuit
réelle, rendu paysage sur device réel, ratio de taille effectif du premier élément, lisibilité
gants/plein soleil — logique de résolution (palette/paysage/hiérarchie) couverte par les tests
unitaires, le rendu visuel reste entièrement à valider par le propriétaire.

### Vérification sur device physique réel (même session, plus tard dans it25)

Un iPhone 13 Pro réel (device de référence du projet) a finalement été branché et rendu
accessible EN COURS de session — captures d'écran obtenues via `pymobiledevice3 developer dvt
screenshot` (élevé en privilèges via `osascript ... with administrator privileges`, popup Touch
ID natif macOS plutôt qu'un mot de passe en clair dans le terminal), `devicectl` pour build/
install/launch. Confirmé visuellement sur device réel : palette sombre automatique correcte
(après le coucher du soleil réel au moment du test), badge Valhalla visible et vert (point 4),
liste scrollable au-delà de 2 éléments en mode Assisté GPS (point 1), hiérarchie ~4× en Roadbook
classique (point 3, mesuré directement sur la capture). PAS vérifié dans cette session : rendu
paysage (nécessite une rotation physique, pas simulable via `devicectl device orientation` —
capacité refusée explicitement pour un device réel, "not supported by this device"),
pictogrammes rond-point/fourche/fusion (aucun rencontré sur la trace testée). Pas
d'automatisation tactile disponible : chaque navigation dans l'app a nécessité un tap réel du
propriétaire, `devicectl`/`pymobiledevice3` ne permettent que build/install/launch/screenshot/
logs, jamais un geste simulé sur un device physique.

## Sens de parcours inversé cassé en Assisté GPS (fix "roadbook-reversed-direction-broken")

Retour terrain : "Road Book Assisté GPS fonctionne normalement en sens A→B, mais affiche
immédiatement 'Toutes les manœuvres de cette trace ont été passées' en sens inversé, alors que
le trajet vient de commencer."

Root cause confirmée par lecture de code (pas de correction à l'aveugle) : `RoadBookTabView`
n'appliquait JAMAIS `GPXTrack.reordered(using:)` (spec "per-track-settings", it13,
`TrackRideSettings.isReversed`) — contrairement à `RideView.rideContent`
(`track.reordered(using: trackRideSettings.settings(for: track.id))`). `selectedTrack`
retournait donc TOUJOURS la trace dans l'ordre CANONIQUE stocké, quel que soit le sens choisi
par l'utilisateur pour cette trace. Les trois consommateurs (`RoadbookExtractor.maneuvers`,
`triggerMapMatchingIfNeeded`, la projection GPS de `liveProgress` via `TrackProjector`)
travaillaient donc tous sur l'ordre canonique. En sens inversé, la position physique de départ
(proche du point B canonique) se projette sur une distance cumulée déjà proche du TOTAL de la
trace — supérieure à celle de TOUTES les manœuvres (elles-mêmes mesurées en ordre canonique,
petites valeurs près de A) — d'où "tout est déjà passé" dès le premier point.

**Important** : l'onglet Ride (`RideSessionManager`) n'était PAS concerné, ni avant ni après le
branchement route-aware du Road Book (`00325fc`) — `RideView.swift` réordonne la trace EN AMONT,
avant tout appel à `session.start(track:)`/`switchMode(track:)`, donc son propre map matching et
ses checkpoints ont toujours travaillé sur l'ordre effectivement affiché. Le bug était strictement
localisé à `RoadBookTabView`.

Fix : `RoadBookTabView` reçoit `@EnvironmentObject private var trackRideSettings:
TrackRideSettingsStore` (déjà injecté à la racine par `GPXlibreApp`, aucune plomberie
supplémentaire nécessaire). `selectedTrack` (utilisé PARTOUT dans ce fichier — extraction,
map matching, projection GPS, mini-carte) devient une trace DÉRIVÉE : `rawSelectedTrack.map {
$0.reordered(using: trackRideSettings.settings(for: $0.id)) }` — `rawSelectedTrack` (la trace
canonique, préexistante sous ce nom) ne sert plus qu'à la comparaison d'id dans le picker de
trace. ⚠️ Ce fix affirmait aussi que `RoadbookMapMatchCache` (clé = `track.id`) restait valide
quel que soit le sens : FAUX, corrigé en it26 ("mapmatch-cache-direction-aware") — vrai pour les
coordonnées, pas pour les TYPES de manœuvre (gauche/droite, rang de sortie de rond-point),
propres au sens de parcours. Clé désormais `GPXTrack.traversalKey`, voir section it26.

Tests : `RoadbookReversedDirectionTests` (nouveau fichier) reproduit le pipeline exact de
`RoadBookTabView` (`reordered(using:)` → `RoadbookExtractor.maneuvers` → `TrackProjector.project`
→ `RoadbookLiveProgress.nextManeuver`) plutôt que d'instancier la vue SwiftUI elle-même (non
testable directement, mêmes contraintes qu'ailleurs dans ce module) — un test positif (sens
inversé, première manœuvre bien à venir), un test de non-régression (sens normal inchangé), et un
test qui reproduit VOLONTAIREMENT le mécanisme du bug d'origine (manœuvres calculées sur l'ordre
canonique + projection au point de départ physique du sens inversé → `nil`) comme garde-fou si
un futur changement réintroduisait `rawSelectedTrack` par erreur sur l'un des trois usages.

Vérification manuelle terrain (le trajet test refait en sens inversé, confirmant un comportement
symétrique au sens normal) : **pas encore faite** — à confirmer par le propriétaire au prochain
test roulant, aucun device physique disponible pour reproduire ce scénario précis dans cette
session.

## Écran maintenu allumé (spec "roadbook-keep-screen-awake", it25)

Retour terrain pendant la vérification device ci-dessus : "l'écran doit rester allumé dans road
book, il a tendance à s'arrêter". `RoadBookTabView` active `IdleTimerCoordinator.setActive(true,
for: .roadBook)` à l'apparition, `false` à la disparition — INCONDITIONNEL (pas de réglage séparé
comme `RideSettingsStore.keepScreenAwakeInRide`, contrairement à Ride) : un roadbook papier ne
s'éteint jamais tout seul, esprit assumé pour cet écran précisément.

`IdleTimerCoordinator` (Services/, nouveau) : `UIApplication.shared.isIdleTimerDisabled` était
auparavant écrit DIRECTEMENT par `RideSessionManager` (`stop()`/`applyIdleTimerSetting()`) — un
flag global unique. Root cause évitée avant même d'exister : si Road Book avait fait de même
directement, quitter le Road Book pendant qu'un Ride tourne toujours en arrière-plan (le Ride
n'est PAS lié à la visibilité de l'onglet, voir `RideSessionManager.isActive`) aurait coupé à tort
le maintien réveillé du Ride. `IdleTimerCoordinator` tient un `Set<IdleTimerReason>` plutôt qu'un
flag — le timer ne se réactive que quand PLUS AUCUNE raison n'est active. `RideSessionManager`
passe maintenant par ce coordinateur au lieu d'écrire `UIApplication.shared` directement.

## Itération 26 — précision, demi-tours, checkpoints de commune, saut carte

Causes réelles identifiées en rejouant les algorithmes sur les traces RÉELLES du propriétaire
(copiées depuis l'iPhone en lecture seule, voir CLAUDE.md racine "Device de référence") — pas
supposées. Détail des trois premiers points côté détection : Ride/CLAUDE.md, section it26.

- **Cache par sens** ("mapmatch-cache-direction-aware") : `RoadBookTabView.task(id:)` indexé sur
  `selectedTrack?.traversalKey` (le sens peut changer depuis Réglages de trace pendant que
  l'onglet reste vivant dans le TabView, sans que `id` ne change).
- **Position exacte du carrefour** ("roadbook-maneuver-position-from-route") : `RoadbookExtractor`
  lit `Checkpoint.cumulativeDistanceMeters(using:)` — la distance interpolée du VRAI carrefour
  Valhalla, plus celle du point GPX voisin. `Checkpoint.id` est dérivé de cette position
  (décimètres), plus de `sourcePointIndex` seul.
- **Plus de faux demi-tours** ("roadbook-no-false-uturn") : nouveau palier `.veryHard`
  "Virage très serré" (flèche à 140°, avec son sens) ; `.uTurn` seulement si la trace repart sur
  la même route. Réglage "Très serré dès" (ex-"Demi-tour dès", même clé persistée).
- **Saut carte** ("roadbook-jump-to-map-sticky") : taper une étape met la carte Ride en mode
  étape, sans minuteur, jusqu'à "Me recentrer" — voir `RideCameraFollowPolicy`.

### Checkpoints d'entrée de commune (point 3) — SUPPRIMÉS en it27

Limites administratives (`admin_level=8`) = donnée invisible sur le terrain : remplacées par les
repères visibles ci-dessous (l'entrée de village n'apparaît plus que via un vrai panneau
d'agglomération). `RoadbookLocality*` supprimés, `RoadbookEntry` déplacé dans
`RoadbookVisibleLandmarks.swift`. Rien d'autre dans l'app n'utilisait ces données (vérifié).

## Repères visibles (fix "roadbook-visible-landmarks-only", it27)

⚠️ Étendu au jalon it28 : catalogue configurable, services, chargement par tronçons — voir la
section "Jalon it28" ci-dessous, qui prime en cas de divergence.

Principe produit (fiche propriétaire) : **un repère n'apparaît que si le conducteur peut le VOIR
en roulant**. Jamais une limite de commune, un lieu-dit sans panneau, un commerce, un arbre.

- **Catégories autorisées** — `RoadbookLandmarkCategory` (RoadbookLandmark.swift), seule liste ;
  `RoadbookLandmark.classify(tags)` (pur) renvoie `nil` pour tout le reste. Trois groupes :
  panneaux (entrée d'agglomération `city_limit`/`FR:EB10` — sortie ignorée —, stop,
  cédez-le-passage, feux, passage à niveau), au sol (passage piéton MARQUÉ, ralentisseur, pont,
  tunnel ; le rond-point est déjà une manœuvre, jamais dupliqué), bâtiments/ouvrages (église/
  chapelle/clocher, mairie, station-service, château d'eau, moulin, calvaire/oratoire, château/
  phare/tour). Libellé : nom OSM, sinon `genericLabel` ; pont/tunnel : `bridge:name`/`tunnel:name`
  seulement (le `name` d'un pont est presque toujours celui de la route → "Route de Kembs").
- **Source** : UNE requête Overpass le long de la trace (`RoadbookLandmarkOverpassService`,
  polyligne `around:` échantillonnée 250 m, plafond 600 points) + chaussées porteuses des nœuds
  posés sur la route (`way(bn.onroad)["highway"]; out geom;`) → `roadAxes` (axe de la chaussée
  au nœud) et sens réel d'un `direction=forward/backward`. 3 essais (5 s, 15 s).
- **Cache** : `RoadbookLandmarkDataCache`, clé `track.id` (candidats = géométrie seule), vide mis
  en cache, échec jamais. La SÉLECTION, elle, dépend du sens : refaite hors main thread à chaque
  `traversalKey`/changement de manœuvres (`RoadBookTabView.refreshLandmarkSelection`).
- **Sélection** (`RoadbookLandmarkSelector.select`, pur) : placement par passage
  (`TrackProjector.passes`) dans le rayon de visibilité de la catégorie ; élément posé sur une
  chaussée gardé seulement si l'axe de cette chaussée est à ±30° de la trajectoire d'arrivée
  (cap sur 30 m) — sinon c'est le stop/passage piéton d'une rue LATÉRALE (bruit constaté sur les
  vraies traces) ; panneau orienté : vu de dos (> 80° de la face) ignoré ; côté gauche/droite
  seulement pour ce qui est à côté de la route (≥ 4 m latéral), jamais pour ce qui la traverse ;
  à ≤ 40 m d'un virage → rattaché au virage (`attached`, le plus prioritaire) ; sinon ligne dédiée
  (`standalone`), fusion < 150 m, au plus 1 par tronçon entre deux virages, priorité panneau >
  au sol > bâtiment puis ordre de déclaration puis distance latérale.
- **Jamais un `Checkpoint`** ni une manœuvre : numérotation inchangée, `RoadbookEntry.merge`
  intercale les lignes dans la table, la liste Assisté GPS (distance depuis la position), le
  paysage et le PDF (pictogramme `RoadbookLandmarkIcon`/emoji par catégorie).
- **Repli "entrée de localité"** par route `maxspeed=50`/`FR:urban` : implémenté mais désactivé
  (`RoadBookConstants.landmarkUrbanEntryFallbackEnabled = false`).
- **Constantes** : toutes dans `RoadBookConstants` (`landmarkVisibilityRadiusMeters` par
  catégorie, `landmarkGroupPriority`, `landmarkMergeMeters`, `landmarkMaxPerSegment`,
  `landmarkJunctionRadiusMeters`, `landmarkRoadAlignmentToleranceDegrees`,
  `landmarkSignFacingToleranceDegrees`, `landmarkApproachMeters`, `landmarkSideMinOffsetMeters`).
- Validé sur deux traces réelles de l'iPhone avec de vraies réponses Overpass (test temporaire,
  non commité) : wahlbach-moulin 191 candidats → 18 lignes + 10 repères de virage.

## Jalon it28 — catalogue configurable, services, progression (v0.0.28-roadbook-stable)

- **Catalogue** : `RoadbookLandmarkCategory.definition` réunit, pour chaque catégorie, famille,
  libellé, emoji, sélecteurs Overpass et règle de reconnaissance. `RoadbookLandmark.classify`
  prend la PREMIÈRE catégorie du catalogue qui reconnaît l'élément : l'ordre des `case` compte
  (antenne avant tour). Familles : Panneaux, Infrastructure, Bâtiments, Services (activées par
  défaut, `RoadBookConstants.landmarkDefaultEnabledCategories`) et Autres (désactivée). Le passage
  piéton est retiré, même quand il est marqué.
- **Services** (carburant, recharge) : rayon de détour de 250 m. Ils suivent une voie à part dans
  `RoadbookLandmarkSelector` : jamais rattachés à un virage, jamais soumis au 1 repère/tronçon,
  seuls leurs doublons sont fusionnés. `RoadbookLandmarkInfo.lateralDistanceMeters` porte la
  distance à la trace, affichée au-delà de 30 m ("Total à droite, 120 m").
- **Réglages** : `RoadbookLandmarkSettingsView` (dans Settings/), persistance
  `RideSettingsStore.roadbookLandmarkCategories` (liste de rawValue).
- **`RoadbookLandmarkLoader`** : seul endroit qui décide QUAND télécharger. Cache par trace avec
  `fetchedCategories` (format `index-v2.json`). Une catégorie désactivée est filtrée sans
  requête ; une catégorie jamais téléchargée est demandée seule, en complément. Le
  téléchargement se fait par tronçons de 8 km (barre N/M), les repères apparaissent au fur et à
  mesure. En cas d'échec, les tronçons reçus sont gardés et "Réessayer" reprend au tronçon en
  échec. Hors ligne (`NetworkMonitor`), aucune requête n'est faite. Seam de test : `fetchChunk`,
  `isOnline`, cache à `directoryOverride`.
- **Overpass public** : 504 intermittents mesurés (un tronçon sur quatre, accepté à l'essai
  suivant), d'où 4 essais par tronçon. Deux autres instances testées ne font pas mieux.
- **Garde-fou** : `RoadbookStableRegressionTests` (trace + réponse Overpass de référence,
  Road Book attendu ligne par ligne, sens A→B, B→A et route-aware). Voir "Jalon stable" dans le
  CLAUDE.md racine.

