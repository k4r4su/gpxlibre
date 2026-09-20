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
