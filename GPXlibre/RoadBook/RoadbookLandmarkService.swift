import Foundation
import CoreLocation

/// Récupère un repère OSM pertinent à proximité d'un point de manœuvre (spec "roadbook-mode",
/// it23quater) via Overpass API — même famille de service qu'OpenStreetMap/Nominatim déjà
/// utilisé dans l'app (`NominatimGeocodingService`), gratuit et sans clé.
///
/// TOUJOURS best-effort : `nil` en cas d'échec réseau/timeout/décodage, JAMAIS une erreur
/// exposée à l'appelant — l'absence de repère local n'est pas un échec, le Road Book reste
/// parfaitement utilisable sans cette info (voir `RoadBookTabView`, l'enrichissement arrive de
/// façon asynchrone et n'empêche jamais l'affichage des manœuvres elles-mêmes).
actor RoadbookLandmarkService {
    static let shared = RoadbookLandmarkService()

    private var lastRequestDate: Date?

    func nearbyLandmark(at coordinate: CLLocationCoordinate2D) async -> RoadbookLandmarkInfo? {
        await respectRateLimit()

        let radius = Int(RoadBookConstants.landmarkSearchRadiusMeters)
        let lat = coordinate.latitude
        let lon = coordinate.longitude
        // Requête Overpass QL : un seul aller-retour réseau par point, plusieurs familles de
        // tags unionnées (way ET node — un rond-point/un revêtement sont des `way`, une église/
        // des feux sont typiquement des `node`) — `out tags center` renvoie les tags SANS la
        // géométrie complète (on n'a besoin que des tags pour `RoadbookLandmark`).
        let query = """
        [out:json][timeout:\(Int(RoadBookConstants.landmarkRequestTimeoutSeconds))];
        (
          node(around:\(radius),\(lat),\(lon))["amenity"];
          node(around:\(radius),\(lat),\(lon))["religion"];
          node(around:\(radius),\(lat),\(lon))["railway"="level_crossing"];
          node(around:\(radius),\(lat),\(lon))["highway"~"traffic_signals|give_way|stop"];
          way(around:\(radius),\(lat),\(lon))["junction"="roundabout"];
          way(around:\(radius),\(lat),\(lon))["power"~"line|tower"];
          way(around:\(radius),\(lat),\(lon))["surface"];
          way(around:\(radius),\(lat),\(lon))["bridge"="yes"];
          way(around:\(radius),\(lat),\(lon))["ford"="yes"];
          way(around:\(radius),\(lat),\(lon))["railway"="rail"];
          node(around:\(radius),\(lat),\(lon))["natural"="tree"];
          node(around:\(radius),\(lat),\(lon))["building"];
          way(around:\(radius),\(lat),\(lon))["building"];
        );
        out tags center \(RoadBookConstants.landmarkResultLimit);
        """

        guard let url = URL(string: RoadBookConstants.overpassBaseURLString) else { return nil }
        var request = URLRequest(url: url, timeoutInterval: RoadBookConstants.landmarkRequestTimeoutSeconds)
        request.httpMethod = "POST"
        request.setValue(MapEngineConstants.userAgent, forHTTPHeaderField: "User-Agent")
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        guard let encodedQuery = query.addingPercentEncoding(withAllowedCharacters: .urlQueryValueAllowed) else { return nil }
        request.httpBody = "data=\(encodedQuery)".data(using: .utf8)

        do {
            let (data, _) = try await URLSession.shared.data(for: request)
            let decoded = try JSONDecoder().decode(OverpassResponse.self, from: data)
            let tagsList = decoded.elements.compactMap(\.tags)
            return RoadbookLandmark.bestLandmark(for: tagsList)
        } catch {
            return nil
        }
    }

    private func respectRateLimit() async {
        defer { lastRequestDate = Date() }
        guard let last = lastRequestDate else { return }
        let elapsed = Date().timeIntervalSince(last)
        let remaining = RoadBookConstants.landmarkMinRequestIntervalSeconds - elapsed
        guard remaining > 0 else { return }
        try? await Task.sleep(nanoseconds: UInt64(remaining * 1_000_000_000))
    }
}

private struct OverpassResponse: Decodable {
    let elements: [OverpassElement]
}

private struct OverpassElement: Decodable {
    let tags: [String: String]?
}

private extension CharacterSet {
    /// `.urlQueryAllowed` n'échappe pas `[`/`]`/`;` utilisés tels quels dans Overpass QL au
    /// sein d'une valeur de formulaire `data=...` — jeu de caractères dédié, plus restrictif
    /// (alphanumériques + quelques signes sûrs), pour rester valide quel que soit le contenu
    /// exact de la requête générée ci-dessus.
    static let urlQueryValueAllowed: CharacterSet = {
        var allowed = CharacterSet.alphanumerics
        allowed.insert(charactersIn: "-._~")
        return allowed
    }()
}
