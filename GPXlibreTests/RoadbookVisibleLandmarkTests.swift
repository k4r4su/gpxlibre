import XCTest
import CoreLocation
@testable import GPXlibre

/// Itération "repères du Road Book = uniquement ce que le conducteur voit" — classification,
/// visibilité (rayon par catégorie, sens des panneaux), côté, priorité et densité. Aucun réseau :
/// réponses Overpass et candidats synthétiques. Trace de test : plein nord, un point tous les 20 m.
@MainActor
final class RoadbookVisibleLandmarkTests: XCTestCase {
    private let start = CLLocationCoordinate2D(latitude: 45.0, longitude: 5.0)

    private func destination(from coordinate: CLLocationCoordinate2D, bearingDegrees: Double, distanceMeters: Double) -> CLLocationCoordinate2D {
        let earthRadius = 6_371_000.0
        let bearing = bearingDegrees * .pi / 180
        let lat1 = coordinate.latitude * .pi / 180
        let lon1 = coordinate.longitude * .pi / 180
        let angularDistance = distanceMeters / earthRadius
        let lat2 = asin(sin(lat1) * cos(angularDistance) + cos(lat1) * sin(angularDistance) * cos(bearing))
        let lon2 = lon1 + atan2(sin(bearing) * sin(angularDistance) * cos(lat1), cos(angularDistance) - sin(lat1) * sin(lat2))
        return CLLocationCoordinate2D(latitude: lat2 * 180 / .pi, longitude: lon2 * 180 / .pi)
    }

    private func northTrack(lengthMeters: Double = 2000) -> GPXTrack {
        let points = stride(from: 0.0, through: lengthMeters, by: 20).map { meters -> GPXPoint in
            let c = destination(from: start, bearingDegrees: 0, distanceMeters: meters)
            return GPXPoint(latitude: c.latitude, longitude: c.longitude)
        }
        return GPXTrack(id: UUID(), name: "Nord", fileName: "n.gpx", importDate: Date(), points: points, waypoints: [])
    }

    /// Point à `along` m de la trace, décalé latéralement (positif = à droite en roulant vers le nord).
    private func place(along: Double, lateral: Double) -> CLLocationCoordinate2D {
        destination(from: destination(from: start, bearingDegrees: 0, distanceMeters: along), bearingDegrees: lateral >= 0 ? 90 : 270, distanceMeters: abs(lateral))
    }

    private func candidate(_ tags: [String: String], at coordinate: CLLocationCoordinate2D, orientation: RoadbookLandmarkCandidate.Orientation? = nil) throws -> RoadbookLandmarkCandidate {
        let classified = try XCTUnwrap(RoadbookLandmark.classify(tags))
        return RoadbookLandmarkCandidate(category: classified.category, label: classified.label, coordinate: coordinate, orientation: orientation)
    }

    private func select(_ candidates: [RoadbookLandmarkCandidate], track: GPXTrack? = nil, maneuvers: [RoadbookManeuver] = []) -> RoadbookLandmarkSelection {
        RoadbookLandmarkSelector.select(RoadbookLandmarkData(candidates: candidates), points: (track ?? northTrack()).points, maneuvers: maneuvers, urbanEntryFallbackEnabled: false)
    }

    private func maneuver(atMeters meters: Double) -> RoadbookManeuver {
        let checkpoint = Checkpoint(coordinate: place(along: meters, lateral: 0), turnAngleDegrees: 90, direction: .right, tier: .hard, sequenceIndex: 1, sourcePointIndex: Int(meters / 20), trackCumulativeDistanceMeters: meters)
        return RoadbookManeuver(checkpoint: checkpoint, partialDistanceMeters: meters, cumulativeDistanceMeters: meters, headingDegrees: 90)
    }

    // MARK: - Tests demandés par la fiche

    /// Trace traversant 3 limites de commune, sans panneau ni bâtiment : 0 repère — les limites
    /// administratives ne sont plus jamais des repères (non classées, jamais retenues).
    func testCrossingThreeCommuneBoundariesWithoutSignOrBuildingGivesNoLandmark() throws {
        let json = """
        {"elements":[
          {"type":"relation","id":1,"center":{"lat":45.002,"lon":5.0},"tags":{"boundary":"administrative","admin_level":"8","name":"A"}},
          {"type":"relation","id":2,"center":{"lat":45.006,"lon":5.0},"tags":{"boundary":"administrative","admin_level":"8","name":"B"}},
          {"type":"relation","id":3,"center":{"lat":45.010,"lon":5.0},"tags":{"boundary":"administrative","admin_level":"8","name":"C"}},
          {"type":"node","id":4,"lat":45.004,"lon":5.0,"tags":{"place":"village","name":"B"}}
        ]}
        """
        let data = try XCTUnwrap(RoadbookLandmarkOverpassService.parse(Data(json.utf8)))

        XCTAssertTrue(data.candidates.isEmpty)
        XCTAssertEqual(select(data.candidates), .empty)
    }

