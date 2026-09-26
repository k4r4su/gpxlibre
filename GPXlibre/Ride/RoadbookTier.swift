import Foundation

/// Palier d'angle du roadbook (spec "roadbook-angle-buckets-replay", it14, Bloc 4 — segmentation
/// inspirée des standards marché type Waze/MUTCD pour la signalisation de virage) :
///
/// - < 30° : rien (tout droit, pas affiché — voir RoadbookAnalyzer.buildRoadbookEvents)
/// - 30-44° : `.light` — virage léger
/// - 45-89° : `.marked` — virage prononcé
/// - 90-134° : `.hard` — virage fort
/// - ≥ 135° : `.veryHard` — virage très serré, AVEC son sens (épingle, lacet : un changement de
///   route, pas un demi-tour — it26 point 2, fix "roadbook-no-false-uturn")
/// - `.uTurn` — demi-tour : PLUS un palier d'angle, seulement si la trace repart sur la MÊME
///   route (voir `NavigationConstants.roadbookUTurn*`), ou demi-tour Valhalla sur la même rue
enum RoadbookTier: Equatable {
    case light, marked, hard, veryHard, uTurn

    /// Détecté via MAP MATCHING Valhalla (spec "valhalla-map-matching-direction-change", it20),
    /// PAS par l'angle géométrique de la trace (qui reste sous `lightThresholdDegrees` par
    /// définition — sinon `.light` l'aurait déjà capturé) : une bifurcation vers une rue/route
    /// différente identifiée par `/trace_route` (changement de manœuvre) sans virage
    /// visuellement marqué sur le tracé GPS lui-même — ex. un léger décalage qui correspond en
    /// réalité à un changement de rue. DISTINCT des 4 paliers ci-dessus, jamais classé parmi eux
    /// (voir RoadbookAnalyzer.buildRoadbookEvents, section map matching).
    case lightDirectionChange

    /// Trois paliers "route-aware" supplémentaires (spec "roadbook-route-aware-maneuvers", it24,
    /// points 1/2) — DÉTECTÉS UNIQUEMENT via map matching Valhalla (`ValhallaManeuverType.
    /// roadbookTier`), jamais par l'angle géométrique seul (comme `.lightDirectionChange`
    /// ci-dessus) : `.roundabout` (rond-point, `Checkpoint.roundaboutExitCount` pilote la sortie
    /// mise en surbrillance du pictogramme circulaire dédié), `.fork` (fourche avec choix réel —
    /// Valhalla `stayStraight/Right/Left`, un embranchement où NE RIEN FAIRE mènerait sur la
    /// mauvaise branche, contrairement à un simple "tout droit"), `.merge` (fusion/bretelle —
    /// Valhalla `merge`/`ramp*`/`exit*`). Les trois ont un pictogramme DESSINÉ dédié sur les
    /// écrans Road Book/le PDF (voir RoadBook/RoadbookPictograms.swift), PAS une simple flèche
    /// tournée comme les 4 paliers d'angle — `rotationDegrees`/`systemImageName` ci-dessous ne
    /// servent que de repli (pins carte `RideMapLibreView`, SF Symbol générique suffisant à cette
    /// échelle).
    case roundabout, fork, merge

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
    /// reconnaissables, pas un curseur continu). Toujours < 180° pour les 4 paliers d'angle —
    /// ne doit JAMAIS s'approcher de 180° (se lirait comme un demi-tour) sauf pour `.uTurn`
    /// lui-même.
    private var baseRotationDegrees: Double {
        switch self {
        case .light: return 30
        case .marked: return 65
        case .hard: return 105
        case .veryHard: return 140
        case .uTurn: return 180
        case .lightDirectionChange, .roundabout, .fork, .merge: return 0
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
        case .lightDirectionChange, .roundabout, .fork, .merge: return nil
        case .light, .marked, .hard, .veryHard: return direction == .left ? -baseRotationDegrees : baseRotationDegrees
        }
    }

    /// `.lightDirectionChange`/`.roundabout`/`.fork`/`.merge` restent des pictogrammes DÉDIÉS
    /// (pas une flèche tournée) — ce repli SF Symbol générique n'est utilisé QUE par les pins
    /// carte (`RideMapLibreView`, échelle trop petite pour un pictogramme dessiné) ; les écrans
    /// Road Book/le PDF utilisent `RoadbookPictograms` pour `.roundabout`/`.fork`/`.merge` (spec
    /// it24, point 2 — "pas une flèche courbe générique").
    func systemImageName(direction: TurnDirection) -> String {
        switch self {
        case .lightDirectionChange:
            return direction == .left ? "signpost.left" : "signpost.right"
        case .roundabout:
            return "arrow.triangle.2.circlepath"
        case .fork:
            return "arrow.triangle.branch"
        case .merge:
            return "arrow.merge"
        case .light, .marked, .hard, .veryHard, .uTurn:
            return Self.baseSystemImageName
        }
    }

    var label: String {
        switch self {
        case .light: return String(localized: "Virage léger", bundle: .appLanguage)
        case .marked: return String(localized: "Virage prononcé", bundle: .appLanguage)
        case .hard: return String(localized: "Virage fort", bundle: .appLanguage)
        case .veryHard: return String(localized: "Virage très serré", bundle: .appLanguage)
        case .uTurn: return String(localized: "Demi-tour", bundle: .appLanguage)
        case .lightDirectionChange: return String(localized: "Changement de direction", bundle: .appLanguage)
        case .roundabout: return String(localized: "Rond-point", bundle: .appLanguage)
        case .fork: return String(localized: "Fourche", bundle: .appLanguage)
        case .merge: return String(localized: "Fusion / bretelle", bundle: .appLanguage)
        }
    }
}
