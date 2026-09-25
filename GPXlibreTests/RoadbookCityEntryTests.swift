import XCTest
import CoreLocation
@testable import GPXlibre

/// It29 — entrées d'agglomération fiables. Diagnostic sur la trace de test réelle : un seul panneau
/// `city_limit` cartographié pour 11 localités traversées ; le repli "Entrée de <localité>" (zone
/// bâtie + nœud `place`) est actif par défaut, le panneau prime quand il existe. Données
/// synthétiques (trace plein nord, zones bâties rectangulaires), aucun réseau — la trace réelle du
/// propriétaire n'est pas versionnée (données personnelles), elle a été rejouée hors dépôt.
@MainActor
final class RoadbookCityEntryTests: XCTestCase {
    private let start = CLLocationCoordinate2D(latitude: 47.5, longitude: 7.3)

    private func north(_ meters: Double, lateral: Double = 0) -> CLLocationCoordinate2D {
        let metersPerDegreeLat = 111_320.0
        let metersPerDegreeLon = metersPerDegreeLat * cos(start.latitude * .pi / 180)
        return CLLocationCoordinate2D(latitude: start.latitude + meters / metersPerDegreeLat, longitude: start.longitude + lateral / metersPerDegreeLon)
    }

    private func track(lengthMeters: Double = 8000) -> [GPXPoint] {
        stride(from: 0.0, through: lengthMeters, by: 20).map { GPXPoint(latitude: north($0).latitude, longitude: north($0).longitude) }
    }

    /// Zone bâtie rectangulaire couvrant la route de `from` à `to` (m le long de la trace).
    private func area(_ from: Double, _ to: Double, name: String? = nil, id: String? = nil) -> RoadbookBuiltUpArea {
        RoadbookBuiltUpArea(osmID: id, name: name, rings: [[north(from, lateral: -150), north(from, lateral: 150), north(to, lateral: 150), north(to, lateral: -150)]])
    }

    private func village(_ name: String, at meters: Double, lateral: Double = 200, kind: RoadbookPlace.Kind = .village) -> RoadbookPlace {
        RoadbookPlace(osmID: "node/\(name)", name: name, kind: kind, coordinate: north(meters, lateral: lateral))
    }

    private func sign(_ name: String?, at meters: Double, lateral: Double = 6, orientation: RoadbookLandmarkCandidate.Orientation? = nil) -> RoadbookLandmarkCandidate {
        RoadbookLandmarkCandidate(category: .citySign, label: name ?? RoadbookLandmarkCategory.citySign.genericLabel, coordinate: north(meters, lateral: lateral), orientation: orientation)
    }

    private func cityLines(_ data: RoadbookLandmarkData, points: [GPXPoint]? = nil) -> [String] {
        RoadbookLandmarkSelector.select(data, points: points ?? track(), maneuvers: [], enabledCategories: RoadBookConstants.landmarkDefaultEnabledCategories)
            .standalone
            .filter { $0.info.category == .citySign }
            .map { "\(Int(($0.cumulativeDistanceMeters / 10).rounded()) * 10) \($0.info.label)" }
    }

    // MARK: - Fiche

    func testTheFallbackIsOnByDefault() {
        XCTAssertTrue(RoadBookConstants.landmarkCityEntryFallbackEnabled)
    }

    /// Chaque village traversé produit une entrée avec le bon nom — même sans aucun panneau
    /// cartographié (cas réel dominant).
    func testEveryVillageCrossedGetsAnEntryWithItsName() {
        let data = RoadbookLandmarkData(
            candidates: [],
            builtUpAreas: [area(1000, 1600), area(3000, 3500), area(5000, 5600)],
            places: [village("Ferrette", at: 1300), village("Riespach", at: 3200, lateral: -400), village("Illfurth", at: 5300)]
        )

        XCTAssertEqual(cityLines(data), ["1000 Entrée de Ferrette", "3000 Entrée de Riespach", "5000 Entrée d’Illfurth"])
    }

    /// Panneau absent, polygone `place` nommé présent : entrée par le repli, nommée d'après le polygone.
    func testANamedPlacePolygonWithoutSignGivesAnEntry() {
        let data = RoadbookLandmarkData(candidates: [], builtUpAreas: [area(2000, 2600, name: "Hundsbach")], places: [])
        XCTAssertEqual(cityLines(data), ["2000 Entrée de Hundsbach"])
    }

