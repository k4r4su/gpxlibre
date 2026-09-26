import Foundation
import CoreLocation

/// Entrée de localité calculée (repli it29) — là où la trace entre dans une zone bâtie nommée.
struct RoadbookCityEntry: Equatable {
    let name: String
    let coordinate: CLLocationCoordinate2D
    let cumulativeDistanceMeters: Double

    /// "Entrée de Ferrette", "Entrée d'Illtal" — position ESTIMÉE (bord de la zone bâtie), d'où un
    /// libellé distinct du nom seul affiché pour un vrai panneau cartographié.
    var label: String { Self.label(for: name) }

    static func label(for name: String) -> String {
        let elides = name.first.map { "AEIOUYÂÀÉÈÊËÎÏÔÖÛÜŒaeiouyâàéèêëîïôöûüœ".contains($0) } ?? false
        return elides ? String(localized: "Entrée d’\(name)", bundle: .appLanguage) : String(localized: "Entrée de \(name)", bundle: .appLanguage)
    }

    static func == (lhs: RoadbookCityEntry, rhs: RoadbookCityEntry) -> Bool {
        lhs.name == rhs.name && lhs.cumulativeDistanceMeters == rhs.cumulativeDistanceMeters
    }
}

/// Repli "Entrée de <localité>" (it29) — PUR, aucun réseau. Diagnostic sur la trace de test réelle :
/// les panneaux `city_limit` ne sont presque jamais cartographiés dans OSM (un sur onze villages),
/// alors que les zones bâties (`landuse=residential`) et les nœuds `place` le sont partout. Le
/// panneau réel se dresse au bord de la zone bâtie : c'est là que l'entrée est placée.
///
/// Trace DÉJÀ dans son sens de parcours. Règles (constantes `RoadBookConstants.landmarkCityEntry*`) :
/// - passages en zone bâtie regroupés en traversées s'ils sont séparés de moins de `MergeGapMeters`,
///   traversée ignorée si plus courte que `MinRunMeters` (ferme isolée) ; une entrée au début de
///   la traversée PUIS à chaque changement de localité à l'intérieur (villages mitoyens) ; jamais
///   une "entrée" au tout début de la trace ;
/// - nom : celui du polygone `place` traversé s'il existe, sinon le nœud `place` le plus proche du
///   point d'entrée (dans sa portée `PlaceReachMeters` ; quartier seulement hors de portée d'une ville) ; sans nom, rien ;
/// - un panneau cartographié gagne s'il est à moins de `SignDedupMeters`, ou s'il porte le nom de la
///   même localité dans la même traversée ; jamais deux entrées de suite dans la même localité
///   (panneau compris).
enum RoadbookCityEntryDetector {
    private struct Ring {
        let points: [CLLocationCoordinate2D]
        let minLat: Double, maxLat: Double, minLon: Double, maxLon: Double
        let name: String?

        init?(_ coordinates: [CLLocationCoordinate2DCodable], name: String?) {
            let points = coordinates.map { CLLocationCoordinate2D(latitude: $0.latitude, longitude: $0.longitude) }
            guard points.count >= 3 else { return nil }
            self.points = points
            self.name = name
            minLat = points.map(\.latitude).min() ?? 0
            maxLat = points.map(\.latitude).max() ?? 0
            minLon = points.map(\.longitude).min() ?? 0
            maxLon = points.map(\.longitude).max() ?? 0
        }

        /// Pair-impair (lancer de rayon), après un test de boîte englobante.
        func contains(_ p: CLLocationCoordinate2D) -> Bool {
            guard p.latitude >= minLat, p.latitude <= maxLat, p.longitude >= minLon, p.longitude <= maxLon else { return false }
            var inside = false
            var j = points.count - 1
            for i in points.indices {
                let a = points[i], b = points[j]
                if (a.latitude > p.latitude) != (b.latitude > p.latitude),
                   p.longitude < (b.longitude - a.longitude) * (p.latitude - a.latitude) / (b.latitude - a.latitude) + a.longitude {
                    inside.toggle()
                }
                j = i
            }
            return inside
        }
    }

    private struct Run {
        var start: Double
        var end: Double
        var areaName: String?
    }

