import Foundation
import CoreLocation

/// Récupère en UNE requête Overpass les repères VISIBLES candidats le long d'une trace (itération
/// "repères = uniquement ce que le conducteur voit") — panneaux, marquages/infrastructures,
/// bâtiments et ouvrages remarquables (liste autorisée : `RoadbookLandmarkCategory`), plus les
/// routes porteuses des panneaux orientés `forward`/`backward` pour en déduire le sens. Remplace
/// l'ancienne requête par manœuvre (une par virage) ET l'ancienne requête des limites de communes.
///
/// Best-effort : `nil` en cas d'échec (réseau, Overpass saturé) — le Road Book s'affiche alors sans
/// repères, ou avec le cache existant, jamais un blocage.
actor RoadbookLandmarkOverpassService {
    static let shared = RoadbookLandmarkOverpassService()

    func fetch(for points: [GPXPoint]) async -> RoadbookLandmarkData? {
        guard let query = Self.query(for: points, includeUrbanWays: RoadBookConstants.landmarkUrbanEntryFallbackEnabled),
              let url = URL(string: RoadBookConstants.overpassBaseURLString),
              let encodedQuery = query.addingPercentEncoding(withAllowedCharacters: .overpassFormValueAllowed)
        else { return nil }

        var request = URLRequest(url: url, timeoutInterval: RoadBookConstants.landmarkRequestTimeoutSeconds)
        request.httpMethod = "POST"
        request.setValue(MapEngineConstants.userAgent, forHTTPHeaderField: "User-Agent")
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.httpBody = "data=\(encodedQuery)".data(using: .utf8)

        let retryDelays = RoadBookConstants.landmarkRetryDelaysSeconds
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

    /// Routes non carrossables : jamais la chaussée qu'un repère "sur la route" doit longer (un nœud
    /// de passage piéton appartient aussi au trottoir qui traverse).
    static let nonVehicleHighways: Set<String> = ["footway", "path", "cycleway", "pedestrian", "steps", "bridleway", "corridor", "elevator", "platform"]

    /// Requête Overpass QL : trace échantillonnée en polyligne `around:` (pas =
    /// `landmarkQuerySampleSpacingMeters`, élargi pour rester sous `landmarkQueryMaxPolylinePoints`),
    /// rayon = pas + rayon de visibilité max de la famille — le filtrage FIN par catégorie se fait
    /// ensuite sur la trace complète (`RoadbookLandmarkSelector`). `nil` si la trace est trop courte.
    static func query(for points: [GPXPoint], includeUrbanWays: Bool) -> String? {
        let cumulative = TrackProjector.cumulativeDistances(for: points)
        guard points.count > 1, let total = cumulative.last, total > 0 else { return nil }

        let spacing = max(RoadBookConstants.landmarkQuerySampleSpacingMeters, total / Double(RoadBookConstants.landmarkQueryMaxPolylinePoints - 1))
        let sampleCount = Int((total / spacing).rounded(.up))
        let polyline = (0...sampleCount)
            .compactMap { TrackProjector.interpolatedCoordinate(atCumulativeDistance: min(Double($0) * spacing, total), points: points, cumulativeDistances: cumulative) }
            .map { String(format: "%.6f,%.6f", $0.latitude, $0.longitude) }
            .joined(separator: ",")

        func radius(_ group: RoadbookLandmarkCategory.Group) -> Int {
            let maxVisibility = RoadBookConstants.landmarkVisibilityRadiusMeters.filter { $0.key.group == group }.map(\.value).max() ?? 0
            return Int((spacing + maxVisibility).rounded(.up))
        }
        let near = "around:\(max(radius(.sign), radius(.ground))),\(polyline)"
        let far = "around:\(radius(.building)),\(polyline)"
        let citySign = RoadbookLandmark.citySignValues.joined(separator: "|")
        let urbanWays = includeUrbanWays ? """
        (
          way(\(near))["highway"]["maxspeed"~"^(50|FR:urban)$"];
          way(\(near))["highway"]["zone:maxspeed"="FR:urban"];
          way(\(near))["highway"]["maxspeed:type"="FR:urban"];
        );
        out geom;
        """ : ""

        return """
        [out:json][timeout:\(Int(RoadBookConstants.landmarkRequestTimeoutSeconds))];
        (
          node(\(near))["traffic_sign"~"\(citySign)"];
          node(\(near))["traffic_sign:forward"~"\(citySign)"];
          node(\(near))["traffic_sign:backward"~"\(citySign)"];
          node(\(near))["highway"~"^(stop|give_way|traffic_signals|crossing)$"];
          node(\(near))["railway"="level_crossing"];
          node(\(near))["traffic_calming"~"^(bump|hump|table|cushion)$"];
          way(\(near))["highway"]["bridge"="yes"];
          way(\(near))["highway"]["tunnel"="yes"];
          nwr(\(far))["amenity"~"^(place_of_worship|townhall|fuel)$"];
          nwr(\(far))["building"~"^(church|chapel)$"];
          nwr(\(far))["man_made"~"^(bell_tower|water_tower|windmill|watermill|lighthouse|tower)$"];
          nwr(\(far))["historic"~"^(wayside_cross|wayside_shrine|castle)$"];
        )->.candidates;
        .candidates out tags center;
        (
          node.candidates["highway"];
          node.candidates["railway"="level_crossing"];
          node.candidates["traffic_calming"];
          node.candidates["traffic_sign"];
          node.candidates["traffic_sign:forward"];
          node.candidates["traffic_sign:backward"];
        )->.onroad;
        way(bn.onroad)["highway"];
        out geom;
        \(urbanWays)
        """
    }

    /// Décode la réponse : éléments classés en repères autorisés (`RoadbookLandmark.classify`, les
    /// autres sont ignorés), sens des panneaux résolu sur leur route porteuse, routes urbaines.
    /// `nil` si ce n'est pas une réponse Overpass.
    static func parse(_ data: Data) -> RoadbookLandmarkData? {
        guard let response = try? JSONDecoder().decode(OverpassLandmarkResponse.self, from: data) else { return nil }

        // Routes renvoyées avec leur géométrie (`out geom`) : chaussées portant un repère "sur la
        // route", et/ou routes urbaines — jamais des candidats (ceux-là arrivent avec `center`).
        let ways = response.elements.filter { $0.type == "way" && $0.geometry != nil && $0.nodes != nil }
        let vehicleWays = ways.filter { !nonVehicleHighways.contains($0.tags?["highway"] ?? "") }

        var candidates: [RoadbookLandmarkCandidate] = []
        for element in response.elements {
            guard let tags = element.tags, let coordinate = element.candidateCoordinate,
                  let classified = RoadbookLandmark.classify(tags)
            else { continue }
            candidates.append(RoadbookLandmarkCandidate(
                category: classified.category,
                label: classified.label,
                coordinate: coordinate,
                orientation: orientation(of: element, tags: tags, carriedBy: vehicleWays),
                roadAxes: element.type == "node" ? element.id.map { roadAxes(of: $0, carriedBy: vehicleWays) } : nil
            ))
        }

        let urbanWays = ways
            .filter { isUrban($0.tags ?? [:]) }
            .map { $0.geometry?.compactMap { $0.map { CLLocationCoordinate2DCodable(CLLocationCoordinate2D(latitude: $0.lat, longitude: $0.lon)) } } ?? [] }
        return RoadbookLandmarkData(candidates: candidates, urbanWays: urbanWays)
    }

    /// Cap de chaque chaussée porteuse au nœud (segment qui en part, ou qui y arrive en bout).
    private static func roadAxes(of nodeID: Int64, carriedBy ways: [OverpassLandmarkResponse.Element]) -> [Double] {
        ways.compactMap { way in bearing(at: nodeID, along: way) }
    }

    private static func bearing(at nodeID: Int64, along way: OverpassLandmarkResponse.Element) -> Double? {
        guard let nodes = way.nodes, let geometry = way.geometry, nodes.count == geometry.count, nodes.count > 1,
              let index = nodes.firstIndex(of: nodeID)
        else { return nil }
        let from = index < nodes.count - 1 ? index : index - 1
        guard let a = geometry[from], let b = geometry[from + 1] else { return nil }
        return RoadbookAnalyzer.bearing(from: CLLocationCoordinate2D(latitude: a.lat, longitude: a.lon), to: CLLocationCoordinate2D(latitude: b.lat, longitude: b.lon))
    }

    private static func isUrban(_ tags: [String: String]) -> Bool {
        ["50", "FR:urban"].contains(tags["maxspeed"] ?? "") || tags["zone:maxspeed"] == "FR:urban" || tags["maxspeed:type"] == "FR:urban"
    }

    /// Sens d'un panneau : `forward`/`backward` (tag `direction`, `traffic_signals:direction` ou
    /// `traffic_sign:forward|backward`) résolu en cap de circulation sur sa route porteuse ; cap ou
    /// point cardinal (`direction=90`, `direction=NE`) = cap vers lequel il fait face. Inconnu (ou
    /// valable dans les deux sens) : `nil`, le panneau est gardé quel que soit le sens.
    private static func orientation(of element: OverpassLandmarkResponse.Element, tags: [String: String], carriedBy ways: [OverpassLandmarkResponse.Element]) -> RoadbookLandmarkCandidate.Orientation? {
        let forwardSign = tags["traffic_sign:forward"] != nil
        let backwardSign = tags["traffic_sign:backward"] != nil
        let relative: String? = {
            if forwardSign != backwardSign { return forwardSign ? "forward" : "backward" }
            if forwardSign && backwardSign { return nil }
            return tags["direction"] ?? tags["traffic_signals:direction"]
        }()

        if let relative, relative == "forward" || relative == "backward" {
            guard let id = element.id,
                  let wayBearing = ways.lazy.compactMap({ bearing(at: id, along: $0) }).first
            else { return nil }
            return .appliesToTravelBearing(relative == "forward" ? wayBearing : wayBearing + 180)
        }
        if let value = tags["direction"], let facing = compassBearing(value) {
            return .faces(facing)
        }
        return nil
    }

    private static let cardinals: [String: Double] = [
        "N": 0, "NNE": 22.5, "NE": 45, "ENE": 67.5, "E": 90, "ESE": 112.5, "SE": 135, "SSE": 157.5,
        "S": 180, "SSW": 202.5, "SW": 225, "WSW": 247.5, "W": 270, "WNW": 292.5, "NW": 315, "NNW": 337.5,
    ]

    private static func compassBearing(_ value: String) -> Double? {
        if let degrees = Double(value.trimmingCharacters(in: .whitespaces)) { return degrees }
        return cardinals[value.uppercased()]
    }
}

private struct OverpassLandmarkResponse: Decodable {
    let elements: [Element]

    struct Element: Decodable {
        let type: String
        let id: Int64?
        let lat: Double?
        let lon: Double?
        let center: LatLon?
        let tags: [String: String]?
        let nodes: [Int64]?
        /// `null` possible dans `out geom` pour un nœud manquant.
        let geometry: [LatLon?]?

        /// Nœud (lat/lon) ou chemin/relation résumé par son centre (`out center`) ; un chemin
        /// renvoyé avec sa géométrie complète n'est jamais un candidat.
        var candidateCoordinate: CLLocationCoordinate2D? {
            if let lat, let lon { return CLLocationCoordinate2D(latitude: lat, longitude: lon) }
            if let center { return CLLocationCoordinate2D(latitude: center.lat, longitude: center.lon) }
            return nil
        }
    }

    struct LatLon: Decodable {
        let lat: Double
        let lon: Double
    }
}

private extension CharacterSet {
    /// Overpass QL contient `[`/`]`/`;`/`~`/`^`/`|` dans une valeur de formulaire `data=...`.
    static let overpassFormValueAllowed: CharacterSet = {
        var allowed = CharacterSet.alphanumerics
        allowed.insert(charactersIn: "-._~")
        return allowed
    }()
}