    func testASignFacingAwayExplicitlyIsAlwaysRejected() {
        let data = RoadbookLandmarkData(candidates: [sign("Hundsbach", at: 2000, orientation: .appliesToTravelBearing(180))])
        XCTAssertEqual(cityLines(data), [])
    }

    func testASignWithoutDirectionIsAccepted() {
        let data = RoadbookLandmarkData(candidates: [sign("Hundsbach", at: 2000)])
        XCTAssertEqual(cityLines(data), ["2000 Hundsbach"])
    }

    /// Panneau ET zone bâtie au même endroit : un seul repère, le panneau.
    func testNoDuplicateWhenSignAndBuiltUpAreaCoexist() {
        let data = RoadbookLandmarkData(
            candidates: [sign("Hundsbach", at: 2010)],
            builtUpAreas: [area(2000, 2600)],
            places: [village("Hundsbach", at: 2300)]
        )
        XCTAssertEqual(cityLines(data), ["2010 Hundsbach"])
    }

    /// Sens inverse réel (Hundsbach) : le panneau non orienté est au bout de la zone bâtie, loin de
    /// l'entrée calculée — même localité, même traversée : le panneau prime, pas de doublon.
    func testAMappedSignOfTheSameVillageFurtherInTheBuiltUpAreaWins() {
        let data = RoadbookLandmarkData(
            candidates: [sign("Hundsbach", at: 2850)],
            builtUpAreas: [area(2000, 2900)],
            places: [village("Hundsbach", at: 2400)]
        )
        XCTAssertEqual(cityLines(data), ["2850 Hundsbach"])
    }

    // MARK: - Règles du repli

    /// Villages mitoyens : zones bâties qui se touchent (Ferrette/Vieux-Ferrette) ou une seule zone
    /// continue (Uffheim/Sierentz) — une entrée à chaque changement de localité.
    func testAdjacentVillagesEachGetAnEntry() {
        let touching = RoadbookLandmarkData(candidates: [], builtUpAreas: [area(1000, 1800), area(1900, 2800)], places: [village("Ferrette", at: 1400), village("Vieux-Ferrette", at: 2400)])
        XCTAssertEqual(cityLines(touching), ["1000 Entrée de Ferrette", "1900 Entrée de Vieux-Ferrette"])

        let continuous = RoadbookLandmarkData(candidates: [], builtUpAreas: [area(1000, 3000)], places: [village("Uffheim", at: 1300), village("Sierentz", at: 2700)])
        let lines = cityLines(continuous)
        XCTAssertEqual(lines.count, 2)
        XCTAssertEqual(lines.first, "1000 Entrée d’Uffheim")
        XCTAssertTrue(lines.last?.hasSuffix("Entrée de Sierentz") ?? false, "\(lines)")
    }

    func testFragmentedResidentialAreasOfOneVillageGiveOneEntry() {
        let data = RoadbookLandmarkData(candidates: [], builtUpAreas: [area(1000, 1200), area(1400, 1700), area(1900, 2300)], places: [village("Riespach", at: 1600)])
        XCTAssertEqual(cityLines(data), ["1000 Entrée de Riespach"])
    }

    func testAnIsolatedFarmIsNotAVillageEntry() {
        let data = RoadbookLandmarkData(candidates: [], builtUpAreas: [area(1000, 1080)], places: [village("Riespach", at: 1040)])
        XCTAssertEqual(cityLines(data), [])
    }

    func testATrackStartingInsideAVillageHasNoEntryThere() {
        let data = RoadbookLandmarkData(candidates: [], builtUpAreas: [area(-200, 600), area(3000, 3500)], places: [village("Wahlbach", at: 200), village("Tagsdorf", at: 3200)])
        XCTAssertEqual(cityLines(data), ["3000 Entrée de Tagsdorf"])
    }

    func testAnUnnamedBuiltUpAreaFarFromAnyPlaceGivesNothing() {
        let data = RoadbookLandmarkData(candidates: [], builtUpAreas: [area(1000, 1600)], places: [village("Loin", at: 1300, lateral: 4000)])
        XCTAssertEqual(cityLines(data), [])
    }

