# TODO

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
- **Satellite : backlog documenté, PAS implémenté** (même traitement que la clé TomTom du Bloc
  Trafic, it13) — aucune source satellite gratuite et réutilisable hors-ligne trouvée :
  Esri/Google/Bing World Imagery imposent des CGU incompatibles avec un cache PMTiles
  auto-hébergé façon it11 (redistribution/mise en cache de tuiles satellite hors des quotas
  gratuits interdite ou payante). Ajouter Satellite sans réseau, ou en violant ces CGU, serait
  contraire à la philosophie hors-ligne-d'abord de l'app. Piste si le besoin devient réel : une
  clé Maxar/Mapbox Satellite payante avec cache local respectant leurs CGU, ou une source
  ouverte type Sentinel-2 cloudless (EOX, résolution/fraîcheur bien inférieures à du satellite
  commercial, mais réellement libre de droits) — aucune des deux tentée ici, décision produit à
  prendre en amont (coût/qualité), pas une implémentation technique bloquée.
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
