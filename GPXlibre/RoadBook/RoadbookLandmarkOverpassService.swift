import Foundation
import CoreLocation

/// Récupère par requête Overpass les repères candidats le long d'un TRONÇON de trace (le
/// découpage en tronçons et la progression sont gérés par `RoadbookLandmarkLoader`) — uniquement
/// les catégories demandées (celles activées et pas encore en cache), plus les routes porteuses
/// des éléments posés sur la chaussée pour en déduire le sens et l'alignement.
///
/// Best-effort : `nil` en cas d'échec (réseau, Overpass saturé) — le Road Book s'affiche alors sans
/// repères, ou avec le cache existant, jamais un blocage.
actor RoadbookLandmarkOverpassService {
    static let shared = RoadbookLandmarkOverpassService()

    /// Candidats du tronçon pour `categories` seulement (tout élément reconnu dans une autre
    /// catégorie est écarté : il n'est pas marqué comme téléchargé).
    /// `onBytes` : octets reçus au fil de l'eau (progression, vitesse) — appelé hors du fil
    /// principal, par paquets.
    func fetch(
        for points: [GPXPoint],
        categories: Set<RoadbookLandmarkCategory>,
        includeCityEntryAreas: Bool = RoadBookConstants.landmarkCityEntryFallbackEnabled,
        onBytes: @escaping @Sendable (Int) -> Void = { _ in }
    ) async -> RoadbookLandmarkData? {
        guard let query = Self.query(for: points, categories: categories, includeCityEntryAreas: includeCityEntryAreas),
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
            if let data = await Self.download(request, onBytes: onBytes) {
                guard let parsed = Self.parse(data) else { return nil }
                let withCityEntries = categories.contains(.citySign)
                return RoadbookLandmarkData(
                    candidates: parsed.candidates.filter { categories.contains($0.category) },
                    builtUpAreas: withCityEntries ? parsed.builtUpAreas : [],
                    places: withCityEntries ? parsed.places : [],
                    fetchedCategories: []
                )
            }
            guard retryDelays.indices.contains(attempt) else { break }
            try? await Task.sleep(nanoseconds: UInt64(retryDelays[attempt] * 1_000_000_000))
            guard !Task.isCancelled else { return nil }
        }
        return nil
    }

    /// Corps d'une réponse 200, lu en flux pour compter les octets au fil de l'eau (Overpass
    /// n'annonce pas de taille : aucun total inventé). `nil` si erreur ou autre statut.
    private static func download(_ request: URLRequest, onBytes: @escaping @Sendable (Int) -> Void) async -> Data? {
        guard let (bytes, response) = try? await URLSession.shared.bytes(for: request),
              (response as? HTTPURLResponse)?.statusCode == 200
        else { return nil }
        var data = Data()
        var pending = 0
        do {
            for try await byte in bytes {
                data.append(byte)
                pending += 1
                if pending >= 16_384 {
                    onBytes(pending)
                    pending = 0
                }
            }
        } catch {
            return nil
        }
        if pending > 0 { onBytes(pending) }
        return data
    }

    /// Routes non carrossables : jamais la chaussée qu'un repère "sur la route" doit longer (un nœud
    /// de feux ou de ralentisseur appartient aussi au trottoir ou à la piste qui traverse).
    static let nonVehicleHighways: Set<String> = ["footway", "path", "cycleway", "pedestrian", "steps", "bridleway", "corridor", "elevator", "platform"]

    /// Requête Overpass QL : trace échantillonnée en polyligne `around:` (pas =
    /// `landmarkQuerySampleSpacingMeters`, élargi pour rester sous `landmarkQueryMaxPolylinePoints`),
    /// UNE ligne par sélecteur des seules `categories` demandées, rayon = pas + rayon de visibilité
    /// de la catégorie — le filtrage FIN se fait ensuite sur la trace complète
    /// (`RoadbookLandmarkSelector`). Les routes porteuses ne sont demandées que si une catégorie
    /// posée sur la chaussée en a besoin. `nil` si la trace est trop courte ou rien n'est demandé.
    static func query(for points: [GPXPoint], categories: Set<RoadbookLandmarkCategory>, includeCityEntryAreas: Bool = RoadBookConstants.landmarkCityEntryFallbackEnabled) -> String? {
        let cumulative = TrackProjector.cumulativeDistances(for: points)
        guard points.count > 1, let total = cumulative.last, total > 0 else { return nil }
        guard !categories.isEmpty else { return nil }

        let spacing = max(RoadBookConstants.landmarkQuerySampleSpacingMeters, total / Double(RoadBookConstants.landmarkQueryMaxPolylinePoints - 1))
        let sampleCount = Int((total / spacing).rounded(.up))
        let polyline = (0...sampleCount)
            .compactMap { TrackProjector.interpolatedCoordinate(atCumulativeDistance: min(Double($0) * spacing, total), points: points, cumulativeDistances: cumulative) }
            .map { String(format: "%.6f,%.6f", $0.latitude, $0.longitude) }
            .joined(separator: ",")

        // Ordre du catalogue : requête déterministe (testable, et identique d'un appel à l'autre).
        let ordered = RoadbookLandmarkCategory.allCases.filter(categories.contains)
        let statements = ordered.flatMap { category -> [String] in
            let radius = Int((spacing + (RoadBookConstants.landmarkVisibilityRadiusMeters[category] ?? 0)).rounded(.up))
            return category.definition.overpassSelectors.map { "  \($0)(around:\(radius),\(polyline));" }
        }
        let needsCarriageways = ordered.contains { $0.requiresRoadAlignment || $0.isDirectional }
        let carriageways = needsCarriageways ? """
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
        """ : ""
        // Repli "Entrée de <localité>" : zones bâties traversées + localités nommées proches.
        let areaRadius = Int((spacing + 30).rounded(.up))
        func placeRadius(_ kinds: [RoadbookPlace.Kind]) -> Int {
            Int((spacing + (kinds.compactMap { RoadBookConstants.landmarkCityEntryPlaceReachMeters[$0] }.max() ?? 0)).rounded(.up))
        }
        let cityEntryAreas = includeCityEntryAreas && categories.contains(.citySign) ? """
        (
          way(around:\(areaRadius),\(polyline))["landuse"="residential"];
          relation(around:\(areaRadius),\(polyline))["landuse"="residential"];
          way(around:\(areaRadius),\(polyline))["place"~"^(village|town|city)$"];
          relation(around:\(areaRadius),\(polyline))["place"~"^(village|town|city)$"];
        );
        out geom;
        (
          node(around:\(placeRadius([.village, .suburb])),\(polyline))["place"~"^(village|town|city|suburb)$"]["name"];
          node(around:\(placeRadius([.city, .town])),\(polyline))["place"~"^(town|city)$"]["name"];
        );
        out body;
        """ : ""

        return """
        [out:json][timeout:\(Int(RoadBookConstants.landmarkRequestTimeoutSeconds))];
        (
        \(statements.joined(separator: "\n"))
        )->.candidates;
        .candidates out tags center;
        \(carriageways)
        \(cityEntryAreas)
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
        let vehicleWays = ways.filter { way in way.tags?["highway"].map { !nonVehicleHighways.contains($0) } ?? false }

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
                roadAxes: element.type == "node" ? element.id.map { roadAxes(of: $0, carriedBy: vehicleWays) } : nil,
                osmID: element.id.map { "\(element.type)/\($0)" }
            ))
        }

        var areas: [RoadbookBuiltUpArea] = []
        var places: [RoadbookPlace] = []
        for element in response.elements {
            let tags = element.tags ?? [:]
            let osmID = element.id.map { "\(element.type)/\($0)" }
            let placeKind = tags["place"].flatMap(RoadbookPlace.Kind.init(rawValue:))
            if element.type == "node", let kind = placeKind, let name = tags["name"], let lat = element.lat, let lon = element.lon {
                places.append(RoadbookPlace(osmID: osmID, name: name, kind: kind, coordinate: CLLocationCoordinate2D(latitude: lat, longitude: lon)))
                continue
            }
            let isResidential = tags["landuse"] == "residential"
            let isPlaceArea = placeKind.map { $0 != .suburb } ?? false
            guard element.type != "node", isResidential || isPlaceArea else { continue }
            let rings = element.outerRings
            guard !rings.isEmpty else { continue }
            areas.append(RoadbookBuiltUpArea(osmID: osmID, name: isPlaceArea ? tags["name"] : nil, rings: rings))
        }
        return RoadbookLandmarkData(candidates: candidates, builtUpAreas: areas, places: places, fetchedCategories: [])
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
        /// Relation en `out geom` : membres avec leur géométrie.
        let members: [Member]?

        struct Member: Decodable {
            let type: String
            let role: String?
            let geometry: [LatLon?]?
        }

        /// Contour(s) extérieur(s) d'une surface : le chemin fermé lui-même, ou les membres `outer`
        /// d'une relation (chaque membre est traité comme un anneau : une zone résidentielle en
        /// plusieurs morceaux reste correctement couverte à l'échelle d'un échantillon de 10 m).
        var outerRings: [[CLLocationCoordinate2D]] {
            func coordinates(_ geometry: [LatLon?]?) -> [CLLocationCoordinate2D] {
                (geometry ?? []).compactMap { $0.map { CLLocationCoordinate2D(latitude: $0.lat, longitude: $0.lon) } }
            }
            if type == "way" {
                let ring = coordinates(geometry)
                return ring.count >= 3 ? [ring] : []
            }
            return (members ?? [])
                .filter { $0.type == "way" && ($0.role ?? "outer") != "inner" }
                .map { coordinates($0.geometry) }
                .filter { $0.count >= 3 }
        }

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
