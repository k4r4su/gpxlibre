import Foundation
import CoreLocation

/// Un élément OSM visible, candidat repère — indépendant du sens de parcours (mis en cache par
/// trace), la sélection se fait ensuite pour le parcours affiché (`RoadbookLandmarkSelector`).
struct RoadbookLandmarkCandidate: Codable, Equatable {
    /// Sens de circulation auquel un panneau s'applique, quand OSM le précise.
    enum Orientation: Codable, Equatable {
        /// `direction=forward|backward` ou `traffic_sign:forward|backward`, résolu sur la route
        /// porteuse : cap de la circulation concernée.
        case appliesToTravelBearing(Double)
        /// `direction=<degrés|cardinal>` : cap vers lequel le panneau FAIT FACE (il regarde les
        /// usagers qui arrivent en face de lui).
        case faces(Double)
    }

    let category: RoadbookLandmarkCategory
    let label: String
    let latitude: Double
    let longitude: Double
    let orientation: Orientation?
    /// Caps (axes, sens indifférent) des routes carrossables qui portent l'élément quand il est un
    /// nœud de chaussée — `nil`/vide si inconnu (panneau posé à côté de la route) : pas de filtre.
    let roadAxes: [Double]?
    /// "node/123" — identifiant OSM, dédoublonne un élément renvoyé par deux tronçons voisins.
    let osmID: String?

    init(category: RoadbookLandmarkCategory, label: String, coordinate: CLLocationCoordinate2D, orientation: Orientation? = nil, roadAxes: [Double]? = nil, osmID: String? = nil) {
        self.category = category
        self.label = label
        latitude = coordinate.latitude
        longitude = coordinate.longitude
        self.orientation = orientation
        self.roadAxes = roadAxes
        self.osmID = osmID
    }

    var coordinate: CLLocationCoordinate2D { CLLocationCoordinate2D(latitude: latitude, longitude: longitude) }
}

/// Tout ce qui est récupéré (et mis en cache) pour une trace — `fetchedCategories` dit quelles
/// catégories ont DÉJÀ été téléchargées : activer une catégorie absente ne télécharge qu'elle
/// (complément), en désactiver une ne fait que filtrer (aucun réseau).
struct RoadbookLandmarkData: Codable, Equatable {
    let candidates: [RoadbookLandmarkCandidate]
    /// Routes limitées à 50 km/h / `FR:urban` — seulement si `landmarkUrbanEntryFallbackEnabled`.
    let urbanWays: [[CLLocationCoordinate2DCodable]]
    let fetchedCategories: Set<RoadbookLandmarkCategory>

    init(candidates: [RoadbookLandmarkCandidate], urbanWays: [[CLLocationCoordinate2DCodable]] = [], fetchedCategories: Set<RoadbookLandmarkCategory> = Set(RoadbookLandmarkCategory.allCases)) {
        self.candidates = candidates
        self.urbanWays = urbanWays
        self.fetchedCategories = fetchedCategories
    }

    static let empty = RoadbookLandmarkData(candidates: [], fetchedCategories: [])

    /// Ajoute des candidats (dédoublonnés par identifiant OSM) et marque `categories` comme
    /// téléchargées.
    func adding(_ other: RoadbookLandmarkData, markingFetched categories: Set<RoadbookLandmarkCategory>) -> RoadbookLandmarkData {
        var known = Set(candidates.compactMap(\.osmID))
        var merged = candidates
        for candidate in other.candidates {
            if let id = candidate.osmID {
                guard known.insert(id).inserted else { continue }
            }
            merged.append(candidate)
        }
        return RoadbookLandmarkData(candidates: merged, urbanWays: urbanWays + other.urbanWays, fetchedCategories: fetchedCategories.union(categories))
    }
}

/// Repère affiché en LIGNE DÉDIÉE du Road Book, entre deux changements de direction — jamais un
/// `Checkpoint` (type partagé avec les pins/la bannière Ride), jamais dans `RoadbookLiveProgress`.
struct RoadbookLandmarkCheckpoint: Identifiable, Hashable, Codable {
    let info: RoadbookLandmarkInfo
    let latitude: Double
    let longitude: Double
    let cumulativeDistanceMeters: Double

    var coordinate: CLLocationCoordinate2D { CLLocationCoordinate2D(latitude: latitude, longitude: longitude) }
    var id: String { "landmark-\(Int((cumulativeDistanceMeters * 10).rounded()))-\(info.category.rawValue)" }
}

/// Résultat de la sélection pour un parcours : repères affichés AVEC un changement de direction
/// (clé = `RoadbookManeuver.id`) et repères en ligne dédiée.
struct RoadbookLandmarkSelection: Equatable {
    let attached: [UUID: RoadbookLandmarkInfo]
    let standalone: [RoadbookLandmarkCheckpoint]