    /// Dans une ville, on entre dans la ville, pas dans un quartier ; une commune nouvelle (village
    /// posé sur l'un de ses anciens villages en `suburb`) laisse la place aux anciens villages.
    func testPlaceNamingPrefersTheCityOverSuburbsAndOldVillagesOverAMergedCommune() {
        let city = [RoadbookPlace(name: "Mulhouse", kind: .city, coordinate: north(2500, lateral: 1500)), village("Dornach", at: 1000, lateral: 100, kind: .suburb)]
        XCTAssertEqual(RoadbookCityEntryDetector.placeName(near: north(1000), places: city), "Mulhouse")

        let merged = [village("Illtal", at: 1000, lateral: 80), village("Grentzingen", at: 1000, lateral: 150, kind: .suburb), village("Oberdorf", at: 2500, kind: .suburb)]
        XCTAssertEqual(RoadbookCityEntryDetector.placeName(near: north(1000), places: merged), "Grentzingen")
        XCTAssertEqual(RoadbookCityEntryDetector.placeName(near: north(2500), places: merged), "Oberdorf")
    }

    /// Deux villages sur la même ligne droite : les deux entrées restent (jamais écartées par la
    /// limite d'un repère par tronçon), les autres repères de ce tronçon cèdent la place.
    func testCityEntriesAreNeverDroppedByTheSegmentDensityLimit() {
        let church = RoadbookLandmarkCandidate(category: .church, label: "Église", coordinate: north(4000, lateral: 20))
        let data = RoadbookLandmarkData(candidates: [church], builtUpAreas: [area(1000, 1500), area(3000, 3500)], places: [village("Ferrette", at: 1200), village("Riespach", at: 3200)])
        let lines = RoadbookLandmarkSelector.select(data, points: track(), maneuvers: [], enabledCategories: RoadBookConstants.landmarkDefaultEnabledCategories).standalone.map(\.info.label)
        XCTAssertEqual(lines, ["Entrée de Ferrette", "Entrée de Riespach"])
    }

    func testDisablingCitySignsAlsoDisablesTheFallback() {
        let data = RoadbookLandmarkData(candidates: [], builtUpAreas: [area(1000, 1600)], places: [village("Ferrette", at: 1300)])
        let selection = RoadbookLandmarkSelector.select(data, points: track(), maneuvers: [], enabledCategories: RoadBookConstants.landmarkDefaultEnabledCategories.subtracting([.citySign]))
        XCTAssertTrue(selection.standalone.isEmpty)
    }

    func testReversedTraversalAnnouncesVillagesInTheOtherOrder() {
        let data = RoadbookLandmarkData(candidates: [], builtUpAreas: [area(1000, 1600), area(5000, 5600)], places: [village("Ferrette", at: 1300), village("Riespach", at: 5300)])
        let reversed = Array(track().reversed())
        XCTAssertEqual(cityLines(data, points: reversed).map { $0.split(separator: " ", maxSplits: 1).last.map(String.init) ?? "" }, ["Entrée de Riespach", "Entrée de Ferrette"])
    }

    func testLabelElidesBeforeAVowel() {
        XCTAssertEqual(RoadbookCityEntry.label(for: "Illtal"), "Entrée d’Illtal")
        XCTAssertEqual(RoadbookCityEntry.label(for: "Œlenberg"), "Entrée d’Œlenberg")
        XCTAssertEqual(RoadbookCityEntry.label(for: "Hundsbach"), "Entrée de Hundsbach")
    }

    // MARK: - Panneaux sous toutes leurs formes

    func testEveryCityLimitTaggingFormIsRecognised() {
        let forms: [[String: String]] = [
            ["traffic_sign": "city_limit"],
            ["traffic_sign": "FR:EB10"],
            ["traffic_sign": "fr:eb10[Hundsbach]"],
            ["traffic_sign": "DE:310"],
            ["traffic_sign:forward": "city_limit"],
            ["traffic_sign": "FR:B14;FR:EB10"],
            ["highway": "city_limit"],
            ["city_limit": "begin", "name": "Hundsbach"],
        ]
        for tags in forms {
            XCTAssertEqual(RoadbookLandmark.classify(tags)?.category, .citySign, "\(tags)")
        }
        XCTAssertNil(RoadbookLandmark.classify(["traffic_sign": "city_limit", "city_limit": "end"]))
    }

