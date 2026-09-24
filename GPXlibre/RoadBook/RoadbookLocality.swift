import Foundation
import CoreLocation

/// Checkpoint "entrée dans une commune" du Road Book (spec "roadbook-locality-checkpoints", it26
/// point 3) — une étape de contrôle qui permet de vérifier qu'on est sur la bonne trace, DISTINCTE
/// d'un changement de direction : jamais un `Checkpoint` (type partagé avec les pins/la bannière
/// du Ride), jamais dans `RoadbookLiveProgress` (la carte hero du mode Assisté GPS reste le
/// prochain virage). Position le long de la trace dans le SENS de parcours affiché.
struct RoadbookLocalityCheckpoint: Identifiable, Hashable, Codable {
    enum Source: String, Codable {
        /// Limite de commune OSM (`boundary=administrative`), source principale.
        case boundary
        /// Repli : panneau d'entrée d'agglomération (`traffic_sign=city_limit`).
        case citySign
        /// Repli : lieu (`place=village/town/city`) le plus proche de la trace.
        case place
    }

    let name: String
    let latitude: Double
    let longitude: Double
    let cumulativeDistanceMeters: Double
    let source: Source

    init(name: String, coordinate: CLLocationCoordinate2D, cumulativeDistanceMeters: Double, source: Source) {
        self.name = name
        latitude = coordinate.latitude
        longitude = coordinate.longitude
        self.cumulativeDistanceMeters = cumulativeDistanceMeters
        self.source = source
    }

    var coordinate: CLLocationCoordinate2D { CLLocationCoordinate2D(latitude: latitude, longitude: longitude) }

    /// Unique au sein d'un parcours (deux checkpoints ne partagent jamais la même position).
    var id: String { "locality-\(Int((cumulativeDistanceMeters * 10).rounded()))-\(name)" }
}

/// Une commune OSM : tous ses anneaux (extérieurs ET intérieurs), testés en pair-impair —
/// un point est dedans s'il est dans un nombre impair d'anneaux (un trou = un anneau de plus).
struct RoadbookLocalityArea {
    let name: String
    let rings: [[CLLocationCoordinate2D]]
    private let minLatitude: Double
    private let maxLatitude: Double
    private let minLongitude: Double
    private let maxLongitude: Double

    init(name: String, rings: [[CLLocationCoordinate2D]]) {
        self.name = name
        self.rings = rings
        let all = rings.flatMap { $0 }
        minLatitude = all.map(\.latitude).min() ?? 0
        maxLatitude = all.map(\.latitude).max() ?? 0
        minLongitude = all.map(\.longitude).min() ?? 0
        maxLongitude = all.map(\.longitude).max() ?? 0
    }

    func contains(_ coordinate: CLLocationCoordinate2D) -> Bool {
        guard coordinate.latitude >= minLatitude, coordinate.latitude <= maxLatitude,
              coordinate.longitude >= minLongitude, coordinate.longitude <= maxLongitude
        else { return false }
        return rings.reduce(false) { inside, ring in
            RoadbookLocalityGeometry.ring(ring, contains: coordinate) ? !inside : inside
        }
    }
}

/// Un nœud OSM ponctuel (panneau d'entrée d'agglomération ou lieu).
struct RoadbookLocalityNode {
    let coordinate: CLLocationCoordinate2D
    let name: String?
}

/// Tout ce qu'Overpass renvoie pour une trace — la logique de choix de la source vit dans
/// `RoadbookLocalityDetector.checkpoints(from:...)`, jamais dans le service réseau.
struct RoadbookLocalityOverpassData {
    let areas: [RoadbookLocalityArea]
    let citySigns: [RoadbookLocalityNode]
    let places: [RoadbookLocalityNode]
}

enum RoadbookLocalityGeometry {
    /// Lancer de rayon en coordonnées lat/lon — approximation plane largement suffisante à
    /// l'échelle d'une commune.
    static func ring(_ ring: [CLLocationCoordinate2D], contains point: CLLocationCoordinate2D) -> Bool {
        guard ring.count >= 3 else { return false }
        var inside = false
        var j = ring.count - 1
        for i in 0..<ring.count {
            let a = ring[i]
            let b = ring[j]
            if (a.latitude > point.latitude) != (b.latitude > point.latitude) {
                let crossingLongitude = (b.longitude - a.longitude) * (point.latitude - a.latitude) / (b.latitude - a.latitude) + a.longitude
                if point.longitude < crossingLongitude { inside.toggle() }
            }
            j = i
        }
        return inside
    }