    func testACityLimitSignOnTheRoadGivesOneLandmarkWithItsName() throws {
        let sign = try candidate(["traffic_sign": "city_limit", "name": "Kœtzingue"], at: place(along: 700, lateral: 6))

        let result = select([sign])

        let landmark = try XCTUnwrap(result.standalone.first)
        XCTAssertEqual(result.standalone.count, 1)
        XCTAssertEqual(landmark.info.category, .citySign)
        XCTAssertEqual(landmark.info.label, "Kœtzingue")
        XCTAssertEqual(landmark.info.side, .right)
        XCTAssertEqual(landmark.cumulativeDistanceMeters, 700, accuracy: 3)
    }

    func testACityLimitSignWithoutNameIsLabelledGenerically() throws {
        let sign = try candidate(["traffic_sign": "city_limit"], at: place(along: 700, lateral: -6))
        let landmark = try XCTUnwrap(select([sign]).standalone.first)

        XCTAssertEqual(landmark.info.label, "Entrée d'agglomération")
        XCTAssertEqual(landmark.info.side, .left)
    }

    /// Panneau vu de dos : `backward` résolu sur sa route porteuse (orientée nord), le panneau
    /// s'adresse à la circulation vers le sud — le pilote qui roule vers le nord ne le voit pas.
    func testASignSeenFromBehindIsIgnored() throws {
        let backward = try candidate(["traffic_sign": "city_limit", "name": "X"], at: place(along: 700, lateral: 5), orientation: .appliesToTravelBearing(180))
        let facingNorth = try candidate(["traffic_sign": "city_limit", "name": "Y"], at: place(along: 1200, lateral: 5), orientation: .faces(0))

        XCTAssertTrue(select([backward, facingNorth]).standalone.isEmpty)
    }

    func testASignFacingTheRiderIsKept() throws {
        let forward = try candidate(["traffic_sign": "city_limit", "name": "X"], at: place(along: 700, lateral: 5), orientation: .appliesToTravelBearing(0))
        let facingSouth = try candidate(["traffic_sign": "city_limit", "name": "Y"], at: place(along: 1500, lateral: 5), orientation: .faces(180))

        // Un virage entre les deux : deux tronçons, sinon un seul repère serait gardé (densité).
        XCTAssertEqual(select([forward, facingSouth], maneuvers: [maneuver(atMeters: 1000)]).standalone.map(\.info.label), ["X", "Y"])
    }

    func testASignTooFarFromTheRoadIsIgnored() throws {
        let far = try candidate(["traffic_sign": "city_limit", "name": "Loin"], at: place(along: 700, lateral: 80))
        XCTAssertTrue(select([far]).standalone.isEmpty)
    }

    func testAChurch15MetersOnTheRightIsOneLandmarkOnTheRight() throws {
        let church = try candidate(["amenity": "place_of_worship", "religion": "christian", "name": "Église Saint-Martin"], at: place(along: 900, lateral: 15))
        let landmark = try XCTUnwrap(select([church]).standalone.first)

        XCTAssertEqual(landmark.info.category, .church)
        XCTAssertEqual(landmark.info.side, .right)
        XCTAssertEqual(landmark.info.displayLabel, "Église Saint-Martin à droite")
    }

    func testAChurch300MetersAwayIsIgnored() throws {
        let church = try candidate(["amenity": "place_of_worship", "name": "Église"], at: place(along: 900, lateral: 300))
        XCTAssertTrue(select([church]).standalone.isEmpty)
    }

    /// Plusieurs candidats rapprochés : un seul repère, selon la priorité fixe (panneau > marquage
    /// au sol > bâtiment ; entrée d'agglomération d'abord parmi les panneaux).
    func testSeveralCloseCandidatesGiveOneLandmarkByPriority() throws {
        let candidates = [
            try candidate(["amenity": "place_of_worship", "name": "Église"], at: place(along: 800, lateral: 20)),
            try candidate(["highway": "crossing", "crossing": "marked"], at: place(along: 820, lateral: 0)),
            try candidate(["highway": "stop"], at: place(along: 840, lateral: 5)),
            try candidate(["traffic_sign": "city_limit", "name": "Village"], at: place(along: 860, lateral: 5)),
        ]
        let result = select(candidates)

        XCTAssertEqual(result.standalone.count, 1)
        XCTAssertEqual(try XCTUnwrap(result.standalone.first).info.category, .citySign)
    }

