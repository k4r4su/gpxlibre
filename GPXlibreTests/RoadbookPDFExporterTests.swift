import XCTest
import CoreGraphics
@testable import GPXlibre

/// Spec "roadbook-mode" (it23, point 2) — tests demandés explicitement : "génération PDF ne
/// plante pas sur une trace vide ou très longue (beaucoup de manœuvres, plusieurs pages)".
final class RoadbookPDFExporterTests: XCTestCase {
    private func maneuver(index: Int) -> RoadbookManeuver {
        let checkpoint = Checkpoint(
            coordinate: .init(latitude: 45, longitude: 5 + Double(index) * 0.001),
            turnAngleDegrees: Double(30 + index % 100),
            direction: index.isMultiple(of: 2) ? .right : .left,
            tier: .marked,
            sequenceIndex: index + 1,
            sourcePointIndex: index
        )
        let cumulative = Double(index + 1) * 300
        return RoadbookManeuver(checkpoint: checkpoint, partialDistanceMeters: 300, cumulativeDistanceMeters: cumulative)
    }

    // MARK: - Trace vide

    func testGenerateNeverCrashesOnEmptyManeuverList() {
        let data = RoadbookPDFExporter.generate(trackName: "Trace vide", maneuvers: [], options: RoadbookPDFOptions())
        XCTAssertGreaterThan(data.count, 0, "un PDF valide (même avec un seul message) doit toujours être produit")
        XCTAssertTrue(data.starts(with: Array("%PDF".utf8)), "doit rester un PDF structurellement valide")
    }

    func testGenerateWithEmptyTrackNameFallsBackToDefaultTitle() {
        let data = RoadbookPDFExporter.generate(trackName: "", maneuvers: [], options: RoadbookPDFOptions())
        XCTAssertGreaterThan(data.count, 0)
    }

    // MARK: - Trace très longue (multi-pages)

    func testGenerateNeverCrashesOnManyManeuvers() {
        let maneuvers = (0..<500).map { maneuver(index: $0) }
        let data = RoadbookPDFExporter.generate(trackName: "Longue trace", maneuvers: maneuvers, options: RoadbookPDFOptions())
        XCTAssertGreaterThan(data.count, 0)
        XCTAssertTrue(data.starts(with: Array("%PDF".utf8)))
    }

    /// Toutes les combinaisons d'options doivent produire un PDF exploitable (spec, checklist
    /// manuelle "toutes les combinaisons de mise en forme produisent un PDF exploitable") — ce
    /// test automatique couvre au moins l'absence de crash pour CHAQUE combinaison, la
    /// lisibilité réelle reste une vérification manuelle (voir TODO.md).
    func testGenerateNeverCrashesForAnyOptionCombination() {
        let maneuvers = (0..<12).map { maneuver(index: $0) }
        for orientation in PDFOrientation.allCases {
            for density in PDFDensity.allCases {
                for headingStyle in PDFHeadingStyle.allCases {
                    for fontSize in PDFFontSize.allCases {
                        for showCumulative in [true, false] {
                            for showNote in [true, false] {
                                var options = RoadbookPDFOptions()
                                options.orientation = orientation
                                options.density = density
                                options.headingStyle = headingStyle
                                options.fontSize = fontSize
                                options.showCumulativeDistance = showCumulative
                                options.showNoteColumn = showNote
                                let data = RoadbookPDFExporter.generate(trackName: "Trace", maneuvers: maneuvers, options: options)
                                XCTAssertGreaterThan(data.count, 0, "\(options)")
                            }
                        }
                    }
                }
            }
        }
    }

    // MARK: - Répartition des colonnes

    func testColumnWidthsAlwaysSumToContentWidthAndNeverGoNegative() {
        let contentRect = CGRect(x: 32, y: 96, width: 500, height: 30)
        for showCumulative in [true, false] {
            for showNote in [true, false] {
                var options = RoadbookPDFOptions()
                options.showCumulativeDistance = showCumulative
                options.showNoteColumn = showNote
                let layout = RoadbookPDFExporter.columnLayout(options: options, contentRect: contentRect)

                XCTAssertGreaterThanOrEqual(layout.partial.width, 0)
                XCTAssertGreaterThanOrEqual(layout.heading.width, 0)
                if let cumulative = layout.cumulative { XCTAssertGreaterThanOrEqual(cumulative.width, 0) }
                if let note = layout.note { XCTAssertGreaterThanOrEqual(note.width, 0) }

                let lastColumnMaxX = (layout.note ?? layout.heading).maxX
                XCTAssertEqual(lastColumnMaxX, contentRect.maxX, accuracy: 0.5, "les colonnes doivent couvrir toute la largeur, sans déborder ni laisser de blanc — showCumulative=\(showCumulative) showNote=\(showNote)")
            }
        }
    }

    func testCumulativeColumnIsNilWhenDisabled() {
        var options = RoadbookPDFOptions()
        options.showCumulativeDistance = false
        let layout = RoadbookPDFExporter.columnLayout(options: options, contentRect: CGRect(x: 0, y: 0, width: 400, height: 30))
        XCTAssertNil(layout.cumulative)
    }

    func testNoteColumnIsNilWhenDisabled() {
        var options = RoadbookPDFOptions()
        options.showNoteColumn = false
        let layout = RoadbookPDFExporter.columnLayout(options: options, contentRect: CGRect(x: 0, y: 0, width: 400, height: 30))
        XCTAssertNil(layout.note)
    }
}
