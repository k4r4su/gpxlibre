import Foundation
import CoreLocation

/// Spec "manual-point-guidance-exclusivity" (it22) — "un seul guidage actif à la fois" : une
/// destination manuelle (tap long sur la carte, ou recherche "Aller à") et le guidage de trace
/// GPX (roadbook + reprise automatique/manuelle) ne doivent jamais tourner en même temps.
/// DISTINCT de l'état de trace unique `LibraryStore.activeTrackID`/`displayedTrackIDs`
/// (invariant it10, régit l'AFFICHAGE de la trace sur la carte) — la trace reste affichée même
/// quand `guidanceTarget` vaut `.manualPoint`, seul son GUIDAGE (roadbook, reprise) se met en
/// pause. Calculé (pas stocké séparément) depuis l'état canonique déjà existant sur
/// `RideSessionManager` (`navDestinationCoordinate`/`goToGuidance`/`track`) — "unique source de
/// vérité" au sens propre : jamais une seconde variable à resynchroniser avec la première.
enum GuidanceTarget: Equatable {
    case trace
    case manualPoint(CLLocationCoordinate2D)
    case none

    static func == (lhs: GuidanceTarget, rhs: GuidanceTarget) -> Bool {
        switch (lhs, rhs) {
        case (.trace, .trace), (.none, .none):
            return true
        case (.manualPoint(let a), .manualPoint(let b)):
            return a.latitude == b.latitude && a.longitude == b.longitude
        default:
            return false
        }
    }
}
