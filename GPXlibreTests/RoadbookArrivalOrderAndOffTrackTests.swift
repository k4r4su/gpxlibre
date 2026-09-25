import XCTest
import CoreLocation
import SwiftUI
@testable import GPXlibre

/// It30 — (3) le prochain élément mis en avant est le plus proche, tous types confondus ;
/// (2) statut "Hors trace" du Road Book, même règle que le Ride.
@MainActor
final class RoadbookArrivalOrderAndOffTrackTests: XCTestCase {
    private let start = CLLocationCoordinate2D(latitude: 47.5, longitude: 7.3)

    private func north(_ meters: Double, lateral: Double = 0) -> CLLocationCoordinate2D {
        let metersPerDegreeLat = 111_320.0
        let metersPerDegreeLon = metersPerDegreeLat * cos(start.latitude * .pi / 180)
        return CLLocationCoordinate2D(latitude: start.latitude + meters / metersPerDegreeLat, longitude: start.longitude + lateral / metersPerDegreeLon)
    }

    private func maneuver(_ meters: Double) -> RoadbookManeuver {
        let checkpoint = Checkpoint(coordinate: north(meters), turnAngleDegrees: 90, direction: .right, tier: .hard, sequenceIndex: 1, sourcePointIndex: Int(meters / 20), trackCumulativeDistanceMeters: meters)
        return RoadbookManeuver(checkpoint: checkpoint, partialDistanceMeters: meters, cumulativeDistanceMeters: meters, headingDegrees: 90)
    }

    private func landmark(_ category: RoadbookLandmarkCategory, _ meters: Double) -> RoadbookLandmarkCheckpoint {
        RoadbookLandmarkCheckpoint(info: RoadbookLandmarkInfo(category: category, label: category.genericLabel), latitude: north(meters).latitude, longitude: north(meters).longitude, cumulativeDistanceMeters: meters)
    }

    private func describe(_ entry: RoadbookEntry) -> String {
        switch entry {
        case .maneuver(let m, _): return "virage@\(Int(m.cumulativeDistanceMeters.rounded()))"
        case .landmark(let l): return "\(l.info.category.rawValue)@\(Int(l.cumulativeDistanceMeters.rounded()))"
        }
    }

    private func describe(_ step: RoadbookFocusedView.UpcomingStep) -> String {
        switch step {
        case .maneuver(_, let rank, let d): return "virage+\(rank - 1)@\(Int(d.rounded()))"
        case .landmark(let l, let d): return "\(l.info.category.rawValue)@\(Int(d.rounded()))"
        }
    }

    // MARK: - (3) Priorité par ordre d'arrivée

    /// Virage à 300 m, stop à 200 m sur le même tronçon : le STOP est mis en avant.
    func testAStopBeforeATurnIsShownFirst() throws {
        let entries = RoadbookEntry.merge(maneuvers: [maneuver(300)], landmarks: [landmark(.stopSign, 200)])

        let next = try XCTUnwrap(RoadbookLiveProgress.nextEntry(entries: entries, currentCumulativeDistanceMeters: 0))

        XCTAssertEqual(describe(entries[next.index]), "stopSign@200")
        XCTAssertEqual(next.distanceRemainingMeters, 200, accuracy: 0.001)
        let upcoming = RoadbookFocusedView.upcomingSteps(entries: entries, currentEntryIndex: next.index, distanceRemainingMeters: next.distanceRemainingMeters, currentCumulativeDistanceMeters: 0)
        XCTAssertEqual(upcoming.map(describe), ["virage+1@300"], "le virage vient ensuite, numéroté +1 (jamais +0)")
    }

