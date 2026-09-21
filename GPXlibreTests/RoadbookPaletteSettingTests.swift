import XCTest
@testable import GPXlibre

/// Spec "roadbook-ui-redesign" (it25, point 0) — mapping réglage utilisateur → override résolveur.
final class RoadbookPaletteSettingTests: XCTestCase {
    func testAutomaticHasNoOverride() {
        XCTAssertNil(RoadbookPaletteSetting.automatic.overrideValue)
    }

    func testPaperAndNightForceTheirOwnValue() {
        XCTAssertEqual(RoadbookPaletteSetting.paper.overrideValue, .paper)
        XCTAssertEqual(RoadbookPaletteSetting.night.overrideValue, .night)
    }

    func testEveryCaseHasANonEmptyLabel() {
        for setting in RoadbookPaletteSetting.allCases {
            XCTAssertFalse(setting.label.isEmpty, "\(setting)")
        }
    }
}
