import Foundation

/// Énumération EXACTE `DirectionsLeg_Maneuver_Type` de Valhalla (spec "nav-classic-rebuild",
/// it21 : "les valeurs exactes de l'énumération type doivent être vérifiées contre la
/// documentation/le code source Valhalla, pas supposées") — vérifiée contre
/// `valhalla/valhalla-docs` (`turn-by-turn/api-reference.md`, section maneuver type), PAS
/// devinée. Valeurs 30+ (transit) ne peuvent jamais apparaître avec `costing: "auto"` (aucun
/// mode piéton/transport en commun demandé) mais sont modélisées pour rester EXHAUSTIF sur le
/// type brut retourné par Valhalla — un type inconnu (ex. une future valeur ajoutée par
/// Valhalla) retombe sur `.none` plutôt que de faire planter le décodage JSON.
enum ValhallaManeuverType: Int, CaseIterable {
    case none = 0
    case start = 1
    case startRight = 2
    case startLeft = 3
    case destination = 4
    case destinationRight = 5
    case destinationLeft = 6
    case becomes = 7
    case continueStraight = 8
    case slightRight = 9
    case right = 10
    case sharpRight = 11
    case uturnRight = 12
    case uturnLeft = 13
    case sharpLeft = 14
    case left = 15
    case slightLeft = 16
    case rampStraight = 17
    case rampRight = 18
    case rampLeft = 19
    case exitRight = 20
    case exitLeft = 21
    case stayStraight = 22
    case stayRight = 23
    case stayLeft = 24
    case merge = 25
    case roundaboutEnter = 26
    case roundaboutExit = 27
    case ferryEnter = 28
    case ferryExit = 29
    case transit = 30
    case transitTransfer = 31
    case transitRemainOn = 32
    case transitConnectionStart = 33
    case transitConnectionTransfer = 34
    case transitConnectionDestination = 35
    case postTransitConnectionDestination = 36
    // Valhalla ajoute occasionnellement de nouvelles valeurs (elevator/steps/escalator/building
    // enter-exit dans certaines branches) — non documentées dans l'API de référence turn-by-turn
    // au moment de cette itération, jamais retournées par `costing: "auto"`. `init(rawValue:)`
    // échouerait sur ces valeurs futures : voir `ValhallaNavManeuver` qui retombe sur `.none`
    // plutôt que de faire planter tout le décodage de la réponse pour un seul maneuver inconnu.

    /// Icône SF Symbol — catégories demandées par la spec : "tourner droite/gauche, léger/
    /// prononcé, épingle, rond-point + sortie, bifurcation, arrivée". `mergeLeft`/`mergeRight`
    /// n'existent PAS dans l'énumération officielle Valhalla (vérifié) — seul `.merge` (25)
    /// existe, sans variante directionnelle.
    var systemImageName: String {
        switch self {
        case .none, .continueStraight, .becomes, .rampStraight, .stayStraight, .transit,
             .transitTransfer, .transitRemainOn, .transitConnectionStart, .transitConnectionTransfer,
             .transitConnectionDestination, .postTransitConnectionDestination:
            return "arrow.up"
        case .start, .startRight, .startLeft:
            return "location.fill"
        case .destination, .destinationRight, .destinationLeft:
            return "flag.checkered"
        case .slightRight, .stayRight:
            return "arrow.up.right"
        case .right, .rampRight, .exitRight:
            return "arrow.turn.up.right"
        case .sharpRight:
            return "arrow.turn.down.right"
        case .slightLeft, .stayLeft:
            return "arrow.up.left"
        case .left, .rampLeft, .exitLeft:
            return "arrow.turn.up.left"
        case .sharpLeft:
            return "arrow.turn.down.left"
        case .uturnRight, .uturnLeft:
            return "arrow.uturn.up"
        case .merge:
            return "arrow.triangle.merge"
        case .roundaboutEnter, .roundaboutExit:
            return "arrow.triangle.2.circlepath"
        case .ferryEnter, .ferryExit:
            return "ferry.fill"
        }
    }

