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
    static let miniMapSpanMetersDefault: Double = 700
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
    static let pdfAccentColorRGB: (red: CGFloat, green: CGFloat, blue: CGFloat) = (0.92, 0.35, 0.15)
}
