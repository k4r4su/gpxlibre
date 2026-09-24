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

    /// Portée de la mini-carte en mode Assisté GPS — PAS la trace complète, juste de quoi
    /// confirmer visuellement qu'on est au bon endroit localement (spec "roadbook-focused-next-
    /// turn", it23ter). Resserrée en it23quinquies (retour terrain : "zoomé beaucoup plus...
    /// qu'on voit les 400 mètres de chaque côté, peut-être même 300") — 700 m de portée totale
    /// (~350 m de chaque côté du point central), RÉGLABLE par l'utilisateur (`RideSettingsStore.
    /// roadbookMiniMapSpanMeters`, cette constante n'est plus que la valeur par défaut).
    static let miniMapSpanMetersDefault: Double = 400
    static let miniMapSpanMetersRange: ClosedRange<Double> = 200...1500
    static let miniMapSpanMetersStep: Double = 100

    /// Position par défaut de la mini-carte flottante (fraction de la zone disponible, 0...1)
    /// — coin bas-droit, comme avant qu'elle devienne déplaçable (it23quinquies, retour terrain :
    /// "il faudrait pouvoir la changer à la volée, comme une fenêtre qu'on peut déplacer").
    static let miniMapDefaultPositionXFraction: Double = 0.82
    static let miniMapDefaultPositionYFraction: Double = 0.82

    // MARK: - Overpass (OSM public, gratuit, aucune clé)

    /// Seul service permettant d'interroger des tags OSM arbitraires le long d'une trace —
    /// Nominatim (recherche d'adresse) ne fait que du géocodage.
    static let overpassBaseURLString = "https://overpass-api.de/api/interpreter"

    // MARK: - Repères visibles (itération "repères = uniquement ce que le conducteur voit")

    /// Rayon de VISIBILITÉ par catégorie (m, distance à la trace) : petit pour ce qui est SUR la
    /// route (panneau, marquage), large pour ce qui se voit de loin (clocher, château d'eau).
    /// Catégorie absente : jamais retenue.
    static let landmarkVisibilityRadiusMeters: [RoadbookLandmarkCategory: Double] = [
        .citySign: 25, .stopSign: 20, .giveWaySign: 20, .trafficSignals: 25, .levelCrossing: 20,
        .pedestrianCrossing: 12, .speedBump: 12, .bridge: 8, .tunnel: 8,
        .church: 150, .townHall: 60, .fuel: 40, .waterTower: 200, .mill: 150, .waysideCross: 30,
        .remarkableStructure: 150,
    ]
    /// Priorité FIXE entre familles, de la plus forte à la plus faible (le carrefour lui-même,
    /// c'est-à-dire la manœuvre, passe avant tout repère). À famille égale : ordre de
    /// `RoadbookLandmarkCategory.allCases` (l'entrée d'agglomération d'abord), puis le plus proche
    /// de la trace.
    static let landmarkGroupPriority: [RoadbookLandmarkCategory.Group] = [.sign, .ground, .building]
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
    /// rayon interrogé = pas + rayon de visibilité max de la famille.
    static let landmarkQuerySampleSpacingMeters: Double = 250
    static let landmarkQueryMaxPolylinePoints = 600
    static let landmarkRequestTimeoutSeconds: Double = 90
    /// L'instance Overpass publique renvoie par intermittence 429/504 : nouveaux essais après ces
    /// pauses, puis abandon propre (Road Book sans repères, cache existant conservé).
    static let landmarkRetryDelaysSeconds: [Double] = [5, 15]
    /// Repli "entrée de localité" quand AUCUN panneau n'est cartographié : passage sur une route
    /// limitée à 50 km/h / `FR:urban`. DÉSACTIVÉ par défaut (ce n'est pas un repère visible en soi,
    /// seulement un indice) — un panneau cartographié gagne toujours.
    static let landmarkUrbanEntryFallbackEnabled = false
    /// Repli ci-dessus : trace considérée "en zone urbaine" à moins de ça d'une route urbaine...
    static let landmarkUrbanWayMatchMeters: Double = 12
    /// ...après au moins ça hors zone urbaine, et jamais à moins de ça d'un panneau cartographié.
    static let landmarkUrbanEntryMinGapMeters: Double = 300

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

    // MARK: - Mini-carte en paysage (spec "roadbook-ui-redesign", it25, point 2)

    /// Taille FIXE (pas une fraction de `containerSize`, root cause du bug terrain "mini-carte
    /// réduite à une bande illisible" — une fraction de hauteur calculée sur un écran deux fois
    /// moins haut qu'en portrait produisait un bandeau écrasé) — ancrée dans un coin dédié via
    /// `.overlay(alignment:)`, jamais déplaçable en paysage (voir RoadbookLandscapeMiniMap).
    static let miniMapLandscapeWidth: Double = 150
    static let miniMapLandscapeHeight: Double = 100
    /// En dessous de cette hauteur de conteneur disponible, la mini-carte est MASQUÉE plutôt
    /// qu'affichée à moitié cassée (demande explicite : "pas de compromis à moitié cassé") — un
    /// iPhone en paysage avec le clavier ouvert, par exemple.
    static let miniMapLandscapeMinContainerHeight: Double = 170
}
