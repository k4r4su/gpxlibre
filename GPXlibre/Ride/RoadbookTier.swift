import Foundation

/// Palier d'angle du roadbook (spec "roadbook-angle-buckets-replay", it14, Bloc 4 — segmentation
/// inspirée des standards marché type Waze/MUTCD pour la signalisation de virage) :
///
/// - < 30° : rien (tout droit, pas affiché — voir RoadbookAnalyzer.buildRoadbookEvents)
/// - 30-44° : `.light` — virage léger
/// - 45-89° : `.marked` — virage prononcé
/// - 90-134° : `.hard` — virage fort
/// - ≥ 135° : `.uTurn` — demi-tour
enum RoadbookTier: Equatable {
    case light, marked, hard, uTurn

    /// Détecté via MAP MATCHING Valhalla (spec "valhalla-map-matching-direction-change", it20),
    /// PAS par l'angle géométrique de la trace (qui reste sous `lightThresholdDegrees` par
    /// définition — sinon `.light` l'aurait déjà capturé) : une bifurcation vers une rue/route
    /// différente identifiée par `/trace_route` (changement de manœuvre) sans virage
    /// visuellement marqué sur le tracé GPS lui-même — ex. un léger décalage qui correspond en
    /// réalité à un changement de rue. DISTINCT des 4 paliers ci-dessus, jamais classé parmi eux
    /// (voir RoadbookAnalyzer.buildRoadbookEvents, section map matching).
    case lightDirectionChange

    /// Fix "turn-icon-backward-looking" (it23bis, retour terrain avec capture d'écran : la ligne
    /// "Virage fort" du Road Book affichait une flèche `arrow.turn.down.right` — visuellement
    /// "descend PUIS crochette à droite", illisible comme "tourne fort à droite EN CONTINUANT
    /// D'AVANCER" puisque toutes les autres icônes de cette liste pointent globalement vers le
    /// HAUT (= tout droit) ; "descendre" se lit comme "fais demi-tour", pas "vire fort". Root
    /// cause : chaque palier avait son PROPRE nom de SF Symbol, choisis indépendamment sans
    /// vérifier qu'ils partagent la même convention visuelle (light/marked pointent vers le
    /// haut, hard pointait vers le bas — incohérence jamais remarquée avant que cet écran ne
    /// l'affiche en grand). Remplacé par UNE SEULE flèche de base, tournée d'un angle
    /// représentatif par palier (`rotationDegrees(direction:)` ci-dessous) — ne peut plus
    /// jamais réintroduire cette incohérence, un seul glyphe à faire pivoter plutôt que 4 noms
    /// à choisir cohérents entre eux à la main. Utilisée par `LateralCapBannerView` (bannière
    /// Ride), `RoadBookTabView` (liste Road Book) et les pins carte (`RideMapLibreView`) — les
    /// TROIS call sites doivent appliquer `.rotationEffect`/une transformation équivalente en
    /// plus de ce nom d'image, sinon toutes les flèches non-uTurn s'afficheraient identiques
    /// (droit devant, non tournées).
    static let baseSystemImageName = "arrow.up"

    /// Angle de rotation représentatif (degrés, non signé) — PAS l'angle géométrique réel mesuré
    /// sur la trace (trop bruité pour un pictogramme stable, voir `RoadbookAnalyzer`), un palier
    /// de sévérité standardisé, esprit pictogramme roadbook papier (une poignée de formes
    /// reconnaissables, pas un curseur continu). Toujours < 180° pour les 3 premiers paliers —
    /// ne doit JAMAIS s'approcher de 180° (se lirait comme un demi-tour) sauf pour `.uTurn`
    /// lui-même.
    private var baseRotationDegrees: Double {
        switch self {
        case .light: return 30
        case .marked: return 65
        case .hard: return 105
        case .uTurn: return 180
        case .lightDirectionChange: return 0
        }
    }

    /// Rotation SIGNÉE à appliquer à `baseSystemImageName` (`.rotationEffect` SwiftUI, ou
    /// `CGAffineTransform(rotationAngle:)` côté UIKit/pins carte) — gauche = négatif, droite =
    /// positif, TOUJOURS 180° pour `.uTurn` quel que soit `direction` (un demi-tour n'a pas de
    /// côté ; `RoadbookAnalyzer` assigne d'ailleurs toujours `.uTurn` sans lien avec le signe de
    /// l'angle mesuré, voir `buildRoadbookEvents`). `nil` pour `.lightDirectionChange`, qui
    /// reste un pictogramme "panneau" fixe (voir `systemImageName`), jamais tourné.
    func rotationDegrees(direction: TurnDirection) -> Double? {
        switch self {
        case .uTurn: return 180
        case .lightDirectionChange: return nil
        case .light, .marked, .hard: return direction == .left ? -baseRotationDegrees : baseRotationDegrees
        }
    }

    /// `.lightDirectionChange` reste un panneau de signalisation dédié (pas une flèche tournée,
    /// voir son commentaire de cas ci-dessus : signale explicitement "pas un virage géométrique
    /// classique") — SEUL cas où le nom d'image diffère encore par palier plutôt que par
    /// rotation d'un glyphe unique.
    func systemImageName(direction: TurnDirection) -> String {
        switch self {
        case .lightDirectionChange:
            return direction == .left ? "signpost.left" : "signpost.right"
        case .light, .marked, .hard, .uTurn:
            return Self.baseSystemImageName
        }
    }

    var label: String {
        switch self {
        case .light: return "Virage léger"
        case .marked: return "Virage prononcé"
        case .hard: return "Virage fort"
        case .uTurn: return "Demi-tour"
        case .lightDirectionChange: return "Changement de direction"
        }
    }
}
