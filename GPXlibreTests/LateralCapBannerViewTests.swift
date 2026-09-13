import XCTest
@testable import GPXlibre

/// Vérifie le countdown par paliers de la bannière latérale (spec
/// "lateral-cap-banner-countdown", it12) : 100 m au-dessus de 150 m, 10 m en dessous.
final class LateralCapBannerViewTests: XCTestCase {
    func testCoarseStepsAboveFineThreshold() {
        XCTAssertEqual(LateralCapBannerView.steppedDistanceText(600), "600 m")
        XCTAssertEqual(LateralCapBannerView.steppedDistanceText(599), "600 m", "reste à 600 juste après l'apparition de la bannière")
        XCTAssertEqual(LateralCapBannerView.steppedDistanceText(501), "600 m")
        XCTAssertEqual(LateralCapBannerView.steppedDistanceText(500), "500 m")
        XCTAssertEqual(LateralCapBannerView.steppedDistanceText(401), "500 m")
        XCTAssertEqual(LateralCapBannerView.steppedDistanceText(400), "400 m")
        XCTAssertEqual(LateralCapBannerView.steppedDistanceText(200), "200 m")
        XCTAssertEqual(LateralCapBannerView.steppedDistanceText(151), "200 m")
    }

    func testFineStepsAtAndBelowThreshold() {
        XCTAssertEqual(LateralCapBannerView.steppedDistanceText(150), "150 m")
        XCTAssertEqual(LateralCapBannerView.steppedDistanceText(149), "140 m")
        XCTAssertEqual(LateralCapBannerView.steppedDistanceText(140), "140 m")
        XCTAssertEqual(LateralCapBannerView.steppedDistanceText(21), "20 m")
        XCTAssertEqual(LateralCapBannerView.steppedDistanceText(9), "0 m")
        XCTAssertEqual(LateralCapBannerView.steppedDistanceText(0), "0 m")
    }

    func testNegativeDistanceClampsToZero() {
        XCTAssertEqual(LateralCapBannerView.steppedDistanceText(-5), "0 m")
    }
}
