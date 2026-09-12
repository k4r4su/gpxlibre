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
