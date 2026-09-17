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
enum ValhallaMapMatchingService {
    /// - Parameter coordinates : trace ENTIÈRE, dans l'ordre du parcours (déjà sous-échantillonnée
    ///   en amont si besoin, voir `RideConstants.mapMatchingMaxTracePoints`).
    /// - Returns : un point par manœuvre INTERMÉDIAIRE uniquement — la première (Départ) et la
    ///   dernière (Arrivée) sont toujours exclues, elles ne représentent pas un changement de
    ///   direction EN COURS de trajet.
    static func matchRoute(
        coordinates: [CLLocationCoordinate2D],
        configuration: ValhallaConfiguration
    ) async throws -> [CLLocationCoordinate2D] {
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

        return decoded.trip.legs.flatMap { leg -> [CLLocationCoordinate2D] in
            let legCoordinates = ValhallaRoutingService.decodePolyline6(leg.shape)
            return intermediateManeuverCoordinates(maneuvers: leg.maneuvers ?? [], legCoordinates: legCoordinates)
        }
    }

    /// Exclut la première ET la dernière manœuvre (Départ/Arrivée, toujours présentes dans une
    /// réponse Valhalla même à une seule manœuvre "vraie") — seules les manœuvres EN COURS de
    /// route sont des candidats à un "léger changement de direction".
    static func intermediateManeuverCoordinates(
        maneuvers: [ValhallaManeuver],
        legCoordinates: [CLLocationCoordinate2D]
    ) -> [CLLocationCoordinate2D] {
        guard maneuvers.count > 2 else { return [] }
        return maneuvers.dropFirst().dropLast().compactMap { maneuver in
            guard legCoordinates.indices.contains(maneuver.beginShapeIndex) else { return nil }
            return legCoordinates[maneuver.beginShapeIndex]
        }
    }
}

/// Abstraction du map matching (même esprit que `RoutingProvider`) — permet à
/// `RideSessionManager.mapMatchingProvider` d'être remplacé par un provider factice en test,
/// sans jamais dépendre d'un vrai réseau Valhalla.
protocol MapMatchingProvider {
    func matchRoute(coordinates: [CLLocationCoordinate2D], configuration: ValhallaConfiguration) async throws -> [CLLocationCoordinate2D]
}

struct ValhallaMapMatchingProvider: MapMatchingProvider {
    func matchRoute(coordinates: [CLLocationCoordinate2D], configuration: ValhallaConfiguration) async throws -> [CLLocationCoordinate2D] {
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

/// `internal` (pas `private`) — utilisée directement par `RoadbookAnalyzerMapMatchingTests` pour
/// construire des fixtures sans dépendre du JSON brut de Valhalla.
struct ValhallaManeuver: Decodable {
    let beginShapeIndex: Int

    enum CodingKeys: String, CodingKey {
        case beginShapeIndex = "begin_shape_index"
    }

    init(beginShapeIndex: Int) {
        self.beginShapeIndex = beginShapeIndex
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        beginShapeIndex = try container.decode(Int.self, forKey: .beginShapeIndex)
    }
}
