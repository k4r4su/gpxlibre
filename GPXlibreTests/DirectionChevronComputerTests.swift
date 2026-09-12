import XCTest
import CoreLocation
@testable import GPXlibre

/// Vérification directe du calcul des chevrons (spec "per-track-settings") — plus fiable
/// qu'une capture simulateur pour confirmer l'espacement et le cap, difficiles à mesurer au
/// pixel près sur une trace courte.
final class DirectionChevronComputerTests: XCTestCase {
    /// Segment de 1000 m plein est (bearing 90°) — un point tous les 250 m attendu.
    func testChevronsAreEvenlySpacedAlongAStraightEastwardSegment() {
        let points = [
            GPXPoint(latitude: 45.0, longitude: 0.0),
            GPXPoint(latitude: 45.0, longitude: 0.0127), // ~1000 m est à cette latitude
        ]
        let chevrons = DirectionChevronComputer.chevrons(for: points, spacingMeters: 250)

        XCTAssertEqual(chevrons.count, 4, "4 chevrons attendus sur ~1000 m à 250 m d'espacement")
        for chevron in chevrons {
            XCTAssertEqual(chevron.bearingDegrees, 90, accuracy: 1, "segment plein est ≈ cap 90°")
        }
        // Espacement réel entre chevrons consécutifs ≈ 250 m.
        for i in 1..<chevrons.count {
            let distance = RoadbookAnalyzer.distanceMeters(chevrons[i - 1].coordinate, chevrons[i].coordinate)
            XCTAssertEqual(distance, 250, accuracy: 5)
        }
    }

    func testNoChevronsOnATrackShorterThanSpacing() {
        let points = [
            GPXPoint(latitude: 45.0, longitude: 0.0),
            GPXPoint(latitude: 45.0, longitude: 0.0005), // ~40 m
        ]
        let chevrons = DirectionChevronComputer.chevrons(for: points, spacingMeters: 500)
        XCTAssertTrue(chevrons.isEmpty)
    }

    func testEmptyOrSinglePointTrackProducesNoChevrons() {
        XCTAssertTrue(DirectionChevronComputer.chevrons(for: [], spacingMeters: 500).isEmpty)
        XCTAssertTrue(DirectionChevronComputer.chevrons(for: [GPXPoint(latitude: 45, longitude: 5)], spacingMeters: 500).isEmpty)
    }

    /// GPXTrack.reordered(using:) — sens inversé + départ personnalisé, sans jamais muter la
    /// trace source (nouvelle valeur retournée).
    func testReorderedReversesAndRotatesWithoutMutatingOriginal() {
        let points = (0..<5).map { GPXPoint(latitude: 45.0, longitude: Double($0) * 0.001) }
        let track = GPXTrack(id: UUID(), name: "Test", fileName: "test.gpx", importDate: Date(), points: points, waypoints: [])

        var settings = TrackRideSettings.default
        settings.isReversed = true
        let reversed = track.reordered(using: settings)
        XCTAssertEqual(reversed.points.map(\.longitude), points.reversed().map(\.longitude))
        XCTAssertEqual(track.points.map(\.longitude), points.map(\.longitude), "la trace source ne doit jamais être mutée")

        settings.isReversed = false
        settings.customStartPointIndex = 2
        let rotated = track.reordered(using: settings)
        XCTAssertEqual(rotated.points.map(\.longitude), [0.002, 0.003, 0.004, 0.000, 0.001])
    }

    func testIsLoopDetectsFirstAndLastPointWithin200Meters() {
        let loopPoints = [
            GPXPoint(latitude: 45.0, longitude: 5.0),
            GPXPoint(latitude: 45.01, longitude: 5.01),
            GPXPoint(latitude: 45.0001, longitude: 5.0001),
        ]
        let loop = GPXTrack(id: UUID(), name: "Loop", fileName: "loop.gpx", importDate: Date(), points: loopPoints, waypoints: [])
        XCTAssertTrue(loop.isLoop)

        let outAndBackPoints = [
            GPXPoint(latitude: 45.0, longitude: 5.0),
            GPXPoint(latitude: 45.5, longitude: 5.5),
        ]
        let outAndBack = GPXTrack(id: UUID(), name: "A-B", fileName: "ab.gpx", importDate: Date(), points: outAndBackPoints, waypoints: [])
        XCTAssertFalse(outAndBack.isLoop)
    }
}
