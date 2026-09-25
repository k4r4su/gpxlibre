import XCTest
import CoreLocation
@testable import GPXlibre

/// GARDE-FOU DU JALON STABLE it28 (v0.0.28-roadbook-stable) — non-régression GLOBALE du Road Book :
/// une trace de référence (4 branches, 3 virages francs) + une réponse Overpass de référence
/// (repères visibles ET pièges : limite de commune, stop de rue latérale, passage piéton, panneau
/// vu de dos, église trop loin, boulangerie désactivée par défaut) passent par la VRAIE chaîne de
/// production — `RoadbookExtractor.maneuvers` (réglages par défaut), `RoadbookLandmarkOverpassService.
/// parse`, `RoadbookLandmarkSelector.select` (catégories par défaut), `RoadbookEntry.merge` — et le
/// Road Book obtenu doit être EXACTEMENT celui attendu, ligne par ligne, dans les deux sens.
///
/// Si ce test casse, une itération a changé le comportement validé du Road Book : soit c'est une
/// régression, soit le changement est voulu et DOIT être justifié par ses propres tests avant de
/// mettre à jour le résultat attendu ici (voir la section "Jalon stable" de CLAUDE.md).
@MainActor
final class RoadbookStableRegressionTests: XCTestCase {
    private let origin = CLLocationCoordinate2D(latitude: 47.60, longitude: 7.35)

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

    /// Branches de la trace de référence : cap, longueur (virages : droite 90°, gauche 90°,
    /// droite 135°).
    private let legs: [(bearing: Double, length: Double)] = [(0, 1500), (90, 1200), (0, 1000), (135, 800)]

    private var legStarts: [CLLocationCoordinate2D] {
        var starts = [origin]
        for leg in legs.dropLast() {
            starts.append(destination(from: starts[starts.count - 1], bearingDegrees: leg.bearing, distanceMeters: leg.length))
        }
        return starts
    }

    private var referenceTrack: GPXTrack {
        var points: [GPXPoint] = []
        for (index, leg) in legs.enumerated() {
            let start = legStarts[index]
            for meters in stride(from: index == 0 ? 0.0 : 10.0, through: leg.length, by: 10) {
                let c = destination(from: start, bearingDegrees: leg.bearing, distanceMeters: meters)
                points.append(GPXPoint(latitude: c.latitude, longitude: c.longitude))
            }
        }
        return GPXTrack(id: UUID(uuidString: "0000A28A-0000-4000-8000-000000000028") ?? UUID(), name: "Référence it28", fileName: "ref.gpx", importDate: Date(timeIntervalSince1970: 0), points: points, waypoints: [])
    }

    /// Point à `along` m sur la branche `leg`, décalé de `lateral` m (positif = à droite du sens de
    /// la branche).
    private func at(leg: Int, along: Double, lateral: Double = 0) -> CLLocationCoordinate2D {
        let onTrack = destination(from: legStarts[leg], bearingDegrees: legs[leg].bearing, distanceMeters: along)
        guard lateral != 0 else { return onTrack }
        return destination(from: onTrack, bearingDegrees: legs[leg].bearing + (lateral > 0 ? 90 : -90), distanceMeters: abs(lateral))
    }

    private func node(_ id: Int, _ c: CLLocationCoordinate2D, _ tags: [String: String]) -> String {
        let tagsJSON = tags.sorted { $0.key < $1.key }.map { "\"\($0.key)\":\"\($0.value)\"" }.joined(separator: ",")
        return #"{"type":"node","id":\#(id),"lat":\#(c.latitude),"lon":\#(c.longitude),"tags":{\#(tagsJSON)}}"#
    }

