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
    /// Position de la manœuvre le long de la route recalée par Valhalla (0 = départ, 1 =
    /// arrivée), calculée depuis `begin_shape_index` — fix "roadbook-maneuver-position-from-
    /// route" (it26 point 1). Sert à choisir le BON passage quand la trace passe plusieurs fois
    /// près du même carrefour (boucle, aller-retour) : la géométrie seule ne peut pas les
    /// départager. `nil` = inconnue (fixture de test), repli sur une projection monotone.
    let routeProgressFraction: Double?
    /// Rue(s) AVANT la manœuvre (`street_names` de la manœuvre précédente) et APRÈS (`street_names`
    /// de celle-ci) — vides si la route n'a pas de nom (fréquent en campagne). Servent à confirmer
    /// un demi-tour sur la même route et un changement de route (voir `changesRoadName`).
    let streetNamesBefore: [String]
    let streetNamesAfter: [String]

    init(
        coordinate: CLLocationCoordinate2D,
        type: ValhallaManeuverType,
        roundaboutExitCount: Int?,
        routeProgressFraction: Double? = nil,
        streetNamesBefore: [String] = [],
        streetNamesAfter: [String] = []
    ) {
        self.coordinate = coordinate
        self.type = type
        self.roundaboutExitCount = roundaboutExitCount
        self.routeProgressFraction = routeProgressFraction
        self.streetNamesBefore = streetNamesBefore
        self.streetNamesAfter = streetNamesAfter
    }

    /// Demi-tour Valhalla CONFIRMÉ sur la même route (fix "roadbook-no-false-uturn", it26 point 2,
    /// règle métier : un demi-tour = repartir en sens inverse sur la MÊME route) : la rue d'après
    /// est aussi celle d'avant. Rue sans nom ou différente : affiché comme un virage très serré.
    var isSameRoadUTurn: Bool {
        (type == .uturnLeft || type == .uturnRight) && !Set(streetNamesBefore).isDisjoint(with: streetNamesAfter)
    }

    /// La route suivie change de nom (les deux noms sont connus et n'ont rien en commun) — un
    /// croisement avec un chemin sans nom, ou une route qui garde son nom, ne l'est jamais.
    var changesRoadName: Bool {
        !streetNamesBefore.isEmpty && !streetNamesAfter.isEmpty && Set(streetNamesBefore).isDisjoint(with: streetNamesAfter)
    }
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

        return matchedManeuvers(legs: decoded.trip.legs.map { leg in
            (maneuvers: leg.maneuvers ?? [], coordinates: ValhallaRoutingService.decodePolyline6(leg.shape))
        })
    }

    /// Manœuvres retenues de TOUS les tronçons (`legs`) de la réponse, chacune avec sa
    /// progression le long de la route recalée ENTIÈRE (tronçons précédents inclus) — pure,
    /// testable sans réseau.
    static func matchedManeuvers(legs: [(maneuvers: [ValhallaManeuver], coordinates: [CLLocationCoordinate2D])]) -> [MapMatchedManeuver] {
        let legCumulativeDistances = legs.map { TrackProjector.cumulativeDistances(for: $0.coordinates.map { GPXPoint(latitude: $0.latitude, longitude: $0.longitude) }) }
        let totalRouteMeters = legCumulativeDistances.reduce(0) { $0 + ($1.last ?? 0) }

        var legStartMeters: Double = 0
        var result: [MapMatchedManeuver] = []
        for (leg, cumulative) in zip(legs, legCumulativeDistances) {
            let offset = legStartMeters
            result += intermediateManeuvers(maneuvers: leg.maneuvers, legCoordinates: leg.coordinates) { shapeIndex in
                guard totalRouteMeters > 0, cumulative.indices.contains(shapeIndex) else { return nil }
                return (offset + cumulative[shapeIndex]) / totalRouteMeters
            }
            legStartMeters += cumulative.last ?? 0
        }
        return result
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
        legCoordinates: [CLLocationCoordinate2D],
        routeProgressFractionAtShapeIndex: (Int) -> Double? = { _ in nil }
    ) -> [MapMatchedManeuver] {
        guard maneuvers.count > 2 else { return [] }
        return maneuvers.indices.dropFirst().dropLast().compactMap { index -> MapMatchedManeuver? in
            let maneuver = maneuvers[index]
            guard legCoordinates.indices.contains(maneuver.beginShapeIndex) else { return nil }
            let type = ValhallaManeuverType(rawValue: maneuver.type) ?? .none
            guard type.roadbookTier != nil else { return nil }
            return MapMatchedManeuver(
                coordinate: legCoordinates[maneuver.beginShapeIndex],
                type: type,
                roundaboutExitCount: maneuver.roundaboutExitCount,
                routeProgressFraction: routeProgressFractionAtShapeIndex(maneuver.beginShapeIndex),
                streetNamesBefore: maneuvers[index - 1].streetNames,
                streetNamesAfter: maneuver.streetNames
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
    /// Rue(s) empruntée(s) APRÈS cette manœuvre — sert uniquement à confirmer un demi-tour sur
    /// la même route (it26 point 2). Vide si la route n'a pas de nom (fréquent en campagne).
    let streetNames: [String]

    enum CodingKeys: String, CodingKey {
        case type
        case beginShapeIndex = "begin_shape_index"
        case roundaboutExitCount = "roundabout_exit_count"
        case streetNames = "street_names"
    }

    init(type: Int = ValhallaManeuverType.none.rawValue, beginShapeIndex: Int, roundaboutExitCount: Int? = nil, streetNames: [String] = []) {
        self.type = type
        self.beginShapeIndex = beginShapeIndex
        self.roundaboutExitCount = roundaboutExitCount
        self.streetNames = streetNames
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        type = try container.decodeIfPresent(Int.self, forKey: .type) ?? ValhallaManeuverType.none.rawValue
        beginShapeIndex = try container.decode(Int.self, forKey: .beginShapeIndex)
        roundaboutExitCount = try container.decodeIfPresent(Int.self, forKey: .roundaboutExitCount)
        streetNames = try container.decodeIfPresent([String].self, forKey: .streetNames) ?? []
    }
}
