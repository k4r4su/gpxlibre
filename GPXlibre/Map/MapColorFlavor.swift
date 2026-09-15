import Foundation

/// Palette de couleurs "maison" appliquée au MÊME squelette de style vectoriel (spec
/// "map-color-flavors", it19) — inspiré du système de Flavors de Protomaps (un objet de palette
/// réutilisable sur un seul style paramétré, plutôt que des styles indépendants), mais
/// implémenté nativement sur le style Liberty déjà embarqué plutôt que de migrer vers le schéma
/// de tuiles propre à Protomaps. Vérifié avant de coder (voir TODO.md) : le système officiel
/// `@protomaps/basemaps` ne s'applique QUE sur le schéma de tuiles Protomaps (10 couches
/// thématiques dérivées de Tilezen) — "l'organisation des features en couches/tags est
/// spécifique aux services Protomaps... pas directement portable vers OpenMapTiles" (doc
/// officielle). Migrer aurait exigé de reconstruire tout le pipeline de tuiles hors-ligne
/// (it11) avec les outils Protomaps — hors budget et hors nécessité pour le besoin réel
/// ("plusieurs palettes, même carte"), donc résolu ici par une transformation de couleur
/// appliquée au style JSON existant (voir `ColorFlavorPatcher`) : ne touche JAMAIS la structure
/// des calques (symbol-placement, rotation-alignment), donc n'a AUCUN effet sur le mécanisme de
/// rotation des labels cap-en-haut (contrainte non négociable du prompt) — celui-ci opère sur
/// `layout`, ce fichier ne touche que `paint`.
enum MapColorFlavor: String, CaseIterable, Codable, Equatable {
    case standard
    case hauteContraste
    case terreux

    var id: String { rawValue }

    var label: String {
        switch self {
        case .standard: return "Standard"
        case .hauteContraste: return "Contraste élevé"
        case .terreux: return "Terreux"
        }
    }

    var description: String {
        switch self {
        case .standard: return "Palette d'origine du style vectoriel, inchangée."
        case .hauteContraste: return "Couleurs plus vives, plus de contraste — pensé pour la lisibilité au soleil, avec des gants."
        case .terreux: return "Teintes plus chaudes et naturelles, esprit carte de randonnée."
        }
    }

    /// Décalage de teinte (degrés, cercle chromatique 0-360) appliqué à CHAQUE couleur du style.
    var hueShiftDegrees: Double {
        switch self {
        case .standard: return 0
        case .hauteContraste: return 0
        case .terreux: return 10
        }
    }

    /// Multiplicateur de saturation (clampé après application, jamais négatif).
    var saturationMultiplier: Double {
        switch self {
        case .standard: return 1.0
        case .hauteContraste: return 1.35
        case .terreux: return 0.85
        }
    }

    /// Facteur de CONTRASTE appliqué à la luminosité par un étirement autour de 50 %
    /// (`l' = 0.5 + (l - 0.5) × facteur`) — > 1 accentue l'écart clair/sombre déjà présent,
    /// contrairement à un simple décalage additif qui ne ferait que translater toutes les
    /// valeurs sans les écarter davantage.
    var contrastFactor: Double {
        switch self {
        case .standard: return 1.0
        case .hauteContraste: return 1.25
        case .terreux: return 1.0
        }
    }

    /// Décalage de luminosité additif (appliqué APRÈS le contraste) — "terreux" légèrement plus
    /// clair/chaud, esprit carte papier.
    var lightnessDelta: Double {
        switch self {
        case .standard: return 0
        case .hauteContraste: return 0
        case .terreux: return 0.03
        }
    }

    /// `true` si ce flavor ne change rien (évite tout parcours/ré-encodage JSON inutile pour
    /// "Standard", et sert de garde générique si un futur flavor était ajouté à l'identique).
    var isIdentity: Bool {
        hueShiftDegrees == 0 && saturationMultiplier == 1 && contrastFactor == 1 && lightnessDelta == 0
    }
}