    /// Vrai pour les deux manœuvres de rond-point — pilote l'affichage du numéro de sortie
    /// (`ValhallaNavManeuver.roundaboutExitCount`) dans la bannière.
    var isRoundabout: Bool {
        self == .roundaboutEnter || self == .roundaboutExit
    }

    var isArrival: Bool {
        self == .destination || self == .destinationRight || self == .destinationLeft
    }

    /// Filtrage + choix de palier "route-aware" (spec "roadbook-route-aware-maneuvers", it24,
    /// point 1) — retour terrain : "une courbe progressive sur le même axe peut déclencher un
    /// événement à tort" côté map matching, root cause identifiée ici : AVANT it24, TOUTE
    /// manœuvre intermédiaire Valhalla devenait un événement roadbook, y compris `.continueStraight`
    /// (route qui continue sans virage) et `.becomes` (la route change de nom SANS tourner) — les
    /// deux exclus explicitement par la fiche. `nil` = pas une vraie décision de conduite, à
    /// écarter (voir `ValhallaMapMatchingService.intermediateManeuvers`, seul point d'appel).
    /// Non-`nil` = le `RoadbookTier` à assigner : `.roundabout`/`.fork`/`.merge` reprennent la
    /// sémantique Valhalla EXACTE (rond-point/fourche avec choix réel — `stayStraight/Right/Left`
    /// désignent un VRAI point de décision à un embranchement, pas un simple "tout droit" —
    /// /bretelle-fusion) plutôt qu'un angle géométrique bruité ; `.uTurn` reste le palier
    /// EXISTANT ("à conserver tel quel", demande explicite de la fiche) ; les virages classiques
    /// et les ferries retombent sur `.lightDirectionChange`, le palier "panneau" déjà en place
    /// depuis it20 pour "pas un virage géométrique classique".
    var roadbookTier: RoadbookTier? {
        switch self {
        case .roundaboutEnter, .roundaboutExit:
            return .roundabout
        case .stayStraight, .stayRight, .stayLeft:
            return .fork
        case .merge, .rampStraight, .rampRight, .rampLeft, .exitRight, .exitLeft:
            return .merge
        case .uturnRight, .uturnLeft:
            return .uTurn
        case .slightRight, .right, .sharpRight, .slightLeft, .left, .sharpLeft, .ferryEnter, .ferryExit:
            return .lightDirectionChange
        case .none, .start, .startRight, .startLeft, .destination, .destinationRight, .destinationLeft,
             .becomes, .continueStraight,
             .transit, .transitTransfer, .transitRemainOn, .transitConnectionStart,
             .transitConnectionTransfer, .transitConnectionDestination, .postTransitConnectionDestination:
            return nil
        }
    }

    /// Direction dérivée du type Valhalla LUI-MÊME (spec it24, point 1) — remplace, pour les
    /// manœuvres de map matching, l'ancien calcul basé sur l'angle géométrique mesuré au point
    /// (`RoadbookAnalyzer.windowedTurn`) : peu fiable pour une décision route-aware qui peut être
    /// un simple changement de rue sans angle visuellement marqué sur le tracé GPS. `.merge`
    /// (aucune variante directionnelle côté Valhalla, voir plus haut) et les ronds-points (la
    /// surbrillance du pictogramme pilote déjà le sens pris, voir `roadbookTier`) retombent sur
    /// `.straight`, une valeur neutre jamais interprétée comme un vrai virage affiché.
    var roadbookDirection: TurnDirection {
        switch self {
        case .right, .slightRight, .sharpRight, .rampRight, .exitRight, .stayRight, .startRight, .destinationRight:
            return .right
        case .left, .slightLeft, .sharpLeft, .rampLeft, .exitLeft, .stayLeft, .startLeft, .destinationLeft:
            return .left
        case .uturnRight, .uturnLeft:
            return .uTurn
        default:
            return .straight
        }
    }
}
