import Foundation
import CoreLocation

/// Map matching Valhalla (`/trace_route`, spec "valhalla-map-matching-direction-change", it20) —
/// recale une trace GPX complète sur le réseau routier réel pour repérer les changements de
/// manœuvre/rue qu'un simple angle géométrique ne peut pas voir (léger virage sous le seuil
/// `.light` qui correspond en réalité à une vraie bifurcation vers une autre rue).
///
/// PAS `/trace_attributes` (endpoint dédié aux attributs d'arête par point, plus riche — noms de
/// rue par segment, ids OSM — mais aussi plus complexe à interpréter) : `/trace_route` suffit
/// pour ce besoin précis, chaque élément de `trip.legs[].maneuvers[]` délimitant déjà un segment
/// de manœuvre distinct (nom de rue différent, type de manœuvre différent) — exactement ce qu'on
/// veut détecter, sans reconstruire cette segmentation nous-mêmes depuis des attributs bas
/// niveau. `shape_match: "map_snap"` (le tracé GPS suit déjà globalement des routes réelles,
/// contrairement à "edge_walk" pensé pour un tracé très bruité).
/// Une manœuvre de map matching RETENUE après filtrage type (spec
/// "roadbook-route-aware-maneuvers", it24, point 1 — voir `ValhallaManeuverType.roadbookTier`
/// pour le filtrage lui-même) : porte tout ce qu'il faut pour choisir le palier ET le
/// pictogramme (point 2) sans re-décoder le JSON Valhalla plus tard.
struct MapMatchedManeuver {
    let coordinate: CLLocationCoordinate2D
    let type: ValhallaManeuverType
    let roundaboutExitCount: Int?
}

enum ValhallaMapMatchingService {
    /// - Parameter coordinates : trace ENTIÈRE, dans l'ordre du parcours (déjà sous-échantillonnée
    ///   en amont si besoin, voir `RideConstants.mapMatchingMaxTracePoints`).
    /// - Returns : une manœuvre par manœuvre INTERMÉDIAIRE RETENUE (voir `intermediateManeuvers`
    ///   pour le filtrage) — la première (Départ) et la dernière (Arrivée) sont TOUJOURS exclues
    ///   en amont du filtrage, elles ne représentent jamais un changement de direction EN COURS
    ///   de trajet.
    static func matchRoute(
        coordinates: [CLLocationCoordinate2D],
        configuration: ValhallaConfiguration
    ) async throws -> [MapMatchedManeuver] {
        guard coordinates.count > 1 else { return [] }
        guard let url = ValhallaRoutingService.endpointURL(configuration.endpointURLString, path: "trace_route") else {
            throw ValhallaRoutingError.invalidEndpoint
        }

        let body: [String: Any] = [
            "shape": coordinates.map { ["lat": $0.latitude, "lon": $0.longitude] },
            "costing": "auto",
            "shape_match": "map_snap",
            // Même réduction de préférence autoroute/péage que le routage classique (spec
            // "valhalla-live-routing", it20) — cohérent, même s'il s'agit ici de recaler plutôt
            // que de calculer un nouvel itinéraire.
            "costing_options": [
                "auto": [
                    "use_highways": RideConstants.valhallaAutoCostingUseHighways,
                    "use_tolls": RideConstants.valhallaAutoCostingUseTolls,
                ],
            ],
        ]

        var request = URLRequest(url: url, timeoutInterval: RideConstants.valhallaMapMatchingTimeoutSeconds)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try? JSONSerialization.data(withJSONObject: body)
        ValhallaRoutingService.applyBasicAuth(to: &request, configuration: configuration)

        let data = try await ValhallaRoutingService.performRequest(request)
        guard let decoded = try? JSONDecoder().decode(ValhallaTraceRouteResponse.self, from: data) else {
            throw ValhallaRoutingError.noRoute
        }

        return decoded.trip.legs.flatMap { leg -> [MapMatchedManeuver] in
            let legCoordinates = ValhallaRoutingService.decodePolyline6(leg.shape)
            return intermediateManeuvers(maneuvers: leg.maneuvers ?? [], legCoordinates: legCoordinates)
        }
    }