    /// Réponse Overpass de référence (format réel `out tags center` + `out geom`).
    private var referenceOverpassResponse: Data {
        let sideStop = at(leg: 0, along: 900, lateral: 10)
        let sideRoadWest = at(leg: 0, along: 900, lateral: -5)
        let sideRoadEast = at(leg: 0, along: 900, lateral: 60)
        let elements = [
            // Pièges : jamais de repère.
            #"{"type":"relation","id":9001,"center":{"lat":\#(at(leg: 1, along: 300).latitude),"lon":\#(at(leg: 1, along: 300).longitude)},"tags":{"boundary":"administrative","admin_level":"8","name":"Commune"}}"#,
            node(9002, at(leg: 0, along: 1000, lateral: 0), ["highway": "crossing", "crossing": "marked"]),
            node(9003, sideStop, ["highway": "stop"]),
            #"{"type":"way","id":9004,"nodes":[9010,9003,9011],"tags":{"highway":"residential"},"geometry":[{"lat":\#(sideRoadWest.latitude),"lon":\#(sideRoadWest.longitude)},{"lat":\#(sideStop.latitude),"lon":\#(sideStop.longitude)},{"lat":\#(sideRoadEast.latitude),"lon":\#(sideRoadEast.longitude)}]}"#,
            node(9005, at(leg: 2, along: 400, lateral: 6), ["traffic_sign": "city_limit", "name": "Dos", "direction": "N"]),
            node(9006, at(leg: 1, along: 800, lateral: 300), ["amenity": "place_of_worship", "name": "Église lointaine"]),
            node(9007, at(leg: 2, along: 250, lateral: 12), ["shop": "bakery", "name": "Au bon pain"]),
            // Repères attendus.
            node(1, at(leg: 0, along: 400, lateral: 6), ["traffic_sign": "city_limit", "name": "Hundsbach", "direction": "S"]),
            node(2, at(leg: 1, along: 600, lateral: 15), ["amenity": "place_of_worship", "religion": "christian", "name": "Église Saint-Blaise"]),
            node(3, at(leg: 2, along: 10, lateral: -8), ["highway": "give_way"]),
            node(4, at(leg: 2, along: 500, lateral: -120), ["amenity": "fuel", "brand": "Total"]),
            node(5, at(leg: 3, along: 350), ["traffic_calming": "hump"]),
        ]
        return Data(#"{"elements":[\#(elements.joined(separator: ","))]}"#.utf8)
    }

    private func roadBook(for track: GPXTrack, mapMatched: [MapMatchedManeuver] = []) throws -> [String] {
        let maneuvers = RoadbookExtractor.maneuvers(
            for: track,
            windowBeforeMeters: NavigationConstants.roadbookWindowBeforeMetersDefault,
            windowAfterMeters: NavigationConstants.roadbookWindowAfterMetersDefault,
            lightThresholdDegrees: NavigationConstants.roadbookLightThresholdDegreesDefault,
            markedThresholdDegrees: NavigationConstants.roadbookMarkedThresholdDegreesDefault,
            hardThresholdDegrees: NavigationConstants.roadbookHardThresholdDegreesDefault,
            veryHardThresholdDegrees: NavigationConstants.roadbookVeryHardThresholdDegreesDefault,
            mergeMinDistanceMeters: RideConstants.turnMergeMinDistanceMetersDefault,
            mapMatchedManeuvers: mapMatched
        )
        let data = try XCTUnwrap(RoadbookLandmarkOverpassService.parse(referenceOverpassResponse))
        let selection = RoadbookLandmarkSelector.select(
            data,
            points: track.points,
            maneuvers: maneuvers,
            enabledCategories: RoadBookConstants.landmarkDefaultEnabledCategories,
            cityEntryFallbackEnabled: RoadBookConstants.landmarkCityEntryFallbackEnabled
        )
        return RoadbookEntry.merge(maneuvers: maneuvers, landmarks: selection.standalone).map { entry in
            // Distances arrondies à 10 m : le résultat attendu reste lisible et stable.
            switch entry {
            case .maneuver(let maneuver, let index):
                let km = String(format: "%.2f", (maneuver.cumulativeDistanceMeters / 10).rounded() / 100)
                let attached = selection.attached[maneuver.id].map { " + \($0.displayLabel)" } ?? ""
                return "\(index + 1). \(km) km \(maneuver.checkpoint.tier.label) \(maneuver.checkpoint.direction)\(attached)"
            case .landmark(let landmark):
                let km = String(format: "%.2f", (landmark.cumulativeDistanceMeters / 10).rounded() / 100)
                return "   \(km) km \(landmark.info.category.emoji) \(landmark.info.displayLabel)"
            }
        }
    }

    func testReferenceRoadBookForward() throws {
        XCTAssertEqual(try roadBook(for: referenceTrack), [
            "   0.40 km 🏘️ Hundsbach à droite",
            "1. 1.50 km Virage fort right",
            "   2.10 km ⛪ Église Saint-Blaise à droite",
            "2. 2.70 km Virage fort left + Cédez-le-passage à gauche",
            "   3.20 km ⛽ Total à gauche, 120 m",
            "3. 3.70 km Virage très serré right",
            "   4.05 km 〰️ Ralentisseur",
        ])
    }

    /// Même trace parcourue en sens inverse (Réglages de trace) : virages inversés, panneaux
    /// orientés revus (Hundsbach vu de dos, "Dos" désormais de face), côtés inversés.
    func testReferenceRoadBookReversed() throws {
        let forward = referenceTrack
        let reversed = forward.reordered(using: TrackRideSettings(isReversed: true))
        XCTAssertEqual(reversed.id, forward.id)

        XCTAssertEqual(try roadBook(for: reversed), [
            "   0.45 km 〰️ Ralentisseur",
            "1. 0.80 km Virage très serré left",
            "   1.30 km ⛽ Total à droite, 120 m",
            "   1.40 km 🏘️ Dos à gauche",
            "2. 1.80 km Virage fort right + Cédez-le-passage à droite",
            "   2.40 km ⛪ Église Saint-Blaise à gauche",
            "3. 3.00 km Virage fort left",
        ])
    }

    /// Détection ROUTE-AWARE (Valhalla, it20/it24/it26) : un rond-point invisible géométriquement
    /// (la trace le traverse tout droit) devient une manœuvre, une continuation sans virage n'en
    /// est jamais une, les vrais virages restent au vrai carrefour ; les repères suivent.
    func testReferenceRoadBookWithRouteAwareManeuvers() throws {
        let mapMatched = [
            MapMatchedManeuver(coordinate: at(leg: 0, along: 800), type: .roundaboutEnter, roundaboutExitCount: 2, routeProgressFraction: 800.0 / 4500),
            MapMatchedManeuver(coordinate: legStarts[1], type: .right, roundaboutExitCount: nil, routeProgressFraction: 1500.0 / 4500),
            MapMatchedManeuver(coordinate: at(leg: 1, along: 300), type: .continueStraight, roundaboutExitCount: nil, routeProgressFraction: 1800.0 / 4500),
            MapMatchedManeuver(coordinate: legStarts[2], type: .left, roundaboutExitCount: nil, routeProgressFraction: 2700.0 / 4500),
            MapMatchedManeuver(coordinate: legStarts[3], type: .sharpRight, roundaboutExitCount: nil, routeProgressFraction: 3700.0 / 4500),
        ]

        XCTAssertEqual(try roadBook(for: referenceTrack, mapMatched: mapMatched), [
            "   0.40 km 🏘️ Hundsbach à droite",
            "1. 0.80 km Rond-point straight",
            "2. 1.50 km Virage fort right",
            "   2.10 km ⛪ Église Saint-Blaise à droite",
            "3. 2.70 km Virage fort left + Cédez-le-passage à gauche",
            "   3.20 km ⛽ Total à gauche, 120 m",
            "4. 3.70 km Virage très serré right",
            "   4.05 km 〰️ Ralentisseur",
        ])
    }
}
