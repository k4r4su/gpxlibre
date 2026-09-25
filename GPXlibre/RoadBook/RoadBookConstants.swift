import CoreGraphics
import Foundation

/// Constantes du Road Book et de son export PDF (spec "roadbook-mode", it23) — domaine
/// entièrement nouveau, fichier dédié plutôt qu'ajouté à `RideConstants`/`NavigationConstants`
/// (même patron qu'`OfflineConstants`/`NavConstants` : chaque domaine porte les siennes,
/// "constantes localisables pour toute valeur sensible", demande explicite de la fiche).
enum RoadBookConstants {
    // MARK: - Lecture Assisté GPS

    /// Distance (m) après avoir ATTEINT une manœuvre pendant laquelle elle reste affichée
    /// (figée à "0 m") avant de basculer sur la suivante — fix "roadbook-live-progress-hold",
    /// retour terrain : "j'ai l'impression que la direction change 15/20 m avant le virage,
    /// j'aimerais qu'une fois arrivé à zéro, la direction reste encore 10/20 m après le virage".
    /// Root cause de l'ancien comportement (anticiper le changement 40 m AVANT d'arriver,
    /// `liveManeuverReachedRadiusMeters` ci-avant) : voir `RoadbookLiveProgress.nextManeuver`,
    /// qui bascule désormais sur la manœuvre atteinte elle-même puis la maintient cette durée —
    /// SAUF virages enchaînés (voir ce même fichier), où le maintien serait contre-productif.
    static let liveManeuverHoldAfterMeters: Double = 15

    // MARK: - Overpass (OSM public, gratuit, aucune clé)

    /// Seul service permettant d'interroger des tags OSM arbitraires le long d'une trace —
    /// Nominatim (recherche d'adresse) ne fait que du géocodage.
    static let overpassBaseURLString = "https://overpass-api.de/api/interpreter"

    // MARK: - Repères visibles (jalon it28 — "uniquement ce que le conducteur voit")