    static func entries(
        areas: [RoadbookBuiltUpArea],
        places: [RoadbookPlace],
        mappedSigns: [(cumulative: Double, name: String)],
        points: [GPXPoint],
        cumulative: [Double]
    ) -> [RoadbookCityEntry] {
        let rings = areas.flatMap { area in area.rings.compactMap { Ring($0, name: area.name) } }
        guard !rings.isEmpty, points.count > 1, let total = cumulative.last, total > 0 else { return [] }

        let step = RoadBookConstants.landmarkCityEntrySampleMeters
        func coordinate(at meters: Double) -> CLLocationCoordinate2D? {
            TrackProjector.interpolatedCoordinate(atCumulativeDistance: meters, points: points, cumulativeDistances: cumulative)
        }

        // Passages en zone bâtie (échantillons consécutifs à l'intérieur).
        var runs: [Run] = []
        var meters: Double = 0
        while meters <= total {
            if let p = coordinate(at: meters), rings.contains(where: { $0.contains(p) }) {
                let named = rings.first { $0.name != nil && $0.contains(p) }?.name
                if var last = runs.last, meters - last.end <= step * 1.5 {
                    last.end = meters
                    last.areaName = last.areaName ?? named
                    runs[runs.count - 1] = last
                } else {
                    runs.append(Run(start: meters, end: meters, areaName: named))
                }
            }
            meters += step
        }

        // Traversées : passages séparés de moins de `MergeGapMeters` (zones résidentielles
        // morcelées d'un même village, ou villages mitoyens).
        var traversals: [[Run]] = []
        for run in runs {
            if let last = traversals.last?.last, run.start - last.end <= RoadBookConstants.landmarkCityEntryMergeGapMeters {
                traversals[traversals.count - 1].append(run)
            } else {
                traversals.append([run])
            }
        }

        var entries: [RoadbookCityEntry] = []
        var announced: [(cumulative: Double, name: String)] = mappedSigns
        for traversal in traversals {
            guard let first = traversal.first, let last = traversal.last,
                  last.end - first.start >= RoadBookConstants.landmarkCityEntryMinRunMeters
            else { continue }
            // Localité le long de la traversée (tous les `NameCheckMeters`) : l'entrée, puis chaque
            // CHANGEMENT de localité à l'intérieur — villages mitoyens (Ferrette puis Vieux-Ferrette,
            // Uffheim puis Sierentz) dont les zones bâties se touchent ou n'en font qu'une.
            var segments: [(start: Double, end: Double, name: String, coordinate: CLLocationCoordinate2D)] = []
            for run in traversal {
                var m = run.start
                while m <= run.end {
                    if let p = coordinate(at: m), let name = run.areaName ?? placeName(near: p, places: places) {
                        if let lastSegment = segments.last, lastSegment.name == name {
                            segments[segments.count - 1].end = m
                        } else {
                            segments.append((m, m, name, p))
                        }
                    }
                    m += RoadBookConstants.landmarkCityEntryNameCheckMeters
                }
            }
            // Hystérésis : un changement de localité qui ne dure pas n'en est pas un.
            let stable = segments.enumerated().filter { $0.offset == 0 || $0.element.end - $0.element.start >= RoadBookConstants.landmarkCityEntryNameMinStretchMeters }.map(\.element)

            for segment in stable {
                let name = segment.name
                let previous = announced.filter { $0.cumulative < segment.start }.max { $0.cumulative < $1.cumulative }
                if previous?.name == name { continue }
                // Trace qui DÉMARRE dans la localité : pas une entrée, mais on y est.
                if segment.start < step {
                    announced.append((segment.start, name))
                    continue
                }
                // Le panneau cartographié prime : tout près, ou de la même localité dans cette traversée.
                let dedup = RoadBookConstants.landmarkCityEntrySignDedupMeters
                if mappedSigns.contains(where: { abs($0.cumulative - segment.start) < dedup || ($0.name == name && $0.cumulative >= first.start - dedup && $0.cumulative <= last.end + dedup) }) {
                    continue
                }
                entries.append(RoadbookCityEntry(name: name, coordinate: segment.coordinate, cumulativeDistanceMeters: segment.start))
                announced.append((segment.start, name))
            }
        }
        return entries
    }

    /// Localité la plus proche du point d'entrée. Un quartier (`suburb`) n'est candidat que si
    /// aucune ville n'est proche : on entre dans "Mulhouse", pas dans l'un de ses quartiers.
    ///
    /// Commune nouvelle (Illtal = Oberdorf + Grentzingen + Henflingen) : son nœud `village` est posé
    /// sur l'un des anciens villages, cartographiés en `suburb` — les panneaux portent les noms des
    /// anciens villages. Un `village` qui a un `suburb` à moins de `ParentSeatMeters` est ce siège :
    /// écarté au profit des `suburb`.
    static func placeName(near coordinate: CLLocationCoordinate2D, places: [RoadbookPlace]) -> String? {
        func reach(_ place: RoadbookPlace) -> Double { RoadBookConstants.landmarkCityEntryPlaceReachMeters[place.kind] ?? 0 }
        let withDistance = places.map { ($0, RoadbookAnalyzer.distanceMeters(coordinate, $0.coordinate)) }.filter { $0.1 <= reach($0.0) }
        let nearCity = withDistance.contains { [.town, .city].contains($0.0.kind) }
        func isMergedCommuneSeat(_ place: RoadbookPlace) -> Bool {
            place.kind == .village && places.contains { $0.kind == .suburb && RoadbookAnalyzer.distanceMeters($0.coordinate, place.coordinate) <= RoadBookConstants.landmarkCityEntryParentSeatMeters }
        }
        return withDistance
            .filter { nearCity ? $0.0.kind != .suburb : !isMergedCommuneSeat($0.0) }
            .min { $0.1 < $1.1 }?
            .0.name
    }
}
