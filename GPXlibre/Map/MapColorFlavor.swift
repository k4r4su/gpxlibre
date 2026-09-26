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
///
/// Fix "flavor-still-imperceptible" (it22bis, 2e retour terrain après le fix "map-flavors-
/// clamp-to-white" d'it22 : "contraste élevés et terreux sont les mêmes que standard") —
/// diagnostiqué par SIMULATION directe sur les vraies couleurs dominantes du style embarqué
/// (fond `#f8f4f0`, forêt/parc/eau/bâti — voir `docs/tuile-sources.md`... non, voir le calcul
/// ci-dessous) plutôt que par un nouveau réglage à l'aveugle : même avec le clamp `0.05...0.92`
/// d'it22, le delta RGB réel sur la couleur de fond (la plus visible, elle domine l'écran à la
/// plupart des zooms) restait de l'ordre de 25-30 sur 765 — imperceptible à l'œil, exactement le
/// symptôme remonté. Root cause du calcul PRÉCÉDENT (`saturationMultiplier`/`contrastFactor`,
/// retirés ici) : un multiplicateur de saturation est quasi sans effet sur une couleur déjà
/// proche du gris (majorité de la surface d'un fond de carte clair), ET un étirement de
/// contraste autour de 50 % pousse une couleur déjà claire vers 100 % de luminosité, où elle se
/// fait immédiatement écrêter (teinte/saturation optiquement invisibles à l=100 %) même avec un
/// clamp à 92 % — 92 % de luminosité reste visuellement "presque blanc" quelle que soit la
/// saturation en dessous.
///
/// Remplacé par un modèle plus simple et plus robuste, à 2 paramètres par flavor :
/// `saturationBoostFraction` comble une FRACTION de l'espace de saturation RESTANT
/// (`s' = s + (1-s) × fraction`) — contrairement à un multiplicateur, l'effet reste fort même
/// partant de zéro (`0 + 1 × 0.45 = 0.45`), ET ne peut jamais dépasser 1 par construction (pas
/// besoin d'un clamp séparé qui écrêterait silencieusement). `lightnessDelta` est un décalage
/// PLAT (pas un étirement autour de 50 %) : un fond très clair reste clairement plus sombre que
/// l'original d'une quantité FIXE, jamais renvoyé vers le plafond 100 % où il deviendrait
/// invisible. Valeurs choisies par simulation directe sur les couleurs réelles du style
/// (fond/parc/forêt/herbe/eau/bâti) pour un delta RGB perceptible (40-160 sur 765) sans sur-
/// saturer les teintes déjà vives en couleur néon.
enum MapColorFlavor: String, CaseIterable, Codable, Equatable {
    case standard
    case hauteContraste
    case terreux

    var id: String { rawValue }

    var label: String {
        switch self {
        case .standard: return String(localized: "Standard", bundle: .appLanguage)
        case .hauteContraste: return String(localized: "Contraste élevé", bundle: .appLanguage)
        case .terreux: return String(localized: "Terreux", bundle: .appLanguage)
        }
    }

    var description: String {
        switch self {
        case .standard: return String(localized: "Palette d'origine du style vectoriel, inchangée.", bundle: .appLanguage)
        case .hauteContraste: return String(localized: "Couleurs plus vives, plus de contraste — pensé pour la lisibilité au soleil, avec des gants.", bundle: .appLanguage)
        case .terreux: return String(localized: "Teintes plus chaudes et naturelles, esprit carte de randonnée.", bundle: .appLanguage)
        }
    }

    /// Décalage de teinte (degrés, cercle chromatique 0-360) appliqué à chaque couleur
    /// CHROMATIQUE du style (jamais aux gris purs, voir `ColorFlavorPatcher` : une couleur sans
    /// saturation n'a pas de teinte réelle à décaler).
    var hueShiftDegrees: Double {
        switch self {
        case .standard: return 0
        case .hauteContraste: return 0
        // Décalage franc vers le chaud (orange/brun) — "Terreux" doit se voir, pas juste se
        // deviner (retour terrain it22bis).
        case .terreux: return 22
        }
    }

    /// Fraction de l'espace de saturation RESTANT comblée : `s' = s + (1 - s) × fraction`.
    /// Contrairement à un multiplicateur (voir historique ci-dessus), reste efficace même sur
    /// une couleur de départ proche du gris — c'est exactement le cas dominant sur un fond de
    /// carte clair. Valeurs choisies par simulation directe sur les couleurs réelles du style
    /// (fond/parc/forêt/eau/bâti) pour un delta RGB perceptible partout, y compris sur les
    /// couleurs les moins favorables (bâti, quasi gris) — voir `ColorFlavorPatcherTests.
    /// testRealDominantStyleColorsProduceAPerceptibleDeltaUnderBothFlavors`.
    var saturationBoostFraction: Double {
        switch self {
        case .standard: return 0
        case .hauteContraste: return 0.45
        case .terreux: return 0.30
        }
    }

    /// Décalage de luminosité PLAT (jamais un étirement proportionnel autour de 50 %, qui
    /// poussait les couleurs déjà claires — la majorité d'un fond de carte clair — droit vers le
    /// plafond où teinte/saturation deviennent invisibles). Négatif pour les deux flavors non
    /// standard : un peu plus sombre/riche partout, lisible au soleil (Contraste élevé) ou esprit
    /// carte papier (Terreux), jamais renvoyé vers un blanc pur qui annulerait l'effet.
    var lightnessDelta: Double {
        switch self {
        case .standard: return 0
        case .hauteContraste: return -0.07
        case .terreux: return -0.05
        }
    }

    /// `true` si ce flavor ne change rien (évite tout parcours/ré-encodage JSON inutile pour
    /// "Standard", et sert de garde générique si un futur flavor était ajouté à l'identique).
    var isIdentity: Bool {
        hueShiftDegrees == 0 && saturationBoostFraction == 0 && lightnessDelta == 0
    }
}