    /// Catégories non autorisées : ignorées (limite administrative, commerce lambda, arbre, parc,
    /// lieu habité, restaurant, passage piéton non marqué, aménagement autre qu'un ralentisseur).
    func testDisallowedCategoriesAreIgnored() {
        let disallowed: [[String: String]] = [
            ["boundary": "administrative", "admin_level": "8", "name": "Commune"],
            ["shop": "bakery", "name": "Boulangerie"],
            ["amenity": "restaurant", "name": "Chez Paul"],
            ["natural": "tree"],
            ["leisure": "park"],
            ["place": "village", "name": "Hameau"],
            ["building": "yes"],
            ["highway": "crossing", "crossing": "unmarked"],
            ["highway": "crossing"],
            ["traffic_calming": "chicane"],
            ["traffic_sign": "city_limit", "city_limit": "end", "name": "Sortie"],
        ]
        for tags in disallowed {
            XCTAssertNil(RoadbookLandmark.classify(tags), "\(tags)")
        }
    }

    func testAllowedCategoriesAreClassifiedWithASpeakingLabel() throws {
        let expectations: [([String: String], RoadbookLandmarkCategory, String)] = [
            (["highway": "give_way"], .giveWaySign, "Cédez-le-passage"),
            (["highway": "traffic_signals"], .trafficSignals, "Feux tricolores"),
            (["railway": "level_crossing"], .levelCrossing, "Passage à niveau"),
            (["traffic_calming": "table"], .speedBump, "Ralentisseur"),
            (["highway": "secondary", "bridge": "yes", "bridge:name": "Pont de la Largue"], .bridge, "Pont de la Largue"),
            (["highway": "primary", "tunnel": "yes"], .tunnel, "Tunnel"),
            (["building": "chapel"], .church, "Chapelle"),
            (["man_made": "bell_tower"], .church, "Clocher"),
            (["amenity": "townhall", "name": "Mairie de Wahlbach"], .townHall, "Mairie de Wahlbach"),
            (["amenity": "fuel", "brand": "Total"], .fuel, "Total"),
            (["man_made": "water_tower"], .waterTower, "Château d'eau"),
            (["man_made": "windmill"], .mill, "Moulin"),
            (["historic": "wayside_cross"], .waysideCross, "Calvaire"),
            (["historic": "castle"], .remarkableStructure, "Château"),
        ]
        for (tags, category, label) in expectations {
            let classified = try XCTUnwrap(RoadbookLandmark.classify(tags), "\(tags)")
            XCTAssertEqual(classified.category, category, "\(tags)")
            XCTAssertEqual(classified.label, label, "\(tags)")
        }
    }

    /// Overpass indisponible / réponse d'erreur : pas de crash, Road Book sans repères.
    func testAnUnavailableOverpassNeverCrashesAndGivesNoLandmark() {
        XCTAssertNil(RoadbookLandmarkOverpassService.parse(Data("<html>504 Gateway Timeout</html>".utf8)))
        XCTAssertNil(RoadbookLandmarkOverpassService.parse(Data()))
        XCTAssertEqual(select([]), .empty)
        XCTAssertEqual(RoadbookLandmarkSelector.select(RoadbookLandmarkData(candidates: []), points: [], maneuvers: []), .empty)
    }

    // MARK: - Densité, carrefours

    /// Un repère au carrefour identifie CE virage : affiché avec la manœuvre, jamais en ligne.
    func testALandmarkAtAJunctionIsAttachedToTheManeuverNotAStandaloneRow() throws {
        let turn = maneuver(atMeters: 1000)
        let church = try candidate(["amenity": "place_of_worship", "name": "Église"], at: place(along: 1020, lateral: 25))
        let result = select([church], maneuvers: [turn])

        XCTAssertTrue(result.standalone.isEmpty)
        XCTAssertEqual(result.attached[turn.id]?.category, .church)
        XCTAssertEqual(result.attached[turn.id]?.side, .right)
    }

    func testAtMostOneStandaloneLandmarkPerSegmentBetweenTwoTurns() throws {
        let candidates = [
            try candidate(["amenity": "fuel", "name": "Station"], at: place(along: 200, lateral: 20)),
            try candidate(["traffic_sign": "city_limit", "name": "Village"], at: place(along: 500, lateral: 5)),
            try candidate(["man_made": "water_tower"], at: place(along: 800, lateral: 50)),
        ]
        let result = select(candidates, maneuvers: [maneuver(atMeters: 1000)])

        XCTAssertEqual(result.standalone.count, RoadBookConstants.landmarkMaxPerSegment)
        XCTAssertEqual(try XCTUnwrap(result.standalone.first).info.category, .citySign)
    }