    // MARK: - Overpass

    func testTheQueryAsksForBuiltUpAreasAndPlacesOnlyWithCitySigns() throws {
        let points = track(lengthMeters: 2000)
        let withSigns = try XCTUnwrap(RoadbookLandmarkOverpassService.query(for: points, categories: [.citySign]))
        XCTAssertTrue(withSigns.contains(#"["landuse"="residential"]"#))
        XCTAssertTrue(withSigns.contains(#"["place"~"^(village|town|city|suburb)$"]["name"]"#))
        XCTAssertTrue(withSigns.contains(#"node["highway"="city_limit"]"#))
        XCTAssertTrue(withSigns.contains(#",i]"#), "valeurs de panneau sans casse")

        let withoutSigns = try XCTUnwrap(RoadbookLandmarkOverpassService.query(for: points, categories: [.church]))
        XCTAssertFalse(withoutSigns.contains("residential"))
        XCTAssertFalse(withoutSigns.contains(#"["place""#))
    }

    func testParseReadsBuiltUpAreasAndPlaces() throws {
        let json = """
        {"elements":[
          {"type":"way","id":1,"nodes":[1,2,3,4,1],"tags":{"landuse":"residential"},"geometry":[{"lat":47.50,"lon":7.30},{"lat":47.50,"lon":7.31},{"lat":47.51,"lon":7.31},{"lat":47.51,"lon":7.30},{"lat":47.50,"lon":7.30}]},
          {"type":"relation","id":2,"tags":{"type":"multipolygon","landuse":"residential"},"members":[
            {"type":"way","ref":5,"role":"outer","geometry":[{"lat":47.52,"lon":7.30},{"lat":47.52,"lon":7.31},{"lat":47.53,"lon":7.31},{"lat":47.52,"lon":7.30}]},
            {"type":"way","ref":6,"role":"inner","geometry":[{"lat":47.521,"lon":7.301},{"lat":47.521,"lon":7.302},{"lat":47.522,"lon":7.302},{"lat":47.521,"lon":7.301}]}]},
          {"type":"way","id":3,"nodes":[7,8,9,7],"tags":{"place":"village","name":"Hundsbach"},"geometry":[{"lat":47.54,"lon":7.30},{"lat":47.54,"lon":7.31},{"lat":47.55,"lon":7.31},{"lat":47.54,"lon":7.30}]},
          {"type":"node","id":10,"lat":47.505,"lon":7.305,"tags":{"place":"village","name":"Ferrette"}},
          {"type":"node","id":11,"lat":47.506,"lon":7.306,"tags":{"place":"hamlet","name":"Lieu-dit"}}
        ]}
        """
        let data = try XCTUnwrap(RoadbookLandmarkOverpassService.parse(Data(json.utf8)))

        XCTAssertEqual(data.builtUpAreas.count, 3)
        XCTAssertEqual(data.builtUpAreas.map(\.name), [nil, nil, "Hundsbach"])
        XCTAssertEqual(try XCTUnwrap(data.builtUpAreas.dropFirst().first).rings.count, 1, "trou (inner) ignoré")
        XCTAssertEqual(data.places.map(\.name), ["Ferrette"], "hameau hors périmètre")
        XCTAssertTrue(data.candidates.isEmpty, "zones et localités ne sont jamais des repères en soi")
    }

    func testChunksNeverDuplicateAreasOrPlaces() {
        let a = RoadbookLandmarkData(candidates: [], builtUpAreas: [area(0, 100, id: "way/1")], places: [village("Ferrette", at: 0)], fetchedCategories: [])
        let merged = RoadbookLandmarkData.empty.adding(a, markingFetched: []).adding(a, markingFetched: [.citySign])
        XCTAssertEqual(merged.builtUpAreas.count, 1)
        XCTAssertEqual(merged.places.count, 1)
        XCTAssertEqual(merged.fetchedCategories, [.citySign])
    }
}
