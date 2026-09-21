import XCTest
@testable import GPXlibre

/// Spec "nav-classic-rebuild" (it21) : "Mapping type Valhalla → icône : test unitaire couvrant
/// chaque valeur d'énumération rencontrée dans une réponse réelle. Les valeurs exactes de
/// l'énumération type doivent être vérifiées contre la documentation/le code source Valhalla,
/// pas supposées" — voir `ValhallaManeuverType` pour la source utilisée (`valhalla/valhalla-docs`,
/// `turn-by-turn/api-reference.md`, section maneuver type).
final class ValhallaManeuverTypeTests: XCTestCase {
    /// Exhaustivité : CHAQUE valeur de l'énumération (0-36) doit produire une icône, jamais un
    /// crash ni une chaîne vide — y compris les types transit (30-36), qui ne peuvent jamais
    /// apparaître avec `costing: "auto"` mais restent modélisés.
    func testEveryEnumerationValueProducesANonEmptyIcon() {
        for type in ValhallaManeuverType.allCases {
            XCTAssertFalse(type.systemImageName.isEmpty, "type \(type.rawValue) (\(type)) doit avoir une icône")
        }
    }

    /// Vérifie les valeurs numériques EXACTES documentées par Valhalla — pas juste qu'un
    /// rawValue existe, mais qu'il correspond au bon nom (un décalage d'un seul cran romprait
    /// silencieusement le mapping type → icône pour toute une catégorie de manœuvres).
    func testRawValuesMatchTheDocumentedValhallaEnumeration() {
        XCTAssertEqual(ValhallaManeuverType.none.rawValue, 0)
        XCTAssertEqual(ValhallaManeuverType.start.rawValue, 1)
        XCTAssertEqual(ValhallaManeuverType.startRight.rawValue, 2)
        XCTAssertEqual(ValhallaManeuverType.startLeft.rawValue, 3)
        XCTAssertEqual(ValhallaManeuverType.destination.rawValue, 4)
        XCTAssertEqual(ValhallaManeuverType.destinationRight.rawValue, 5)
        XCTAssertEqual(ValhallaManeuverType.destinationLeft.rawValue, 6)
        XCTAssertEqual(ValhallaManeuverType.becomes.rawValue, 7)
        XCTAssertEqual(ValhallaManeuverType.continueStraight.rawValue, 8)
        XCTAssertEqual(ValhallaManeuverType.slightRight.rawValue, 9)
        XCTAssertEqual(ValhallaManeuverType.right.rawValue, 10)
        XCTAssertEqual(ValhallaManeuverType.sharpRight.rawValue, 11)
        XCTAssertEqual(ValhallaManeuverType.uturnRight.rawValue, 12)
        XCTAssertEqual(ValhallaManeuverType.uturnLeft.rawValue, 13)
        XCTAssertEqual(ValhallaManeuverType.sharpLeft.rawValue, 14)
        XCTAssertEqual(ValhallaManeuverType.left.rawValue, 15)
        XCTAssertEqual(ValhallaManeuverType.slightLeft.rawValue, 16)
        XCTAssertEqual(ValhallaManeuverType.rampStraight.rawValue, 17)
        XCTAssertEqual(ValhallaManeuverType.rampRight.rawValue, 18)
        XCTAssertEqual(ValhallaManeuverType.rampLeft.rawValue, 19)
        XCTAssertEqual(ValhallaManeuverType.exitRight.rawValue, 20)
        XCTAssertEqual(ValhallaManeuverType.exitLeft.rawValue, 21)
        XCTAssertEqual(ValhallaManeuverType.stayStraight.rawValue, 22)
        XCTAssertEqual(ValhallaManeuverType.stayRight.rawValue, 23)
        XCTAssertEqual(ValhallaManeuverType.stayLeft.rawValue, 24)
        XCTAssertEqual(ValhallaManeuverType.merge.rawValue, 25)
        XCTAssertEqual(ValhallaManeuverType.roundaboutEnter.rawValue, 26)
        XCTAssertEqual(ValhallaManeuverType.roundaboutExit.rawValue, 27)
        XCTAssertEqual(ValhallaManeuverType.ferryEnter.rawValue, 28)
        XCTAssertEqual(ValhallaManeuverType.ferryExit.rawValue, 29)
        XCTAssertEqual(ValhallaManeuverType.transit.rawValue, 30)
        XCTAssertEqual(ValhallaManeuverType.transitTransfer.rawValue, 31)
        XCTAssertEqual(ValhallaManeuverType.transitRemainOn.rawValue, 32)
        XCTAssertEqual(ValhallaManeuverType.transitConnectionStart.rawValue, 33)
        XCTAssertEqual(ValhallaManeuverType.transitConnectionTransfer.rawValue, 34)
        XCTAssertEqual(ValhallaManeuverType.transitConnectionDestination.rawValue, 35)
        XCTAssertEqual(ValhallaManeuverType.postTransitConnectionDestination.rawValue, 36)
    }

    func testDestinationVariantsAreRecognizedAsArrival() {
        XCTAssertTrue(ValhallaManeuverType.destination.isArrival)
        XCTAssertTrue(ValhallaManeuverType.destinationRight.isArrival)
        XCTAssertTrue(ValhallaManeuverType.destinationLeft.isArrival)
        XCTAssertFalse(ValhallaManeuverType.start.isArrival)
        XCTAssertFalse(ValhallaManeuverType.right.isArrival)
    }

