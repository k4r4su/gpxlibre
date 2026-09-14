import Foundation

/// Textes pédagogiques de l'encart "Comprendre le zoom max" (spec "tiles-zoom-explainer",
/// it17, Bloc 2) — regroupés en constantes plutôt qu'écrits en dur dans la vue, pour rester
/// facilement remplaçables par un mécanisme de localisation le jour où l'app en aura un
/// (aucune infrastructure `Localizable.strings`/`String(localized:)` dans le projet à ce jour
/// — pas ajoutée ici, hors périmètre de ce bloc, qui ne demande que des constantes prêtes à
/// migrer). Contenu conforme aux conventions standard OSM de niveaux de zoom (z10 ≈ ville, z12
/// ≈ rue, z14 ≈ bâtiment).
enum OfflineExplainerText {
    static let title = "Comprendre le zoom max"

    static let body = """
    Le zoom max correspond au niveau de détail pré-téléchargé. En dessous de ce niveau, la carte reste parfaitement nette hors-ligne. Au-delà, l'app agrandit une tuile existante (moins nette). Plus le niveau est élevé, plus le téléchargement est volumineux.

    z10 : villes et routes principales
    z12 : rues secondaires
    z13 à 14 : chemins et bâtiments

    Choisis en fonction de la zone parcourue.
    """
}