    /// Catégories ACTIVÉES par défaut (menu Réglages > Repères du Road Book, "Réinitialiser") —
    /// toutes les autres catégories du catalogue (`RoadbookLandmarkCategory`, famille "Autres")
    /// sont désactivées par défaut.
    static let landmarkDefaultEnabledCategories: Set<RoadbookLandmarkCategory> = [
        .citySign, .stopSign, .giveWaySign, .trafficSignals, .levelCrossing,
        .speedBump, .bridge, .tunnel,
        .church, .townHall, .waterTower, .mill, .waysideCross, .castle,
        .fuel, .chargingStation,
    ]
    /// Rayon de VISIBILITÉ par catégorie (m, distance à la trace) : petit pour ce qui est SUR la
    /// route (panneau, ralentisseur), large pour ce qui se voit de loin (clocher, château d'eau,
    /// éolienne) ; pour un service, rayon de DÉTOUR raisonnable (la distance est affichée).
    /// Catégorie absente : jamais retenue.
    static let landmarkVisibilityRadiusMeters: [RoadbookLandmarkCategory: Double] = [
        // Panneaux
        .citySign: 30, .stopSign: 20, .giveWaySign: 20, .trafficSignals: 25, .levelCrossing: 20,
        // Infrastructure
        .speedBump: 12, .bridge: 8, .tunnel: 8,
        // Bâtiments et ouvrages
        .church: 150, .townHall: 60, .waterTower: 200, .mill: 150, .waysideCross: 30, .castle: 250,
        // Services
        .fuel: 250, .chargingStation: 250,
        // Autres
        .parking: 40, .restArea: 80, .drinkingWater: 20, .restaurant: 40, .cafe: 40, .bakery: 30,
        .supermarket: 80, .pharmacy: 30, .hotel: 60, .campsite: 150, .trainStation: 120, .school: 60,
        .cemetery: 100, .memorial: 30, .windTurbine: 500, .antenna: 300, .lighthouse: 500, .tower: 200,
    ]
    /// Priorité FIXE entre familles, de la plus forte à la plus faible — le carrefour lui-même
    /// (la manœuvre, rond-point compris) passe avant tout repère. À famille égale : ordre du
    /// catalogue (`RoadbookLandmarkCategory.allCases`), puis le plus proche de la trace.
    static let landmarkGroupPriority: [RoadbookLandmarkCategory.Group] = [.sign, .infrastructure, .service, .building, .other]
    /// Services (carburant, recharge) : jamais soumis à la limite de densité des repères de
    /// repérage ni rattachés à un virage — seul un doublon de la même catégorie à moins de ça
    /// (station cartographiée en nœud ET en surface) est fusionné.
    static let landmarkServiceMergeMeters: Double = 100
    /// Service : distance à la trace affichée ("à droite, 120 m") au-delà de ça.
    static let landmarkServiceShowDistanceFromMeters: Double = 30
    /// Un repère à moins de ça (le long de la trace) d'un changement de direction sert à
    /// identifier CE carrefour : affiché avec la manœuvre (le plus prioritaire seulement), jamais
    /// en ligne séparée.
    static let landmarkJunctionRadiusMeters: Double = 40
    /// Au plus N repères en ligne dédiée par tronçon entre deux changements de direction.
    static let landmarkMaxPerSegment = 1
    /// Deux repères à moins de ça l'un de l'autre : seul le plus prioritaire reste.
    static let landmarkMergeMeters: Double = 150
    /// Élément posé sur une chaussée (panneau, passage piéton, ralentisseur...) : retenu seulement si
    /// sa route porteuse est dans l'axe de la trajectoire d'ARRIVÉE du pilote à cette tolérance près
    /// (degrés, dans un sens ou l'autre). Validé sur une trace réelle : sans ce filtre, les stops et
    /// cédez-le-passage des rues latérales ressortaient tout au long des lignes droites.
    static let landmarkRoadAlignmentToleranceDegrees: Double = 30
    /// Trajectoire d'arrivée = corde des N derniers mètres avant le repère (sens, côté, alignement).
    static let landmarkApproachMeters: Double = 30
    /// Sous cette distance latérale, le repère est SUR la route (passage piéton, pont) : pas de côté.
    static let landmarkSideMinOffsetMeters: Double = 4
    /// Panneau avec `direction=<cap>` : il FAIT FACE aux usagers concernés — retenu si le sens de
    /// marche est opposé à ce cap à cette tolérance près (degrés).
    static let landmarkSignFacingToleranceDegrees: Double = 80
    /// Requête Overpass : trace échantillonnée tous les N m (au moins), plafonnée en points ; le
    /// rayon interrogé = pas + rayon de visibilité de la catégorie.
    static let landmarkQuerySampleSpacingMeters: Double = 250
    static let landmarkQueryMaxPolylinePoints = 600
    /// Téléchargement découpé en TRONÇONS de trace de cette longueur (une requête chacun) : c'est
    /// l'unité de la barre de progression, et les repères apparaissent au fur et à mesure.
    static let landmarkQueryChunkMeters: Double = 8000
    /// Débit affiché = octets reçus sur cette fenêtre glissante (lissage).
    static let landmarkProgressSpeedWindowSeconds: Double = 3
    /// Pas de débit affiché avant ça (valeur non significative au démarrage).
    static let landmarkProgressSpeedMinSeconds: Double = 1
    /// Temps restant affiché seulement après ce nombre de tronçons terminés (estimation stable).
    static let landmarkProgressMinChunksForEstimate = 1
    /// Le bandeau n'apparaît qu'après ce délai : un chargement quasi instantané ne clignote pas.
    static let landmarkProgressShowDelaySeconds: Double = 0.6
    /// Rafraîchissement du débit et du temps restant pendant le téléchargement.
    static let landmarkProgressRefreshSeconds: Double = 0.5
    /// Durée d'affichage de l'état "Terminé" avant que l'indicateur ne disparaisse.
    static let landmarkProgressDoneDisplaySeconds: Double = 2
    static let landmarkRequestTimeoutSeconds: Double = 90
    /// L'instance Overpass publique renvoie par intermittence 429/504 (mesuré au jalon it28 : un
    /// tronçon sur quatre en 504 après ~9 s, le même accepté à l'essai suivant) : nouveaux essais
    /// PAR TRONÇON après ces pauses, puis échec propre ("Réessayer" reprend à ce tronçon). Deux
    /// autres instances publiques testées (private.coffee, kumi.systems) : plus lentes, autant de
    /// 504 — pas de bascule d'instance.
    static let landmarkRetryDelaysSeconds: [Double] = [5, 15, 30]
    /// Repli "Entrée de <localité>" (it29) — ACTIF par défaut. Diagnostic sur la trace de test
    /// réelle (27 km, 11 villages traversés) : UN SEUL panneau `city_limit` cartographié dans OSM
    /// (Hundsbach) ; les autres villages n'en ont aucun. Le repli place l'entrée là où la trace
    /// entre dans la ZONE BÂTIE (`landuse=residential`, ou polygone `place` s'il existe) — là où se
    /// dresse le vrai panneau : à Hundsbach, zone bâtie à 18,91 km, panneau OSM à 18,90 km — et la
    /// nomme d'après le nœud `place` le plus proche. Un panneau cartographié gagne toujours.
    static let landmarkCityEntryFallbackEnabled = true
    /// Échantillonnage de la trace pour détecter l'entrée dans une zone bâtie.
    static let landmarkCityEntrySampleMeters: Double = 10
    /// Deux passages en zone bâtie séparés de moins de ça = une seule traversée (zones
    /// résidentielles morcelées d'un même village).
    static let landmarkCityEntryMergeGapMeters: Double = 300
    /// Traversée plus courte que ça (après fusion) : ferme ou lotissement isolé, pas une entrée.
    static let landmarkCityEntryMinRunMeters: Double = 150
    /// Dans une zone bâtie, la localité (nœud `place` le plus proche) est réévaluée tous les N m :
    /// villages mitoyens dont les zones bâties se touchent.
    static let landmarkCityEntryNameCheckMeters: Double = 50
    /// Un changement de localité à l'intérieur d'une zone bâtie doit tenir au moins ça (hystérésis).
    static let landmarkCityEntryNameMinStretchMeters: Double = 100
    /// Portée d'un nœud `place` : il nomme une zone bâtie jusqu'à cette distance du point d'entrée
    /// — une ville a son nœud au centre, loin de ses bords. Un `suburb` n'est retenu que hors de
    /// portée de toute ville (`town`/`city`) : on entre dans "Mulhouse", pas dans un quartier ;
    /// mais dans "Oberdorf" (ancien village d'une commune nouvelle).
    static let landmarkCityEntryPlaceReachMeters: [RoadbookPlace.Kind: Double] = [.city: 5000, .town: 3000, .village: 1500, .suburb: 1500]
    /// Nœud `village` avec un `suburb` à moins de ça : siège d'une commune nouvelle (Illtal), écarté
    /// au profit des anciens villages (`suburb`) dont les panneaux portent le nom.
    static let landmarkCityEntryParentSeatMeters: Double = 500
    /// Panneau cartographié à moins de ça d'une entrée calculée : le panneau seul est affiché.
    static let landmarkCityEntrySignDedupMeters: Double = 400
    /// La requête Overpass des nœuds `place` couvre ces portées (au-delà du pas d'échantillonnage).