    /// Recolle les chemins (`way`) d'une relation de limite en anneaux fermés — une limite de
    /// commune est découpée en plusieurs chemins partagés avec les communes voisines, dans un
    /// sens quelconque. Un anneau qui ne se referme pas (données incomplètes) est écarté.
    static func assembleRings(_ ways: [[CLLocationCoordinate2D]]) -> [[CLLocationCoordinate2D]] {
        var remaining = ways.filter { $0.count >= 2 }
        var rings: [[CLLocationCoordinate2D]] = []

        while !remaining.isEmpty {
            var ring = remaining.removeFirst()
            while !isClosed(ring), let end = ring.last {
                if let index = remaining.firstIndex(where: { isSame($0[0], end) }) {
                    ring += remaining.remove(at: index).dropFirst()
                } else if let index = remaining.firstIndex(where: { isSame($0[$0.count - 1], end) }) {
                    ring += remaining.remove(at: index).reversed().dropFirst()
                } else {
                    break
                }
            }
            if isClosed(ring), ring.count >= 4 { rings.append(ring) }
        }
        return rings
    }

    private static func isClosed(_ ring: [CLLocationCoordinate2D]) -> Bool {
        guard ring.count >= 2, let first = ring.first, let last = ring.last else { return false }
        return isSame(first, last)
    }

    private static func isSame(_ a: CLLocationCoordinate2D, _ b: CLLocationCoordinate2D) -> Bool {
        abs(a.latitude - b.latitude) < 1e-7 && abs(a.longitude - b.longitude) < 1e-7
    }
}

/// Calcule les checkpoints d'entrée de commune le long d'une trace DÉJÀ dans son sens de
/// parcours (`GPXTrack.reordered(using:)`) — sens inversé = entrées dans l'ordre inverse, aux
/// limites opposées, sans aucun cas particulier. Pur, testable sans réseau.
enum RoadbookLocalityDetector {
    /// Pas d'échantillonnage de la trace pour détecter les franchissements de limite — une
    /// trace peu dense (segments de plusieurs centaines de mètres) ne saute ainsi jamais une
    /// commune traversée sur une courte distance ; chaque franchissement est ensuite affiné par
    /// dichotomie à quelques décimètres près.
    static let probeSpacingMeters: Double = 20

    /// Source principale (limites) si Overpass en a renvoyé au moins une ; sinon panneaux
    /// d'entrée d'agglomération ; sinon lieux les plus proches de la trace.
    static func checkpoints(
        from data: RoadbookLocalityOverpassData,
        points: [GPXPoint],
        minStayMeters: Double = RoadBookConstants.localityMinStayMeters,
        reentryMinDistanceMeters: Double = RoadBookConstants.localityReentryMinDistanceMeters
    ) -> [RoadbookLocalityCheckpoint] {
        let cumulativeDistances = TrackProjector.cumulativeDistances(for: points)
        if !data.areas.isEmpty {
            return boundaryEntries(points: points, cumulativeDistances: cumulativeDistances, areas: data.areas, minStayMeters: minStayMeters, reentryMinDistanceMeters: reentryMinDistanceMeters)
        }
        if !data.citySigns.isEmpty {
            return citySignEntries(points: points, cumulativeDistances: cumulativeDistances, signs: data.citySigns, places: data.places, reentryMinDistanceMeters: reentryMinDistanceMeters)
        }
        return placeEntries(points: points, cumulativeDistances: cumulativeDistances, places: data.places, reentryMinDistanceMeters: reentryMinDistanceMeters)
    }

    // MARK: - Limites de commune

    private struct Run {
        var area: Int?
        var startMeters: Double
        var coordinate: CLLocationCoordinate2D
    }

