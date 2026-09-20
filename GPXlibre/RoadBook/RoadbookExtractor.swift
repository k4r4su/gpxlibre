import Foundation

/// Construit la liste ORDONNÉE de manœuvres d'un Road Book à partir d'une trace (spec
/// "roadbook-mode", it23, point 1) — RÉUTILISE `RoadbookAnalyzer.buildRoadbookEvents`
/// (détection de virage existante, it14, paliers 30/45/90/135°) et
/// `TrackProjector.cumulativeDistances` (distance cumulée par point de trace) SANS nouvelle
/// logique de détection ("pas de nouvelle logique de détection à ce stade", demande explicite
/// de la fiche) : ce fichier ne fait qu'ASSEMBLER les distances partielle/cumulée autour de la
/// liste de checkpoints déjà produite ailleurs — seule vraie nouveauté ici.
///
/// Pure et testable, AUCUNE dépendance à `RideSessionManager`/`LibraryStore` — prend une
/// `GPXTrack` en entrée, ne lit ni n'écrit aucun état partagé. C'est cette pureté qui garantit
/// l'invariant "Road Book totalement découplé de l'état de Ride actif" (spec) : rien ici ne
/// PEUT toucher `GuidanceTarget` (it22) ni l'invariant trace unique `activeTrackID`/
/// `displayedTrackIDs` (it10), puisque ce module n'y a tout simplement pas accès.
enum RoadbookExtractor {
    static func maneuvers(
        for track: GPXTrack,
        windowBeforeMeters: Double,
        windowAfterMeters: Double,
        lightThresholdDegrees: Double,
        markedThresholdDegrees: Double,
        hardThresholdDegrees: Double,
        uTurnThresholdDegrees: Double,
        mergeMinDistanceMeters: Double
    ) -> [RoadbookManeuver] {
        let checkpoints = RoadbookAnalyzer.buildRoadbookEvents(
            for: track,
            windowBeforeMeters: windowBeforeMeters,
            windowAfterMeters: windowAfterMeters,
            lightThresholdDegrees: lightThresholdDegrees,
            markedThresholdDegrees: markedThresholdDegrees,
            hardThresholdDegrees: hardThresholdDegrees,
            uTurnThresholdDegrees: uTurnThresholdDegrees,
            mergeMinDistanceMeters: mergeMinDistanceMeters
        )
        // Trace sans aucun changement de direction (ou trop courte pour buildRoadbookEvents,
        // voir son garde `points.count > 2`) → liste vide, jamais un crash ni un repli sur un
        // "point de départ" fictif.
        guard !checkpoints.isEmpty else { return [] }

        let cumulativeDistances = TrackProjector.cumulativeDistances(for: track.points)
        var previousCumulative: Double = 0
        return checkpoints.map { checkpoint in
            // `sourcePointIndex` est toujours un index valide de `track.points` (produit par
            // `RoadbookAnalyzer` lui-même à partir de la même trace) — le repli sur
            // `previousCumulative` ne sert qu'à ne jamais planter si cette garantie venait à
            // changer un jour, jamais un cas attendu en usage normal.
            let cumulative = cumulativeDistances.indices.contains(checkpoint.sourcePointIndex)
                ? cumulativeDistances[checkpoint.sourcePointIndex]
                : previousCumulative
            let partial = max(cumulative - previousCumulative, 0)
            previousCumulative = cumulative
            return RoadbookManeuver(
                checkpoint: checkpoint,
                partialDistanceMeters: partial,
                cumulativeDistanceMeters: cumulative,
                headingDegrees: outgoingHeadingDegrees(at: checkpoint.sourcePointIndex, in: track.points)
            )
        }
    }

    /// Cap du segment SORTANT (juste après le point de manœuvre) — bearing brut entre ce point
    /// et le suivant, jamais une moyenne lissée sur une fenêtre (le cap affiché doit refléter la
    /// direction IMMÉDIATE à prendre en sortant du virage, pas une tendance générale). Replie
    /// sur le segment ENTRANT si le point de manœuvre est le dernier de la trace (pas de point
    /// suivant) — cas limite, jamais un crash.
    private static func outgoingHeadingDegrees(at pointIndex: Int, in points: [GPXPoint]) -> Double {
        guard points.count > 1 else { return 0 }
        if points.indices.contains(pointIndex + 1) {
            return RoadbookAnalyzer.bearing(from: points[pointIndex].coordinate, to: points[pointIndex + 1].coordinate)
        }
        let previousIndex = max(pointIndex - 1, 0)
        return RoadbookAnalyzer.bearing(from: points[previousIndex].coordinate, to: points[pointIndex].coordinate)
    }
}
