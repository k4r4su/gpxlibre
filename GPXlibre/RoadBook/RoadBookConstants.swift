import CoreGraphics
import Foundation

/// Constantes du Road Book et de son export PDF (spec "roadbook-mode", it23) — domaine
/// entièrement nouveau, fichier dédié plutôt qu'ajouté à `RideConstants`/`NavigationConstants`
/// (même patron qu'`OfflineConstants`/`NavConstants` : chaque domaine porte les siennes,
/// "constantes localisables pour toute valeur sensible", demande explicite de la fiche).
enum RoadBookConstants {
    // MARK: - Lecture Assisté GPS

    /// Rayon de "manœuvre atteinte" — au-delà, la ligne courante avance à la suivante. Généreux
    /// (pas besoin de la précision "vraie arrivée" du guidage riche Ride) : le Road Book est un
    /// filet de lecture, pas un second moteur de guidage.
    static let liveManeuverReachedRadiusMeters: Double = 40

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

    // MARK: - Enrichissement par repères OSM (spec "roadbook-mode", it23quater)

    /// Overpass API (OSM public, gratuit, aucune clé — même philosophie que Nominatim déjà
    /// utilisé ailleurs dans l'app) : seul service permettant d'interroger des tags OSM
    /// arbitraires (église, rond-point, revêtement...) autour d'un point — Nominatim (déjà
    /// utilisé pour la recherche d'adresse) ne fait que du géocodage inverse d'adresse, pas une
    /// recherche de tags à proximité.
    static let overpassBaseURLString = "https://overpass-api.de/api/interpreter"
    /// Rayon de recherche autour de chaque point de manœuvre — assez large pour capter un
    /// repère visible depuis la route (église en léger retrait, rond-point dont le centre n'est
    /// pas exactement sur le point détecté), assez restreint pour rester PERTINENT au virage
    /// lui-même (pas un repère à 200 m qui n'a rien à voir avec CE virage précis).
    static let landmarkSearchRadiusMeters: Double = 40
    static let landmarkRequestTimeoutSeconds: Double = 8
    /// ToS Overpass (instance publique partagée) : pas de limite stricte documentée comme
    /// Nominatim (1 req/s), mais même discipline appliquée par précaution et pour éviter de
    /// saturer un service gratuit partagé avec de nombreuses manœuvres à interroger d'un coup.
    static let landmarkMinRequestIntervalSeconds: Double = 1.0
    /// Nombre max d'éléments OSM renvoyés par requête — assez large pour que le décompte de
    /// bâtiments à proximité (voir `RoadbookLandmark`, détection "maison isolée") reste fiable
    /// même si d'autres tags (commerces, etc.) matchent aussi au même endroit.
    static let landmarkResultLimit = 30

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
    static let focusedHeroLandscapeHeight: Double = 170

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

    /// Largeur max du sélecteur de mode en paysage (fix "roadbook-landscape-picker-stretched",
    /// it25, retour terrain avec capture : un `.segmented` sans largeur bornée s'étire sur toute
    /// la largeur, démesuré sur un écran deux fois plus large qu'en portrait) — portrait
    /// inchangé (`.infinity`, déjà confirmé correct par capture terrain).
    static let modePickerLandscapeMaxWidth: Double = 420
}
