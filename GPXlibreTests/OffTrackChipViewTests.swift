import XCTest
@testable import GPXlibre

/// Spec "offtrack-compact-chip" (it18, Bloc 1) : le chip hors-trace n'affiche la distance de
/// reprise qu'après `RideConstants.offTrackChipDistanceDelaySeconds` (30 s) sans retour sur
/// trace — titre seul avant ça.
final class OffTrackChipViewTests: XCTestCase {
    func testHidesDistanceBeforeDelay() {
        let since = Date()
        let chip = OffTrackChipView(relativeBearingDegrees: 0, distanceMeters: 250, pausedSinceDate: since)

        XCTAssertFalse(chip.shouldShowDistance(now: since.addingTimeInterval(10)))
        XCTAssertFalse(chip.shouldShowDistance(now: since.addingTimeInterval(29)))
    }

    func testShowsDistanceAtAndAfterDelay() {
        let since = Date()
        let chip = OffTrackChipView(relativeBearingDegrees: 0, distanceMeters: 250, pausedSinceDate: since)

        XCTAssertTrue(chip.shouldShowDistance(now: since.addingTimeInterval(30)))
        XCTAssertTrue(chip.shouldShowDistance(now: since.addingTimeInterval(45)))
    }

    func testNilPausedSinceDateNeverShowsDistance() {
        let chip = OffTrackChipView(relativeBearingDegrees: 0, distanceMeters: 250, pausedSinceDate: nil)

        XCTAssertFalse(chip.shouldShowDistance(now: Date().addingTimeInterval(1000)))
    }

    func testDistanceTextFormatting() {
        XCTAssertEqual(OffTrackChipView.distanceText(250), "250 m")
        XCTAssertEqual(OffTrackChipView.distanceText(1500), "1.5 km")
    }
}
