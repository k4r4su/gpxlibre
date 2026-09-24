import Foundation

/// Décide, à chaque mise à jour de la carte Ride, ce que fait la caméra — logique pure extraite
/// de `RideMapLibreView.updateUIView` pour être testable (fix "roadbook-jump-to-map-sticky", it26
/// point 4).
///
/// Retour terrain : "le tap sur une étape saute vers la bonne position une fois sur deux ; et
/// quand il fonctionne, la carte revient d'elle-même sur la position GPS après quelques
/// secondes". Cause unique des deux symptômes : le saut ne suspendait le suivi GPS qu'à travers
/// la fenêtre générique d'un geste manuel (`registerManualGesture`, 5 s), posée APRÈS le rendu qui
/// applique le saut — dans ce même rendu, le bloc de suivi recentrait aussitôt sur le GPS (sauf
/// geste manuel de moins de 5 s, d'où "une fois sur deux"), puis la fenêtre expirait (retour
/// automatique). Le mode "étape Road Book" suspend désormais le suivi sans minuteur, jusqu'à "Me
/// recentrer".
enum RideCameraFollowPolicy {
    enum Decision: Equatable {
        /// Ne rien toucher : la caméra reste où elle est (saut vers l'étape en cours, carte
        /// explorée à la main, étape Road Book affichée).
        case keepCamera
        /// Suivi normal : centrée sur la position GPS.
        case followCurrentLocation
        /// Commande explicite (+/-) pendant que le suivi est suspendu : appliquée autour du
        /// centre ACTUEL de l'écran, jamais un retour sur le GPS (fix "explore-zoom-anchoring", it14).
        case applyCommandAroundScreenCenter
    }

    static func decide(
        isForcedCommand: Bool,
        isManualOverrideActive: Bool,
        isRoadBookFocusActive: Bool,
        didJumpToRoadBookFocus: Bool
    ) -> Decision {
        // Le saut vient d'être lancé dans cette même mise à jour : rien ne doit l'écraser.
        if didJumpToRoadBookFocus { return .keepCamera }
        let isFollowSuspended = isManualOverrideActive || isRoadBookFocusActive
        if isForcedCommand {
            return isFollowSuspended ? .applyCommandAroundScreenCenter : .followCurrentLocation
        }
        return isFollowSuspended ? .keepCamera : .followCurrentLocation
    }
}
