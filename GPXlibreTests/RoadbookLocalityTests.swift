import XCTest
import CoreLocation
@testable import GPXlibre

/// Spec "roadbook-locality-checkpoints" (it26 point 3) — checkpoints d'entrée de commune, logique
/// pure (aucun réseau : communes synthétiques). Trois communes carrées A/B/C côte à côte d'ouest en
/// est (0,01° de longitude chacune ≈ 787 m à 45° de latitude).
@MainActor
final class RoadbookLocalityTests: XCTestCase {
    /// Distance le long du parallèle 45°, mesurée comme l'app (`CLLocation`, ellipsoïde) — une
    /// conversion sphérique fixe dévierait de ~0,17 %.
    private func meters(from startLongitude: Double, to longitude: Double) -> Double {
        RoadbookAnalyzer.distanceMeters(.init(latitude: 45, longitude: startLongitude), .init(latitude: 45, longitude: longitude))
    }

    private func square(_ name: String, west: Double, east: Double) -> RoadbookLocalityArea {
        RoadbookLocalityArea(name: name, rings: [[
            .init(latitude: 44.99, longitude: west), .init(latitude: 44.99, longitude: east),
            .init(latitude: 45.01, longitude: east), .init(latitude: 45.01, longitude: west),
            .init(latitude: 44.99, longitude: west),
        ]])
    }

    private var threeCommunes: [RoadbookLocalityArea] {
        [square("A", west: 5.000, east: 5.010), square("B", west: 5.010, east: 5.020), square("C", west: 5.020, east: 5.030)]
    }

    /// Trace passant par les longitudes données (points intermédiaires tous les ~40 m).
    private func track(through longitudes: [Double], latitude: Double = 45.0) -> GPXTrack {
        var points: [GPXPoint] = []
        for (from, to) in zip(longitudes, longitudes.dropFirst()) {
            let steps = max(Int((abs(to - from) / 0.0005).rounded(.up)), 1)
            for step in 0..<steps {
                points.append(GPXPoint(latitude: latitude, longitude: from + (to - from) * Double(step) / Double(steps)))
            }
        }
        points.append(GPXPoint(latitude: latitude, longitude: longitudes.last!))
        return GPXTrack(id: UUID(), name: "Communes", fileName: "c.gpx", importDate: Date(), points: points, waypoints: [])
    }

    private func checkpoints(_ track: GPXTrack, areas: [RoadbookLocalityArea]) -> [RoadbookLocalityCheckpoint] {
        RoadbookLocalityDetector.checkpoints(from: RoadbookLocalityOverpassData(areas: areas, citySigns: [], places: []), points: track.points)
    }

    // MARK: - Test demandé par la fiche : 3 communes, ordre, doublons, sens inversé

    func testATrackCrossingThreeCommunesProducesThreeCheckpointsInOrder() {
        let result = checkpoints(track(through: [4.995, 5.035]), areas: threeCommunes)

        XCTAssertEqual(result.map(\.name), ["A", "B", "C"])
        XCTAssertEqual(result.map(\.source), [.boundary, .boundary, .boundary])
        // Entrée affinée au vrai franchissement de limite, pas au point GPX voisin.
        XCTAssertEqual(result[0].cumulativeDistanceMeters, meters(from: 4.995, to: 5.000), accuracy: 1)
        XCTAssertEqual(result[1].cumulativeDistanceMeters, meters(from: 4.995, to: 5.010), accuracy: 1)
        XCTAssertEqual(result[2].cumulativeDistanceMeters, meters(from: 4.995, to: 5.020), accuracy: 1)
    }

    func testReversedDirectionProducesTheCheckpointsInReverseOrderAtTheOppositeBoundaries() {
        let forward = track(through: [4.995, 5.035])
        let reversed = forward.reordered(using: TrackRideSettings(isReversed: true))

        let result = checkpoints(reversed, areas: threeCommunes)

        XCTAssertEqual(result.map(\.name), ["C", "B", "A"])
        XCTAssertEqual(result[0].cumulativeDistanceMeters, meters(from: 5.030, to: 5.035), accuracy: 1, "C est entrée par sa limite EST en sens inversé")
    }

