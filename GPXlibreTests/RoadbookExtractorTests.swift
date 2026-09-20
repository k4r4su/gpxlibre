import XCTest
@testable import GPXlibre

/// Spec "roadbook-mode" (it23, point 1) — tests demandés explicitement par la fiche :
/// "extraction de la liste de manœuvres à partir d'une trace (distances partielle/cumulée
/// cohérentes, cas trace avec un seul point de manœuvre, cas trace sans aucun changement de
/// direction)".
final class RoadbookExtractorTests: XCTestCase {
    private let latPerMeter = 1.0 / 111_320
    private let lonPerMeter = 1.0 / (111_320 * cos(45 * .pi / 180))

    /// Trace en "escalier" : `legs` segments rectilignes, chacun tournant à 90° par rapport au
    /// précédent (est, nord, est, nord...) — `legs - 1` virages francs, bien au-dessus du seuil
    /// "light" (30°) par défaut, espacés largement au-delà de `turnMergeMinDistanceMetersDefault`
    /// (150 m) pour ne jamais fusionner deux virages en un seul.
    private func staircaseTrack(legs: Int, pointsPerLeg: Int = 6, legLengthMeters: Double = 220) -> GPXTrack {
        var points: [GPXPoint] = []
        var lat = 45.000
        var lon = 5.000
        points.append(GPXPoint(latitude: lat, longitude: lon))
        let step = legLengthMeters / Double(pointsPerLeg)
        for leg in 0..<legs {
            let headingEast = leg % 2 == 0
            for _ in 0..<pointsPerLeg {
                if headingEast {
                    lon += step * lonPerMeter
                } else {
                    lat += step * latPerMeter
                }
                points.append(GPXPoint(latitude: lat, longitude: lon))
            }
        }
        return GPXTrack(id: UUID(), name: "Test", fileName: "test.gpx", importDate: Date(), points: points, waypoints: [])
    }

    private func extract(_ track: GPXTrack) -> [RoadbookManeuver] {
        RoadbookExtractor.maneuvers(
            for: track,
            windowBeforeMeters: NavigationConstants.roadbookWindowBeforeMetersDefault,
            windowAfterMeters: NavigationConstants.roadbookWindowAfterMetersDefault,
            lightThresholdDegrees: NavigationConstants.roadbookLightThresholdDegreesDefault,
            markedThresholdDegrees: NavigationConstants.roadbookMarkedThresholdDegreesDefault,
            hardThresholdDegrees: NavigationConstants.roadbookHardThresholdDegreesDefault,
            uTurnThresholdDegrees: NavigationConstants.roadbookUTurnThresholdDegreesDefault,
            mergeMinDistanceMeters: RideConstants.turnMergeMinDistanceMetersDefault
        )
    }

    // MARK: - Trace sans aucun changement de direction

    func testStraightTrackProducesNoManeuvers() {
        let track = staircaseTrack(legs: 1, pointsPerLeg: 10, legLengthMeters: 500)
        XCTAssertEqual(extract(track), [])
    }

    func testTooShortTrackProducesNoManeuversRatherThanCrashing() {
        let track = GPXTrack(
            id: UUID(), name: "Trop courte", fileName: "t.gpx", importDate: Date(),
            points: [GPXPoint(latitude: 45, longitude: 5), GPXPoint(latitude: 45.001, longitude: 5)],
            waypoints: []
        )
        XCTAssertEqual(extract(track), [])
    }

    // MARK: - Trace avec un seul point de manœuvre

    func testSingleCornerTrackProducesExactlyOneManeuver() {
        let track = staircaseTrack(legs: 2)
        let maneuvers = extract(track)
        XCTAssertEqual(maneuvers.count, 1)
        // Partielle == cumulée pour la toute première manœuvre de la liste (rien avant elle).
        XCTAssertEqual(maneuvers[0].partialDistanceMeters, maneuvers[0].cumulativeDistanceMeters, accuracy: 0.01)
        XCTAssertGreaterThan(maneuvers[0].cumulativeDistanceMeters, 0)
    }

    // MARK: - Distances partielle/cumulée cohérentes (plusieurs manœuvres)

    func testPartialAndCumulativeDistancesAreConsistentAcrossMultipleManeuvers() {
        let track = staircaseTrack(legs: 4) // 3 virages francs
        let maneuvers = extract(track)
        XCTAssertEqual(maneuvers.count, 3, "3 segments de jonction pour 4 tronçons rectilignes")

        let cumulativeDistances = TrackProjector.cumulativeDistances(for: track.points)

        var runningTotal: Double = 0
        for maneuver in maneuvers {
            runningTotal += maneuver.partialDistanceMeters
            // Somme des partielles jusqu'ici == la cumulée annoncée à ce point (propriété
            // "télescopique", vraie quelle que soit la forme de la trace).
            XCTAssertEqual(runningTotal, maneuver.cumulativeDistanceMeters, accuracy: 0.01)
            // La cumulée doit correspondre exactement à la distance cumulée réelle au point
            // source de la trace (pas une approximation séparée).
            XCTAssertEqual(maneuver.cumulativeDistanceMeters, cumulativeDistances[maneuver.checkpoint.sourcePointIndex], accuracy: 0.01)
        }

        // Monotone croissante — jamais une manœuvre "avant" la précédente dans l'ordre de la liste.
        for i in 1..<maneuvers.count {
            XCTAssertGreaterThan(maneuvers[i].cumulativeDistanceMeters, maneuvers[i - 1].cumulativeDistanceMeters)
        }
    }

    /// Aucune dépendance à `RideSessionManager`/`LibraryStore` — ce test compile et passe sans
    /// jamais importer/instancier l'un ou l'autre, preuve directe du découplage (spec : "Road
    /// Book totalement découplé de l'état de Ride actif").
    func testExtractionNeedsOnlyAGPXTrackValue() {
        let track = staircaseTrack(legs: 2)
        XCTAssertNoThrow(extract(track))
    }
}
