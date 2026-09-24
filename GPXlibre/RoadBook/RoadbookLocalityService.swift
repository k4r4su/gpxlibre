import Foundation
import CoreLocation

/// Récupère en UNE requête Overpass tout ce qu'il faut pour les checkpoints d'entrée de commune
/// d'une trace (spec "roadbook-locality-checkpoints", it26 point 3) : limites de communes
/// (`boundary=administrative`, `admin_level=8`) avec leur géométrie complète, plus les panneaux
/// d'entrée d'agglomération et les lieux, pour les replis.
///
/// Best-effort, même esprit que `RoadbookLandmarkService` : `nil` en cas d'échec (réseau,
/// timeout, Overpass saturé) — l'appelant ne met alors rien en cache et n'affiche aucun
/// checkpoint, jamais un blocage du Road Book.
actor RoadbookLocalityService {
    static let shared = RoadbookLocalityService()

    func fetch(for points: [GPXPoint]) async -> RoadbookLocalityOverpassData? {
        guard let query = Self.query(for: points),
              let url = URL(string: RoadBookConstants.overpassBaseURLString),
              let encodedQuery = query.addingPercentEncoding(withAllowedCharacters: .overpassFormValueAllowed)
        else { return nil }

        var request = URLRequest(url: url, timeoutInterval: RoadBookConstants.localityRequestTimeoutSeconds)
        request.httpMethod = "POST"
        request.setValue(MapEngineConstants.userAgent, forHTTPHeaderField: "User-Agent")
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.httpBody = "data=\(encodedQuery)".data(using: .utf8)

        // L'instance publique renvoie par intermittence 429/504 même à une requête triviale
        // (constaté pendant le développement) — nouveaux essais après des pauses croissantes ;
        // au-delà, abandon propre jusqu'à la prochaine ouverture.
        let retryDelays = RoadBookConstants.localityRetryDelaysSeconds
        for attempt in 0...retryDelays.count {
            if let (data, response) = try? await URLSession.shared.data(for: request),
               (response as? HTTPURLResponse)?.statusCode == 200 {
                return Self.parse(data)
            }
            guard retryDelays.indices.contains(attempt) else { break }
            try? await Task.sleep(nanoseconds: UInt64(retryDelays[attempt] * 1_000_000_000))
            guard !Task.isCancelled else { return nil }
        }
        return nil
    }

    /// Requête Overpass QL : la trace est échantillonnée (`localityQuerySampleSpacingMeters`, pas
    /// élargi pour rester sous `localityQueryMaxPolylinePoints`) en une polyligne `around:` dont
    /// le rayon vaut ce pas — la corde entre deux échantillons ne sort ainsi jamais de la zone
    /// interrogée. Seules les communes dont la limite passe près de la trace reviennent : ce
    /// sont exactement celles dans lesquelles on peut ENTRER. `nil` si la trace est trop courte.
    static func query(for points: [GPXPoint]) -> String? {
        let cumulative = TrackProjector.cumulativeDistances(for: points)
        guard points.count > 1, let total = cumulative.last, total > 0 else { return nil }

        let spacing = max(RoadBookConstants.localityQuerySampleSpacingMeters, total / Double(RoadBookConstants.localityQueryMaxPolylinePoints - 1))
        let sampleCount = Int((total / spacing).rounded(.up))
        let samples = (0...sampleCount).compactMap {
            TrackProjector.interpolatedCoordinate(atCumulativeDistance: min(Double($0) * spacing, total), points: points, cumulativeDistances: cumulative)
        }
        let polyline = samples.map { String(format: "%.6f,%.6f", $0.latitude, $0.longitude) }.joined(separator: ",")
        let radius = Int(spacing.rounded(.up))
        let placeRadius = radius + Int(RoadBookConstants.localityPlaceMaxOffTrackMeters)

        return """
        [out:json][timeout:\(Int(RoadBookConstants.localityRequestTimeoutSeconds))];
        rel(around:\(radius),\(polyline))["boundary"="administrative"]["admin_level"="\(RoadBookConstants.localityAdminLevel)"];
        out geom;
        (
          node(around:\(radius),\(polyline))["traffic_sign"="city_limit"];
          node(around:\(placeRadius),\(polyline))["place"~"^(village|town|city)$"];
        );
        out;
        """
    }

    /// Décode la réponse JSON d'Overpass — relations → communes (anneaux recollés), nœuds →
    /// panneaux/lieux. Une commune sans nom ou sans anneau fermé est écartée. `nil` si le JSON
    /// n'est pas une réponse Overpass.
    static func parse(_ data: Data) -> RoadbookLocalityOverpassData? {
        guard let response = try? JSONDecoder().decode(OverpassLocalityResponse.self, from: data) else { return nil }

        var areas: [RoadbookLocalityArea] = []
        var citySigns: [RoadbookLocalityNode] = []
        var places: [RoadbookLocalityNode] = []

        for element in response.elements {
            switch element.type {
            case "relation":
                guard let name = element.tags?["name"] else { continue }
                let ways = (element.members ?? [])
                    .filter { $0.type == "way" }
                    .map { $0.geometry?.compactMap { $0.map { CLLocationCoordinate2D(latitude: $0.lat, longitude: $0.lon) } } ?? [] }
                let rings = RoadbookLocalityGeometry.assembleRings(ways)
                guard !rings.isEmpty else { continue }
                areas.append(RoadbookLocalityArea(name: name, rings: rings))
            case "node":
                guard let lat = element.lat, let lon = element.lon else { continue }
                let node = RoadbookLocalityNode(coordinate: CLLocationCoordinate2D(latitude: lat, longitude: lon), name: element.tags?["name"])
                if element.tags?["traffic_sign"] == "city_limit" {
                    citySigns.append(node)
                } else if element.tags?["place"] != nil {
                    places.append(node)
                }
            default:
                continue
            }
        }
        return RoadbookLocalityOverpassData(areas: areas, citySigns: citySigns, places: places)
    }
}

private struct OverpassLocalityResponse: Decodable {
    let elements: [Element]

    struct Element: Decodable {
        let type: String
        let lat: Double?
        let lon: Double?
        let tags: [String: String]?
        let members: [Member]?
    }

    struct Member: Decodable {
        let type: String
        /// `null` possible dans `out geom` pour un nœud manquant — un anneau troué ne se
        /// refermera pas et sera écarté par `assembleRings`, jamais un échec de décodage.
        let geometry: [LatLon?]?
    }

    struct LatLon: Decodable {
        let lat: Double
        let lon: Double
    }
}

private extension CharacterSet {
    /// Même jeu restreint que `RoadbookLandmarkService` : Overpass QL contient `[`/`]`/`;`/`~`/`^`
    /// dans une valeur de formulaire `data=...`.
    static let overpassFormValueAllowed: CharacterSet = {
        var allowed = CharacterSet.alphanumerics
        allowed.insert(charactersIn: "-._~")
        return allowed
    }()
}