    /// Trace qui LONGE la limite A/B (route qui suit la limite, GPS qui oscille de part et
    /// d'autre sur 1 km) avant d'entrer vraiment dans B : ni les incursions dans B, ni les retours
    /// dans A ne sont des entrées.
    func testSkirtingABoundaryProducesNoEntryNorReentry() {
        var points: [GPXPoint] = track(through: [4.995, 5.0098]).points
        var latitude = 45.0
        for step in 0..<20 {
            latitude += 50 / 111_320
            points.append(GPXPoint(latitude: latitude, longitude: step.isMultiple(of: 2) ? 5.0102 : 5.0098))
        }
        points += track(through: [5.0102, 5.018], latitude: latitude).points
        let skirting = GPXTrack(id: UUID(), name: "Longe", fileName: "l.gpx", importDate: Date(), points: points, waypoints: [])

        let result = checkpoints(skirting, areas: threeCommunes)

        XCTAssertEqual(result.map(\.name), ["A", "B"])
    }

    /// Sortie puis ré-entrée dans la même commune plus tôt que
    /// `localityReentryMinDistanceMeters` : la ré-entrée n'est pas un nouveau checkpoint.
    func testAReentryIntoTheSameCommuneTooSoonIsIgnored() {
        // Entre dans A (~390 m), passe ~950 m dans B (aller-retour), revient dans A ~1,7 km après
        // sa première entrée (< 2 km) et y reste.
        let result = checkpoints(track(through: [4.995, 5.016, 5.004]), areas: threeCommunes)

        XCTAssertEqual(result.map(\.name), ["A", "B"])
    }

    func testATrackThatNeverLeavesItsStartCommuneHasNoCheckpoint() {
        XCTAssertTrue(checkpoints(track(through: [5.001, 5.009]), areas: threeCommunes).isEmpty)
    }

    func testTheStartCommuneIsNeverACheckpoint() {
        XCTAssertEqual(checkpoints(track(through: [5.005, 5.015]), areas: threeCommunes).map(\.name), ["B"])
    }

    // MARK: - Géométrie

    func testRingAssemblyJoinsBoundaryWaysGivenInAnyDirection() {
        let a = CLLocationCoordinate2D(latitude: 45, longitude: 5)
        let b = CLLocationCoordinate2D(latitude: 45, longitude: 5.01)
        let c = CLLocationCoordinate2D(latitude: 45.01, longitude: 5.01)
        let d = CLLocationCoordinate2D(latitude: 45.01, longitude: 5)
        // Deux moitiés de limite, la seconde dans le sens inverse (cas réel : chemins partagés).
        let rings = RoadbookLocalityGeometry.assembleRings([[a, b, c], [a, d, c]])

        XCTAssertEqual(rings.count, 1)
        let area = RoadbookLocalityArea(name: "X", rings: rings)
        XCTAssertTrue(area.contains(.init(latitude: 45.005, longitude: 5.005)))
        XCTAssertFalse(area.contains(.init(latitude: 45.005, longitude: 5.015)))
    }

    func testAnUnclosedBoundaryIsDiscardedRatherThanGuessed() {
        let rings = RoadbookLocalityGeometry.assembleRings([[.init(latitude: 45, longitude: 5), .init(latitude: 45, longitude: 5.01), .init(latitude: 45.01, longitude: 5.01)]])
        XCTAssertTrue(rings.isEmpty)
    }

    func testAPointInsideAnInnerRingIsOutsideTheCommune() {
        let outer = square("X", west: 5.0, east: 5.03).rings[0]
        let hole = square("trou", west: 5.01, east: 5.02).rings[0]
        let area = RoadbookLocalityArea(name: "X", rings: [outer, hole])

        XCTAssertTrue(area.contains(.init(latitude: 45.0, longitude: 5.005)))
        XCTAssertFalse(area.contains(.init(latitude: 45.0, longitude: 5.015)))
    }

    // MARK: - Replis (limites indisponibles)