    static let empty = RoadbookLandmarkSelection(attached: [:], standalone: [])
}

/// Sélection PURE des repères visibles le long d'une trace DÉJÀ dans son sens de parcours —
/// filtre de visibilité (rayon par catégorie, sens des panneaux), côté, priorité et densité. Voir
/// `RoadBookConstants.landmark*` pour tous les réglages.
enum RoadbookLandmarkSelector {
    private struct Placement {
        let info: RoadbookLandmarkInfo
        let coordinate: CLLocationCoordinate2D
        let cumulative: Double
        let lateral: Double
    }

    static func select(
        _ data: RoadbookLandmarkData,
        points: [GPXPoint],
        maneuvers: [RoadbookManeuver],
        enabledCategories: Set<RoadbookLandmarkCategory> = Set(RoadbookLandmarkCategory.allCases),
        urbanEntryFallbackEnabled: Bool = RoadBookConstants.landmarkUrbanEntryFallbackEnabled
    ) -> RoadbookLandmarkSelection {
        let cumulative = TrackProjector.cumulativeDistances(for: points)
        guard points.count > 1, (cumulative.last ?? 0) > 0 else { return .empty }

        var placements = data.candidates
            .filter { enabledCategories.contains($0.category) }
            .flatMap { visiblePlacements(of: $0, points: points, cumulative: cumulative) }
        if urbanEntryFallbackEnabled, enabledCategories.contains(.citySign) {
            placements += urbanEntries(data.urbanWays, mappedSigns: placements.filter { $0.info.category == .citySign }, points: points, cumulative: cumulative)
        }

        let maneuverPositions = maneuvers.map(\.cumulativeDistanceMeters)
        var attached: [UUID: Placement] = [:]
        var standalone: [Placement] = []
        // Services : voie à part — jamais rattachés à un virage ni écartés par la densité des
        // repères de repérage (seuls leurs doublons sont fusionnés).
        let services = placements.filter { $0.info.category.group == .service }
        for placement in placements where placement.info.category.group != .service {
            let nearest = maneuvers.indices.min { abs(maneuverPositions[$0] - placement.cumulative) < abs(maneuverPositions[$1] - placement.cumulative) }
            if let nearest, abs(maneuverPositions[nearest] - placement.cumulative) <= RoadBookConstants.landmarkJunctionRadiusMeters {
                let id = maneuvers[nearest].id
                if attached[id].map({ isStronger(placement, than: $0) }) ?? true { attached[id] = placement }
            } else {
                standalone.append(placement)
            }
        }

        return RoadbookLandmarkSelection(
            attached: attached.mapValues(\.info),
            standalone: (densityLimited(standalone, maneuverPositions: maneuverPositions) + deduplicatedServices(services))
                .sorted { $0.cumulative < $1.cumulative }
                .map {
                RoadbookLandmarkCheckpoint(info: $0.info, latitude: $0.coordinate.latitude, longitude: $0.coordinate.longitude, cumulativeDistanceMeters: $0.cumulative)
            }
        )
    }

    // MARK: - Visibilité

    /// Un placement par PASSAGE de la trace à portée du candidat (une boucle revoit la même
    /// église) — côté et sens calculés sur le cap de la trace à cet endroit.
    private static func visiblePlacements(of candidate: RoadbookLandmarkCandidate, points: [GPXPoint], cumulative: [Double]) -> [Placement] {
        guard let radius = RoadBookConstants.landmarkVisibilityRadiusMeters[candidate.category] else { return [] }
        return TrackProjector.passes(of: candidate.coordinate, onto: points, cumulativeDistances: cumulative, maxDistanceMeters: radius).compactMap { pass in
            guard let onTrack = TrackProjector.interpolatedCoordinate(atCumulativeDistance: pass.cumulativeDistanceMeters, points: points, cumulativeDistances: cumulative),
                  let heading = approachHeading(at: pass.cumulativeDistanceMeters, points: points, cumulative: cumulative)
            else { return nil }
            if candidate.category.requiresRoadAlignment, let axes = candidate.roadAxes, !axes.isEmpty,
               !axes.contains(where: { isAligned($0, with: heading) }) { return nil }
            if candidate.category.isDirectional, let orientation = candidate.orientation, !isSeen(orientation, travelHeading: heading) { return nil }
            // Côté seulement pour ce qui est posé À CÔTÉ de la route : un élément qui traverse la
            // chaussée (famille "au sol") ou un nœud de la route elle-même n'en a pas — l'écart
            // mesuré n'y est que celui entre la trace GPS et l'axe de la route.
            let isOnRoad = candidate.category.isOnRoad || !(candidate.roadAxes ?? []).isEmpty
            let side = (isOnRoad || pass.distanceToTrackMeters < RoadBookConstants.landmarkSideMinOffsetMeters)
                ? nil
                : side(of: candidate.coordinate, from: onTrack, travelHeading: heading)
            let showsDistance = candidate.category.group == .service && pass.distanceToTrackMeters >= RoadBookConstants.landmarkServiceShowDistanceFromMeters
            return Placement(
                info: RoadbookLandmarkInfo(category: candidate.category, label: candidate.label, side: side, lateralDistanceMeters: showsDistance ? pass.distanceToTrackMeters : nil),
                coordinate: candidate.coordinate,
                cumulative: pass.cumulativeDistanceMeters,
                lateral: pass.distanceToTrackMeters
            )
        }
    }

