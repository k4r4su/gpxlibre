import Foundation

/// Calcul PUR de la manœuvre à venir en mode Assisté GPS (spec "roadbook-mode", it23, point 1)
/// — prend une distance cumulée déjà projetée (voir `TrackProjector.project`) et la liste de
/// manœuvres, ne touche JAMAIS à cette liste : le mode Assisté GPS calcule un index/une
/// distance restante EN PLUS, jamais en mutant `[RoadbookManeuver]` elle-même. C'est cette
/// séparation qui garantit qu'aucun état parasite ne fuit entre les deux modes de lecture — le
/// mode Roadbook classique affiche EXACTEMENT la même liste, simplement sans jamais appeler
/// cette fonction.
///
/// Fix "roadbook-live-progress-hold" (retour terrain : "la direction change 15/20 m avant le
/// virage, j'aimerais qu'une fois arrivé à zéro, la direction reste encore 10/20 m après le
/// virage, sauf si les virages s'enchaînent") — root cause de l'ancien comportement :
/// `nextManeuver` cherchait la première manœuvre dont la distance cumulée dépassait la position
/// actuelle d'au moins `liveManeuverReachedRadiusMeters` (40 m), ce qui faisait basculer
/// l'affichage sur la manœuvre SUIVANTE 40 m AVANT d'avoir réellement atteint la manœuvre en
/// cours. Désormais : countdown normal jusqu'à 0 m, puis maintien de la manœuvre ATTEINTE
/// pendant `RoadBookConstants.liveManeuverHoldAfterMeters`, sauf si la manœuvre suivante est
/// elle-même plus proche que cette zone de maintien (virages enchaînés) — dans ce cas, basculer
/// immédiatement plutôt que de retarder artificiellement une instruction déjà pertinente.
enum RoadbookLiveProgress {
    /// `nil` si aucune manœuvre à venir (dernière manœuvre déjà passée au-delà de la zone de
    /// maintien, ou liste vide).
    static func nextManeuver(
        maneuvers: [RoadbookManeuver],
        currentCumulativeDistanceMeters: Double
    ) -> (index: Int, distanceRemainingMeters: Double)? {
        next(positions: maneuvers.map(\.cumulativeDistanceMeters), currentCumulativeDistanceMeters: currentCumulativeDistanceMeters)
    }

    /// Prochain élément du Road Book, TOUS TYPES CONFONDUS (it30, "priorité par ordre
    /// d'arrivée") — virage OU repère (stop, feux, entrée d'agglomération...) : seul l'ordre le
    /// long de la trace compte, aucune catégorie n'a de priorité. Un stop à 200 m passe avant un
    /// virage à 300 m. Même compte à rebours, même maintien et même exception "virages
    /// enchaînés" que pour les manœuvres. `entries` : `RoadbookEntry.merge`, déjà dans l'ordre.
    static func nextEntry(
        entries: [RoadbookEntry],
        currentCumulativeDistanceMeters: Double
    ) -> (index: Int, distanceRemainingMeters: Double)? {
        next(positions: entries.map(\.cumulativeDistanceMeters), currentCumulativeDistanceMeters: currentCumulativeDistanceMeters)
    }

    /// Positions (distances cumulées) croissantes.
    private static func next(positions: [Double], currentCumulativeDistanceMeters: Double) -> (index: Int, distanceRemainingMeters: Double)? {
        guard let first = positions.first else { return nil }

        guard let reachedIndex = positions.lastIndex(where: { $0 <= currentCumulativeDistanceMeters }) else {
            // Rien atteint encore — le tout premier élément de la trace, countdown normal.
            return (0, max(first - currentCumulativeDistanceMeters, 0))
        }

        let distancePastReached = currentCumulativeDistanceMeters - positions[reachedIndex]
        let nextIndex = reachedIndex + 1

        guard positions.indices.contains(nextIndex) else {
            // Dernière manœuvre de la trace : maintenue affichée (figée à "0 m") pendant la
            // zone de grâce, puis `nil` (toutes les manœuvres sont passées) — comportement de
            // fin de trace inchangé au-delà de cette fenêtre.
            return distancePastReached < RoadBookConstants.liveManeuverHoldAfterMeters ? (reachedIndex, 0) : nil
        }

        let gapToNext = positions[nextIndex] - positions[reachedIndex]
        // Virages enchaînés (demande explicite : "sauf si les virages s'enchaînent") — la
        // manœuvre suivante est déjà plus proche que la zone de maintien elle-même : basculer
        // tout de suite plutôt que de retarder une instruction déjà imminente.
        if distancePastReached < RoadBookConstants.liveManeuverHoldAfterMeters, gapToNext > RoadBookConstants.liveManeuverHoldAfterMeters {
            return (reachedIndex, 0)
        }

        let distance = positions[nextIndex] - currentCumulativeDistanceMeters
        return (nextIndex, max(distance, 0))
    }
}
