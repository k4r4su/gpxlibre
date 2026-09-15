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
        case .terreux: return 14
        }
    }

    /// Multiplicateur de saturation (clampé après application avec `saturationBoost`, jamais
    /// négatif). Fix "flavor-parameters-imperceptible" (retour terrain, it19-bis :
    /// "standard et les autres se ressemblent") — diagnostiqué en rejouant le patch sur le VRAI
    /// style embarqué (111 calques) : le calcul était correct (confirmé, ex. landcover_wood
    /// 61%→82% de saturation), mais un simple MULTIPLICATEUR n'a quasiment aucun effet sur les
    /// teintes DÉJÀ peu saturées (fond de carte, zones neutres — la majorité de la surface
    /// visible à l'écran) : 1.35 × une saturation proche de 0 reste proche de 0. Voir
    /// `saturationBoost` ci-dessous, qui corrige ce problème par un terme ADDITIF.
    var saturationMultiplier: Double {
        switch self {
        case .standard: return 1.0
        case .hauteContraste: return 1.5
        case .terreux: return 0.9
        }
    }

    /// Terme ADDITIF de saturation (après multiplication, avant clamp) — garantit un effet
    /// visible même sur une couleur de départ quasi grise/neutre, où un multiplicateur seul
    /// n'a aucune prise. C'est ce terme qui rend "Terreux" visible sur un fond de carte clair
    /// (teinte chaude qui apparaît enfin) et "Contraste élevé" franchement plus vif partout,
    /// pas seulement sur les couleurs déjà saturées.
    var saturationBoost: Double {
        switch self {
        case .standard: return 0
        case .hauteContraste: return 0.15
        case .terreux: return 0.06
        }
    }

    /// Facteur de CONTRASTE appliqué à la luminosité par un étirement autour de 50 %
    /// (`l' = 0.5 + (l - 0.5) × facteur`) — > 1 accentue l'écart clair/sombre déjà présent,
    /// contrairement à un simple décalage additif qui ne ferait que translater toutes les
    /// valeurs sans les écarter davantage.
    var contrastFactor: Double {
        switch self {
        case .standard: return 1.0
        case .hauteContraste: return 1.4
        case .terreux: return 1.0
        }
    }

    /// Décalage de luminosité additif (appliqué APRÈS le contraste) — "terreux" légèrement plus
    /// clair/chaud, esprit carte papier.
    var lightnessDelta: Double {
        switch self {
        case .standard: return 0
        case .hauteContraste: return 0
        case .terreux: return 0.04
        }
    }

    /// `true` si ce flavor ne change rien (évite tout parcours/ré-encodage JSON inutile pour
    /// "Standard", et sert de garde générique si un futur flavor était ajouté à l'identique).
    var isIdentity: Bool {
        hueShiftDegrees == 0 && saturationMultiplier == 1 && saturationBoost == 0
            && contrastFactor == 1 && lightnessDelta == 0
    }
}
