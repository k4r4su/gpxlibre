import XCTest
@testable import GPXlibre

/// Spec "roadbook-route-aware-maneuvers" (it24, point 2) — géométrie PURE partagée entre le
/// rendu SwiftUI et le rendu PDF (jamais testée via une vue/un contexte Core Graphics ici).
final class RoadbookPictogramGeometryTests: XCTestCase {
    func testFirstExitPointsAtOneSpacingFromEntry() {
        XCTAssertEqual(
            RoadbookPictogramGeometry.roundaboutExitAngleDegrees(exitCount: 1),
            RoadBookConstants.roundaboutExitSpacingDegrees
        )
    }

    func testThirdExitIsThreeTimesTheSpacing() {
        XCTAssertEqual(
            RoadbookPictogramGeometry.roundaboutExitAngleDegrees(exitCount: 3),
            RoadBookConstants.roundaboutExitSpacingDegrees * 3
        )
    }

    /// Repli honnête : `nil`/0/négatif ne doivent jamais produire un angle nul ou négatif
    /// absurde — toujours au moins la 1ʳᵉ sortie.
    func testNilOrNonPositiveExitCountFallsBackToTheFirstExit() {
        let expected = RoadBookConstants.roundaboutExitSpacingDegrees
        XCTAssertEqual(RoadbookPictogramGeometry.roundaboutExitAngleDegrees(exitCount: nil), expected)
        XCTAssertEqual(RoadbookPictogramGeometry.roundaboutExitAngleDegrees(exitCount: 0), expected)
        XCTAssertEqual(RoadbookPictogramGeometry.roundaboutExitAngleDegrees(exitCount: -3), expected)
    }

    func testFirstExitHasNoSkippedRanksToShow() {
        XCTAssertTrue(RoadbookPictogramGeometry.skippedExitRanks(exitCount: 1).isEmpty)
        XCTAssertTrue(RoadbookPictogramGeometry.skippedExitRanks(exitCount: nil).isEmpty)
    }

    func testThirdExitShowsTheTwoPrecedingRanksAsSkipped() {
        XCTAssertEqual(RoadbookPictogramGeometry.skippedExitRanks(exitCount: 3), [1, 2])
    }

    /// Garde-fou lisibilité : jamais plus de 6 traits discrets, même pour un rang de sortie
    /// aberrant (rond-point à répétition mal détecté plutôt qu'une vraie longue liste).
    func testSkippedRanksAreCappedForReadability() {
        XCTAssertEqual(RoadbookPictogramGeometry.skippedExitRanks(exitCount: 50).count, 6)
    }
}
