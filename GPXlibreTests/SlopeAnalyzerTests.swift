import XCTest
import CoreLocation
@testable import GPXlibre

/// Spec "slope-warning-native" (it19) : détection native de pente forte (élévation déjà
/// disponible par point), symboles PONCTUELS jamais un dégradé continu.
final class SlopeAnalyzerTests: XCTestCase {
    /// Trace rectiligne nord-sud, un point tous les ~111 m (0.001° de latitude), élévation
    /// fournie explicitement par point.
    private func track(elevations: [Double?]) -> [GPXPoint] {
        elevations.enumerated().map { index, elevation in
            GPXPoint(latitude: 45.0 + Double(index) * 0.001, longitude: 5.0, elevation: elevation)
        }
    }

    func testFlatTrackProducesNoWarnings() {
        let points = track(elevations: Array(repeating: 100, count: 10))

        let warnings = SlopeAnalyzer.steepGradeWarnings(for: points, thresholdPercent: 10, minSegmentMeters: 100, minMarkerSpacingMeters: 300)

        XCTAssertTrue(warnings.isEmpty)
    }

    /// ~111 m par point ; +15 m sur le premier point (dans la fenêtre de 100 m minimum) →
    /// pente ≈ 13.5 %, au-dessus du seuil 10 %.
    func testSteepClimbAboveThresholdProducesWarning() {
        let points = track(elevations: [100, 115, 115, 115, 115])

        let warnings = SlopeAnalyzer.steepGradeWarnings(for: points, thresholdPercent: 10, minSegmentMeters: 100, minMarkerSpacingMeters: 300)

        XCTAssertEqual(warnings.count, 1)
        XCTAssertTrue(warnings[0].isClimbing)
        XCTAssertGreaterThan(warnings[0].gradePercent, 10)
    }

    func testSteepDescentProducesNegativeGradeWarning() {
        let points = track(elevations: [115, 100, 100, 100, 100])

        let warnings = SlopeAnalyzer.steepGradeWarnings(for: points, thresholdPercent: 10, minSegmentMeters: 100, minMarkerSpacingMeters: 300)

        XCTAssertEqual(warnings.count, 1)
        XCTAssertFalse(warnings[0].isClimbing)
        XCTAssertLessThan(warnings[0].gradePercent, -10)
    }

    func testGentleSlopeBelowThresholdProducesNoWarning() {
        // +5 m sur ~111 m ≈ 4.5 %, sous le seuil 10 %.
        let points = track(elevations: [100, 105, 105, 105, 105])

        let warnings = SlopeAnalyzer.steepGradeWarnings(for: points, thresholdPercent: 10, minSegmentMeters: 100, minMarkerSpacingMeters: 300)

        XCTAssertTrue(warnings.isEmpty)
    }

    func testMissingElevationDataNeverCrashesAndProducesNoWarning() {
        let points = track(elevations: [nil, nil, nil, nil, nil])

        let warnings = SlopeAnalyzer.steepGradeWarnings(for: points, thresholdPercent: 10, minSegmentMeters: 100, minMarkerSpacingMeters: 300)

        XCTAssertTrue(warnings.isEmpty)
    }

    /// Longue montée régulière et forte sur ~1 km — un seul symbole tous les
    /// `minMarkerSpacingMeters`, jamais un mur de triangles.
    func testLongSustainedClimbRespectsMinimumMarkerSpacing() {
        var elevations: [Double?] = []
        for i in 0...9 {
            elevations.append(Double(i) * 20) // +20 m tous les ~111 m ≈ 18 % constant
        }
        let points = track(elevations: elevations)

        let warnings = SlopeAnalyzer.steepGradeWarnings(for: points, thresholdPercent: 10, minSegmentMeters: 100, minMarkerSpacingMeters: 300)

        XCTAssertGreaterThan(warnings.count, 0)
        for i in 1..<warnings.count {
            let distance = RoadbookAnalyzer.distanceMeters(warnings[i - 1].coordinate, warnings[i].coordinate)
            XCTAssertGreaterThanOrEqual(distance, 300 - 1, "espacement minimal entre deux symboles non respecté")
        }
    }

    func testZeroOrNegativeThresholdProducesNoWarnings() {
        let points = track(elevations: [100, 115, 115])

        XCTAssertTrue(SlopeAnalyzer.steepGradeWarnings(for: points, thresholdPercent: 0, minSegmentMeters: 100, minMarkerSpacingMeters: 300).isEmpty)
        XCTAssertTrue(SlopeAnalyzer.steepGradeWarnings(for: points, thresholdPercent: -5, minSegmentMeters: 100, minMarkerSpacingMeters: 300).isEmpty)
    }

    func testSingleOrEmptyPointArrayProducesNoWarnings() {
        XCTAssertTrue(SlopeAnalyzer.steepGradeWarnings(for: [], thresholdPercent: 10, minSegmentMeters: 100, minMarkerSpacingMeters: 300).isEmpty)
        XCTAssertTrue(SlopeAnalyzer.steepGradeWarnings(for: track(elevations: [100]), thresholdPercent: 10, minSegmentMeters: 100, minMarkerSpacingMeters: 300).isEmpty)
    }
}