    /// Un village a un panneau à chaque bout : seul le PREMIER rencontré dans le sens de parcours
    /// compte. Panneau sans nom : nom du lieu le plus proche. Panneau loin de la trace : ignoré.
    func testCitySignFallbackKeepsTheFirstSignOfEachVillageInTravelOrder() {
        let route = track(through: [4.995, 5.035])
        let data = RoadbookLocalityOverpassData(
            areas: [],
            citySigns: [
                RoadbookLocalityNode(coordinate: .init(latitude: 45.0001, longitude: 5.012), name: "Villebis"),
                RoadbookLocalityNode(coordinate: .init(latitude: 45.0001, longitude: 5.002), name: "Villebis"),
                RoadbookLocalityNode(coordinate: .init(latitude: 45.0001, longitude: 5.025), name: nil),
                RoadbookLocalityNode(coordinate: .init(latitude: 45.01, longitude: 5.030), name: "Trop loin"),
            ],
            places: [RoadbookLocalityNode(coordinate: .init(latitude: 45.002, longitude: 5.027), name: "Hameau")]
        )

        let forward = RoadbookLocalityDetector.checkpoints(from: data, points: route.points)
        XCTAssertEqual(forward.map(\.name), ["Villebis", "Hameau"])
        XCTAssertEqual(forward.map(\.source), [.citySign, .citySign])
        XCTAssertEqual(forward[0].cumulativeDistanceMeters, meters(from: 4.995, to: 5.002), accuracy: 2, "premier panneau rencontré (5,002)")

        let backward = RoadbookLocalityDetector.checkpoints(from: data, points: route.reordered(using: TrackRideSettings(isReversed: true)).points)
        XCTAssertEqual(backward.map(\.name), ["Hameau", "Villebis"])
        XCTAssertEqual(backward[1].cumulativeDistanceMeters, meters(from: 5.012, to: 5.035), accuracy: 2, "en sens inverse, le premier panneau rencontré est l'autre (5,012)")
    }

    func testPlaceFallbackUsesTheNearestPointOfTheTrack() {
        let route = track(through: [4.995, 5.035])
        let data = RoadbookLocalityOverpassData(areas: [], citySigns: [], places: [
            RoadbookLocalityNode(coordinate: .init(latitude: 45.003, longitude: 5.015), name: "Proche"),
            RoadbookLocalityNode(coordinate: .init(latitude: 45.05, longitude: 5.015), name: "Loin"),
        ])

        let result = RoadbookLocalityDetector.checkpoints(from: data, points: route.points)

        XCTAssertEqual(result.map(\.name), ["Proche"])
        XCTAssertEqual(result[0].source, .place)
        XCTAssertEqual(result[0].coordinate.latitude, 45.0, accuracy: 1e-6, "checkpoint SUR la trace, pas au centre du village")
    }

    // MARK: - Overpass

    func testOverpassResponseIsParsedIntoCommunesSignsAndPlaces() throws {
        let json = """
        {"elements":[
          {"type":"relation","id":1,"tags":{"boundary":"administrative","admin_level":"8","name":"Wahlbach"},
           "members":[
             {"type":"way","ref":10,"role":"outer","geometry":[{"lat":45.0,"lon":5.0},{"lat":45.0,"lon":5.01},{"lat":45.01,"lon":5.01}]},
             {"type":"way","ref":11,"role":"outer","geometry":[{"lat":45.0,"lon":5.0},{"lat":45.01,"lon":5.0},{"lat":45.01,"lon":5.01}]},
             {"type":"node","ref":12,"role":"admin_centre","lat":45.005,"lon":5.005}
           ]},
          {"type":"relation","id":2,"tags":{"boundary":"administrative","admin_level":"8"},"members":[]},
          {"type":"node","id":3,"lat":45.0,"lon":5.02,"tags":{"traffic_sign":"city_limit","name":"Sierentz"}},
          {"type":"node","id":4,"lat":45.0,"lon":5.03,"tags":{"place":"village","name":"Uffheim"}}
        ]}
        """

        let data = try XCTUnwrap(RoadbookLocalityService.parse(Data(json.utf8)))

        XCTAssertEqual(data.areas.map(\.name), ["Wahlbach"], "commune sans nom écartée")
        XCTAssertTrue(data.areas[0].contains(.init(latitude: 45.005, longitude: 5.005)))
        XCTAssertEqual(data.citySigns.map(\.name), ["Sierentz"])
        XCTAssertEqual(data.places.map(\.name), ["Uffheim"])
    }

    func testANonOverpassResponseIsRejected() {
        XCTAssertNil(RoadbookLocalityService.parse(Data("<html>504 Gateway Timeout</html>".utf8)))
    }