    /// Stop/cédez-le-passage/passage piéton de la rue qui DÉBOUCHE sur celle du pilote : à
    /// quelques mètres de la trace, mais sa chaussée est perpendiculaire — il ne le concerne pas.
    /// Validé sur une trace réelle : sans ce filtre, ils ressortaient tout au long des lignes droites.
    func testASignOrCrossingOnASideRoadIsIgnored() throws {
        let sideStop = try candidate(["highway": "stop"], at: place(along: 700, lateral: 12), orientation: nil)
        let sideStopOnRoad = RoadbookLandmarkCandidate(category: sideStop.category, label: sideStop.label, coordinate: sideStop.coordinate, roadAxes: [90])
        let sideCrossing = RoadbookLandmarkCandidate(category: .pedestrianCrossing, label: "Passage piéton", coordinate: place(along: 1500, lateral: 8), roadAxes: [270, 0])

        XCTAssertTrue(select([sideStopOnRoad]).standalone.isEmpty, "stop sur une route perpendiculaire")
        XCTAssertEqual(select([sideCrossing]).standalone.count, 1, "passage piéton porté AUSSI par la route du pilote (axe 0°) : gardé")
    }

    func testAStopOnTheRidersOwnRoadIsKeptWithoutASide() throws {
        let ownStop = RoadbookLandmarkCandidate(category: .stopSign, label: "Stop", coordinate: place(along: 700, lateral: 6), roadAxes: [180])
        let landmark = try XCTUnwrap(select([ownStop]).standalone.first)

        XCTAssertEqual(landmark.info.category, .stopSign)
        XCTAssertNil(landmark.info.side, "nœud de la route elle-même : pas de côté")
    }

    func testSomethingAcrossTheRoadHasNoSide() throws {
        let bump = RoadbookLandmarkCandidate(category: .speedBump, label: "Ralentisseur", coordinate: place(along: 700, lateral: 7))
        XCTAssertNil(try XCTUnwrap(select([bump]).standalone.first).info.side)
    }

    func testABridgeLabelIsNeverTheRoadName() throws {
        XCTAssertEqual(try XCTUnwrap(RoadbookLandmark.classify(["highway": "primary", "bridge": "yes", "name": "Route de Kembs"])).label, "Pont")
    }

    func testRoundaboutsAreNeverLandmarks() {
        XCTAssertNil(RoadbookLandmark.classify(["junction": "roundabout"]))
        XCTAssertNil(RoadbookLandmark.classify(["highway": "mini_roundabout"]))
    }

    // MARK: - Overpass : sens résolu sur la route porteuse

    func testForwardBackwardIsResolvedOnTheCarryingWay() throws {
        let json = """
        {"elements":[
          {"type":"node","id":10,"lat":45.005,"lon":5.0,"tags":{"traffic_sign":"city_limit","name":"Nord","direction":"forward"}},
          {"type":"node","id":11,"lat":45.006,"lon":5.0,"tags":{"traffic_sign":"city_limit","name":"Sud","direction":"backward"}},
          {"type":"node","id":12,"lat":45.007,"lon":5.0,"tags":{"traffic_sign":"city_limit","name":"Face","direction":"SW"}},
          {"type":"way","id":20,"nodes":[9,10,11,12,13],"tags":{"highway":"secondary"},
           "geometry":[{"lat":45.004,"lon":5.0},{"lat":45.005,"lon":5.0},{"lat":45.006,"lon":5.0},{"lat":45.007,"lon":5.0},{"lat":45.008,"lon":5.0}]}
        ]}
        """
        let data = try XCTUnwrap(RoadbookLandmarkOverpassService.parse(Data(json.utf8)))
        let byName = Dictionary(uniqueKeysWithValues: data.candidates.map { ($0.label, $0.orientation) })

        XCTAssertEqual(data.candidates.count, 3, "la route porteuse n'est pas un candidat")
        guard case .appliesToTravelBearing(let north)?? = byName["Nord"], case .appliesToTravelBearing(let south)?? = byName["Sud"], case .faces(let facing)?? = byName["Face"] else {
            return XCTFail("orientations non résolues : \(byName)")
        }
        XCTAssertEqual(north, 0, accuracy: 1)
        XCTAssertEqual(south, 180, accuracy: 1)
        XCTAssertEqual(facing, 225, accuracy: 0.1)
    }

