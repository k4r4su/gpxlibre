import Foundation
import CoreLocation

/// Détection de pente forte le long d'une trace (spec "slope-warning-native", it19) — logique
/// pure, aucune dépendance à MapLibre/UIKit, même patron que `DirectionChevronComputer`/
/// `RoadbookAnalyzer`. Détection NATIVE (élévation déjà disponible sur `GPXPoint.elevation`) :
/// décision tranchée avec le propriétaire plutôt que d'ajouter le package tiers GPXKit, qui
/// aurait violé la règle du projet "MapLibre est la SEULE dépendance tierce autorisée" (voir
/// project.yml) — GPXKit offre une détection de dénivelé/pente comparable, mais le calcul reste
/// simple (delta d'élévation / distance horizontale) pour un besoin qui ne demande pas son
/// algorithme complet de détection de côtes (scores FIETS, etc., hors périmètre ici).
enum SlopeAnalyzer {
    /// Symbole PONCTUEL (jamais un dégradé continu, demande explicite du prompt) — posé à la
    /// fin de la fenêtre où la pente a été mesurée.
    struct SlopeWarning: Equatable {
        let coordinate: CLLocationCoordinate2D
        /// Signé : positif = montée, négatif = descente.
        let gradePercent: Double
        let sourcePointIndex: Int

        var isClimbing: Bool { gradePercent > 0 }

        static func == (lhs: SlopeWarning, rhs: SlopeWarning) -> Bool {
            lhs.coordinate.latitude == rhs.coordinate.latitude
                && lhs.coordinate.longitude == rhs.coordinate.longitude
                && lhs.gradePercent == rhs.gradePercent
                && lhs.sourcePointIndex == rhs.sourcePointIndex
        }
    }

    /// Découpe la trace en fenêtres consécutives NON chevauchantes d'au moins
    /// `minSegmentMeters` (évite les pentes aberrantes mesurées sur quelques mètres, bruit GPS/
    /// altimétrique) ; une fenêtre dont la pente moyenne dépasse `thresholdPercent` (en valeur
    /// absolue, montée OU descente) pose un symbole à son point final — au minimum
    /// `minMarkerSpacingMeters` après le précédent, pour ne jamais empiler des triangles sur une
    /// longue pente régulière.
    static func steepGradeWarnings(
        for points: [GPXPoint],
        thresholdPercent: Double,
        minSegmentMeters: Double,
        minMarkerSpacingMeters: Double
    ) -> [SlopeWarning] {
        guard points.count > 1, thresholdPercent > 0 else { return [] }

        var warnings: [SlopeWarning] = []
        var windowStartIndex = 0
        var windowDistance: Double = 0
        var cumulativeDistance: Double = 0
        var lastMarkerCumulativeDistance = -Double.greatestFiniteMagnitude

        for i in 1..<points.count {
            let segmentDistance = RoadbookAnalyzer.distanceMeters(points[i - 1].coordinate, points[i].coordinate)
            cumulativeDistance += segmentDistance
            windowDistance += segmentDistance

            guard windowDistance >= minSegmentMeters else { continue }
            defer {
                windowStartIndex = i
                windowDistance = 0
            }

            guard let startElevation = points[windowStartIndex].elevation, let endElevation = points[i].elevation else { continue }
            let gradePercent = (endElevation - startElevation) / windowDistance * 100
            guard abs(gradePercent) >= thresholdPercent else { continue }
            guard cumulativeDistance - lastMarkerCumulativeDistance >= minMarkerSpacingMeters else { continue }

            lastMarkerCumulativeDistance = cumulativeDistance
            warnings.append(SlopeWarning(coordinate: points[i].coordinate, gradePercent: gradePercent, sourcePointIndex: i))
        }
        return warnings
    }
}
