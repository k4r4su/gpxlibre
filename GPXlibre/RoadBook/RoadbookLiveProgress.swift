import Foundation

/// Calcul PUR de la manœuvre à venir en mode Assisté GPS (spec "roadbook-mode", it23, point 1)
/// — prend une distance cumulée déjà projetée (voir `TrackProjector.project`) et la liste de
/// manœuvres, ne touche JAMAIS à cette liste : le mode Assisté GPS calcule un index/une
/// distance restante EN PLUS, jamais en mutant `[RoadbookManeuver]` elle-même. C'est cette
/// séparation qui garantit qu'aucun état parasite ne fuit entre les deux modes de lecture — le
/// mode Roadbook classique affiche EXACTEMENT la même liste, simplement sans jamais appeler
/// cette fonction.
enum RoadbookLiveProgress {
    /// Première manœuvre dont la distance cumulée dépasse la position courante d'au moins
    /// `RoadBookConstants.liveManeuverReachedRadiusMeters` — jamais une manœuvre déjà dépassée
    /// (le rayon évite qu'une manœuvre "juste franchie" reste ciblée à cause du bruit GPS).
    /// `nil` si aucune manœuvre à venir (dernière manœuvre déjà passée, ou liste vide).
    static func nextManeuver(
        maneuvers: [RoadbookManeuver],
        currentCumulativeDistanceMeters: Double
    ) -> (index: Int, distanceRemainingMeters: Double)? {
        guard let index = maneuvers.firstIndex(where: {
            $0.cumulativeDistanceMeters > currentCumulativeDistanceMeters + RoadBookConstants.liveManeuverReachedRadiusMeters
        }) else { return nil }
        let distance = maneuvers[index].cumulativeDistanceMeters - currentCumulativeDistanceMeters
        return (index, max(distance, 0))
    }
}
