import XCTest
@testable import GPXlibre

/// Fix "turn-icon-backward-looking" (it23bis, retour terrain avec capture d'écran : la ligne
/// "Virage fort" affichait une flèche `arrow.turn.down.right` qui pointe vers le BAS avant de
/// crocheter à droite — illisible comme "tourne fort à droite" dans une liste où "haut" = tout
/// droit). Verrouille la nouvelle convention : un seul glyphe de base, tourné d'un angle
/// standardisé qui ne s'approche JAMAIS de 180° sauf pour un vrai demi-tour.
final class RoadbookTierTests: XCTestCase {
    private static let geometricTiers: [RoadbookTier] = [.light, .marked, .hard]

    func testNoGeometricTierRotatesCloseToADemiTour() {
        for tier in Self.geometricTiers {
            for direction in [TurnDirection.left, .right] {
                guard let rotation = tier.rotationDegrees(direction: direction) else {
                    return XCTFail("\(tier) doit produire une rotation")
                }
                XCTAssertLessThan(abs(rotation), 150, "\(tier)/\(direction) : une rotation proche de 180° se lit comme un demi-tour")
            }
        }
    }

    func testRotationSignMatchesDirection() {
        for tier in Self.geometricTiers {
            guard let left = tier.rotationDegrees(direction: .left), let right = tier.rotationDegrees(direction: .right) else {
                return XCTFail("\(tier) doit produire une rotation pour gauche/droite")
            }
            XCTAssertLessThan(left, 0, "\(tier) gauche doit tourner dans le sens négatif")
            XCTAssertGreaterThan(right, 0, "\(tier) droite doit tourner dans le sens positif")
            XCTAssertEqual(abs(left), abs(right), "même amplitude des deux côtés, seul le signe change")
        }
    }

    /// Sévérité croissante : un virage "fort" doit tourner PLUS qu'un "prononcé", qui doit
    /// tourner plus qu'un "léger" — sinon les pictogrammes ne se distingueraient pas entre eux.
    func testRotationMagnitudeIncreasesWithSeverity() {
        let light = abs(RoadbookTier.light.rotationDegrees(direction: .right) ?? 0)
        let marked = abs(RoadbookTier.marked.rotationDegrees(direction: .right) ?? 0)
        let hard = abs(RoadbookTier.hard.rotationDegrees(direction: .right) ?? 0)
        XCTAssertLessThan(light, marked)
        XCTAssertLessThan(marked, hard)
    }

    func testUTurnAlwaysRotatesOneEightyRegardlessOfDirection() {
        XCTAssertEqual(RoadbookTier.uTurn.rotationDegrees(direction: .left), 180)
        XCTAssertEqual(RoadbookTier.uTurn.rotationDegrees(direction: .right), 180)
        XCTAssertEqual(RoadbookTier.uTurn.rotationDegrees(direction: .uTurn), 180)
    }

    func testLightDirectionChangeHasNoRotationItRemainsAFixedSignpostGlyph() {
        XCTAssertNil(RoadbookTier.lightDirectionChange.rotationDegrees(direction: .left))
        XCTAssertNil(RoadbookTier.lightDirectionChange.rotationDegrees(direction: .right))
    }

    /// Cœur du fix : les 4 paliers géométriques partagent TOUS le même nom de glyphe — c'est
    /// justement l'incohérence de noms différents par palier qui avait produit le bug.
    func testAllGeometricTiersShareTheSameBaseGlyph() {
        for tier in Self.geometricTiers + [.uTurn] {
            XCTAssertEqual(tier.systemImageName(direction: .left), RoadbookTier.baseSystemImageName)
            XCTAssertEqual(tier.systemImageName(direction: .right), RoadbookTier.baseSystemImageName)
        }
    }

    func testLightDirectionChangeKeepsItsOwnSignpostGlyph() {
        XCTAssertEqual(RoadbookTier.lightDirectionChange.systemImageName(direction: .left), "signpost.left")
        XCTAssertEqual(RoadbookTier.lightDirectionChange.systemImageName(direction: .right), "signpost.right")
    }
}
