import XCTest
import CoreLocation
@testable import GPXlibre

/// Itérations it27/it28 "repères du Road Book = uniquement ce que le conducteur voit" —
/// catalogue, visibilité (rayon par catégorie, sens des panneaux), côté, priorité et densité,
/// services. Chargement/progression/complément par catégorie : `RoadbookLandmarkLoaderTests`. Aucun réseau :
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
        RoadbookLandmarkSelector.select(RoadbookLandmarkData(candidates: candidates), points: (track ?? northTrack()).points, maneuvers: maneuvers, cityEntryFallbackEnabled: false)
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

    /// Plusieurs candidats rapprochés : un seul repère, selon la priorité fixe (panneau >
    /// infrastructure > bâtiment ; entrée d'agglomération d'abord parmi les panneaux).
    func testSeveralCloseCandidatesGiveOneLandmarkByPriority() throws {
        let candidates = [
            try candidate(["amenity": "place_of_worship", "name": "Église"], at: place(along: 800, lateral: 20)),
            try candidate(["traffic_calming": "hump"], at: place(along: 820, lateral: 0)),
            try candidate(["highway": "stop"], at: place(along: 840, lateral: 5)),
            try candidate(["traffic_sign": "city_limit", "name": "Village"], at: place(along: 860, lateral: 5)),
        ]
        let result = select(candidates)

        XCTAssertEqual(result.standalone.count, 1)
        XCTAssertEqual(try XCTUnwrap(result.standalone.first).info.category, .citySign)
    }

    /// Hors catalogue : ignoré (limite administrative, commerce lambda, arbre, parc, lieu habité,
    /// passage piéton — même marqué, retiré du catalogue en it28 —, aménagement autre qu'un
    /// ralentisseur, panneau de sortie d'agglomération).
    func testDisallowedCategoriesAreIgnored() {
        let disallowed: [[String: String]] = [
            ["boundary": "administrative", "admin_level": "8", "name": "Commune"],
            ["shop": "clothes", "name": "Boutique"],
            ["amenity": "bank", "name": "Banque"],
            ["natural": "tree"],
            ["leisure": "park"],
            ["place": "village", "name": "Hameau"],
            ["building": "yes"],
            ["highway": "crossing", "crossing": "unmarked"],
            ["highway": "crossing", "crossing": "marked"],
            ["highway": "crossing", "crossing": "zebra"],
            ["highway": "crossing", "crossing_ref": "zebra"],
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
            (["historic": "castle"], .castle, "Château"),
            (["amenity": "charging_station", "operator": "Ionity"], .chargingStation, "Ionity"),
            (["amenity": "charging_station"], .chargingStation, "Borne de recharge"),
            (["historic": "wayside_shrine"], .waysideCross, "Oratoire"),
            (["shop": "bakery", "name": "Au bon pain"], .bakery, "Au bon pain"),
            (["man_made": "tower", "tower:type": "communication"], .antenna, "Antenne"),
            (["man_made": "tower"], .tower, "Tour"),
            (["power": "generator", "generator:source": "wind"], .windTurbine, "Éolienne"),
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
            try candidate(["amenity": "townhall"], at: place(along: 200, lateral: 20)),
            try candidate(["traffic_sign": "city_limit", "name": "Village"], at: place(along: 500, lateral: 5)),
            try candidate(["man_made": "water_tower"], at: place(along: 800, lateral: 50)),
        ]
        let result = select(candidates, maneuvers: [maneuver(atMeters: 1000)])

        XCTAssertEqual(result.standalone.count, RoadBookConstants.landmarkMaxPerSegment)
        XCTAssertEqual(try XCTUnwrap(result.standalone.first).info.category, .citySign)
    }

    /// Stop/cédez-le-passage/ralentisseur de la rue qui DÉBOUCHE sur celle du pilote : à
    /// quelques mètres de la trace, mais sa chaussée est perpendiculaire — il ne le concerne pas.
    /// Validé sur une trace réelle : sans ce filtre, ils ressortaient tout au long des lignes droites.
    func testASignOrCrossingOnASideRoadIsIgnored() throws {
        let sideStop = try candidate(["highway": "stop"], at: place(along: 700, lateral: 12), orientation: nil)
        let sideStopOnRoad = RoadbookLandmarkCandidate(category: sideStop.category, label: sideStop.label, coordinate: sideStop.coordinate, roadAxes: [90])
        let sharedBump = RoadbookLandmarkCandidate(category: .speedBump, label: "Ralentisseur", coordinate: place(along: 1500, lateral: 8), roadAxes: [270, 0])

        XCTAssertTrue(select([sideStopOnRoad]).standalone.isEmpty, "stop sur une route perpendiculaire")
        XCTAssertEqual(select([sharedBump]).standalone.count, 1, "ralentisseur porté AUSSI par la route du pilote (axe 0°) : gardé")
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
        let query = try XCTUnwrap(RoadbookLandmarkOverpassService.query(for: northTrack().points, categories: RoadBookConstants.landmarkDefaultEnabledCategories))

        XCTAssertFalse(query.contains("boundary"), "plus aucune limite administrative")
        // Les localités (`place`) ne sont demandées que pour NOMMER les entrées calculées (it29),
        // jamais comme repères en soi — voir `RoadbookCityEntryTests`.
        XCTAssertTrue(query.contains(#"node["traffic_sign"~"city_limit|FR:EB10|DE:310",i]"#))
        XCTAssertTrue(query.contains("way(bn.onroad)"), "chaussées porteuses des éléments posés sur la route (sens, alignement)")
        XCTAssertFalse(query.contains("maxspeed"), "plus de repli par limitation de vitesse")
        XCTAssertFalse(query.contains(#""crossing""#), "plus jamais de passage piéton")
    }

    // Repli "Entrée de <localité>" (it29) : voir `RoadbookCityEntryTests`.

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

    // MARK: - Jalon it28 : catalogue, services, catégories actives

    /// Station-service et borne de recharge proches de la trace : présentes PAR DÉFAUT, avec côté
    /// et distance à la trace, et jamais écartées par la densité des repères de repérage.
    func testFuelAndChargingStationsNearTheTrackArePresentByDefault() throws {
        let candidates = [
            try candidate(["amenity": "fuel", "brand": "Total"], at: place(along: 600, lateral: 120)),
            try candidate(["amenity": "charging_station"], at: place(along: 650, lateral: -12)),
            try candidate(["traffic_sign": "city_limit", "name": "Village"], at: place(along: 620, lateral: 5)),
            try candidate(["amenity": "place_of_worship", "name": "Église"], at: place(along: 900, lateral: 20)),
        ]
        let result = RoadbookLandmarkSelector.select(
            RoadbookLandmarkData(candidates: candidates),
            points: northTrack().points,
            maneuvers: [],
            enabledCategories: RoadBookConstants.landmarkDefaultEnabledCategories,
            cityEntryFallbackEnabled: false
        )
        let byCategory = Dictionary(grouping: result.standalone, by: \.info.category)

        let fuel = try XCTUnwrap(byCategory[.fuel]?.first)
        XCTAssertEqual(fuel.info.label, "Total")
        XCTAssertEqual(fuel.info.side, .right)
        XCTAssertEqual(fuel.info.lateralDistanceMeters ?? 0, 120, accuracy: 3)
        XCTAssertEqual(fuel.info.displayLabel, "Total à droite, 120 m")
        let charger = try XCTUnwrap(byCategory[.chargingStation]?.first)
        XCTAssertEqual(charger.info.side, .left)
        XCTAssertNil(charger.info.lateralDistanceMeters, "au bord de la route : pas de distance")
        // Repérage : une seule ligne sur ce tronçon (le panneau), les services en plus.
        XCTAssertEqual(byCategory[.citySign]?.count, 1)
        XCTAssertNil(byCategory[.church])
        XCTAssertEqual(result.standalone.count, 3)
    }

    func testAServiceMappedTwiceIsShownOnce() throws {
        let node = try candidate(["amenity": "fuel", "name": "Station"], at: place(along: 600, lateral: 40))
        let area = try candidate(["amenity": "fuel", "name": "Station"], at: place(along: 630, lateral: 55))
        let result = select([node, area])

        XCTAssertEqual(result.standalone.count, 1)
        XCTAssertEqual(try XCTUnwrap(result.standalone.first).info.lateralDistanceMeters ?? 0, 40, accuracy: 3)
    }

    func testServicesAreNeverAttachedToATurn() throws {
        let turn = maneuver(atMeters: 1000)
        let fuel = try candidate(["amenity": "fuel", "name": "Station"], at: place(along: 1010, lateral: 20))
        let result = select([fuel], maneuvers: [turn])

        XCTAssertNil(result.attached[turn.id])
        XCTAssertEqual(result.standalone.map(\.info.category), [.fuel])
    }

    /// Passage piéton présent dans les données : jamais affiché (ni candidat, ni demandé).
    func testAPedestrianCrossingInTheDataIsNeverShown() throws {
        let json = """
        {"elements":[
          {"type":"node","id":1,"lat":45.005,"lon":5.0,"tags":{"highway":"crossing","crossing":"marked"}},
          {"type":"node","id":2,"lat":45.006,"lon":5.0,"tags":{"highway":"crossing","crossing":"zebra","crossing_ref":"zebra"}},
          {"type":"node","id":3,"lat":45.007,"lon":5.0,"tags":{"highway":"crossing","crossing":"traffic_signals"}}
        ]}
        """
        let data = try XCTUnwrap(RoadbookLandmarkOverpassService.parse(Data(json.utf8)))

        XCTAssertTrue(data.candidates.isEmpty)
        XCTAssertFalse(RoadbookLandmarkCategory.allCases.contains { $0.rawValue.lowercased().contains("crossing") && $0 != .levelCrossing })
        let everything = try XCTUnwrap(RoadbookLandmarkOverpassService.query(for: northTrack().points, categories: Set(RoadbookLandmarkCategory.allCases)))
        XCTAssertFalse(everything.contains(#""crossing""#))
    }

    /// La requête ne contient QUE les catégories demandées.
    func testTheQueryIsBuiltWithTheActiveCategoriesOnly() throws {
        let points = northTrack().points
        let signsOnly = try XCTUnwrap(RoadbookLandmarkOverpassService.query(for: points, categories: [.stopSign, .fuel]))

        XCTAssertTrue(signsOnly.contains(#"node["highway"="stop"](around:"#))
        XCTAssertTrue(signsOnly.contains(#"nwr["amenity"="fuel"](around:"#))
        XCTAssertFalse(signsOnly.contains("place_of_worship"))
        XCTAssertFalse(signsOnly.contains("give_way"))
        XCTAssertFalse(signsOnly.contains("charging_station"))
        XCTAssertTrue(signsOnly.contains("way(bn.onroad)"), "un stop a besoin de sa route porteuse")

        let buildingsOnly = try XCTUnwrap(RoadbookLandmarkOverpassService.query(for: points, categories: [.church]))
        XCTAssertTrue(buildingsOnly.contains("place_of_worship"))
        XCTAssertFalse(buildingsOnly.contains("highway\"=\"stop"))
        XCTAssertFalse(buildingsOnly.contains("way(bn.onroad)"), "rien de posé sur la chaussée : pas de routes porteuses")

        XCTAssertNil(RoadbookLandmarkOverpassService.query(for: points, categories: []), "aucune catégorie : aucune requête")
    }

    /// Radius per category : la requête interroge chaque catégorie à son propre rayon.
    func testEachCategoryIsQueriedAtItsOwnRadius() throws {
        let query = try XCTUnwrap(RoadbookLandmarkOverpassService.query(for: northTrack().points, categories: [.stopSign, .waterTower]))
        let spacing = RoadBookConstants.landmarkQuerySampleSpacingMeters
        let stopRadius = Int((spacing + (RoadBookConstants.landmarkVisibilityRadiusMeters[.stopSign] ?? 0)).rounded(.up))
        let towerRadius = Int((spacing + (RoadBookConstants.landmarkVisibilityRadiusMeters[.waterTower] ?? 0)).rounded(.up))

        XCTAssertTrue(query.contains(#"node["highway"="stop"](around:\#(stopRadius),"#))
        XCTAssertTrue(query.contains(#"nwr["man_made"="water_tower"](around:\#(towerRadius),"#))
    }

    func testDisabledCategoriesAreFilteredOutOfTheSelection() throws {
        let bakery = try candidate(["shop": "bakery", "name": "Au bon pain"], at: place(along: 600, lateral: 10))
        let data = RoadbookLandmarkData(candidates: [bakery])
        let points = northTrack().points

        XCTAssertTrue(RoadbookLandmarkSelector.select(data, points: points, maneuvers: [], enabledCategories: RoadBookConstants.landmarkDefaultEnabledCategories).standalone.isEmpty, "Autres : désactivées par défaut")
        XCTAssertEqual(RoadbookLandmarkSelector.select(data, points: points, maneuvers: [], enabledCategories: [.bakery]).standalone.map(\.info.label), ["Au bon pain"])
    }

    /// Catalogue : chaque catégorie a un rayon, un libellé, un pictogramme et au moins un
    /// sélecteur Overpass ; défaut = panneaux, infrastructure, bâtiments, services ; "Autres" off.
    func testTheCatalogIsCompleteAndDefaultsMatchTheSpec() {
        for category in RoadbookLandmarkCategory.allCases {
            XCTAssertNotNil(RoadBookConstants.landmarkVisibilityRadiusMeters[category], "\(category) sans rayon")
            XCTAssertFalse(category.genericLabel.isEmpty)
            XCTAssertFalse(category.emoji.isEmpty)
            XCTAssertFalse(category.definition.overpassSelectors.isEmpty, "\(category) sans sélecteur")
            XCTAssertEqual(category.isEnabledByDefault, category.group != .other, "\(category)")
        }
        XCTAssertTrue(RoadbookLandmarkCategory.Group.service.categories.contains(.fuel))
        XCTAssertTrue(RoadbookLandmarkCategory.Group.service.categories.contains(.chargingStation))
        XCTAssertEqual(Set(RoadBookConstants.landmarkGroupPriority), Set(RoadbookLandmarkCategory.Group.allCases))
    }
}