    func testRoundaboutVariantsAreRecognized() {
        XCTAssertTrue(ValhallaManeuverType.roundaboutEnter.isRoundabout)
        XCTAssertTrue(ValhallaManeuverType.roundaboutExit.isRoundabout)
        XCTAssertFalse(ValhallaManeuverType.left.isRoundabout)
        XCTAssertFalse(ValhallaManeuverType.merge.isRoundabout)
    }

    /// Repli documenté (voir ValhallaNavManeuverResponse.asNavManeuver) : une valeur de type
    /// future/non documentée par Valhalla ne doit jamais faire planter tout le décodage de la
    /// réponse — testé au niveau du décodage complet (pas seulement `init(rawValue:)`, qui
    /// échoue normalement pour une valeur inconnue).
    func testUnknownRawValueFailsToInitDirectly() {
        XCTAssertNil(ValhallaManeuverType(rawValue: 999), "précondition : une valeur inconnue ne doit PAS correspondre à un cas existant par accident")
    }

    // MARK: - roadbookTier/roadbookDirection (spec "roadbook-route-aware-maneuvers", it24, point 1)

    /// Cœur du bug terrain corrigé : "continuer tout droit"/"la route change de nom" ne sont
    /// JAMAIS une vraie décision de conduite.
    func testContinueStraightAndBecomesAreNotRoadbookRelevant() {
        XCTAssertNil(ValhallaManeuverType.continueStraight.roadbookTier)
        XCTAssertNil(ValhallaManeuverType.becomes.roadbookTier)
    }

    /// Ni le départ/l'arrivée, ni le transit (jamais retourné avec `costing: "auto"` mais modélisé
    /// par exhaustivité) — aucun n'est une décision EN COURS de route.
    func testStartDestinationAndTransitAreNotRoadbookRelevant() {
        for type: ValhallaManeuverType in [.none, .start, .startRight, .startLeft, .destination, .destinationRight, .destinationLeft, .transit, .transitTransfer, .transitRemainOn, .transitConnectionStart, .transitConnectionTransfer, .transitConnectionDestination, .postTransitConnectionDestination] {
            XCTAssertNil(type.roadbookTier, "\(type)")
        }
    }

    func testRoundaboutTypesMapToTheRoundaboutTier() {
        XCTAssertEqual(ValhallaManeuverType.roundaboutEnter.roadbookTier, .roundabout)
        XCTAssertEqual(ValhallaManeuverType.roundaboutExit.roadbookTier, .roundabout)
    }

    /// `stay*` = un VRAI point de décision à un embranchement (ne rien faire mènerait sur la
    /// mauvaise branche) — distinct de `continueStraight`, filtré ci-dessus.
    func testStayTypesMapToTheForkTier() {
        XCTAssertEqual(ValhallaManeuverType.stayStraight.roadbookTier, .fork)
        XCTAssertEqual(ValhallaManeuverType.stayRight.roadbookTier, .fork)
        XCTAssertEqual(ValhallaManeuverType.stayLeft.roadbookTier, .fork)
    }

    func testMergeAndRampTypesMapToTheMergeTier() {
        for type: ValhallaManeuverType in [.merge, .rampStraight, .rampRight, .rampLeft, .exitRight, .exitLeft] {
            XCTAssertEqual(type.roadbookTier, .merge, "\(type)")
        }
    }

    /// "Demi-tour : déjà existant (palier uTurn), à conserver tel quel."
    func testUTurnTypesReuseTheExistingUTurnTier() {
        XCTAssertEqual(ValhallaManeuverType.uturnRight.roadbookTier, .uTurn)
        XCTAssertEqual(ValhallaManeuverType.uturnLeft.roadbookTier, .uTurn)
    }

    func testPlainTurnsAndFerriesMapToLightDirectionChange() {
        for type: ValhallaManeuverType in [.slightRight, .right, .sharpRight, .slightLeft, .left, .sharpLeft, .ferryEnter, .ferryExit] {
            XCTAssertEqual(type.roadbookTier, .lightDirectionChange, "\(type)")
        }
    }

    func testRoadbookDirectionMatchesTheSemanticSideOfTheManeuver() {
        XCTAssertEqual(ValhallaManeuverType.right.roadbookDirection, .right)
        XCTAssertEqual(ValhallaManeuverType.sharpRight.roadbookDirection, .right)
        XCTAssertEqual(ValhallaManeuverType.rampRight.roadbookDirection, .right)
        XCTAssertEqual(ValhallaManeuverType.stayRight.roadbookDirection, .right)
        XCTAssertEqual(ValhallaManeuverType.left.roadbookDirection, .left)
        XCTAssertEqual(ValhallaManeuverType.stayLeft.roadbookDirection, .left)
        XCTAssertEqual(ValhallaManeuverType.uturnRight.roadbookDirection, .uTurn)
        XCTAssertEqual(ValhallaManeuverType.uturnLeft.roadbookDirection, .uTurn)
    }

    /// `.merge` n'a aucune variante directionnelle côté Valhalla (vérifié, voir Nav/CLAUDE.md) —
    /// retombe sur `.straight`, jamais interprété comme un vrai virage affiché.
    func testMergeAndRoundaboutHaveANeutralStraightDirection() {
        XCTAssertEqual(ValhallaManeuverType.merge.roadbookDirection, .straight)
        XCTAssertEqual(ValhallaManeuverType.roundaboutEnter.roadbookDirection, .straight)
        XCTAssertEqual(ValhallaManeuverType.roundaboutExit.roadbookDirection, .straight)
    }
}