    /// Plusieurs repères et virages entremêlés : ordre strictement croissant depuis la position.
    func testMixedEntriesAreStrictlyOrderedByDistanceFromThePosition() throws {
        let entries = RoadbookEntry.merge(
            maneuvers: [maneuver(900), maneuver(400), maneuver(1500)].sorted { $0.cumulativeDistanceMeters < $1.cumulativeDistanceMeters },
            landmarks: [landmark(.citySign, 150), landmark(.trafficSignals, 650), landmark(.church, 1200), landmark(.levelCrossing, 880)]
        )
        let position = 100.0
        let next = try XCTUnwrap(RoadbookLiveProgress.nextEntry(entries: entries, currentCumulativeDistanceMeters: position))
        let upcoming = RoadbookFocusedView.upcomingSteps(entries: entries, currentEntryIndex: next.index, distanceRemainingMeters: next.distanceRemainingMeters, currentCumulativeDistanceMeters: position)

        XCTAssertEqual(describe(entries[next.index]), "citySign@150")
        XCTAssertEqual(upcoming.map(describe), ["virage+1@300", "trafficSignals@550", "levelCrossing@780", "virage+2@800", "church@1100", "virage+3@1400"])
        let distances = upcoming.map(\.distanceFromNowMeters)
        XCTAssertEqual(distances, distances.sorted(), "ordre croissant, aucune priorité de catégorie")
    }

    /// Après être passé le stop : le virage devient l'élément mis en avant (maintien 15 m
    /// inchangé, mais le virage à 100 m n'est pas "enchaîné").
    func testOnceTheStopIsPassedTheTurnComesForward() throws {
        let entries = RoadbookEntry.merge(maneuvers: [maneuver(300)], landmarks: [landmark(.stopSign, 200)])
        let justAfter = try XCTUnwrap(RoadbookLiveProgress.nextEntry(entries: entries, currentCumulativeDistanceMeters: 205))
        XCTAssertEqual(describe(entries[justAfter.index]), "stopSign@200", "maintien juste après l'avoir atteint")
        let later = try XCTUnwrap(RoadbookLiveProgress.nextEntry(entries: entries, currentCumulativeDistanceMeters: 230))
        XCTAssertEqual(describe(entries[later.index]), "virage@300")
        XCTAssertEqual(later.distanceRemainingMeters, 70, accuracy: 0.001)
    }

    /// Non-régression : un seul élément à venir, et le calcul historique par manœuvres inchangé.
    func testSingleUpcomingElementAndLegacyManeuverProgressAreUnchanged() throws {
        let only = RoadbookEntry.merge(maneuvers: [maneuver(500)], landmarks: [])
        let next = try XCTUnwrap(RoadbookLiveProgress.nextEntry(entries: only, currentCumulativeDistanceMeters: 100))
        XCTAssertEqual(next.index, 0)
        XCTAssertEqual(next.distanceRemainingMeters, 400, accuracy: 0.001)
        XCTAssertTrue(RoadbookFocusedView.upcomingSteps(entries: only, currentEntryIndex: 0, distanceRemainingMeters: 400, currentCumulativeDistanceMeters: 100).isEmpty)

        let legacy = try XCTUnwrap(RoadbookLiveProgress.nextManeuver(maneuvers: [maneuver(500)], currentCumulativeDistanceMeters: 100))
        XCTAssertEqual(legacy.index, next.index)
        XCTAssertEqual(legacy.distanceRemainingMeters, next.distanceRemainingMeters, accuracy: 0.001)
        XCTAssertNil(RoadbookLiveProgress.nextEntry(entries: [], currentCumulativeDistanceMeters: 0))
    }

    /// La règle de densité (1 repère par tronçon) limite le NOMBRE, jamais l'ordre : le repère
    /// retenu dans un tronçon passe avant le virage qui ferme ce tronçon s'il est plus proche.
    func testDensityRuleNeverDelaysACloserLandmark() throws {
        let points = stride(from: 0.0, through: 2000, by: 20).map { GPXPoint(latitude: north($0).latitude, longitude: north($0).longitude) }
        let turn = maneuver(1000)
        let data = RoadbookLandmarkData(candidates: [
            RoadbookLandmarkCandidate(category: .stopSign, label: "Stop", coordinate: north(600, lateral: 6)),
            RoadbookLandmarkCandidate(category: .church, label: "Église", coordinate: north(700, lateral: 30)),
        ])
        let selection = RoadbookLandmarkSelector.select(data, points: points, maneuvers: [turn], enabledCategories: RoadBookConstants.landmarkDefaultEnabledCategories)
        let entries = RoadbookEntry.merge(maneuvers: [turn], landmarks: selection.standalone)
        let next = try XCTUnwrap(RoadbookLiveProgress.nextEntry(entries: entries, currentCumulativeDistanceMeters: 0))

        XCTAssertEqual(entries.map { $0.isManeuver ? "virage" : "repère" }, ["repère", "virage"], "densité : 1 repère sur ce tronçon")
        guard case .landmark(let first) = entries[next.index] else { return XCTFail("le repère plus proche doit passer en premier") }
        XCTAssertEqual(first.info.category, .stopSign)
        XCTAssertEqual(next.distanceRemainingMeters, 600, accuracy: 3)
    }

