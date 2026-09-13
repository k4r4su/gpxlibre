import Foundation
import CoreLocation

/// Géométrie pure pour la miniature directionnelle Biblio (spec "biblio-preview-direction",
/// it11). Projette une trace déjà en mémoire (déjà réordonnée via `GPXTrack.reordered(using:)`
/// — jamais recalculée depuis un rescan GPS) dans un repère normalisé [0,1]×[0,1], origine
/// haut-gauche (repère écran SwiftUI), pour un dessin `Canvas` léger — pas de tuile, pas de
/// MapKit.
///
/// Projection équirectangulaire locale (même esprit que `GPXTrack.boundingRegion`, adapté à
/// l'étendue réduite d'une seule trace) : la longitude est compressée par `cos(latitude
/// moyenne)` pour que les angles restent visuellement fidèles à la réalité — sans cette
/// correction, une trace nord-sud parfaitement rectiligne s'étirerait en diagonale aux
/// latitudes élevées. Cette même correction rend les caps des chevrons directement
/// réutilisables sans transformation d'angle séparée (approximation localement conforme,
/// valable sur l'étendue d'une trace individuelle).
enum TrackThumbnailGeometry {
    struct ProjectedChevron {
        let point: CGPoint
        let bearingDegrees: Double
    }

    struct Projection {
        /// Points normalisés [0,1]×[0,1] de la trace, dans l'ordre de parcours actif.
        let points: [CGPoint]
        let chevrons: [ProjectedChevron]
    }

    /// - Parameter chevronSpacingMeters: l'espacement ACTUEL de la trace (réglage par trace,
    ///   pas un défaut fixe) — spec "chevrons de direction actifs (espacement actuel)".
    static func project(points trackPoints: [GPXPoint], chevronSpacingMeters: Double) -> Projection {
        guard !trackPoints.isEmpty else { return Projection(points: [], chevrons: []) }

        let lats = trackPoints.map(\.latitude)
        let lons = trackPoints.map(\.longitude)
        guard let minLat = lats.min(), let maxLat = lats.max(),
              let minLon = lons.min(), let maxLon = lons.max() else {
            return Projection(points: [], chevrons: [])
        }

        let midLat = (minLat + maxLat) / 2
        let midLon = (minLon + maxLon) / 2
        let longitudeCorrection = cos(midLat * .pi / 180)
        let latSpan = max(maxLat - minLat, 0.0001)
        let lonSpan = max((maxLon - minLon) * longitudeCorrection, 0.0001)
        // Repère carré (même échelle X/Y) : la plus grande étendue des deux fixe le zoom,
        // l'autre axe reste centré — pas d'étirement anisotrope.
        let span = max(latSpan, lonSpan)

        func normalize(_ coordinate: CLLocationCoordinate2D) -> CGPoint {
            let x = 0.5 + (coordinate.longitude - midLon) * longitudeCorrection / span
            let y = 0.5 - (coordinate.latitude - midLat) / span
            return CGPoint(x: x, y: y)
        }

        let points = trackPoints.map { normalize($0.coordinate) }
        let chevrons = DirectionChevronComputer.chevrons(for: trackPoints, spacingMeters: chevronSpacingMeters)
            .map { ProjectedChevron(point: normalize($0.coordinate), bearingDegrees: $0.bearingDegrees) }

        return Projection(points: points, chevrons: chevrons)
    }
}