    func testTheQueryAsksForCommuneBoundariesAndBothFallbacksAlongTheSampledTrack() throws {
        let query = try XCTUnwrap(RoadbookLocalityService.query(for: track(through: [4.995, 5.035]).points))

        XCTAssertTrue(query.contains(#"["boundary"="administrative"]["admin_level"="8"]"#))
        XCTAssertTrue(query.contains("out geom;"))
        XCTAssertTrue(query.contains(#"["traffic_sign"="city_limit"]"#))
        XCTAssertTrue(query.contains(#"["place"~"^(village|town|city)$"]"#))
        XCTAssertTrue(query.contains("around:250,45.000000,4.995000"), "polyligne échantillonnée à partir du départ, rayon = pas d'échantillonnage")
    }

    func testAVeryLongTrackIsSampledWithinThePolylineCap() throws {
        let long = track(through: [0.0, 5.0])
        let query = try XCTUnwrap(RoadbookLocalityService.query(for: long.points))
        let boundaryLine = try XCTUnwrap(query.split(separator: "\n").first { $0.contains("boundary") })
        let coordinateCount = boundaryLine.split(separator: ",").count / 2

        XCTAssertLessThanOrEqual(coordinateCount, RoadBookConstants.localityQueryMaxPolylinePoints + 1)
    }

    // MARK: - Cache par trace ET par sens

    func testTheCacheIsKeptPerTrackAndPerDirection() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let forward = track(through: [4.995, 5.035])
        let reversed = forward.reordered(using: TrackRideSettings(isReversed: true))
        let cache = RoadbookLocalityCache(directoryOverride: directory)

        cache.store(checkpoints(forward, areas: threeCommunes), traversalKey: forward.traversalKey)

        XCTAssertNil(cache.checkpoints(for: reversed), "l'autre sens a ses propres entrées, jamais celles-ci")
        XCTAssertEqual(RoadbookLocalityCache(directoryOverride: directory).checkpoints(for: forward)?.map(\.name), ["A", "B", "C"], "relu par une nouvelle instance (relancement de l'app)")
    }

    func testAnEmptyResultIsCachedSoItIsNeverRequestedAgain() {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let route = track(through: [5.001, 5.009])
        let cache = RoadbookLocalityCache(directoryOverride: directory)

        cache.store([], traversalKey: route.traversalKey)

        XCTAssertEqual(cache.checkpoints(for: route)?.count, 0)
    }

    // MARK: - Lignes du Road Book

    func testEntriesInterleaveManeuversAndCheckpointsByProgressKeepingManeuverNumbering() {
        func maneuver(at meters: Double, index: Int) -> RoadbookManeuver {
            let checkpoint = Checkpoint(coordinate: .init(latitude: 45, longitude: 5), turnAngleDegrees: 60, direction: .left, tier: .marked, sequenceIndex: index + 1, sourcePointIndex: index, trackCumulativeDistanceMeters: meters)
            return RoadbookManeuver(checkpoint: checkpoint, partialDistanceMeters: meters, cumulativeDistanceMeters: meters, headingDegrees: 0)
        }
        let localities = [
            RoadbookLocalityCheckpoint(name: "A", coordinate: .init(latitude: 45, longitude: 5), cumulativeDistanceMeters: 50, source: .boundary),
            RoadbookLocalityCheckpoint(name: "B", coordinate: .init(latitude: 45, longitude: 5), cumulativeDistanceMeters: 700, source: .boundary),
        ]

        let entries = RoadbookEntry.merge(maneuvers: [maneuver(at: 300, index: 0), maneuver(at: 900, index: 1)], localities: localities)

        let description: [String] = entries.map {
            switch $0 {
            case .maneuver(_, let index): return "m\(index)"
            case .locality(let locality): return locality.name
            }
        }
        XCTAssertEqual(description, ["A", "m0", "B", "m1"])
    }

    func testThePDFIncludesCheckpointRowsWithoutCrashing() {
        let checkpoint = Checkpoint(coordinate: .init(latitude: 45, longitude: 5), turnAngleDegrees: 60, direction: .left, tier: .marked, sequenceIndex: 1, sourcePointIndex: 1, trackCumulativeDistanceMeters: 300)
        let maneuvers = [RoadbookManeuver(checkpoint: checkpoint, partialDistanceMeters: 300, cumulativeDistanceMeters: 300, headingDegrees: 90)]
        let localities = [RoadbookLocalityCheckpoint(name: "Kœtzingue", coordinate: .init(latitude: 45, longitude: 5), cumulativeDistanceMeters: 120, source: .boundary)]
        var withoutNote = RoadbookPDFOptions()
        withoutNote.showNoteColumn = false
        withoutNote.showCumulativeDistance = false

        for options in [RoadbookPDFOptions(), withoutNote] {
            let data = RoadbookPDFExporter.generate(trackName: "Communes", maneuvers: maneuvers, localities: localities, options: options)
            XCTAssertGreaterThan(data.count, 1000)
        }
    }
}