    /// Un panneau vu de dos est ignoré.
    private static func isSeen(_ orientation: RoadbookLandmarkCandidate.Orientation, travelHeading: Double) -> Bool {
        switch orientation {
        case .appliesToTravelBearing(let bearing):
            return abs(RoadbookAnalyzer.signedAngleDifference(from: bearing, to: travelHeading)) < 90
        case .faces(let facing):
            return abs(RoadbookAnalyzer.signedAngleDifference(from: facing + 180, to: travelHeading)) <= RoadBookConstants.landmarkSignFacingToleranceDegrees
        }
    }

    /// Cap de la trajectoire d'ARRIVÉE sur le repère (corde des `landmarkApproachMeters` derniers
    /// mètres, robuste aux points dupliqués) — c'est le sens dans lequel le pilote le découvre ; un
    /// panneau au carrefour s'adresse à la route par laquelle on ARRIVE, pas à celle où l'on tourne.
    /// Tout début de trace : corde vers l'avant.
    private static func approachHeading(at c: Double, points: [GPXPoint], cumulative: [Double]) -> Double? {
        let total = cumulative.last ?? 0
        let span = RoadBookConstants.landmarkApproachMeters
        let from = c >= span / 2 ? max(c - span, 0) : c
        let to = c >= span / 2 ? c : min(c + span, total)
        guard let a = TrackProjector.interpolatedCoordinate(atCumulativeDistance: from, points: points, cumulativeDistances: cumulative),
              let b = TrackProjector.interpolatedCoordinate(atCumulativeDistance: to, points: points, cumulativeDistances: cumulative),
              RoadbookAnalyzer.distanceMeters(a, b) > 1
        else { return nil }
        return RoadbookAnalyzer.bearing(from: a, to: b)
    }

    /// Axe de route aligné sur le cap, dans un sens ou dans l'autre.
    private static func isAligned(_ axis: Double, with heading: Double) -> Bool {
        let difference = abs(RoadbookAnalyzer.signedAngleDifference(from: axis, to: heading))
        let tolerance = RoadBookConstants.landmarkRoadAlignmentToleranceDegrees
        return difference <= tolerance || difference >= 180 - tolerance
    }

    private static func side(of target: CLLocationCoordinate2D, from origin: CLLocationCoordinate2D, travelHeading: Double) -> RoadbookLandmarkSide {
        let toTarget = RoadbookAnalyzer.bearing(from: origin, to: target)
        return RoadbookAnalyzer.signedAngleDifference(from: travelHeading, to: toTarget) > 0 ? .right : .left
    }

    // MARK: - Priorité et densité

    private static func rank(_ placement: Placement) -> (Int, Int, Double) {
        let category = placement.info.category
        return (
            RoadBookConstants.landmarkGroupPriority.firstIndex(of: category.group) ?? .max,
            RoadbookLandmarkCategory.allCases.firstIndex(of: category) ?? .max,
            placement.lateral
        )
    }

    private static func isStronger(_ lhs: Placement, than rhs: Placement) -> Bool {
        rank(lhs) < rank(rhs)
    }

    /// Fusion des repères trop proches (le plus prioritaire reste), puis au plus
    /// `landmarkMaxPerSegment` par tronçon entre deux changements de direction.
    private static func densityLimited(_ placements: [Placement], maneuverPositions: [Double]) -> [Placement] {
        var merged: [Placement] = []
        for placement in placements.sorted(by: { $0.cumulative < $1.cumulative }) {
            if let last = merged.last, placement.cumulative - last.cumulative < RoadBookConstants.landmarkMergeMeters {
                if isStronger(placement, than: last) { merged[merged.count - 1] = placement }
            } else {
                merged.append(placement)
            }
        }
        let segments = Dictionary(grouping: merged) { placement in maneuverPositions.filter { $0 < placement.cumulative }.count }
        return segments.values
            .flatMap { $0.sorted(by: isStronger).prefix(RoadBookConstants.landmarkMaxPerSegment) }
            .sorted { $0.cumulative < $1.cumulative }
    }