    // MARK: - Export PDF

    /// A4 à 72 dpi (unité native PDFKit/UIGraphicsPDFRenderer, indépendante de l'orientation —
    /// `RoadbookPDFExporter` permute largeur/hauteur selon `PDFOrientation`).
    static let pdfPageWidthPoints: CGFloat = 595.2
    static let pdfPageHeightPoints: CGFloat = 841.8
    static let pdfMarginPoints: CGFloat = 32
    static let pdfHeaderHeightPoints: CGFloat = 64

    /// Hauteur de ligne selon la densité choisie — pilote directement le nombre de manœuvres
    /// par page (calculé depuis la hauteur de page réelle, jamais un nombre de lignes fixe codé
    /// en dur qui se désynchroniserait si la police ou les marges changent).
    static let pdfRowHeightCompact: CGFloat = 22
    static let pdfRowHeightComfortable: CGFloat = 32

    static let pdfFontSizeSmall: CGFloat = 8
    static let pdfFontSizeMedium: CGFloat = 10
    static let pdfFontSizeLarge: CGFloat = 13

    /// Largeurs de colonnes (fraction de la largeur de contenu disponible) — se répartissent le
    /// reste entre elles si une colonne optionnelle (cumulée/note) est masquée, voir
    /// `RoadbookPDFExporter.columnLayout(options:contentWidth:)`.
    static let pdfPartialColumnFraction: CGFloat = 0.16
    static let pdfCumulativeColumnFraction: CGFloat = 0.16
    static let pdfHeadingColumnFraction: CGFloat = 0.18
    // Le reste de la largeur disponible revient toujours à la colonne note (voir
    // columnLayout) — pas de fraction fixe ici, elle absorbe l'espace restant.

