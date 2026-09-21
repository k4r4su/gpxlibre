import UIKit

/// Coordonne `UIApplication.shared.isIdleTimerDisabled` entre PLUSIEURS écrans qui peuvent
/// chacun vouloir empêcher la mise en veille indépendamment (Ride, Road Book...) — spec
/// "roadbook-keep-screen-awake", it25, retour terrain : "l'écran doit rester allumé dans road
/// book, il a tendance à s'arrêter". Un ENSEMBLE de raisons actives plutôt qu'un flag unique
/// direct : sans ça, quitter le Road Book couperait le maintien réveillé demandé par un Ride
/// TOUJOURS actif en arrière-plan (le Ride continue d'enregistrer même quand un autre onglet est
/// affiché — voir `RideSessionManager.isActive`, indépendant de la visibilité de l'onglet), et
/// inversement. Le désactiver ne redevient donc effectif QUE quand plus AUCUN écran n'en a besoin.
enum IdleTimerReason: Hashable {
    case ride
    case roadBook
}

@MainActor
enum IdleTimerCoordinator {
    private static var activeReasons: Set<IdleTimerReason> = []

    static func setActive(_ isActive: Bool, for reason: IdleTimerReason) {
        if isActive {
            activeReasons.insert(reason)
        } else {
            activeReasons.remove(reason)
        }
        UIApplication.shared.isIdleTimerDisabled = !activeReasons.isEmpty
    }
}