    // MARK: - (2) Hors trace

    private var trackPoints: [GPXPoint] {
        stride(from: 0.0, through: 2000, by: 20).map { GPXPoint(latitude: north($0).latitude, longitude: north($0).longitude) }
    }

    private func location(_ coordinate: CLLocationCoordinate2D, at seconds: Double) -> CLLocation {
        CLLocation(coordinate: coordinate, altitude: 0, horizontalAccuracy: 5, verticalAccuracy: 5, timestamp: Date(timeIntervalSince1970: 1_000_000 + seconds))
    }

    func testOffTrackAppearsAndDisappearsWithTheRideThresholds() {
        let points = trackPoints
        let cumulative = TrackProjector.cumulativeDistances(for: points)
        var state = RoadbookOffTrackState()

        state.update(location: location(north(500, lateral: 10), at: 0), points: points, cumulativeDistances: cumulative)
        XCTAssertFalse(state.isOffTrack, "sur la trace")

        state.update(location: location(north(520, lateral: RideConstants.horsTraceEnterMeters + 5), at: 5), points: points, cumulativeDistances: cumulative)
        XCTAssertTrue(state.isOffTrack, "au-delà du seuil d'entrée du Ride")

        // Bande d'hystérésis : ni entrée ni sortie.
        state.update(location: location(north(540, lateral: (RideConstants.horsTraceEnterMeters + RideConstants.horsTraceExitMeters) / 2), at: 10), points: points, cumulativeDistances: cumulative)
        XCTAssertTrue(state.isOffTrack, "reste hors trace tant qu'on n'est pas revenu sous le seuil de sortie")

        state.update(location: location(north(560, lateral: RideConstants.horsTraceExitMeters - 5), at: 15), points: points, cumulativeDistances: cumulative)
        XCTAssertFalse(state.isOffTrack, "retour sur la trace : affichage normal")
        XCTAssertNil(state.rejoinDistanceMeters)
    }

    /// Même règle que le Ride : le Road Book et `RideSessionManager` passent par `OffTrackDetector`.
    func testRoadBookAndRideShareTheSameRule() {
        for distance in stride(from: 0.0, through: 60, by: 1) {
            for was in [false, true] {
                let expected = was ? distance > RideConstants.horsTraceExitMeters : distance > RideConstants.horsTraceEnterMeters
                XCTAssertEqual(OffTrackDetector.isOffTrack(wasOffTrack: was, distanceToTrackMeters: distance), expected)
            }
        }
    }

    func testRejoinDistanceAppearsAfterTheSameDelayAsTheRideChip() throws {
        let points = trackPoints
        let cumulative = TrackProjector.cumulativeDistances(for: points)
        var state = RoadbookOffTrackState()
        state.update(location: location(north(500, lateral: 200), at: 0), points: points, cumulativeDistances: cumulative)

        XCTAssertTrue(state.isOffTrack)
        XCTAssertEqual(try XCTUnwrap(state.rejoinDistanceMeters), 200, accuracy: 2)
        XCTAssertFalse(state.showsRejoinDistance(now: Date(timeIntervalSince1970: 1_000_000 + 5)))
        XCTAssertTrue(state.showsRejoinDistance(now: Date(timeIntervalSince1970: 1_000_000 + RideConstants.offTrackChipDistanceDelaySeconds)))
    }
}