    /// Couleur d'accent des pictogrammes (spec : "réutiliser le style visuel du logo — chevrons,
    /// dégradé orange/rouge en accents — pas nécessairement en fond de page pour rester
    /// imprimable en niveaux de gris") — une seule teinte plate plutôt qu'un vrai dégradé par
    /// glyphe (un dégradé par petit pictogramme serait imperceptible et compliquerait le rendu
    /// PDF pour rien) ; rendu correctement en gris moyen sur une impression noir & blanc.
    /// PLUS seulement le PDF depuis it24 (point 2) — `RoadbookPictograms.swift` (écrans) réutilise
    /// EXACTEMENT la même valeur (`Color(red:green:blue:)`), un seul repère visuel dans toute
    /// l'app plutôt que deux teintes "orange" indépendantes qui pourraient dériver l'une de
    /// l'autre au fil des itérations.
    static let pdfAccentColorRGB: (red: CGFloat, green: CGFloat, blue: CGFloat) = (0.92, 0.35, 0.15)

    // MARK: - Pictogrammes enrichis (spec "roadbook-route-aware-maneuvers", it24, point 2)

    /// Rond-point : angle (degrés, 0 = tout droit/12h, sens HORAIRE positif) entre deux sorties
    /// consécutives — convention visuelle FIXE, Valhalla ne fournit que le RANG de la sortie
    /// prise (`roundabout_exit_count`), jamais la géométrie réelle des sorties intermédiaires.
    /// 45° laisse la place à 7 sorties avant de boucler sur 315°, largement au-delà de la
    /// quasi-totalité des ronds-points rencontrés en usage réel.
    static let roundaboutExitSpacingDegrees: Double = 45

    // MARK: - Palette jour/nuit (spec "roadbook-ui-redesign", it25, point 0)

    /// Repli SANS position GPS (permission refusée/pas encore de fix) — heuristique horaire
    /// simple, jamais une fausse précision astronomique qu'on ne peut pas calculer sans
    /// coordonnées. Plage large et prudente (7h-20h) plutôt que calée sur un lever/coucher moyen.
    static let paletteFallbackDayStartHour = 7
    static let paletteFallbackDayEndHour = 20
    /// Fréquence de réévaluation de la palette automatique pendant que l'écran est ouvert — le
    /// lever/coucher du soleil ne change jamais assez vite pour justifier plus fréquent, mais
    /// sans ce filet, un roadbook ouvert à cheval sur le coucher du soleil resterait figé sur la
    /// palette du moment de l'ouverture jusqu'au prochain changement de trace/onglet.
    static let paletteReevaluationIntervalSeconds: Double = 300

    // MARK: - Mode Assisté GPS : carte hero + liste (spec "roadbook-ui-redesign", it25, points 1/2)

    /// "Au moins la moitié de l'écran" (spec it23ter, réaffirmé it25) — fraction de la hauteur
    /// disponible en PORTRAIT. En paysage, hauteur FIXE bien plus compacte à la place (voir
    /// `focusedHeroLandscapeHeight`) : sur un écran deux fois moins haut, la même fraction
    /// laisserait beaucoup trop peu de place à la liste scrollable en dessous.
    static let focusedHeroHeightFraction: Double = 0.5
    static let focusedHeroMinHeight: Double = 220
    /// Hauteur FIXE de la carte hero en paysage — layout dédié horizontal (pictogramme à gauche,
    /// distance à droite), volontairement compact pour laisser de la place à la liste et ne
    /// jamais chevaucher la tab bar (retour terrain : "634 m"/"Virage prononcé" qui chevauchent").
    /// Augmentée de 170 à 210 une fois le sélecteur de mode déplacé dans une colonne à droite
    /// plutôt qu'une bande en haut (retour terrain : "donner la priorité à la direction et la
    /// distance") — la hauteur ainsi libérée revient à la carte hero plutôt que de rester
    /// inexploitée.
    static let focusedHeroLandscapeHeight: Double = 210
}