    /// Doublons d'un même service (nœud + surface, deux bornes d'une même station) : le plus proche
    /// de la trace reste.
    private static func deduplicatedServices(_ services: [Placement]) -> [Placement] {
        var kept: [Placement] = []
        for placement in services.sorted(by: { $0.cumulative < $1.cumulative }) {
            if let index = kept.lastIndex(where: { $0.info.category == placement.info.category && placement.cumulative - $0.cumulative < RoadBookConstants.landmarkServiceMergeMeters }) {
                if placement.lateral < kept[index].lateral { kept[index] = placement }
            } else {
                kept.append(placement)
            }
        }
        return kept
    }

    // MARK: - Repli zone urbaine (désactivé par défaut)

    /// Entrée sur une route urbaine (50 km/h / `FR:urban`) après au moins
    /// `landmarkUrbanEntryMinGapMeters` hors zone urbaine, et loin de tout panneau cartographié.
    private static func urbanEntries(_ urbanWays: [[CLLocationCoordinate2DCodable]], mappedSigns: [Placement], points: [GPXPoint], cumulative: [Double]) -> [Placement] {
        let ways = urbanWays.map { way in way.map { GPXPoint(latitude: $0.latitude, longitude: $0.longitude) } }.filter { $0.count > 1 }
        guard !ways.isEmpty, let total = cumulative.last else { return [] }
        let wayCumulatives = ways.map { TrackProjector.cumulativeDistances(for: $0) }

        func isUrban(_ coordinate: CLLocationCoordinate2D) -> Bool {
            zip(ways, wayCumulatives).contains { way, wayCumulative in
                (TrackProjector.project(coordinate, onto: way, cumulativeDistances: wayCumulative)?.distanceToTrackMeters ?? .infinity) <= RoadBookConstants.landmarkUrbanWayMatchMeters
            }
        }

        var entries: [Placement] = []
        var lastUrbanMeters: Double?
        var meters: Double = 0
        while meters <= total {
            if let coordinate = TrackProjector.interpolatedCoordinate(atCumulativeDistance: meters, points: points, cumulativeDistances: cumulative), isUrban(coordinate) {
                let isEntry = lastUrbanMeters.map { meters - $0 >= RoadBookConstants.landmarkUrbanEntryMinGapMeters } ?? (meters > 0)
                if isEntry, !mappedSigns.contains(where: { abs($0.cumulative - meters) < RoadBookConstants.landmarkUrbanEntryMinGapMeters }) {
                    entries.append(Placement(info: RoadbookLandmarkInfo(category: .citySign, label: RoadbookLandmarkCategory.citySign.genericLabel), coordinate: coordinate, cumulative: meters, lateral: 0))
                }
                lastUrbanMeters = meters
            }
            meters += 20
        }
        return entries
    }
}

/// Une ligne du Road Book : changement de direction OU repère visible, dans l'ordre de
/// progression le long de la trace — seule façon dont les écrans/le PDF les mêlent.
enum RoadbookEntry: Identifiable {
    case maneuver(RoadbookManeuver, index: Int)
    case landmark(RoadbookLandmarkCheckpoint)

    var id: String {
        switch self {
        case .maneuver(let maneuver, _): return "maneuver-\(maneuver.id.uuidString)"
        case .landmark(let landmark): return landmark.id
        }
    }

    var cumulativeDistanceMeters: Double {
        switch self {
        case .maneuver(let maneuver, _): return maneuver.cumulativeDistanceMeters
        case .landmark(let landmark): return landmark.cumulativeDistanceMeters
        }
    }

    /// `index` = rang de la manœuvre dans la liste des manœuvres (numérotation affichée
    /// inchangée : un repère n'est pas une manœuvre numérotée). À distance égale, la manœuvre
    /// passe avant le repère.
    static func merge(maneuvers: [RoadbookManeuver], landmarks: [RoadbookLandmarkCheckpoint]) -> [RoadbookEntry] {
        let entries = maneuvers.enumerated().map { RoadbookEntry.maneuver($0.element, index: $0.offset) }
            + landmarks.map { RoadbookEntry.landmark($0) }
        return entries.enumerated().sorted { lhs, rhs in
            let l = lhs.element.cumulativeDistanceMeters
            let r = rhs.element.cumulativeDistanceMeters
            return l == r ? lhs.offset < rhs.offset : l < r
        }.map(\.element)
    }
}