    /// Exclut la première ET la dernière manœuvre (Départ/Arrivée, toujours présentes dans une
    /// réponse Valhalla même à une seule manœuvre "vraie") — seules les manœuvres EN COURS de
    /// route sont des candidates. Filtrage route-aware (spec it24, point 1, root cause du bug
    /// terrain "une courbe progressive sur le même axe déclenche un événement à tort") : SEULES
    /// les manœuvres dont `ValhallaManeuverType.roadbookTier` n'est pas `nil` survivent — écarte
    /// notamment `.continueStraight`/`.becomes`, présents à CHAQUE changement de nom de rue même
    /// sans virage réel.
    static func intermediateManeuvers(
        maneuvers: [ValhallaManeuver],
        legCoordinates: [CLLocationCoordinate2D]
    ) -> [MapMatchedManeuver] {
        guard maneuvers.count > 2 else { return [] }
        return maneuvers.dropFirst().dropLast().compactMap { maneuver -> MapMatchedManeuver? in
            guard legCoordinates.indices.contains(maneuver.beginShapeIndex) else { return nil }
            let type = ValhallaManeuverType(rawValue: maneuver.type) ?? .none
            guard type.roadbookTier != nil else { return nil }
            return MapMatchedManeuver(
                coordinate: legCoordinates[maneuver.beginShapeIndex],
                type: type,
                roundaboutExitCount: maneuver.roundaboutExitCount
            )
        }
    }
}

/// Abstraction du map matching (même esprit que `RoutingProvider`) — permet à
/// `RideSessionManager.mapMatchingProvider` d'être remplacé par un provider factice en test,
/// sans jamais dépendre d'un vrai réseau Valhalla.
protocol MapMatchingProvider {
    func matchRoute(coordinates: [CLLocationCoordinate2D], configuration: ValhallaConfiguration) async throws -> [MapMatchedManeuver]
}

struct ValhallaMapMatchingProvider: MapMatchingProvider {
    func matchRoute(coordinates: [CLLocationCoordinate2D], configuration: ValhallaConfiguration) async throws -> [MapMatchedManeuver] {
        try await ValhallaMapMatchingService.matchRoute(coordinates: coordinates, configuration: configuration)
    }
}

private struct ValhallaTraceRouteResponse: Decodable {
    let trip: ValhallaTraceTrip
}
private struct ValhallaTraceTrip: Decodable {
    let legs: [ValhallaTraceLeg]
}
private struct ValhallaTraceLeg: Decodable {
    let shape: String
    let maneuvers: [ValhallaManeuver]?
}

/// `internal` (pas `private`) — utilisée directement par `RoadbookMapMatchingTests`/
/// `ValhallaMapMatchingServiceTests` pour construire des fixtures sans dépendre du JSON brut de
/// Valhalla. `type`/`roundaboutExitCount` ajoutés en it24 (point 1) — PAS `bearing_before`/
/// `bearing_after` : vérifié dès it21 (`Nav/CLAUDE.md`, "dépendance dure") que ces deux champs
/// N'EXISTENT PAS sur les manœuvres Valhalla `/route` (même schéma que `/trace_route`), contexte
/// vérifié plutôt que supposé de la doc tierce citée par la fiche it24.
struct ValhallaManeuver: Decodable {
    let type: Int
    let beginShapeIndex: Int
    let roundaboutExitCount: Int?

    enum CodingKeys: String, CodingKey {
        case type
        case beginShapeIndex = "begin_shape_index"
        case roundaboutExitCount = "roundabout_exit_count"
    }

    init(type: Int = ValhallaManeuverType.none.rawValue, beginShapeIndex: Int, roundaboutExitCount: Int? = nil) {
        self.type = type
        self.beginShapeIndex = beginShapeIndex
        self.roundaboutExitCount = roundaboutExitCount
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        type = try container.decodeIfPresent(Int.self, forKey: .type) ?? ValhallaManeuverType.none.rawValue
        beginShapeIndex = try container.decode(Int.self, forKey: .beginShapeIndex)
        roundaboutExitCount = try container.decodeIfPresent(Int.self, forKey: .roundaboutExitCount)
    }
}
