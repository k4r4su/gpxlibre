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

    /// Spec "roadbook-mode" it23quater : le cap doit refléter le segment SORTANT (juste après
    /// le point de manœuvre RÉEL choisi par l'algorithme existant), jamais une valeur supposée
    /// à l'aveugle — `RoadbookAnalyzer` peut retenir un `sourcePointIndex` légèrement avant ou
    /// après le coin géométrique exact selon la fenêtre de détection (comportement PRÉ-EXISTANT,
    /// pas de sa responsabilité ici) ; ce test verrouille le CONTRAT de `headingDegrees` :
    /// toujours le bearing exact entre ce point et le suivant, quel que soit l'index retenu.
    func testHeadingDegreesMatchesTheBearingOfTheSegmentRightAfterTheSourcePoint() {
        let track = staircaseTrack(legs: 2)
        let maneuvers = extract(track)
        XCTAssertEqual(maneuvers.count, 1)
        let pointIndex = maneuvers[0].checkpoint.sourcePointIndex
        let expectedHeading = RoadbookAnalyzer.bearing(from: track.points[pointIndex].coordinate, to: track.points[pointIndex + 1].coordinate)
        XCTAssertEqual(maneuvers[0].headingDegrees, expectedHeading, accuracy: 0.01)
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

    // MARK: - Stabilité de l'identité (fix "roadbook-landmark-id-stability")

    /// Root cause du bug terrain "aucun emoji de repère ne s'affiche jamais" : `RoadBookTabView.
    /// maneuvers` est une propriété CALCULÉE, réévaluée à CHAQUE rendu SwiftUI (chaque fix GPS en
    /// mode Assisté) — si `Checkpoint.id` changeait à chaque extraction, le dictionnaire
    /// `landmarks: [UUID: RoadbookLandmarkInfo?]` rempli lors d'un rendu perdait toutes ses
    /// entrées dès le rendu suivant. Verrouille le contrat : extraire DEUX FOIS la MÊME trace
    /// (mêmes réglages) doit produire EXACTEMENT les mêmes ids, dans le même ordre.
    func testManeuverIdentityIsStableAcrossRepeatedExtractionsOfTheSameTrack() {
        let track = staircaseTrack(legs: 5)
        let firstPass = extract(track)
        let secondPass = extract(track)

        XCTAssertFalse(firstPass.isEmpty, "précondition : au moins une manœuvre à comparer")
        XCTAssertEqual(firstPass.map(\.id), secondPass.map(\.id))
    }

    /// Deux manœuvres DISTINCTES de la même trace ne doivent jamais partager le même id (l'id
    /// dérive uniquement de `sourcePointIndex`, unique par trace après fusion).
    func testDifferentManeuversOfTheSameTrackHaveDistinctIdentities() {
        let track = staircaseTrack(legs: 5)
        let maneuvers = extract(track)
        XCTAssertEqual(Set(maneuvers.map(\.id)).count, maneuvers.count)
    }

    // MARK: - Route-aware Valhalla (fix "roadbook-valhalla-route-aware")

    /// Root cause du bug terrain "le Road Book n'utilise jamais la détection route-aware" :
    /// `mapMatchedManeuvers` n'existait pas du tout sur cette API avant ce fix. Verrouille que le
    /// paramètre atteint bien `RoadbookAnalyzer` et produit le palier attendu (rond-point, ici),
    /// pas seulement qu'il compile.
    func testMapMatchedManeuverProducesTheCorrespondingRoadbookTier() {
        // Trace RECTILIGNE (aucun virage géométrique, voir `testStraightTrackProducesNoManeuvers`)
        // — un point de map matching placé sur un virage géométrique DÉJÀ détecté serait fusionné
        // dans cet événement existant plutôt que d'apparaître comme un événement séparé (voir
        // `RoadbookMapMatchingTests.testMapMatchedCoordinateAtAnExistingGeometricEventProducesNoDuplicate`,
        // comportement voulu) — sans virage géométrique concurrent ici, rien ne peut absorber le
        // rond-point route-aware.
        let track = staircaseTrack(legs: 1, pointsPerLeg: 10, legLengthMeters: 200)
        let matched = MapMatchedManeuver(coordinate: track.points[5].coordinate, type: .roundaboutExit, roundaboutExitCount: 2)

        let maneuvers = RoadbookExtractor.maneuvers(
            for: track,
            windowBeforeMeters: NavigationConstants.roadbookWindowBeforeMetersDefault,
            windowAfterMeters: NavigationConstants.roadbookWindowAfterMetersDefault,
            lightThresholdDegrees: NavigationConstants.roadbookLightThresholdDegreesDefault,
            markedThresholdDegrees: NavigationConstants.roadbookMarkedThresholdDegreesDefault,
            hardThresholdDegrees: NavigationConstants.roadbookHardThresholdDegreesDefault,
            uTurnThresholdDegrees: NavigationConstants.roadbookUTurnThresholdDegreesDefault,
            mergeMinDistanceMeters: RideConstants.turnMergeMinDistanceMetersDefault,
            mapMatchedManeuvers: [matched]
        )

        XCTAssertTrue(maneuvers.contains { $0.checkpoint.tier == .roundabout && $0.checkpoint.roundaboutExitCount == 2 })
    }

    /// Non-régression explicite : omettre `mapMatchedManeuvers` (valeur par défaut `[]`) laisse
    /// le comportement géométrique STRICTEMENT identique à avant ce fix.
    func testOmittingMapMatchedManeuversLeavesGeometricDetectionUnchanged() {
        let track = staircaseTrack(legs: 4)
        let withoutParam = extract(track)
        let withEmptyParam = RoadbookExtractor.maneuvers(
            for: track,
            windowBeforeMeters: NavigationConstants.roadbookWindowBeforeMetersDefault,
            windowAfterMeters: NavigationConstants.roadbookWindowAfterMetersDefault,
            lightThresholdDegrees: NavigationConstants.roadbookLightThresholdDegreesDefault,
            markedThresholdDegrees: NavigationConstants.roadbookMarkedThresholdDegreesDefault,
            hardThresholdDegrees: NavigationConstants.roadbookHardThresholdDegreesDefault,
            uTurnThresholdDegrees: NavigationConstants.roadbookUTurnThresholdDegreesDefault,
            mergeMinDistanceMeters: RideConstants.turnMergeMinDistanceMetersDefault,
            mapMatchedManeuvers: []
        )
        XCTAssertEqual(withoutParam.map(\.id), withEmptyParam.map(\.id))
        XCTAssertEqual(withoutParam.map { $0.checkpoint.tier }, withEmptyParam.map { $0.checkpoint.tier })
    }
}