    static func boundaryEntries(
        points: [GPXPoint],
        cumulativeDistances: [Double],
        areas: [RoadbookLocalityArea],
        minStayMeters: Double,
        reentryMinDistanceMeters: Double
    ) -> [RoadbookLocalityCheckpoint] {
        guard points.count > 1, let total = cumulativeDistances.last, total > 0 else { return [] }

        func membership(at meters: Double) -> Int? {
            guard let coordinate = TrackProjector.interpolatedCoordinate(atCumulativeDistance: meters, points: points, cumulativeDistances: cumulativeDistances) else { return nil }
            return areas.firstIndex { $0.contains(coordinate) }
        }

        // 1. Suite des communes traversées, franchissements localisés au décimètre près.
        var runs = [Run(area: membership(at: 0), startMeters: 0, coordinate: points[0].coordinate)]
        var previousMeters: Double = 0
        while previousMeters < total {
            let nextMeters = min(previousMeters + probeSpacingMeters, total)
            let currentArea = runs[runs.count - 1].area
            guard membership(at: nextMeters) != currentArea else {
                previousMeters = nextMeters
                continue
            }
            var low = previousMeters
            var high = nextMeters
            for _ in 0..<12 {
                let mid = (low + high) / 2
                if membership(at: mid) == currentArea { low = mid } else { high = mid }
            }
            let crossing = TrackProjector.interpolatedCoordinate(atCumulativeDistance: high, points: points, cumulativeDistances: cumulativeDistances) ?? points[0].coordinate
            runs.append(Run(area: membership(at: high), startMeters: high, coordinate: crossing))
            // Repart du franchissement affiné (toujours > previousMeters) : une seconde limite
            // dans le même pas de 20 m n'est jamais sautée.
            previousMeters = high
        }

        // 2. Trace qui longe une limite (une route qui SUIT la limite entre deux communes est
        //    fréquente : le GPS oscille de part et d'autre) : un passage plus court que
        //    `minStayMeters` dans une commune n'est pas une entrée. S'il est encadré par la même
        //    commune (X → Y court → X), le retour dans X n'en est pas une non plus. Vérifié sur
        //    une trace réelle de 110 km du propriétaire.
        var removed = true
        while removed {
            removed = false
            for k in stride(from: 1, to: runs.count - 1, by: 1) where runs[k + 1].startMeters - runs[k].startMeters < minStayMeters {
                if runs[k - 1].area == runs[k + 1].area {
                    runs.removeSubrange(k...(k + 1))
                } else {
                    // X → Y court → Z : l'entrée dans Z reste à SA limite réelle.
                    runs.remove(at: k)
                }
                removed = true
                break
            }
        }

        // 3. Une entrée par commune franchie (jamais la commune de départ), sans ré-entrée trop
        //    proche de la précédente dans la même commune.
        var entries: [RoadbookLocalityCheckpoint] = []
        var lastEntryMetersByArea: [Int: Double] = [:]
        for run in runs.dropFirst() {
            guard let area = run.area else { continue }
            if let last = lastEntryMetersByArea[area], run.startMeters - last < reentryMinDistanceMeters { continue }
            lastEntryMetersByArea[area] = run.startMeters
            entries.append(RoadbookLocalityCheckpoint(name: areas[area].name, coordinate: run.coordinate, cumulativeDistanceMeters: run.startMeters, source: .boundary))
        }
        return entries
    }

    // MARK: - Replis

    /// Panneaux d'entrée d'agglomération sur la trace — un village a un panneau à chaque bout
    /// (entrée ET sortie, souvent sans indication de sens dans OSM) : seul le PREMIER rencontré
    /// dans le sens de parcours compte, les panneaux suivants du même nom sont la sortie.
    static func citySignEntries(
        points: [GPXPoint],
        cumulativeDistances: [Double],
        signs: [RoadbookLocalityNode],
        places: [RoadbookLocalityNode],
        reentryMinDistanceMeters: Double
    ) -> [RoadbookLocalityCheckpoint] {
        let located = signs.compactMap { sign -> RoadbookLocalityCheckpoint? in
            guard let projection = TrackProjector.project(sign.coordinate, onto: points, cumulativeDistances: cumulativeDistances),
                  projection.distanceToTrackMeters <= RoadBookConstants.localitySignMaxOffTrackMeters,
                  let name = sign.name ?? nearestPlaceName(to: sign.coordinate, in: places),
                  let coordinate = TrackProjector.interpolatedCoordinate(atCumulativeDistance: projection.cumulativeDistanceMeters, points: points, cumulativeDistances: cumulativeDistances)
            else { return nil }
            return RoadbookLocalityCheckpoint(name: name, coordinate: coordinate, cumulativeDistanceMeters: projection.cumulativeDistanceMeters, source: .citySign)
        }
        return firstOfEachConsecutiveName(located.sorted { $0.cumulativeDistanceMeters < $1.cumulativeDistanceMeters }, reentryMinDistanceMeters: reentryMinDistanceMeters)
    }

