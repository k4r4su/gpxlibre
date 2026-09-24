# TODO

## Itération bugfix — repères du Road Book = ce que le conducteur voit — v0.0.27

Commit `roadbook-visible-landmarks-only` (détail : RoadBook/CLAUDE.md, "Repères visibles").
Checklist manuelle (trace "wahlbach-moulin-bas-test-gpx", sens inversé comme sur l'iPhone) :
- [ ] Plus aucune ligne "entrée de commune" issue d'une limite administrative.
- [ ] Hundsbach : une ligne "Hundsbach" avec le panneau d'agglomération, du bon côté.
- [ ] Églises/calvaires/mairie proches de la route : présents, avec "à gauche"/"à droite" cohérent.
- [ ] Aucun stop/cédez-le-passage/passage piéton d'une rue latérale en ligne droite.
- [ ] Ponts : libellé "Pont" (jamais le nom de la route).
- [ ] Jamais deux repères dans le même tronçon entre deux virages ; aucun repère ne décale la
      numérotation des manœuvres.
- [ ] Même contenu dans la table, le mode Assisté GPS (countdown), le paysage et le PDF.
- [ ] Mode avion à la première ouverture d'une nouvelle trace : Road Book normal, sans repères.

Identifié, NON traité : dépend d'OSM — un village sans panneau `city_limit` cartographié n'aura
pas de ligne d'entrée (repli 50 km/h disponible derrière `landmarkUrbanEntryFallbackEnabled`).

## Itération corrective — fiabilité des checkpoints du Road Book

Commits `roadbook-turn-angle-from-heading-chords` et `roadbook-valhalla-road-change-and-debug-dump`
(détail : Ride/CLAUDE.md, dernière section). Checklist manuelle (même trace
"wahlbach-moulin-bas-test-gpx", sens inversé comme sur l'iPhone) :
- [ ] Vers 20,5 km : UN seul checkpoint, "Virage fort" à gauche, cap ~270° (plus de 0°).
- [ ] Vers 20,8 km : plus aucun checkpoint (ligne droite).
- [ ] Croisements de chemins forestiers/sentiers où la trace va tout droit : aucun checkpoint.
- [ ] Rond-points et vraies fourches toujours présents.
- [ ] Nombre de checkpoints nettement réduit (301 au lieu de 436 sur les 12 traces de l'iPhone).
- [ ] Premier affichage d'une trace : le cache Valhalla est recalculé (format changé), les
      manœuvres route-aware réapparaissent après quelques secondes.
- [ ] Réglages > Roadbook : la fenêtre "après" est encore à 60 m sur l'iPhone (valeur enregistrée
      avant) — revenir à "Seuils standard"/40 m si les virages paraissent décalés.

## Itération 26 (précision du Road Book, checkpoints villages, saut carte) — v0.0.26

Commits : `mapmatch-cache-direction-aware` (trouvé en route : types Valhalla gauche/droite
réutilisés tels quels en sens inverse), `roadbook-maneuver-position-from-route` (point 1),
`roadbook-no-false-uturn` (point 2), `roadbook-jump-to-map-sticky` (point 4),
`roadbook-locality-checkpoints` (point 3). Détails et causes réelles : Ride/CLAUDE.md et
RoadBook/CLAUDE.md, sections it26. Les points 1/2/3 ont été validés sur les traces RÉELLES du
propriétaire (copiées depuis l'iPhone en lecture seule) et, pour le point 3, avec de vraies
réponses Overpass.

Checklist manuelle restant à faire par le propriétaire :
- [ ] Trajet réel connu : l'annonce tombe au niveau du vrai carrefour (point 1).
- [ ] Trajet avec un virage très serré / une épingle : jamais annoncé "Demi-tour" (point 2).
- [ ] Trajet traversant plusieurs villages, en A→B PUIS en B→A : checkpoints dans le bon ordre
      (point 3) — la version installée sur l'iPhone le 24/09 ne contient PAS encore ce point.
- [ ] Tap sur 10 étapes différentes du Road Book : la carte arrive au bon endroit à chaque fois
      et y reste ; "Me recentrer" ramène sur le GPS (point 4).
- [ ] Première ouverture après mise à jour : les caches map matching sont recalculés (format
      changé), vérifier que les manœuvres route-aware réapparaissent.

Identifié, volontairement NON traité (hors périmètre de la fiche) :
- **Téléports GPS enregistrés** : "Travail maison fin" contient 5 allers-retours entre deux
  positions à 290 m en < 16 s (vitesses de 170 à 1000 km/h). Ce sont de vrais retours sur le
  même tracé, donc encore classés "demi-tour" par la nouvelle règle. Piste : filtrer les sauts
  à vitesse impossible à l'enregistrement (RideSessionManager) et/ou à l'import.
- **Demi-tour de départ/arrivée** : ignoré dans les 200 m (stationnement) ; un vrai demi-tour de
  parcours dans ces 200 m serait donc aussi ignoré — accepté.
- **Aller-retour : carrefour à < 60 m du point de demi-tour** : les deux passages sont contigus,
  fusionnés en un seul candidat par `TrackProjector.passes` — une des deux manœuvres disparaît.
- **Overpass public** (checkpoints de commune it26, repères visibles depuis it27) : l'instance renvoie par intermittence 504/429
  (constaté plusieurs fois pendant l'itération). 3 essais puis abandon propre, nouvel essai à
  la prochaine ouverture. Si ça reste fréquent sur le terrain : auto-héberger Overpass sur le
  NAS (déjà envisagé pour Photon, voir Nav/CLAUDE.md).
- **Signature Xcode** : `project.yml` déclare `DEVELOPMENT_TEAM: V9Q4V3W2RZ`, mais le build device
  ne signe qu'avec l'équipe 5X72C94C94 (celle du compte Xcode du propriétaire, qui réécrit
  `project.pbxproj` localement à chaque build GUI). Décision au propriétaire : mettre à jour
  `project.yml` si V9Q4V3W2RZ n'est plus utilisée.

## Itération 25 (refonte UI/UX du Road Book)

Retour terrain avec captures à l'appui, sur la livraison it24 : "aucun pictogramme visible,
liste illisible, mode paysage cassé". Quatre points, tous scopés à l'écran Road Book (jamais la
carte Ride/le reste de l'app) : (0) palette jour/nuit façon roadbook papier (auto au lever/
coucher du soleil réel + forçage manuel) ; (1) liste scrollable complète en mode Assisté GPS
(plus de limite à 2 éléments) ; (2) layout paysage dédié (hero horizontal compact + mini-carte
en coin fixe, plus de chevauchement de la tab bar) ; (3) hiérarchie visuelle du Roadbook
classique (premier élément ~3× plus grand, texte agrandi partout, pictogrammes it24 réutilisés
à plus grande taille) ; (4) badge de service de routage actif visible sur l'écran lui-même.

- **`feat:"roadbook-ui-redesign"`** : `RoadbookPalette.swift` (nouveau — `RoadbookPalette`/
  `RoadbookPaletteSetting`/`RoadbookPaletteResolver`/`SolarTimeCalculator`/
  `RoadbookPaletteColors`), `RoadbookLandscapeMiniMap.swift` (nouveau), `RoadbookFocusedView.swift`
  (liste complète + layout paysage dédié), `RoadBookTabView.swift` (application de la palette,
  bascule paysage de la mini-carte, hero row classique, badge de routage),
  `RideSettingsStore.roadbookPaletteSetting` (Réglages > Apparence). Voir RoadBook/CLAUDE.md
  section "Refonte UI/UX" pour le détail complet, dont les root cause identifiées des bugs
  terrain (mini-carte en bande illisible = fraction de hauteur sur un conteneur 2× plus court ;
  texte qui chevauche la tab bar = mêmes tailles de police qu'en portrait débordant d'un écran
  2× moins haut).

Checklist manuelle restant à faire par le propriétaire (pas de device physique dans cet
environnement, demande EXPLICITE de la fiche pour cette itération vu son caractère purement
visuel) : bascule automatique jour/nuit + forçage manuel (2 modes × 2 orientations) ; scroll
jusqu'au dernier événement sur une trace 20+ changements ; rotation portrait→paysage sans rien
de coupé/chevauché ; ratio de taille réel du premier élément en Roadbook classique ; pictogramme
distinctif rond-point/fourche/demi-tour visible dans les 2 modes et 2 palettes ; badge de service
cohérent avec Réglages au même instant.

**Suite, même session** : un iPhone 13 Pro réel a été branché et rendu accessible (voir
RoadBook/CLAUDE.md, "Vérification sur device physique réel") — confirmé visuellement sur device :
palette sombre auto correcte, badge Valhalla visible, liste scrollable (+1 à +6 vus), hiérarchie
~4× en Roadbook classique. Paysage et pictogrammes rond-point/fourche pas rencontrés faute de
rotation physique/trace adaptée testée. Retour terrain additionnel pendant ce test : "l'écran
doit rester allumé dans road book, il a tendance à s'arrêter" →
**`fix:"roadbook-keep-screen-awake"`** : nouveau `IdleTimerCoordinator` (Services/, ensemble de
raisons actives plutôt qu'un flag `UIApplication.shared.isIdleTimerDisabled` unique) — évite
qu'un Ride actif en arrière-plan perde son maintien réveillé quand on quitte le Road Book, et
vice-versa. `RoadBookTabView` l'active inconditionnellement tant que l'écran est affiché.

## Itération 24 (roadbook route-aware + diagnostic Valhalla)

Trois points indépendants : (0) diagnostic + indicateur de service de routage actif, retour
terrain "aucun moyen de confirmer à l'œil quel service répond réellement" ; (1) détection de
virage route-aware via filtrage du type de manœuvre Valhalla, root cause du bug "une courbe
progressive sur le même axe déclenche un événement à tort" ; (2) pictogrammes enrichis
(rond-point avec sortie surlignée, fourche en Y, fusion/bretelle) ; (3) liste de tags OSM
étendue à 50 pour l'enrichissement visuel du roadbook.

- **`feat:"routing-active-service-indicator"`** : `RoutingActivityMonitor` (Ride/) — dernier
  service ayant EFFECTIVEMENT répondu à une requête de routage réelle, affiché dans Réglages >
  Avancé > Routage Valhalla ("Valhalla"/"OSRM (repli)"/"Aucune requête récente" + heure).
  Vérification technique préalable : `RoutingProviderResolver` existait déjà (it20), confirmé
  réellement câblé + un vrai appel réseau vers `valhalla.zim.ovh` (401/Basic Auth attendu, sans
  identifiants disponibles dans cet environnement). Voir Ride/CLAUDE.md.
- **`feat:"roadbook-route-aware-maneuver-filtering"`** : `ValhallaManeuverType.roadbookTier`/
  `roadbookDirection` filtrent les manœuvres de map matching par TYPE (écarte `.continueStraight`/
  `.becomes`) plutôt que d'accepter toute manœuvre intermédiaire comme avant it24 — nouveaux
  paliers `RoadbookTier.roundabout`/`.fork`/`.merge`, `Checkpoint.roundaboutExitCount`. Format de
  cache `RoadbookMapMatchCache` changé (dégradation propre sur un ancien cache it20). Voir
  RoadBook/CLAUDE.md section "Détection route-aware".
- **`feat:"roadbook-enriched-pictograms"`** : `RoadbookPictogramGeometry`/`RoadbookPictograms.swift`
  (SwiftUI Canvas) + équivalents Core Graphics dans `RoadbookPDFExporter` — rond-point/fourche/
  fusion dessinés dédiés, même géométrie partagée écran/PDF. Non vérifié visuellement (pas de
  device physique dans cet environnement).
- **`feat:"roadbook-poi-tag-list-expansion"`** : `RoadbookLandmarkCategory` (32 catégories,
  `CaseIterable`) + `RoadbookLandmark.bestLandmark` réécrit en table déclarative de `Matcher`.
  Requête Overpass étendue (familles de tags en bloc). `highway=speed_camera` explicitement
  hors périmètre (même sujet que TomTom, à trancher séparément). Voir RoadBook/CLAUDE.md.

Checklist manuelle restant à faire par le propriétaire (pas de device physique dans cet
environnement) : lire l'indicateur de service actif en conditions réelles (couper le réseau
pour forcer un repli OSRM et vérifier le changement) ; vérifier sur une trace routière connue
qu'une longue courbe douce sur le même axe ne génère plus d'événement à tort ; rond-point réel
(bonne sortie affichée) ; traverser une zone avec plusieurs POI de la nouvelle liste.

## Itération 23sexies (repères en pictogrammes emoji + zoom mini-carte encore resserré)

Retour terrain double : "zoom serré je pense que tu peux mettre 200m de chaque côté, c'est
mieux" (réglage à la volée et déplaçable confirmés OK) + "pour ces points je ne vois rien.
J'aimerais que dans l'espace, à côté de la flèche il y ait des pictogrammes (niveau emoji) afin
d'augmenter l'aide au niveau du prochain virage."

- **`fix:"roadbook-minimap-tighter-zoom"`** : portée par défaut de la mini-carte 700 m → 400 m
  (200 m de chaque côté).
- **`feat:"roadbook-landmark-emoji-pictograms"`** : `RoadbookLandmark.bestDescription` (String?)
  devient `bestLandmark` (`RoadbookLandmarkInfo?` = catégorie + libellé) — `RoadbookLandmarkCategory.
  emoji` fournit un pictogramme Unicode par catégorie (🚧🚂🌉💧🔄⛪⚡🚦🛑⛽🚆🌳🏠📍), affiché À CÔTÉ
  du pictogramme de direction (jamais seulement en petit texte en dessous, retour terrain : "je
  ne vois rien") dans les 3 surfaces (table écran, focus GPS, export PDF). Voir RoadBook/CLAUDE.md.

## Itération 23quinquies (mini-carte : zoom réglable + fenêtre déplaçable)

"Zoomé beaucoup plus... 400 mètres de chaque côté, peut-être même 300, ou fait que ce paramètre
soit changeable. Et cette même map, il faudrait pouvoir la changer à la volée, comme une
fenêtre qu'on peut déplacer suivant la préférence de l'utilisateur."

- **`feat:"roadbook-minimap-draggable-zoom"`** : `RoadbookDraggableMiniMap` (nouveau) — portée
  par défaut resserrée à 700 m (contre 2 km avant), réglable par +/- directement sur la carte
  (200-1500 m par pas de 100, persisté). Position déplaçable par glisser, persistée en fraction
  d'écran (jamais en points absolus). Voir RoadBook/CLAUDE.md.

## Itération 23quater (colonnes distance/cap + repères OSM à proximité)

Capture d'un vrai roadbook rallye fournie par le propriétaire : "les deux premières colonnes,
avec distance section et distance cumulée, puis la direction, avec des indications si possible
(église, rond-point...) — est-ce que c'est possible d'avoir des infos pertinentes depuis la map
et récupérer le maximum si possible ?"

- **`feat:"roadbook-heading-degrees"`** : `RoadbookManeuver.headingDegrees` (cap absolu du
  segment sortant, calculé dans `RoadbookExtractor`) — affiché sous le pictogramme partout
  (table écran, focus GPS, export PDF). Mode "Degrés" de l'export basé sur ce cap absolu plutôt
  que l'ancien angle relatif du virage.
- **`refactor:"roadbook-columns-distance-block"`** : table écran réorganisée en 3 blocs
  (distances cumulée/partielle empilées, cap+degrés, direction+info) au lieu de 4 colonnes
  égales — plus proche de la référence rallye montrée.
- **`feat:"roadbook-osm-landmarks"`** : nouveau `RoadbookLandmarkService` (Overpass API,
  gratuit, sans clé) + `RoadbookLandmark` (heuristique pure de choix du meilleur tag : route non
  goudronnée/passage à niveau/pont d'abord, puis église/rond-point/ligne électrique/feux) +
  `RoadbookLandmarkCache` (cache disque par coordonnée, distingue "jamais interrogé" de
  "interrogé sans résultat"). Best-effort total : résolution séquentielle en arrière-plan
  (`RoadBookTabView.loadLandmarksIfNeeded`), n'empêche jamais l'affichage des manœuvres, aucune
  erreur réseau exposée. Affiché dans les 3 surfaces (table, focus GPS, colonne Note du PDF).
  Voir RoadBook/CLAUDE.md pour le détail complet.

**Limite connue, honnête** : contrairement à la référence montrée (vrais schémas d'intersection
dessinés, ex. croisement en croix/rond-point avec la vraie forme du carrefour), les pictogrammes
restent des flèches simples tournées par palier (voir fix "turn-icon-backward-looking", it23bis)
— dessiner la VRAIE géométrie de chaque carrefour demanderait d'extraire la forme du réseau
routier local (nombre de branches, type de jonction) depuis Overpass en plus des tags, hors
scope de cette itération. Piste pour une itération future si le besoin se confirme.

## Itération 23ter (retour terrain sur l'UI du mode Assisté GPS)

"Le road book est pas mal" — mais le mode Assisté GPS doit mettre en avant la manœuvre en cours
plutôt qu'une simple ligne dans une liste, et la mini-carte doit être un aperçu de proximité
(pas la trace entière) posé en coin, pas une bande pleine largeur.

- **`refactor:"roadbook-focused-next-turn"`** : nouvelle `RoadbookFocusedView` (mode Assisté GPS
  uniquement) — manœuvre en cours en très grand (pictogramme 120pt + distance 64pt, occupe tout
  l'espace restant, largement plus de la moitié de l'écran en pratique), les 2 manœuvres
  suivantes en dessous en plus petit avec leur distance recalculée depuis la position actuelle.
  Mini-carte repositionnée en overlay coin bas-droit (15% de hauteur d'écran max), centrée en
  continu sur la position live à portée FIXE 2 km (`RoadbookMiniMapView.spanMeters`) plutôt que
  sur l'emprise de la trace entière. Le mode Roadbook classique garde la table complète
  (`RoadbookTableView`) inchangée — voir RoadBook/CLAUDE.md pour le détail.

## Itération 23bis (retours terrain immédiats sur it23)

Trois retours terrain distincts après livraison d'it23, chacun diagnostiqué avant correctif.

- **`fix:"splash-version-still-1.0"`** — root cause RÉELLE trouvée (le fix "splash-version-
  robustness" d'it23 n'en était pas un) : XcodeGen insère ses PROPRES valeurs par défaut
  ("1.0"/"1", en dur) pour `CFBundleShortVersionString`/`CFBundleVersion` quand ces clés sont
  ABSENTES de `info.properties` dans `project.yml` — `MARKETING_VERSION`/
  `CURRENT_PROJECT_VERSION` (`settings.base`) n'étaient donc JAMAIS lus, quelle que soit leur
  valeur. Corrigé en référençant explicitement `$(MARKETING_VERSION)`/
  `$(CURRENT_PROJECT_VERSION)` dans `info.properties` — vérifié dans le VRAI Info.plist compilé
  du bundle (`PlistBuddy -c "Print :CFBundleShortVersionString"`), pas juste dans le template
  généré. `MARKETING_VERSION` passé à "0.0.23" (itération courante).
- **`fix:"turn-icon-backward-looking"`** — capture d'écran à l'appui : la ligne "Virage fort"
  (palier `.hard`) affichait `arrow.turn.down.right`, qui pointe vers le BAS avant de crocheter
  à droite — se lit comme "fais demi-tour" plutôt que "tourne fort", incohérent avec les autres
  paliers qui pointent vers le HAUT. `RoadbookTier` réécrit : un seul glyphe de base tourné d'un
  angle standardisé par palier (30°/65°/105°/180°) — répercuté sur les 3 consommateurs
  (`LateralCapBannerView`, pins carte `RideMapLibreView`, export PDF). Détail complet :
  `GPXlibre/RoadBook/CLAUDE.md`.
- **`refactor:"roadbook-table-ui"`** — "niveau UI c'est pas ça du tout... copie ce qui se fait
  en affichage roadbook" (référence choisie : roadbook papier de rallye classique). L'ancien
  `List` SwiftUI générique remplacé par `RoadbookTableView` : vraie table dense en colonnes
  (N°/Cap/Partiel/Cumulé), mêmes colonnes/terminologie que l'export PDF, largeurs
  proportionnelles à l'écran (jamais fixes, pour ne pas laisser de vide sur un téléphone large).

## Itération 23 (Mode Road Book + export PDF imprimable)

Fiche de développement complète, 3 points — tous livrés.

- **`feat:"roadbook-mode"`** (point 1) : nouvel onglet Road Book (`RoadBookTabView`), TOTALEMENT
  découplé de l'état de Ride actif (voir RoadBook/CLAUDE.md pour le détail de la garantie
  d'invariant). `RoadbookExtractor` réutilise `RoadbookAnalyzer.buildRoadbookEvents` (paliers
  30/45/90/135°, it14) et `TrackProjector.cumulativeDistances` SANS nouvelle logique de
  détection. Deux modes de lecture (`RoadbookReadingMode`) : Assisté GPS (countdown live via
  `RoadbookLiveProgress`, fonction pure, GPS local à l'écran — jamais `RideSessionManager`) et
  Roadbook classique (distances fixes précalculées). Mini-carte optionnelle
  (`RoadbookMiniMapView`, MapKit léger, même esprit que `CameraPreviewMapView`).
- **`feat:"roadbook-pdf-export"`** (point 2) : `RoadbookPDFExporter` génère un PDF A4 façon
  roadbook papier de rallye (colonnes distance partielle/cumulée/cap/note) via
  `UIGraphicsPDFRenderer` natif, aucun service externe — lit la MÊME liste de manœuvres que
  l'écran (une seule source de vérité). Panneau d'options avant export
  (`RoadbookExportOptionsView`) : portrait/paysage, densité, colonnes affichées, unité km/mi
  (`DistanceUnit`, nouveau — scopé au Road Book, ne touche pas l'affichage des distances
  ailleurs dans l'app), taille de police, cap en pictogramme (flèche vectorielle teintée
  orange/rouge, clin d'œil au logo) ou en degrés. Partage via `ShareLink` (même patron que
  l'export GPX de l'it19). Bug attrapé par les tests AVANT tout usage réel : `columnLayout`
  laissait un blanc à droite de page quand la colonne "note" était masquée (l'espace récupéré
  n'était redistribué nulle part) — corrigé, voir RoadBook/CLAUDE.md.
- **`fix:"splash-version-robustness"`** (point 3) : audit fait, aucun second endroit hardcodé
  trouvé (seul le splash affichait une version, déjà lue dynamiquement). Factorisé dans
  `AppVersion.swift` (point d'accès unique, testable) pour qu'un futur écran "À propos" ne
  puisse pas diverger en recopiant `CFBundleShortVersionString` à la main.

**Checklist manuelle restant à faire par le pilote** (pas de device physique côté IA, voir
CLAUDE.md racine section "Device de référence") :
- [ ] Lire un Road Book en conditions réelles sur une trace connue, comparer aux vraies
      distances/virages (mode Assisté GPS ET mode Classique).
- [ ] Exporter un PDF, l'ouvrir sur un autre appareil/imprimante, vérifier la lisibilité en A4
      réel (pas juste à l'écran) — polices petite/moyenne/grande, portrait ET paysage.
- [ ] Vérifier chaque combinaison d'options de mise en forme à l'œil (pas de colonne coupée, pas
      de texte qui déborde) — la suite automatique (`RoadbookPDFExporterTests.
      testGenerateNeverCrashesForAnyOptionCombination`) garantit l'absence de crash, PAS la
      qualité visuelle réelle du rendu.
- [ ] Vérifier partout où la version s'affiche dans l'app qu'elle correspond bien à `0.0.22`
      (ou au numéro courant) après un vrai rebuild propre (pas un cache Xcode périmé).
- [ ] Tester le Road Book/l'export PDF sur l'iPhone 6s de test secondaire, une fois son
      deployment target confirmé (voir contrainte connue : iOS 16.0 minimum du projet vs
      plafond iOS 15 du 6s — non résolu, mentionné pour mémoire).

## Itération 22 (exclusivité de guidage / icône de reprise dynamique / bouton stop / recherche POI / cohérence des styles)

Fiche de développement complète, 6 points — tous livrés. Dépendance confirmée : les points 1-3
s'appuient sur le branchement Valhalla réel (it20), déjà en place.

- **`feat:"manual-point-guidance-exclusivity"`** (points 1, 3, 4) : voir Ride/CLAUDE.md,
  sections dédiées. `GuidanceTarget` calculé (jamais un second état stocké), `startNav`/
  `startGoTo` mettent en pause la reprise de trace (`cancelResume()`), la colonne latérale se
  retire proprement (gardée par `guidanceTarget == .trace`, pas juste "figée"), bouton stop
  ajouté à `NavGuidancePanelView` ("Revenir à la trace" si une trace est active), icône de
  `RejoinGuidanceBannerView` désormais tournée selon le vrai bearing. Bug manqué en it21
  corrigé au passage : `RideView.commitGoTo` (tap long sur la carte) avait le même
  `modeStore.mode == .nav` mort que `DestinationSearchTabView` (déjà fixé en it21), jamais
  corrigé sur ce second point d'entrée — le guidage riche n'était donc jamais atteignable via
  tap long, seulement via la recherche "Aller à".
- **Point 2 (flèches turn-by-turn vers le point manuel)** : aucun nouveau composant — la
  réutilisation demandée de `NavGuidancePanelView` était DÉJÀ effective une fois le bug
  `commitGoTo` corrigé (elle s'affiche dès que `session.navRoute != nil`, quelle que soit
  l'origine du guidage riche). Rien à construire, juste rendre le point d'entrée atteignable.
- **`feat:"poi-search-nominatim"`** (point 5) : voir Nav/CLAUDE.md. Biais `viewbox` (PAS
  `bounded=1`, volontairement) autour de la position connue pour les requêtes génériques
  ("pharmacie", "supermarché") — une adresse lointaine bien formée continue de fonctionner.
- **`fix:"map-flavor-differentiation"`** (point 6) : voir Map/CLAUDE.md, section dédiée.
  Diagnostic mené AVANT tout correctif (demande explicite), deux causes DISTINCTES trouvées :
  (a) rotation "incohérente" = Relief (raster, jamais de rotation possible par nature) vs les
  3 flavors vectoriels (toujours corrects) — pas un bug de code, documenté via un footer
  Réglages plutôt que "corrigé" ; (b) "3 thèmes identiques" = VRAI bug, le clamp de luminosité
  `0...1` laissait "Contraste élevé" s'écrêter en BLANC PUR sur les couleurs de fond déjà
  claires (majorité de la surface visible), effaçant toute teinte/saturation — corrigé par un
  clamp `safeLightnessRange` (0.05...0.92) qui garde toujours une marge.
- Tests (15 nouveaux ce tour-ci, 219 au total, 0 échec, 1 skip préexistant) :
  `GuidanceTargetTests` (transition trace→point manuel→trace, jamais resumeGuidance ET
  navRoute simultanément dans un sens comme dans l'autre), `RejoinBearingTests` (5 cas :
  tout droit, gauche, droite, cap non nul, demi-tour), `ColorFlavorPatcherTests` (2 nouveaux :
  plus jamais clampé à blanc pur, les 3 flavors distinguables sur la couleur dominante réelle
  du style).
- **Non vérifié visuellement/en conditions réelles** (pas de device physique ni de serveur
  Valhalla réel dans cet environnement) : disparition effective de la colonne latérale au tap
  d'un point manuel, rotation réelle de l'icône de reprise, bouton stop en conditions gantées/
  plein soleil, pertinence des résultats "pharmacie"/"supermarché" en zone urbaine réelle,
  différenciation réellement perçue des 3 thèmes de carte après le fix de clamp.

## Retours terrain it21 (premier vrai test du guidage classique + demande de métriques)

Le propriétaire a testé la livraison it21 en conditions réelles ("je peux l'utiliser comme un
vrai GPS !") et remonté 3 fixes + 1 nouvelle demande :

- **`fix:"search-bar-requires-pull-down"`** : voir Nav/CLAUDE.md, section "Retours terrain
  post-livraison".
- **`fix:"nav-banner-too-verbose"`** : idem — bannière redécoupée en 2 zones (direction/distance
  proéminentes à gauche, texte en retrait à droite).
- **`fix:"nav-goto-mutual-exclusion"`** : bug RÉEL trouvé via le retour "je vois pas de diff" en
  testant le repli sans Valhalla — voir Nav/CLAUDE.md pour le détail (startNav/startGoTo ne
  s'excluaient jamais mutuellement à l'activation).
- **`feat:"track-geek-metrics"`** : voir CLAUDE.md racine (section Views/Rendering) et
  `TrackMetricsCalculator`. Nouvelle section "Statistiques avancées" repliée par défaut dans
  TrackFullSheetView — durée/vitesse moyenne globale et "en mouvement"/vitesse max/dénivelé +
  et −/altitude min-max/pente max. `nil` proprement affiché (message explicatif) si la trace n'a
  pas d'horodatage réel exploitable (import externe).
- **`feat:"region-download-by-shape"`** : refonte de l'écran "Zone par lieu" — confirmé par le
  propriétaire, REMPLACE entièrement `PlaceRegionPickerView` (recherche par nom de lieu,
  supprimée, pas orpheline) par `CircleRegionPickerView`/`CircleRegionPickerMapView` : carte +
  cercle de sélection redimensionnable (slider rayon), estimation de taille en direct, bouton
  télécharger. Voir Offline/CLAUDE.md, section dédiée.
- Tests (7 nouveaux ce tour-ci, 211 au total, 0 échec, 1 skip préexistant) :
  `TrackMetricsCalculatorTests` (moyenne exacte sur cas simple, gain/perte dénivelé séparés,
  filtrage des sauts GPS/segments trop courts, moyenne "en mouvement" > moyenne globale avec un
  arrêt), `NavGoToMutualExclusionTests` (les deux sens, vérifiés au niveau synchrone).

## Itération 21 (bugs Cartes hors-ligne / zone par lieu / refonte Mode Nav)

Fiche de développement complète, trois chantiers — tous livrés.

### Refonte du guidage classique ("Aller à" > Itinéraire, `feat:"nav-classic-rebuild"`)

Voir Nav/CLAUDE.md pour le détail complet. Points saillants :

- **Bug critique trouvé et corrigé, PAS introduit par cette itération** : `modeStore.mode ==
  .nav` (jamais vrai en usage réel depuis it12, `RideModeSegmentedControl` masqué) rendait TOUT
  le guidage classique complètement inerte depuis it5 — y compris `updateNavProgress`
  elle-même, jamais appelée. Trouvé en écrivant `NavProgressTests`/`NavAutoRecomputeTests`
  (leurs premières versions échouaient silencieusement) plutôt qu'en lisant le code seul —
  aucun test n'existait sur cette zone avant it21, donc ce bug n'avait jamais pu être détecté.
  Fix dans `RideSessionManager.handle(location:)` ET `RideView` (bannières/panneau de
  direction) : les deux dépendent désormais de `navDestinationCoordinate`/`navRoute`
  directement, jamais de `modeStore.mode`.
- **Vérification active de l'énumération Valhalla** (demandée explicitement par la fiche,
  "pas supposées") : récupérée via WebSearch/WebFetch contre `valhalla/valhalla-docs`
  pendant cette itération, pas depuis la mémoire seule. Deux champs de la fiche de départ
  n'existent PAS réellement dans le schéma `/route` (vérifié, pas supposé) :
  `bearing_before`/`bearing_after` (existent seulement côté `/trace_attributes`, un autre
  endpoint) et `mergeLeft`/`mergeRight` (seul `kMerge` existe, sans variante directionnelle).
  Icône orientée par CATÉGORIE de type plutôt que par angle exact — couvre les catégories
  demandées par la fiche sans field inexistant.
- **Beaucoup moins de code neuf que prévu à la lecture initiale de la fiche** : le guidage
  vocal (P2), le recalcul automatique de base, la progression de manœuvre et les stats ETA/
  distance/pourcentage existaient déjà depuis it5 (juste jamais exécutés, voir le bug
  ci-dessus) — le travail réel a été de brancher Valhalla à la place d'OSRM (données plus
  riches, texte déjà en français via `language: "fr-FR"`, plus besoin de synthétiser
  l'instruction), rendre le point d'entrée réellement atteignable, et ajouter les deux
  vraies nouveautés P1 (bannière secondaire "puis...", tracé de progression parcouru/restant).
- **Décision de scope assumée** : "Aller à" > Itinéraire ET Valhalla configuré → guidage
  riche ; sinon (Valhalla désactivé/non configuré, ou profil Piste/Mixte) → repli sur le
  guidage simple existant (`GoToGuidance`, pointillés + ETA), inchangé. Pas de guidage riche
  à moitié construit avec des données insuffisantes (OSRM n'a pas l'équivalent).
- **Duplication retirée, pas orpheline** : un second sheet de recherche de destination dans
  `RideView` (accessible seulement via le bouton mort `.navChooseDestination`) était un strict
  doublon de `DestinationSearchTabView` (it19) — supprimé plutôt que laissé en place, pour ne
  pas perpétuer le même bug si quelqu'un le rebranchait un jour.
- Tests (9 nouveaux, 202 au total avec le reste de l'itération, 0 échec, 1 skip
  préexistant) : `ValhallaManeuverTypeTests` (mapping exhaustif type → icône, valeurs
  numériques vérifiées), `NavProgressTests` (avancement de manœuvre + countdown décroissant +
  bannière secondaire multi-cue), `NavAutoRecomputeTests` (recalcul déclenché après écart
  soutenu, cooldown empêchant une boucle si le recalcul échoue en continu, minuteur remis à
  zéro au retour sur trace). Provider Valhalla toujours factice (`NavRoutingProvider`, même
  patron que `RoutingProvider`/`MapMatchingProvider` it20) — jamais de vrai réseau en test.
- **Non vérifié visuellement** (pas de device physique ni de serveur Valhalla réel ici) :
  rendu de la bannière/l'icône/la bannière secondaire, découpage visuel parcouru/restant sur
  la carte (deux `MLNPolylineFeature` filtrées par `.predicate`, technique jamais éprouvée
  ailleurs dans ce fichier), guidage vocal entendu en conditions réelles.

### Bugs Cartes hors-ligne (déjà livrés, section historique ci-dessous)

- **`fix:"region-picker-atlantic-ocean-default"`** : voir Offline/CLAUDE.md, section dédiée,
  pour le détail root cause (coordonnée de centre jamais posée, seulement le zoom) et le fix
  (LocationManager.currentLocation, seedé synchrone depuis `manager.location` pour la "dernière
  position connue" demandée par la spec, sans nouvelle persistance dédiée).
- **`feat:"region-download-by-place"`** : voir Offline/CLAUDE.md, section dédiée. Décision
  d'implémentation notable : "Région" utilise le `featureType` Nominatim `"state"` (pas de
  valeur "region" dédiée côté Nominatim, c'est l'équivalent le plus proche d'une région
  administrative française). `OfflineTileEstimator` extrait le garde-fou "compter avant
  d'énumérer" (it16) pour être partagé entre cadrage manuel ET zone par lieu — refactor sans
  changement de comportement côté `RegionDownloadView`.
- **Piège Swift documenté** (Offline/CLAUDE.md) : un `List` SwiftUI avec trop de sections
  conditionnelles denses en ligne peut dépasser ce que le type-checker résout en temps
  raisonnable, ET produire des erreurs de diagnostic complètement trompeuses (`Binding<...>`
  fantaisistes sur un `ForEach` par ailleurs correct) avant qu'on isole la vraie cause — corrigé
  en factorisant en sous-vues `@ViewBuilder` distinctes. À garder en tête pour tout futur écran
  similaire.
- **Non vérifié visuellement** (pas de device physique dans cet environnement) : le centrage
  GPS réel de la prévisualisation, l'ergonomie du picker Pays/Région/Ville, l'exactitude des
  résultats de recherche Nominatim avec `featureType` en conditions réelles. Logique pure
  couverte par 14 nouveaux tests (193 au total, 0 échec) : `GeocodingBoundingBoxTests`,
  `OfflineTileEstimatorTests`, `PlaceKindTests`, + 3 tests `TileCoordinate.boundingBox(around:)`
  (existant depuis it17, jamais testé directement jusqu'ici).

## Itération 20 (branchement réel Valhalla / map matching pour virages légers)

Fiche de développement complète fournie par le propriétaire, deux chantiers :

- **Constat de départ à nuancer** : la fiche affirmait "`ValhallaRoutingService` n'est utilisé
  que par le bouton Tester la connexion" — en réalité, DÉJÀ FAUX au moment de recevoir cette
  fiche : `DetourRoutingService.route(from:to:profile:valhalla:)` appelait déjà Valhalla en
  premier (repli OSRM inline) depuis it19, branché sur le contournement/la reprise hors-trace/
  le hors-route d'Aller à (voir `RideSessionManager.currentValhallaConfiguration`, section
  "Routage Valhalla optionnel" du CLAUDE.md Ride/, ligne appelante `requestRoute`/`route` déjà
  passée `valhalla: currentValhallaConfiguration`). La partie RÉELLEMENT neuve de ce chantier :
  extraire cette logique inline dans un vrai protocole `RoutingProvider` + un
  `RoutingProviderResolver` testable (voir Ride/CLAUDE.md, "Branchement réel de Valhalla") — un
  refactor de clarté/testabilité, pas un branchement qui manquait fonctionnellement. Ligne
  d'état ajoutée dans Réglages (visible seulement toggle ON) pour rendre le périmètre RÉEL
  explicite au propriétaire, plutôt que le texte suggéré par la fiche (incomplet : omettait le
  contournement et le hors-route d'Aller à, déjà couverts depuis it19).
- **Map matching (`valhalla-map-matching-direction-change`)** : nouveau, voir Ride/CLAUDE.md
  pour le détail complet (`ValhallaMapMatchingService`/`RoadbookMapMatchCache`/
  `RoadbookTier.lightDirectionChange`). Décision d'implémentation : `/trace_route`
  (`maneuvers[]`) plutôt que `/trace_attributes` — suffit pour détecter un changement de
  manœuvre/rue sans interpréter des attributs d'arête bas niveau, plus simple pour un résultat
  équivalent dans ce périmètre.
- **Découverte en cours de route (tests), documentée pour référence future — PAS corrigée ce
  tour-ci, hors périmètre de cette fiche** : `RoadbookAnalyzer.windowedTurn` (donc
  `buildRoadbookEvents` depuis it14, comportement PRÉEXISTANT, pas introduit par it20) a une
  particularité de fenêtrage sur une trace à segments LONGS (≥ la fenêtre avant/après, ex.
  100-300 m — un enregistrement GPS réel a des segments bien plus courts, quelques mètres à
  quelques dizaines de mètres selon la densité, donc ce cas ne se présente normalement jamais en
  usage réel) : dès qu'un point intérieur a au moins un segment de chaque côté (`startSeg > 0`
  ou extension avant `endSeg`), la fenêtre s'étend TOUJOURS d'au moins un segment complet
  supplémentaire, même si le segment immédiatement adjacent dépasse déjà largement la fenêtre
  demandée — la mesure résultante (somme télescopique des deltas de cap) peut alors capter le
  virage d'UN sommet voisin en plus de celui visé, et deux sommets voisins portant le même angle
  réel peuvent se voir mesurés identiquement puis fusionnés par `mergeNearby` sur le PREMIER
  rencontré plutôt que celui géométriquement "central". Trouvé en écrivant
  `RoadbookMapMatchingTests.testMergedEventsStayOrderedByProgressionAlongTheTrack` (trace
  synthétique à segments longs, jamais exercée par la suite de tests existante qui n'utilise que
  des traces à 2-4 segments ou des segments courts). Aucun symptôme terrain rapporté à ce jour
  (aucune trace réelle n'a des segments aussi longs) — à garder en tête si un futur bug roadbook
  "virage détecté au mauvais point" est signalé sur une trace au maillage GPS inhabituellement
  large (import externe rééchantillonné, par exemple).
- **Non vérifié visuellement/en conditions réelles (pas de device physique ni de serveur
  Valhalla réel dans cet environnement)** : l'apparition effective de l'icône "signpost" sur la
  carte pour un vrai virage léger détecté par map matching, le temps réel d'un appel
  `/trace_route` sur une trace de plusieurs milliers de points (voir
  `mapMatchingMaxTracePoints`, sous-échantillonnage jamais exercé contre un vrai serveur), et la
  ligne d'état des Réglages Valhalla (texte, pas de bug de layout attendu mais jamais rendue à
  l'écran ici). Logique couverte par 23 nouveaux tests unitaires (179 au total, 0 échec) :
  `RoutingProviderTests` (résolution + repli en chaîne, providers factices), 
  `RoadbookMapMatchingTests` (fusion géométrique/map matching, non-régression explicite),
  `ValhallaMapMatchingServiceTests` (extraction pure des manœuvres intermédiaires),
  `RoadbookMapMatchCacheTests` (persistance disque par trace),
  `RideSessionManagerMapMatchingTests` (déclenchement une fois par trace, cache, dégradation
  propre — provider Valhalla toujours factice, jamais de vrai réseau).

## Étude UX "boutons icône+texte" (it19, propriétaire : "proposition, pas une refonte")

Recensement exhaustif effectué (sous-agent dédié) de tous les boutons texte-seul de l'app.
Constat central : beaucoup vivent dans un `.confirmationDialog`/`.alert` système (Contourner
route/piste, Itinéraire.../Mixte, Arrêter/Continuer, Fermer/Annuler de toolbar, Supprimer/
Renommer) — iOS ne permet PAS d'icône dans ces rangées système ; les changer irait contre le
HIG plutôt que d'aider, donc explicitement HORS candidats malgré leur fréquence.

**Corrigé tout de suite (incohérences évidentes, zéro risque, pas besoin d'attendre un feu
vert)** :
- `FavoriteAddressesView`/`NavDestinationSearchView` : lignes de résultat de recherche
  d'adresse passées en `Label(icon: "mappin.and.ellipse")` — la ligne "Position actuelle"/les
  favoris Domicile-Travail juste au-dessus avaient déjà une icône, pas les résultats.
- `LibraryView` (état vide) + `OnboardingView` (3 écrans) : boutons "Charger la trace
  d'exemple"/"Importer un fichier GPX" alignés sur les icônes déjà utilisées pour les MÊMES
  actions ailleurs dans l'app (menu "+" Biblio) — "C'est parti" reçoit une icône cohérente
  (arrow.right.circle.fill).

**Proposé, en attente d'un feu vert du propriétaire avant d'y toucher** (boutons custom hors
dialog système, changement plus visible/plus de surface à valider) :
- Bannières Ride custom : "Contourner" (BlockedPathBannerView), "Reprendre ici"/"Annuler"
  (ResumeGuidanceCardView), "Annuler" (DetourStatusView)
- CTA état vide Ride : "Aller à la Bibliothèque"
- `TrackSettingsView` : "Revenir à l'apparence globale" / "Revenir au début d'origine"
  (sémantique reset, icône `arrow.uturn.backward` proposée)
- `NavigationSettingsView` : "Sauvegarder"/"Valider" (réglages stagés) — icône `checkmark`
- `SettingsView` : "Revoir le didacticiel" — seule ligne de sa liste sans icône
- `Offline/RegionDownloadView`, `VectorPackagesView` : "Télécharger..." — icône déjà utilisée
  ailleurs pour la même action (`arrow.down.circle`, toolbar Biblio)
- `PrecacheConfirmationView` : choix Wi-Fi/mobile (vue custom, pas un system alert — fréquente
  en pratique, affichée avant chaque Ride sur une trace non entièrement en cache)

## Icônes complémentaires (retour terrain via /powerup : "j'en aurais ajouté à d'autres
## endroits... amener un peu de fun")

Suite de l'étude UX icône+texte (it19) — le propriétaire a validé l'esprit et demandé
d'appliquer le reste de la liste déjà proposée (voir section dédiée plus bas), tous des
boutons CUSTOM hors dialog système (donc de vrais candidats, contrairement au reste déjà
exclu pour raison HIG) : bannières Ride (Contourner/Reprendre ici/Annuler ×2), CTA état vide
Ride, TrackSettingsView (2 boutons reset), réglages stagés Navigation (Sauvegarder/Valider),
"Revoir le didacticiel", téléchargements Offline (région/paquet vectoriel/précache Wi-Fi-
mobile). Icônes choisies pour RÉUTILISER une iconographie déjà présente ailleurs dans l'app
quand c'est le même concept (ex. "arrow.triangle.swap" déjà utilisé par DetourStatusView pour
le mode routé ; "arrow.down.circle" déjà utilisé par le lien toolbar "Cartes hors-ligne" ;
"arrow.uturn.backward" pour les deux actions "revenir à/reset" de TrackSettingsView) plutôt
que d'inventer une symbolique différente à chaque fois.

## Retour terrain it19 (via /powerup) — 2 bugs réels trouvés et corrigés

Le propriétaire a testé les livrables d'it19 sur simulateur/device et donné un retour concret
sur 5 points demandés. Deux résultats attendus ("pas grave", à re-tester avec une trace plus
pentue) et un déjà correct (rotation labels). Les deux autres ont révélé de VRAIS bugs :

- **Palettes de couleur "invisibles"** : diagnostiqué en rejouant `ColorFlavorPatcher` contre le
  VRAI style embarqué (pas une supposition) — la transformation s'appliquait bien
  techniquement (confirmé), mais un simple MULTIPLICATEUR de saturation n'a quasiment aucun
  effet sur les teintes déjà peu saturées (fond de carte, zones neutres — la majorité de la
  surface visible). Fix : terme ADDITIF de saturation (`MapColorFlavor.saturationBoost`) en plus
  du multiplicateur, paramètres globalement plus marqués. Voir section dédiée ci-dessous.
- **Fiche trace A→B "toujours rien"** : root cause trouvée en LANÇANT RÉELLEMENT l'app dans le
  simulateur (screenshot + logs de diagnostic temporaires, plutôt qu'une troisième supposition)
  — `mapView(_:didFinishLoading:)` ne se déclenche JAMAIS pour cette carte (confirmé après 20 s
  d'attente), très probablement parce que cette `MLNMapView` vit dans un `Form`/`List`
  (contrairement à la Ride map, plein écran, où ce délégué fonctionne normalement). Les DEUX
  correctifs précédents (it18-bis) partaient d'une fausse prémisse (une course sur la
  disponibilité du style) et n'ont donc rien résolu. Fix réel : `sync()` ne dépend plus DU TOUT
  de `didFinishLoading` pour créer les sources/couches — il le fait dès que `mapView.style` est
  disponible (empiriquement déjà le cas dès le tout premier appel). `didFinishLoading` reste un
  filet de sécurité redondant, `setupLayers` rendue idempotente pour supporter un double appel
  sans planter. **Vérifié visuellement** (capture simulateur : tracé + chevrons + pastille B
  visibles, bon cadrage) — pas juste "ça devrait marcher" cette fois.
- Leçon methodologique retenue : pour ce bug précis, deviner à partir de la lecture de code
  seule a échoué deux fois de suite — lancer l'app réellement (simulateur + logs temporaires)
  a trouvé la vraie cause en un seul passage. À privilégier plus tôt pour tout bug qui résiste
  à un premier correctif "raisonné".

## Palettes de carte "maison" (spec "map-color-flavors", it19, décision tranchée avec le
## propriétaire)

Remplace la demande initiale "Flavors Protomaps" — investigation menée AVANT de coder (voir
message de session) : le système officiel `@protomaps/basemaps` ne s'applique qu'au schéma de
tuiles PROPRE à Protomaps (10 couches Tilezen), incompatible avec le pipeline OpenMapTiles déjà
en place (OpenFreeMap hébergé + paquets `.pmtiles` auto-hébergés Planetiler, it11). Migrer aurait
exigé de reconstruire tout le pipeline hors-ligne avec les outils Protomaps — proposé au
propriétaire, refusé au profit d'un système de palettes maison sur le style Liberty existant,
même esprit que les Flavors (un objet de palette réutilisable sur un seul "squelette").

- `MapColorFlavor` (Map/) : 3 palettes prédéfinies choisies pour être "très utilisées" (demande
  explicite) — Standard (identité, palette d'origine inchangée), Contraste élevé (saturation
  ×1.35 + étirement de contraste ×1.25 autour de 50 % de luminosité — pensé pour la lisibilité
  au soleil/avec des gants, cohérent avec la philosophie moto de l'app), Terreux (teinte +10°,
  saturation ×0.85, légèrement plus clair — esprit carte de randonnée sans reconstruire un
  schéma de tuiles séparé).
- `ColorFlavorPatcher` (Map/) : transforme RÉCURSIVEMENT la clé `paint` de chaque calque
  (jamais `layout`, contrainte non négociable du prompt sur la rotation cap-en-haut) — gère les
  couleurs simples ET imbriquées dans des expressions (`interpolate`/`step`), 4 formats
  (`#rgb`/`#rrggbb`/`rgb()`/`rgba()`/`hsl()`/`hsla()`), toujours ré-émises en `hsla(...)`.
  Paramètres de transformation choisis à l'aveugle (pas de device physique pour un retour
  visuel réel) — documentés comme constantes ajustables dans `MapColorFlavor`, à affiner après
  test terrain réel plutôt que devinés une seconde fois ici.
- `MapThemePreset` : "Sombre" RETIRÉ (n'existait que côté raster, accroc hors-ligne documenté en
  it18-bis — plus nécessaire, les 3 flavors fonctionnent identiquement hébergé/local, aucune
  limitation hors-ligne contrairement à Sombre). "Relief" inchangé (renommage reporté, comme
  demandé). Migration silencieuse pour un utilisateur ayant l'ancienne valeur persistée
  (osmStandard/clair/sombre) : retombe sur "Standard" au prochain lancement, comme un premier
  lancement — même patron que la migration `legacySelectedTrackKey` de LibraryStore.
- Rotation des labels cap-en-haut : AUCUNE modification du mécanisme (`patchedSymbolLayerForCapUp`
  toujours appliqué APRÈS `ColorFlavorPatcher`, sur les clés `layout` uniquement, totalement
  indépendant) — contrainte non négociable respectée par construction, pas par vigilance.
- Non vérifié visuellement (pas de device physique) — les paramètres numériques des 3 flavors
  sont un point de départ raisonnable, pas un résultat validé à l'œil.

## Avertissement de pente natif (spec "slope-warning-native", it19, décision tranchée avec le
## propriétaire)

Remplace la demande initiale "utiliser GPXKit" — `GPXKit` (mmllr/GPXKit) existe bien et
conviendrait techniquement (détection de dénivelé/grade intégrée), mais c'est un VRAI package
tiers, contraire à la règle explicite du projet ("MapLibre est la SEULE dépendance tierce
autorisée", `project.yml`). Proposé au propriétaire, confirmé : détection native.

- `SlopeAnalyzer` (Rendering/) : calcul pur (delta d'élévation / distance horizontale sur des
  fenêtres non chevauchantes d'au moins 100 m, `RideConstants.slopeWarningMinSegmentMeters` —
  évite le bruit GPS/altimétrique sur de trop courts segments), symboles PONCTUELS uniquement
  (jamais un dégradé continu, demande explicite) espacés d'au moins 300 m
  (`slopeWarningMinMarkerSpacingMeters`) pour ne jamais empiler des triangles sur une longue
  pente régulière. Seuil par défaut 10 % (`slopeWarningThresholdPercentDefault`, proche des
  paliers réels des panneaux routiers français 8/10/12 %), réglable (8/10/12/15 %,
  Réglages > Pente).
- Rendu (RideMapLibreView) : symbole triangle jaune/noir façon panneau routier de danger, DEUX
  variantes dessinées (rampe montante/descendante selon le signe de la pente), `icon-rotation-
  alignment: viewport` — reste lisible à l'écran quel que soit le cap, comme un vrai panneau
  planté au bord de la route ne tourne jamais avec la caméra du motard. Passé par
  `.environment(...)` plutôt qu'en paramètre d'init (même contrainte MapProvider que le
  marqueur replay debug, it17).
- Nouveau réglage `RideSettingsStore.slopeWarningsEnabled` (ON par défaut, cohérent avec les
  autres avertissements de sécurité déjà ON par défaut) + `slopeWarningThresholdPercent`.
- MapKit (RideMapView, comparaison uniquement) non concerné — décision de scope assumée, comme
  pour tout le reste des features avancées (chevrons, fond vectoriel), pas d'obligation de
  parité.
- Non vérifié visuellement (pas de device physique, pas de trace réelle avec élévation
  disponible dans cet environnement) — logique testée unitairement (8 tests), le rendu visuel
  réel (triangle bien positionné, lisible, montée/descente distinguables) reste à confirmer par
  le propriétaire en conditions réelles.

## Itération 19 (P0 fiche trace / styles carte / pente / étude boutons)

- **P0 "trace-ab-line-invisible", investigation menée avant tout correctif (comme demandé)** :
  relu entièrement `TrackFicheMapView.swift` et son unique appelant (`TrackSettingsView`) à
  froid, sans supposer que le fix `6a2a676` (session précédente) suffisait. Aucune régression
  it17→it18 trouvée dans le chemin de données trace → vue (le call site n'a pas changé) ; il
  n'existe qu'UNE SEULE fiche avec carte (`TrackSettingsView`, via swipe "Paramétrer" ou
  `TrackFullSheetView` → "Paramètres") — `TrackFullSheetView` lui-même n'a pas de carte du tout
  (fiche texte pure), donc pas de second endroit où chercher. Le fix déjà en place (garde de
  `sync()` sur l'existence réelle de la source, pas la seule non-nullité de `mapView.style`)
  reste correct à la relecture — s'il persistait un symptôme PIRE (pastilles ET ligne absentes)
  au moment où ce ticket a été rédigé, c'est très probablement parce qu'il décrit l'état
  D'AVANT ce fix (déjà poussé), pas une nouvelle régression : pas de device physique disponible
  ici pour confirmer un aller-retour réel. À reconfirmer par le propriétaire après avoir tiré
  la dernière version.
- **Marge de cadrage 2 km (nouveau, ce tour-ci)** : remplace l'ancien `edgePadding` en POINTS
  ÉCRAN (32 pt, variait avec le zoom/la taille d'écran) par une vraie marge GÉOGRAPHIQUE
  (`TrackFicheMapView.cameraGeographicMarginMeters = 2000`, appliquée à la bbox AVANT
  `setVisibleCoordinateBounds`, formule équirectangulaire locale déjà utilisée ailleurs dans le
  projet — `TrackProjector`). `cameraEdgePadding` réduit à 8 pt, devient un confort minimal, pas
  le mécanisme de marge principal.
- **Persistance "trace sélectionnée reste affichée au changement d'onglet"** : déjà garanti par
  l'invariant it10 "Caméra stable aux bascules" pour la carte Ride (`switchMode`, jamais
  `start()`, sur changement d'onglet — voir CLAUDE.md racine, règle absolue #2) — rien à
  changer, ce comportement existe et est déjà couvert par la philosophie de l'app. Pour la
  fiche trace elle-même (`TrackFicheMapView`), le dédup de `sync()` (id/isReversed inchangés →
  ne re-mute jamais `.shape`) garantit déjà qu'un re-render du `Form` parent (ex : toucher un
  autre réglage dans le même écran) ne fait jamais disparaître la ligne déjà posée.
- **Test d'intégration réel tenté puis retiré, honnêteté** : un vrai `MLNMapView` (style
  embarqué, hors écran, comme le veut XCTest) ne termine JAMAIS son chargement de style dans cet
  environnement (`didFinishLoading` ne se déclenche pas en 5 s, testé et confirmé, pas juste
  supposé) — aucun autre test de cette suite n'instancie de vrai `MLNMapView` pour la même
  raison probable, cohérence avec ce précédent. Gardé à la place : `TrackFicheCameraFitTests`
  (logique pure de bbox + marge, testable sans MapLibre réel). Les points 1/2 du "test attendu"
  du prompt (source de ligne complète, marqueurs A/B aux bonnes coordonnées) restent donc NON
  vérifiés automatiquement — seule la checklist manuelle du propriétaire peut les confirmer
  dans cet environnement.

## Itération 18-bis (bug A→B, styles de carte, précision rotation labels)

Suite directe de l'itération 18 — trois sujets discutés avec le propriétaire après retour sur
le premier passage : `fix:"trace-ab-line-invisible"`, `fix:"symbols-rotation-alignment-parity"`,
`feat:"map-style-visual-picker"` livrés. Mode sombre volontairement laissé de côté (décision du
propriétaire, hors périmètre de cette itération).

- **Sélecteur visuel de style de carte (`MapThemePickerView`)** : vignettes dessinées (icône +
  dégradé représentatif), pas des cartes MapLibre live — 4 instances de carte simultanées dans
  une liste de réglages aurait été un coût de rendu disproportionné pour un simple choix de
  palette. Remplace le `Picker` texte de Réglages > Carte > Thème, mêmes 4 valeurs
  (`MapThemePreset`), aucun nouveau style ajouté ce tour-ci (voir ci-dessous).
- **Satellite : IMPLÉMENTÉ puis RETIRÉ (spec "satellite-sentinel2" it22, chore
  "remove-satellite" it22bis)** — Sentinel-2 cloudless (EOX, gratuit) avait été choisi
  explicitement par le propriétaire face à l'alternative payante (Maxar/Mapbox Satellite,
  nécessite un compte que l'app ne peut pas provisionner). Retiré dès le retour terrain suivant
  la livraison : "vraiment pixelisé et inutilisable" — la contrepartie de résolution (~10 m/pixel
  natif, mosaïque annuelle), déjà documentée comme assumée AVANT l'implémentation, s'est avérée
  rédhibitoire en usage réel, bien plus grossière qu'un satellite commercial. `TileSource.
  satellite`/`MapThemePreset.satellite` et tout le code associé (vignette, footer raster, ancrage
  hillshade) ont été intégralement supprimés — voir `GPXlibre/Offline/CLAUDE.md` pour
  l'historique complet. Ne pas réintroduire cette même source sans un changement de fournisseur
  (résolution) en amont ; si le besoin redevient réel, repartir directement de la piste Maxar/
  Mapbox payante plutôt que retenter une source gratuite basse résolution déjà rejetée à l'usage.
- **"Rando" (nouveau style vectoriel outdoor)** : proposé au propriétaire (réutilise les MÊMES
  tuiles OpenMapTiles déjà hébergées/téléchargées, donc zéro risque hors-ligne — juste un
  nouvel habillage JSON, chemins/pistes plus visibles, teintes terrain), mais PAS implémenté —
  en attente d'un feu vert explicite avant d'investir dans la conception d'un style complet
  (travail non trivial, ~110 couches à repenser comme pour le style Liberty existant, mieux fait
  avec des retours visuels réels qu'aucun device physique ne permet ici).
- **Accroc hors-ligne existant, documenté (pas un bug de cette itération)** : le thème Sombre
  force le raster OSM (+ filtre nuit) même si un paquet vectoriel local est actif —
  `MapSourceResolver` teste `themePreset == .relief || .sombre` AVANT même de regarder le
  paquet local (voir sa doc). Un utilisateur hors-ligne avec un paquet PMTiles préparé perd donc
  son fond de carte hors-ligne en passant en Sombre (retombe sur du raster EN LIGNE, ou rien du
  tout en vrai mode avion sans tuiles raster déjà en cache). Cause : le style vectoriel Liberty
  embarqué n'a qu'une variante claire (déjà noté en it11). Averti maintenant dans Réglages
  (footer de section, visible seulement quand Sombre est sélectionné) plutôt que silencieux —
  pas de vrai fix ce tour-ci, demanderait de repeindre le style vectoriel en sombre (gros
  chantier à part, voir it11/Map CLAUDE.md, VersaTiles fournirait déjà clair+sombre si besoin
  réel confirmé).

## Itération 18 (compacité bannières / traces enregistrées visibles / zoom reset / cap-en-haut vrai)

- **Hygiène de staging git, documentée par honnêteté (aucun risque fonctionnel)** : le Bloc 4
  (`manualZoomBackTapsForDefaultRideZoom` 4→5, `fix:"default-zoom-persist-rework"`) a été édité
  dans `RideConstants.swift` avant le premier commit de cette itération, et s'est retrouvé
  entraîné dans le commit `fix:"offtrack-compact-chip"` (Bloc 1) faute d'avoir `git add -p`
  séparé les deux hunks du même fichier — même situation déjà rencontrée et documentée à
  l'identique en it14. Contenu correct des deux côtés, juste une frontière de commit imparfaite.
- **Backlog explicite du prompt (Bloc 1, "offtrack-compact-chip")** : action contextuelle par
  appui-long sur le chip hors-trace (`OffTrackChipView`), popup "Marquer portion bloquée &
  Contourner" — le prompt demandait de ne l'ajouter QUE si le chip reste visuellement propre
  sans elle ; le chip (icône + titre + distance optionnelle) est déjà dense pour 92 pt de large,
  donc non implémenté ce tour-ci pour ne pas le surcharger. Le bouton "Bloqué" (toujours visible,
  colonne de contrôles) reste le chemin manuel existant, inchangé. À ajouter si le propriétaire
  confirme le besoin après test terrain du chip actuel.
- **`RoadbookPanelView` (Ride/) orpheline** depuis ce bloc — plus aucun appelant
  (`directionPanelLayer` ne branche plus que le cas Nav) : fichier intact, même patron que
  `TrackDetailView`/`TrackThumbnailView` (voir it13/it17 plus bas), pas supprimé.
- **BLOC 2 (ride-record-tracks-visible), décision de scope tranchée avec le propriétaire avant
  codage** : le prompt proposait de rendre la trace fraîchement enregistrée automatiquement
  ACTIVE pour le Ride après "Terminer la sortie" (seul moyen, dans l'architecture actuelle à
  UNE SEULE trace rendue à la fois — règle absolue du CLAUDE.md racine, "Ne JAMAIS réintroduire
  un rendu multi-trace" — de la faire apparaître sur la carte Ride en direct). Réponse du
  propriétaire : non, la trace suivie ne doit pas être remplacée automatiquement. Résolution
  retenue à la place, qui ne touche pas à cette règle absolue : `EndRideView` affiche désormais
  un aperçu carte immédiat (`TrackFicheMapView`, cadrage auto sur l'emprise) juste après
  l'enregistrement, avec la couleur ambre distinctive (`RideConstants.recordedTrackColorPreset`)
  appliquée par défaut à la trace enregistrée — donc "apparaît sur la carte immédiatement après
  validation" est satisfait sans toucher à la trace active. Pour la voir ensuite sur la carte
  Ride en conditions réelles de suivi, il faut toujours la rendre active à la main depuis la
  Biblio (case à cocher, déjà existante et déjà live sans reload) — un vrai rendu multi-trace
  simultané (active + "affichée" superposées) reste hors périmètre de cette itération, à
  discuter explicitement si le besoin recontacte le propriétaire.
- **BLOC 3/5 (link-recompute-on-divergence / rejoin-trace-guidance-banner), décision
  d'architecture assumée** : le recalcul automatique (divergence > 100 m pendant > 2 s) réutilise
  tel quel le mécanisme "Reprendre la trace ici" existant (`ResumeGuidance`/`requestResume`,
  OSRM, tracé pointillé bleu déjà en place depuis it10) plutôt que d'inventer un second moteur de
  routing parallèle — un nouveau champ `ResumeGuidance.isAutomatic` distingue les deux origines
  (tap manuel → bannière du haut + confirmation ; divergence automatique → auto-confirmé, toast
  bref "Recalcul", bannière latérale indigo `RejoinGuidanceBannerView`). Simplification assumée :
  la bannière latérale affiche la distance ROUTÉE jusqu'à la jonction (pas "la prochaine
  manœuvre" détaillée du tracé de liaison lui-même, qui demanderait de décoder les étapes OSRM
  du détour — hors budget de cette itération, la trace principale garde ses propres virages/
  chevrons intacts et inchangés pendant ce temps).
- **BLOC 6 (trace-sheet-auto-frame)** : `TrackFicheMapView` cadrait déjà sur l'emprise de la
  trace depuis it17 (`fitCamera`, spec "trace-fiche-map-ab-markers") — la cause probable du bug
  terrain (carte centrée monde) est une course : `fitCamera` peut s'exécuter dès
  `didFinishLoading` (style JSON embarqué, quasi instantané), potentiellement avant que SwiftUI
  ait donné à la `MLNMapView` (créée `frame: .zero`) sa vraie taille de layout — auquel cas
  `setVisibleCoordinateBounds` calcule un zoom aberrant sur une vue de taille nulle. Fix : un
  second passage de cadrage, idempotent, rejoué une fois dès `mapViewDidFinishRenderingMap`
  quand les bounds sont enfin non nulles. Non confirmé visuellement (pas d'automatisation
  tactile dans cet environnement, limite documentée depuis it9) — à valider par le propriétaire
  en ouvrant une fiche trace.
- **BLOC 7 (rotating-symbols-cap-up)** : uniquement pertinent quand le fond VECTORIEL est actif
  (hébergé en ligne, ou paquet local) — le raster (thème par défaut hors connexion) n'a aucun
  label vectoriel, cette itération ne le concerne pas. Vérifié dans les headers vendored
  MapLibre : les 25 calques symbol du style Liberty embarqué omettent tous `text`/`icon-
  rotation-alignment` (comptent sur la résolution implicite `auto` du spec, qui DEVRAIT déjà
  donner `viewport` pour les labels à placement point) — rendu désormais EXPLICITE au chargement
  du style plutôt que de compter sur cette résolution implicite, changement sûr même si `auto`
  fonctionnait déjà correctement. Non confirmé visuellement en conditions de virage réel (pas de
  device physique dans cet environnement) — à valider par le propriétaire.

## Itération 17 (zones hors-ligne, explication tuiles, chevrons dézoom, replay v2, fiche trace A/B)

Cinq blocs livrés : `feat:"offline-zones-outline"`, `docs:"tiles-zoom-explainer"`,
`feat:"chevrons-zoom-adaptive"`, `feat:"replay-marker-heading-x2"`,
`feat:"trace-fiche-map-ab-markers"` — plus un passage `/doctor` en cours de route
(`docs:"claude-md-lazy-load-migration"`, réorganisation de la mémoire de travail en
CLAUDE.md par dossier, aucun rapport avec le produit).

- **Vérification de cette itération** : builds simulateur + device (compile-only) + suite de
  tests (76, 0 échec, 1 skip) verts après chaque bloc. Comme toujours, **aucun** des 6 tests
  manuels de la checklist du prompt n'a pu être exécuté dans cet environnement (pas
  d'automatisation tactile) — contour de zone visible, encart tuiles lisible, dézoom
  progressif sans saut, replay ×2/×8 avec virage connu, toggle A↔B ×5 sur la fiche trace,
  sortie réelle 10-15 min : tout reste à confirmer par le propriétaire.

- **Décision de scope assumée (Bloc 5)** : `TrackMapView` (MapKit) et `TrackThumbnailView`
  (Canvas) ne sont plus appelés depuis `TrackSettingsView` (remplacés par
  `TrackFicheMapView`), mais ni l'un ni l'autre n'a été supprimé. `TrackMapView` garde un
  autre consommateur réel (`TrackDetailView`, it13). `TrackThumbnailView` devient orphelin
  (plus aucun point d'entrée UI) mais suit le même patron déjà établi pour
  `RideModeSegmentedControl`/`TrackDetailView` : fichier intact, pas de suppression tant
  qu'un besoin de le réutiliser n'est pas confirmé.

- **Décision de scope assumée (Bloc 1)** : `DownloadedRegion.boundingBox` affiche un
  rectangle englobant pour TOUTES les zones, y compris les corridors de trace (non
  rectangulaires en réalité) — repli explicitement autorisé par le prompt, pas une
  approximation cachée. Une vraie géométrie de corridor demanderait de re-dériver la forme
  depuis la trace d'origine (si elle est encore en Biblio), non fait ce tour-ci.

- **Bug trouvé et corrigé en cours de route (pas un TODO, tracé pour mémoire)** : les 4
  nouveaux `CLAUDE.md` par dossier créés pendant le passage `/doctor` faisaient planter le
  build (xcodegen les traitait comme des ressources à copier dans le bundle, collision de 4
  fichiers homonymes sur le même chemin de sortie) — corrigé par des `excludes:` explicites
  dans `project.yml`. À surveiller si un futur `CLAUDE.md` par dossier est ajouté.

## Itération 16 (corrections terrain — retours de tests tactiles réels du propriétaire)

Six bugs remontés par un vrai passage terrain sur les fonctionnalités it14/it15 (checklist de
10 tests tactiles proposée, tous exécutés côté propriétaire — la toute première fois que ces
fonctionnalités étaient réellement touchées du doigt depuis leur écriture) :

- `fix:"region-picker-huge-bbox-crash"` — **crash confirmé**, le plus critique des six : bouton
  "Cartes hors-ligne" plantait l'app après ~10 s (main thread bloqué à énumérer une bbox
  quasi mondiale). Voir CLAUDE.md, section "Compter avant d'énumérer".
- `fix:"settings-segmented-picker-missing-title"` — "Position contrôles" (et "Épaisseur",
  même bug) sans titre visible, `.pickerStyle(.segmented)` masque le label par défaut.
- `fix:"settings-preview-panel-hides-anchor-dot"` — le panneau de réglage Position point bleu
  cachait son propre indicateur de position (ancré en bas, comme l'ancre à 75 %).
- `fix:"pause-stop-indistinguishable"` — Pause et Stop défini (it15, Bloc 3) étaient
  impossibles à distinguer à l'usage (même absence de signal visuel/toast, haptique seule
  trop discrète) — toast dédié ajouté sur les deux chemins.
- `fix:"end-ride-default-name"` — la trace enregistrée en fin de sortie reprenait le nom de la
  trace suivie À L'IDENTIQUE, impossible à distinguer de l'originale une fois dans Biblio ;
  nom désormais éditable, préempli "<nom trace> – <date du jour>".
- `fix:"debug-replay-erratic-speed"` — le mode replay debug (jamais exercé avant ce round)
  avançait de façon erratique ("un oiseau qui vole au-dessus de la trace"), intervalle fixe
  par point indépendant de la distance réelle — corrigé en dérivant le délai de la distance à
  vitesse simulée constante.

**Confirmés fonctionnels sans changement** (mêmes 10 tests) : colonne contrôles gauche/droite
live (bien qu'ayant révélé le bug de titre manquant), slider Position point bleu, zoom par
défaut persistant après kill+relance de l'app, tri Biblio par date (plus récente en tête,
confirmé visuellement).

**Toujours pas vérifié** (pas de trajet réel possible au moment du test) : hors-trace
hystérésis en conditions réelles, paliers roadbook (icônes par sévérité + flash 100 m) — le
mode replay debug qui aurait dû permettre de les valider sans sortir avait lui-même un bug
(voir `debug-replay-erratic-speed` ci-dessus), donc ni l'un ni l'autre n'a pu être confirmé ce
tour-ci. À reprendre maintenant que le replay est corrigé.

## Itération 15 (horodatage traces Biblio / sheets translucides / Stop↔Pause/Play toggle)

- **Vérification de cette itération** : builds simulateur + device (compile-only) + suite de
  tests (58, 0 échec, 1 skip) verts après chaque bloc. Le test du Bloc 1 (tri par date GPX
  metadata) exerce le vrai chemin `importTrack` de bout en bout (pas un raccourci de test) et
  importe volontairement les traces dans l'ordre INVERSE de leur date pour ne pas laisser un
  tri par insertion se faire passer pour un tri par date par coïncidence. Comme d'habitude,
  aucun item visuel/tactile (sous-titre date effectivement lisible en Biblio, translucidité du
  sheet effectivement lisible en plein soleil, geste appui-long → menu contextuel Stop
  effectivement déclenché du doigt) n'a pu être confirmé dans cet environnement — pas
  d'automatisation tactile disponible (limite documentée depuis it9).

- **Décision de design tranchée avec le propriétaire avant codage (Bloc 3)** : le prompt
  laissait explicitement ouvert le mécanisme du Stop défini ("to decide : appui long = Stop
  définitif, appui simple = Pause↔Play"). En creusant le code existant, appui long s'est avéré
  être DÉJÀ la convention systématique de toute l'app pour afficher une infobulle
  (`longPressTooltip`, sur tout bouton à icône seule) — le réutiliser pour déclencher un arrêt
  définitif aurait cassé ce réflexe partout ailleurs, avec un vrai risque d'arrêt accidentel du
  guidage en conditions gantées. Question posée, réponse : menu contextuel (`.contextMenu`)
  plutôt qu'un appui long fonctionnel direct — voir CLAUDE.md, section
  `isGuidanceStopped`/toggle, pour le détail.

- **Filet de secours conservé (Bloc 3)** : `RideConstants.guidanceButtonMode` permet de
  revenir instantanément au comportement à 2 boutons empilés d'it14 (`.twoButtons`) si le
  bouton toggle unique s'avère mal compris sur le terrain — code intact, pas supprimé.

## Itération 14 (roadbook rebuild / layout ride final / zoom)

- **Vérification de cette itération** : builds simulateur + device (compile-only) + suite de
  tests (54, 0 échec, 1 skip) verts après CHAQUE bloc et en final. Logique pure testée
  unitairement (`RoadbookAnalyzer.buildRoadbookEvents` — dont un vrai bug de mesure d'angle
  trouvé et corrigé en cours de route, voir plus bas ; `OffTrackHysteresisTests` pour le
  double seuil du Bloc 8 ; `TrackThumbnailGeometryTests` pour le plafond de chevrons Biblio).
  **Aucun item de la checklist "Vérifications avant merge" du prompt n'a pu être confirmé
  visuellement/tactilement** — pas d'automatisation tactile disponible dans cet environnement
  (limite déjà documentée it9-it13) : ni l'ancre à 75 % visuellement, ni le switch live de
  colonne, ni le toast/haptic Stop, ni le mode replay debug exercé par un vrai tap (implémenté
  et compile, mais jamais lancé à la main — validé seulement indirectement via les tests
  unitaires qui exercent le même chemin `handle(location:)`/fonctions pures), ni l'hystérésis
  hors-trace en conditions réelles (20 m/35 m/20 m de la checklist), ni la comparaison
  photo avant/après à vitesse et position identiques demandée par le propriétaire. Tout ceci
  relève de son propre protocole de test terrain, pas d'une simulation que j'aurais pu faire
  ici — à confirmer par le propriétaire lui-même avant de considérer l'itération pleinement
  validée.

- **Bug trouvé et corrigé en cours de développement (pas un TODO, juste tracé pour mémoire)** :
  la toute première implémentation de `buildRoadbookEvents` mesurait l'angle entrant/sortant
  par CORDE directe (bord de fenêtre → point central), copiant le patron de l'ancien
  `buildCheckpoints` — cette mesure sous-estime mathématiquement le virage cumulé sur une
  courbe progressive (une corde ≈ la tangente moyenne sur l'intervalle, pas la vraie variation
  de cap bout à bout). Détecté par un test qui échouait (`testGradualCurveDetectedViaWindow`),
  tracé à la main (courbe à 10 segments de 8°/20m : 24° mesurés par corde contre 48° réels).
  Corrigé par sommation pas-à-pas des deltas de cap segment par segment sur toute la fenêtre
  (voir `RoadbookAnalyzer.swift`). Sert de rappel : toujours dériver une mesure d'angle sur
  fenêtre par sommation télescopique, jamais par corde directe, dès qu'une courbe progressive
  (pas un simple coin net) peut se présenter.

- **Hygiène de staging git, documentée par honnêteté (aucun risque fonctionnel)** : le commit
  `fix:"biblio-chevrono-cap"` a embarqué par erreur le retrait (non lié) de
  `RideConstants.customStartPickRadiusMeters`, destiné à `refactor:"remove-start-choice"` —
  un reliquat de `git add -p` resté indexé puis inclus par un `git commit -m` sans pathspec.
  Par ailleurs, vu l'enchevêtrement réel du contenu des Blocs 4/5/6/7 dans les mêmes zones de
  `RideSessionManager.swift`, `RideSettingsStore.swift` et `NavigationSettingsView.swift`
  (constantes/propriétés/init écrites en continu au fil des blocs), j'ai choisi consciemment
  de ne PAS forcer un split `git add -p` plus loin pour ces 3 fichiers : chacun est entré
  intégralement dans le commit du bloc en cours d'écriture au moment où le fichier s'est
  stabilisé (Bloc 4 pour `RideSessionManager.swift`, Bloc 5 pour `RideSettingsStore.swift`/
  `SettingsView.swift`, Bloc 6 pour `NavigationSettingsView.swift`), chaque message de commit
  le documente explicitement. Aucun contenu perdu ni contradictoire, juste des frontières de
  commit pas parfaitement alignées bloc-par-bloc sur ces 3 fichiers précis.

- **Décision de scope assumée (Bloc 10, remove-start-choice)** : le contrôle "Départ" est
  retiré de `TrackSettingsView`/`TrackMapView`, mais `TrackRideSettings.customStartPointIndex`
  reste dans le modèle/la persistance (une valeur déjà enregistrée par un utilisateur avant
  cette itération continue de s'appliquer par défaut, comme demandé) — juste plus aucun moyen
  d'en DÉFINIR une nouvelle depuis l'UI. Si le besoin de repartir d'un point choisi à la main
  revient, il faudra soit rebrancher un contrôle dédié, soit l'unifier avec le sens A→B/B→A.

## Itération 13 (chevrons-live-refresh / biblio-track-fullsheet / map-theme-binding / zoom-out-unclamped / thick-label-live-thickness / offroad-routing-preference / home-work-favorites / temp-trace-dash-readability)

- **DÉCOUVERTE IMPORTANTE, NON RÉSOLUE : les chevrons de direction pourraient ne jamais
  s'afficher visuellement sur la VRAIE carte Ride (MapLibre), indépendamment du fix
  "chevrons-live-refresh" de ce bloc.** Trouvé en vérifiant ce fix par injection d'une trace
  synthétique (droite, 500 m plein nord, 11 points/50 m) + `simctl location` dans le
  simulateur (méthode déjà utilisée it12, code jamais commité) : le calque
  `direction-chevron-layer` existe bien dans le style courant, `isVisible=true`, zoom réel
  mesuré ≈18.8 (≫ `chevronMinZoom`=14), l'icône est enregistrée (`style.image(forName:)` non
  nil), et `updateChevronShape` rapporte avoir posé 4 features sur la source (`chevrons=4`,
  `source.shape` non-nil juste après l'affectation) — pourtant AUCUN triangle n'apparaît à
  l'écran sur 6 captures successives, avec plusieurs variantes testées sans succès :
  - Mise en cache de la source (`chevronSourceRef`, même patron que `trackSourceRef` déjà
    fiable pour la trace) — tentée, puis RETIRÉE (n'a rien changé, gardée hors du commit
    final pour ne pas ajouter un changement non justifié empiriquement).
  - Rotation forcée à une constante (0°) au lieu de l'expression `NSExpression(forKeyPath:
    "bearing")` — aucun changement, écarte un souci lié à l'expression data-driven.
  - Un lookup FRAIS de la source par identifiant (`style.source(withIdentifier:)`, indépendant
    du cache du Coordinator) rapporte `.shape == nil` juste après que `updateChevronShape`
    ait affirmé l'avoir posée avec succès sur SA PROPRE instance — signale une possible
    incohérence de lecture `.shape` selon l'instance de wrapper `MLNShapeSource`, mais la
    mise en cache (ci-dessus) n'a pourtant pas résolu le symptôme visuel, donc ce n'est
    probablement pas (ou pas seulement) la cause réelle.
  - Écarté : seuil de zoom (14, largement dépassé), thème/fond de carte (reproduit identique
    en raster ET en vectoriel hébergé), mémoïsation (le fix de ce bloc justement).
  - **Piste à creuser en priorité la prochaine session** : comparer avec le rendu des
    ANNOTATIONS (checkpoints/waypoints, `MLNPointAnnotation` via `mapView.addAnnotations`,
    mécanisme différent qui lui est confirmé fonctionnel visuellement dans des itérations
    passées) pour isoler si le problème est spécifique aux COUCHES DE STYLE SYMBOL
    (`MLNSymbolStyleLayer` + `MLNShapeSource`) en général sur cette version de MapLibre/ce
    simulateur, ou spécifique aux chevrons. Vérifier aussi avec une VRAIE trace importée
    (pas synthétique) et en conditions device réel (pas seulement simulateur) avant de
    conclure à un bug plutôt qu'un artefact de simulateur.
  - Le fix "chevrons-live-refresh" lui-même (mémoïsation par valeur plutôt que par clé
    aveugle à l'ordre) reste correct et committé tel quel — il corrige un vrai bug de cache
    indépendant de ce problème de rendu plus profond, mais son bénéfice VISIBLE réel ne
    pourra être confirmé qu'une fois ce second problème résolu ou infirmé.

- **Bloc 2 (biblio-track-fullsheet), décision de scope assumée** : le tap sur une ligne
  Biblio n'ouvre plus `TrackDetailView` (carte + "Utiliser pour le Ride" avec précache de
  tuiles), qui n'a donc plus de point d'entrée dans l'UI. Fichier intact (comme
  `RideModeSegmentedControl` it12), pas supprimé. "Utiliser pour le Ride" reste accessible
  (check-mark de ligne, TrackSettingsView) mais sans l'étape de précache. Pas explicitement
  demandé par le bloc ; à rouvrir un accès si le propriétaire en confirme le besoin.

- **Bloc 7 (home-work-favorites), décision de scope assumée** : pas de sélection "pan sur la
  carte" pour définir Domicile/Travail (demandée en alternative à la recherche) — recherche
  d'adresse (Nominatim) + "Utiliser ma position actuelle" couvrent le besoin réel sans
  construire un nouveau composant carte interactif (MKMapView dédié, iOS 16). À ajouter si
  réclamé explicitement.

- **Bloc 6 (offroad-routing-preference)** : réutilise le profil `.offroad` déjà documenté de
  `DetourRoutingService` (OSRM "cycling", seule approximation disponible sans clé ni serveur
  dédié — aucun profil "moto offroad" public). Alternatives documentées directement dans
  `DetourRoutingService.swift` (profil "foot", ou BRouter auto-hébergé/embarqué) si ce choix
  s'avère insuffisant en usage réel (terrain très accidenté, pistes mal cartographiées). Les
  estimations distance/durée sont des ESTIMATIONS à vitesse moyenne assumée par profil
  (70/30/50 km/h route/piste/mixte), PAS un ETA OSRM réel (jamais parsé côté service).

- **Vérification de cette itération** : builds simulateur + device + suite de tests (46,
  0 échec) verts après CHAQUE bloc. Logique pure testée unitairement (MapSourceResolver,
  GoToGuidance). Les items de la checklist terrain qui demandent une interaction tactile
  réelle (toggle Sens en Biblio, tap sur une ligne, Picker Thème/Épaisseur, recherche
  d'adresse) n'ont PAS pu être confirmés visuellement — pas d'automatisation tactile
  disponible dans cet environnement (limite déjà documentée it9-it12). Seule la vérification
  chevrons ci-dessus a été tentée par injection de code temporaire (jamais commité), et a
  débouché sur la découverte non résolue plutôt qu'une confirmation.

## Itération 12 (progress-marker / lateral-cap-banner / chevrons-100m / biblio-direction / raw-speed-1hz / hide-nav-tab) — idées annexes notées, non traitées

- **Fenêtre d'inflexion fixée à 150 m** (une seule valeur, `bannerInflectionWindowMeters`)
  plutôt que "100-150 m" comme deux seuils distincts — décision de scope assumée : une vraie
  "split" nette déclenche de toute façon largement dans une fenêtre de 150 m (tout l'angle
  tombe dans un petit sous-segment), donc une seule valeur couvre déjà les deux cas demandés
  (validé par test, voir RoadbookInflectionTests). À revisiter seulement si un virage réel
  s'avère mal détecté en usage (fenêtre trop courte ou trop longue pour un cas précis).
- **Validation paysage de la bannière latérale non faite** — même limite déjà documentée pour
  it9 (pas d'automatisation de rotation dans cet environnement), pas spécifique à ce bloc.
- **Fix "biblio-direction-live-refresh" vérifié par lecture de code + connaissance d'un bug
  SwiftUI documenté** (Canvas figé dans une List/Form), pas par confirmation visuelle
  simulateur (pas d'automatisation tactile pour actionner le Picker "Sens"). Logique de
  données déjà prouvée correcte avant le fix ; à confirmer par le propriétaire au prochain
  test terrain.
- **Captures AVANT/APRÈS bannière latérale (300/200/100/90/80 m) obtenues via injection de
  trace synthétique + `simctl location`** (pas de trace réelle, pas de tap UI possible) —
  méthode temporaire (code jamais commité, voir historique de session), donc pas une trace
  GPX réelle importée par l'utilisateur. À reconfirmer en conditions réelles (vraie trace,
  vrai déplacement) dès que possible. Note technique : `simctl location set` répété
  rapidement (quelques secondes d'écart) peut accumuler un décalage/une animation résiduelle
  de la position affichée — un seul `set` par position + attente ~4 s avant capture donne un
  résultat exact ; utile à savoir pour toute capture future du même genre.

## Itération 11 (2d-only / biblio-preview-direction / vector-pmtiles) — idées annexes notées, non traitées

- **Mode avion + paquet `.pmtiles` importé non testé de bout en bout** : `MapSourceResolver`
  est testé unitairement (4 tests, priorité local > hébergé > raster) et la logique de lecture
  `pmtiles://file://...` s'appuie sur le support natif MapLibre (vérifié dans les headers
  vendored), mais il n'existe pas de vrai fichier `region.pmtiles` dans cet environnement pour
  un test bout-en-bout réel (import → coupure réseau simulateur → vérification visuelle). À
  faire une fois `docs/generation-tuiles-regionales.md` exécuté sur le NAS et un premier
  `.pmtiles` réel disponible.
- **Dimming nuit non implémenté côté fond vectoriel** — décision de scope assumée au commit
  "vector-pmtiles" : repeindre les ~110 couches du style Liberty pour une variante sombre
  était hors budget de cette itération. VersaTiles (documenté dans `docs/tuile-sources.md`)
  fournit déjà des builds clair/sombre prêts à l'emploi — piste la plus rapide si le besoin
  devient réel, plutôt que de repeindre le style Liberty à la main.
- **Pas d'empreinte région (bbox/zoom) affichée pour un paquet vectoriel** dans
  `VectorPackagesView` — lire l'en-tête PMTiles côté Swift aurait demandé soit une dépendance
  supplémentaire, soit un parseur maison du format d'en-tête PMTiles (magic bytes + métadonnées
  compressées) ; l'écran affiche taille/date/nom uniquement. À revisiter si le propriétaire
  gère plusieurs paquets régionaux et a besoin de les distinguer sans les renommer à la main.
- **Attribution OpenTopoMap corrigée en passant** (bug pré-existant, pas une regression de
  cette itération) : `OSMAttributionView` affichait toujours le texte OSM générique, y compris
  sous le thème Relief (OpenTopoMap, qui a sa propre exigence d'attribution SRTM/CC-BY-SA) —
  corrigé au même endroit que le câblage de l'attribution vectorielle, voir commit
  "vector-pmtiles".

## Itération 10 — idées annexes notées, non traitées

- **Test "sans réseau" pour resume-at-point non fiable à écrire tel quel** :
  `RideSessionManager.requestResume` dégrade honnêtement (pin + vol d'oiseau, message clair)
  quand `networkMonitor.isReachable == false`, mais le simulateur a un vrai accès réseau et
  `NetworkMonitor` s'appuie sur `NWPathMonitor` (pas d'état forçable depuis un test). Pour
  tester ce chemin de façon déterministe, il faudrait extraire un petit protocole
  `NetworkReachability` (`var isReachable: Bool`) que `NetworkMonitor` implémenterait, et
  typer `RideSessionManager.networkMonitor`/`NavRoutingService.route(networkMonitor:)` sur ce
  protocole plutôt que la classe concrète — repoussé cette itération (pas demandé, risque de
  toucher plusieurs fichiers pour un seul test). Le test actuel
  (`ResumeGuidanceTests.testRequestResumeStartsUnroutedBeforeAnyNetworkResponse`) vérifie à la
  place que le mode "non routé" est garanti tant qu'aucune réponse réseau n'est arrivée.

## Itération 9 (stabilisation UI) — idées annexes notées, non traitées

Consigne explicite de cette itération : "aucune nouvelle feature, si tenté d'améliorer
autre chose, note-le ici à la place." Voici ce qui a été repéré en marge des 6 bugs
demandés, volontairement laissé de côté :

- **Chrome secondaire sous 56pt** : icône recherche (40×40), bascule 2D/3D (40×40),
  sous-boutons de catégorie du panneau POI (48×48) sont plus petits que les boutons
  critiques (≥56pt, déjà conformes). Le Bug 6 ne visait que les boutons critiques
  ("gants") — uniformiser aussi ce chrome secondaire à 56pt serait un choix de design
  à valider (risque de surcharger l'écran), pas un bug d'affichage.
- **Bug 1 (nav-route-overlay), cause racine non isolée avec certitude** : l'ancien
  rendu suivait déjà le patron du détour (fonctionnel), sans defect structurel trouvé.
  Si le symptôme "route invisible" réapparaît malgré la reconstruction de ce commit, il
  faudrait instrumenter `NavigationCoordinator`/`updateNavRouteShape` avec un compteur
  de features pour confirmer que `source.shape` reçoit bien une géométrie non vide au
  moment du symptôme (piste de debug, pas un fix).
- **Validation paysage non faite cette itération** : toutes les captures de vérification
  (grille, ancrage position) ont été prises en portrait uniquement — pas d'automatisation
  de rotation disponible dans cet environnement. `RideOverlayLayout.landscapeSidePanelWidth`
  existe déjà mais n'a pas été revérifiée visuellement pour cette itération.
- **Overlay POI/paramètres "centré" (validation Bug 5)** : n'a pas pu être capturé en
  simulateur faute d'automatisation tactile pour ouvrir la feuille de recherche/réglages ;
  vérifié uniquement par lecture de code (alignements relatifs, pas d'offset absolu).

## Thème Relief : Option A retenue (raster OpenTopoMap), Option B non tentée

**Choix assumé** : Option A (tuiles raster OpenTopoMap toutes prêtes) est implémentée et
active. Option B (hillshade MapLibre via une source DEM comme les AWS Terrain Tiles /
`elevation-tiles.openstreetmap.fr`) n'a pas été tentée dans cette session.

### Pourquoi Option A plutôt que B

- Option A fonctionne immédiatement avec l'infrastructure déjà en place (même mécanisme
  d'interception/cache que les tuiles OSM standard, juste une deuxième `TileSource`) —
  fiable, zéro nouvelle dépendance, ToS claire (attribution obligatoire, déjà affichée).
- Option B (hillshade sur un fond OSM standard) est visuellement supérieure en théorie
  (relief vectoriel superposable à n'importe quel style) mais demande une source DEM dont
  la fiabilité/gratuité à long terme n'a pas pu être vérifiée dans cette session (la spec
  elle-même anticipait ce risque : "si la source DEM pose un souci de fiabilité/clé →
  fallback Option A"). Plutôt que de livrer un hillshade non testé, l'agent a choisi
  directement le fallback documenté.

### Compromis honnête

- Relief en raster = image pré-rendue : pas de recolorisation possible (contrairement à un
  hillshade vectoriel qui s'adapterait à un thème sombre par exemple). Le thème Relief
  ignore volontairement le mode nuit (`isNightModeActive` retourne `false` pour `.relief`
  dans `RideView`/`TrackDetailView`) plutôt que d'assombrir artificiellement une image qui
  n'a pas été conçue pour ça.
- Zoom plafonné à 17 (`TileSource.openTopoMap.maxZoomLevel`) — OpenTopoMap ne sert pas de
  tuiles au-delà, contrairement à OSM standard (19).
- MapKit (comparaison, non actif) simule Relief via un simple `MKTileOverlay` sur un seul
  sous-domaine (`a.tile.opentopomap.org`) — pas de cache disque partagé avec MapLibre côté
  MapKit, ce chemin n'est pas celui testé/documenté pour l'usage hors-ligne réel.

### Pour tenter Option B plus tard

1. Source DEM candidate : `https://elevation-tiles-prod.s3.amazonaws.com/terrarium/{z}/{x}/{y}.png`
   (AWS Terrain Tiles, terrarium encoding) — vérifier d'abord la disponibilité/CORS/ToS
   actuelles (aucune garantie de pérennité, projet tiers).
2. Ajouter un cas `TileSource` dédié (ex. `.hillshadeDEM`) + une couche
   `MLNHillshadeStyleLayer` (existe côté MapLibre) par-dessus le raster OSM standard, avec
   `hillshadeExaggeration`/`hillshadeShadowColor` réglables.
3. Garder le fallback Option A automatique si le premier fetch DEM échoue (timeout court,
   ne jamais bloquer l'affichage de la carte).

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