    func testTheQueryAsksOnlyForAllowedCategories() throws {
        let query = try XCTUnwrap(RoadbookLandmarkOverpassService.query(for: northTrack().points, includeUrbanWays: false))

        XCTAssertFalse(query.contains("boundary"), "plus aucune limite administrative")
        XCTAssertFalse(query.contains(#"["place""#), "plus aucun lieu habité")
        XCTAssertTrue(query.contains(#"["traffic_sign"~"city_limit|FR:EB10"]"#) || query.contains(#"["traffic_sign"~"FR:EB10|city_limit"]"#))
        XCTAssertTrue(query.contains("way(bn.onroad)"), "chaussées porteuses des éléments posés sur la route (sens, alignement)")
        XCTAssertFalse(query.contains("maxspeed"), "repli zone urbaine désactivé par défaut")
    }

    // MARK: - Repli "entrée de localité" par limitation 50 km/h (désactivé par défaut)

    func testTheUrbanEntryFallbackIsOffByDefaultAndOnlyAddsAnEntryWhenEnabled() {
        XCTAssertFalse(RoadBookConstants.landmarkUrbanEntryFallbackEnabled)
        let urbanWay = [place(along: 1000, lateral: 0), place(along: 2000, lateral: 0)].map(CLLocationCoordinate2DCodable.init)
        let data = RoadbookLandmarkData(candidates: [], urbanWays: [urbanWay])
        let points = northTrack().points

        XCTAssertTrue(RoadbookLandmarkSelector.select(data, points: points, maneuvers: [], urbanEntryFallbackEnabled: false).standalone.isEmpty)
        let enabled = RoadbookLandmarkSelector.select(data, points: points, maneuvers: [], urbanEntryFallbackEnabled: true).standalone
        XCTAssertEqual(enabled.count, 1)
        XCTAssertEqual(enabled.first?.info.label, "Entrée d'agglomération")
        XCTAssertEqual(enabled.first?.cumulativeDistanceMeters ?? 0, 1000, accuracy: 25)
    }

    // MARK: - Cache, lignes, PDF

    func testTheCandidateCacheSurvivesARelaunch() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let trackID = UUID()
        let sign = try candidate(["traffic_sign": "city_limit", "name": "Kœtzingue"], at: place(along: 700, lateral: 6), orientation: .faces(180))

        RoadbookLandmarkDataCache(directoryOverride: directory).store(RoadbookLandmarkData(candidates: [sign]), for: trackID)

        XCTAssertEqual(RoadbookLandmarkDataCache(directoryOverride: directory).data(for: trackID)?.candidates, [sign])
        XCTAssertNil(RoadbookLandmarkDataCache(directoryOverride: directory).data(for: UUID()))
    }

    func testEntriesInterleaveManeuversAndLandmarksKeepingManeuverNumbering() {
        let info = RoadbookLandmarkInfo(category: .citySign, label: "A")
        let entries = RoadbookEntry.merge(
            maneuvers: [maneuver(atMeters: 300), maneuver(atMeters: 900)],
            landmarks: [
                RoadbookLandmarkCheckpoint(info: info, latitude: 45, longitude: 5, cumulativeDistanceMeters: 50),
                RoadbookLandmarkCheckpoint(info: info, latitude: 45, longitude: 5, cumulativeDistanceMeters: 700),
            ]
        )
        let description: [String] = entries.map {
            switch $0 {
            case .maneuver(_, let index): return "m\(index)"
            case .landmark(let landmark): return "l\(Int(landmark.cumulativeDistanceMeters))"
            }
        }
        XCTAssertEqual(description, ["l50", "m0", "l700", "m1"])
    }

    func testThePDFIncludesLandmarkRowsWithoutCrashing() {
        let landmarks = [
            RoadbookLandmarkCheckpoint(info: RoadbookLandmarkInfo(category: .citySign, label: "Kœtzingue", side: .right), latitude: 45, longitude: 5, cumulativeDistanceMeters: 120),
            RoadbookLandmarkCheckpoint(info: RoadbookLandmarkInfo(category: .church, label: "Église", side: .left), latitude: 45, longitude: 5, cumulativeDistanceMeters: 600),
        ]
        var compact = RoadbookPDFOptions()
        compact.showNoteColumn = false
        compact.showCumulativeDistance = false

        for options in [RoadbookPDFOptions(), compact] {
            let data = RoadbookPDFExporter.generate(trackName: "Repères", maneuvers: [maneuver(atMeters: 300)], landmarkCheckpoints: landmarks, options: options)
            XCTAssertGreaterThan(data.count, 1000)
        }
    }
}