    /// Lieux (`place=village/town/city`) proches de la trace — checkpoint au point de la trace
    /// le plus proche du lieu (un nœud `place` est au centre du village, pas sur la route).
    static func placeEntries(
        points: [GPXPoint],
        cumulativeDistances: [Double],
        places: [RoadbookLocalityNode],
        reentryMinDistanceMeters: Double
    ) -> [RoadbookLocalityCheckpoint] {
        let located = places.compactMap { place -> RoadbookLocalityCheckpoint? in
            guard let name = place.name,
                  let projection = TrackProjector.project(place.coordinate, onto: points, cumulativeDistances: cumulativeDistances),
                  projection.distanceToTrackMeters <= RoadBookConstants.localityPlaceMaxOffTrackMeters,
                  let coordinate = TrackProjector.interpolatedCoordinate(atCumulativeDistance: projection.cumulativeDistanceMeters, points: points, cumulativeDistances: cumulativeDistances)
            else { return nil }
            return RoadbookLocalityCheckpoint(name: name, coordinate: coordinate, cumulativeDistanceMeters: projection.cumulativeDistanceMeters, source: .place)
        }
        return firstOfEachConsecutiveName(located.sorted { $0.cumulativeDistanceMeters < $1.cumulativeDistanceMeters }, reentryMinDistanceMeters: reentryMinDistanceMeters)
    }

    private static func nearestPlaceName(to coordinate: CLLocationCoordinate2D, in places: [RoadbookLocalityNode]) -> String? {
        places
            .filter { $0.name != nil }
            .min { RoadbookAnalyzer.distanceMeters($0.coordinate, coordinate) < RoadbookAnalyzer.distanceMeters($1.coordinate, coordinate) }?
            .name
    }

    private static func firstOfEachConsecutiveName(_ sorted: [RoadbookLocalityCheckpoint], reentryMinDistanceMeters: Double) -> [RoadbookLocalityCheckpoint] {
        var result: [RoadbookLocalityCheckpoint] = []
        var lastMetersByName: [String: Double] = [:]
        for checkpoint in sorted {
            if result.last?.name == checkpoint.name { continue }
            if let last = lastMetersByName[checkpoint.name], checkpoint.cumulativeDistanceMeters - last < reentryMinDistanceMeters { continue }
            lastMetersByName[checkpoint.name] = checkpoint.cumulativeDistanceMeters
            result.append(checkpoint)
        }
        return result
    }
}

/// Une ligne du Road Book : changement de direction OU checkpoint d'entrée de commune, dans
/// l'ordre de progression le long de la trace — seule façon dont les écrans/le PDF les mêlent.
enum RoadbookEntry: Identifiable {
    case maneuver(RoadbookManeuver, index: Int)
    case locality(RoadbookLocalityCheckpoint)

    var id: String {
        switch self {
        case .maneuver(let maneuver, _): return "maneuver-\(maneuver.id.uuidString)"
        case .locality(let locality): return locality.id
        }
    }

    var cumulativeDistanceMeters: Double {
        switch self {
        case .maneuver(let maneuver, _): return maneuver.cumulativeDistanceMeters
        case .locality(let locality): return locality.cumulativeDistanceMeters
        }
    }

    /// `index` = rang de la manœuvre dans la liste des manœuvres (numérotation affichée
    /// inchangée : un checkpoint n'est pas une manœuvre numérotée). À distance égale, la
    /// manœuvre passe avant le checkpoint.
    static func merge(maneuvers: [RoadbookManeuver], localities: [RoadbookLocalityCheckpoint]) -> [RoadbookEntry] {
        let entries = maneuvers.enumerated().map { RoadbookEntry.maneuver($0.element, index: $0.offset) }
            + localities.map { RoadbookEntry.locality($0) }
        return entries.enumerated().sorted { lhs, rhs in
            let l = lhs.element.cumulativeDistanceMeters
            let r = rhs.element.cumulativeDistanceMeters
            return l == r ? lhs.offset < rhs.offset : l < r
        }.map(\.element)
    }
}
