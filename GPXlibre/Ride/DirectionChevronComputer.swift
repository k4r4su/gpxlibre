import Foundation
import CoreLocation

/// Calcule les positions + caps des chevrons de direction le long d'une trace, une seule
/// fois par (trace, espacement) — spec "per-track-settings" : "depuis n'importe quel point le
/// long de la trace, le sens est lisible < 1 s sans zoomer". Jamais recalculé par frame (Bloc
/// 6, performance) : voir RideMapLibreView.updateChevronShape, qui ne réinvoque ceci que si
/// la trace ou l'espacement a réellement changé.
enum DirectionChevronComputer {
    struct Chevron {
        let coordinate: CLLocationCoordinate2D
        let bearingDegrees: Double
    }

    /// Palier (borne basse incluse) → espacement (m) — spec "chevrons-zoom-adaptive", it17,
    /// Bloc 3. Bug corrigé : les chevrons disparaissaient totalement en dessous d'un seuil de
    /// zoom fixe sur la couche (`minimumZoomLevel`), une coupure binaire plutôt qu'une densité
    /// progressive. Cette table pilote désormais UNIQUEMENT quelles données existent dans la
    /// source (voir `adaptiveSpacingMeters` + `RideMapLibreView.updateChevronShape`), la couche
    /// elle-même n'a plus de `minimumZoomLevel` — jamais masquée, seulement plus clairsemée.
    static let zoomSpacingTable: [(minZoom: Double, spacingMeters: Double)] = [
        (14, 100),
        (12, 500),
        (10, 1_000),
        (8, 5_000),
        (5, 10_000),
        (-.infinity, 20_000)
    ]

    /// Espacement effectif à un zoom donné — le PLUS GRAND des deux : l'espacement réglé par
    /// l'utilisateur pour cette trace (`configuredSpacingMeters`, réglage existant depuis it11,
    /// jamais perdu) reste la référence tant que le zoom courant n'exige pas plus large ; passé
    /// un certain dézoom, la table ci-dessus prend le relais pour éviter la bouillie visuelle
    /// (et implicitement, empêcher la disparition — la table ne descend jamais à 0).
    static func adaptiveSpacingMeters(configuredSpacingMeters: Double, zoomLevel: Double) -> Double {
        let zoomFloorSpacing = zoomSpacingTable.first { zoomLevel >= $0.minZoom }?.spacingMeters
            ?? zoomSpacingTable.last!.spacingMeters
        return max(configuredSpacingMeters, zoomFloorSpacing)
    }

    static func chevrons(for points: [GPXPoint], spacingMeters: Double) -> [Chevron] {
        guard points.count > 1, spacingMeters > 0 else { return [] }
        var result: [Chevron] = []
        var accumulated: Double = 0
        var nextTarget = spacingMeters

        for i in 1..<points.count {
            let segmentStart = points[i - 1].coordinate
            let segmentEnd = points[i].coordinate
            let segmentLength = RoadbookAnalyzer.distanceMeters(segmentStart, segmentEnd)
            guard segmentLength > 0 else { continue }
            let bearing = RoadbookAnalyzer.bearing(from: segmentStart, to: segmentEnd)

            while accumulated + segmentLength >= nextTarget {
                let t = (nextTarget - accumulated) / segmentLength
                let coordinate = CLLocationCoordinate2D(
                    latitude: segmentStart.latitude + (segmentEnd.latitude - segmentStart.latitude) * t,
                    longitude: segmentStart.longitude + (segmentEnd.longitude - segmentStart.longitude) * t
                )
                result.append(Chevron(coordinate: coordinate, bearingDegrees: bearing))
                nextTarget += spacingMeters
            }
            accumulated += segmentLength
        }
        return result
    }
}
