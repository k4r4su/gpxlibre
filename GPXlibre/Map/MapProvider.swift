import SwiftUI
import CoreLocation

/// Contrat commun aux moteurs de carte du mode Ride. MapLibre (`RideMapLibreView`) est le
/// moteur actif par défaut (tuiles OSM, hors-ligne à terme) ; MapKit (`RideMapView`) reste
/// dans le projet, conforme au même contrat, pour comparaison — ni supprimé, ni désactivé,
/// juste non sélectionné (voir `MapEngineConstants.active`).
protocol MapProvider: View {
    init(
        track: GPXTrack?,
        checkpoints: [Checkpoint],
        waypoints: [RollingWaypoint],
        navRoute: NavRoute?,
        traceAppearance: TraceAppearance,
        /// Fond raster actif (OSM standard ou OpenTopoMap pour le thème Relief, #10).
        tileSource: TileSource,
        currentLocation: CLLocation?,
        headingDegrees: CLLocationDirection,
        cameraDistanceMeters: Double,
        /// Zone visible réellement utile pour la caméra (spec "camera-inset") : exclut les
        /// panneaux qui recouvrent la carte (segmented control en haut, roadbook/tab bar en
        /// bas) pour que la position ne soit jamais masquée. Voir RideOverlayLayout pour le
        /// calcul et MLNMapView.contentInset pour l'implémentation MapLibre ; MapKit
        /// (comparaison uniquement) n'a pas d'équivalent persistant pour une caméra continue,
        /// voir le commentaire dans RideMapView.
        cameraContentInsetTop: Double,
        cameraContentInsetBottom: Double,
        cameraContentInsetLeft: Double,
        cameraContentInsetRight: Double,
        northUp: Bool,
        /// Vue alternative nord-en-haut (Bloc 2, Mode Nav) — le cap-en-haut reste le défaut
        /// partout ; ceci force nord en haut (et l'ancrage centré, `positionAnchorRatio2D`)
        /// le temps du toggle. Depuis "2d-only" (it11), la caméra est TOUJOURS plate (pitch 0)
        /// des deux côtés du toggle — seule l'orientation (cap vs nord) change, plus le pitch.
        is2DNorthUp: Bool,
        isManualOverrideActive: Bool,
        /// Change à chaque tap +/- ou recentrage : force l'application immédiate de la
        /// caméra (animation courte) même pendant la fenêtre d'override manuel.
        cameraCommandToken: UUID?,
        detourRoute: DetourRoute?,
        /// "Aller à" universel (Bloc 4) : guidage parallèle, jamais un remplacement de la
        /// trace ou de la route Nav — toujours en pointillés cyan.
        goToGuidance: GoToGuidance?,
        /// "Reprendre la trace ici" (Bloc 3, it10) : pin + route (ou vol d'oiseau dégradé)
        /// vers un point tapé plus loin sur la trace — toujours en pointillés bleus, distinct
        /// de la trace, du détour (rouge) et de "Aller à" (cyan).
        resumeGuidance: ResumeGuidance?,
        /// Base partagée des points bloqués (Bloc 5) : marqueurs triangle rouge, opacité
        /// réduite au-delà de 90 j sans reconfirmation (voir SharedBlockage.isFaded).
        sharedBlockages: [SharedBlockage],
        /// Chevrons de direction par trace (spec "per-track-settings", DIRECTION_ARROW_SPACING_M) —
        /// orientés selon le sens déjà appliqué à `track.points` (voir GPXTrack.reordered).
        chevronSpacingMeters: Double,
        onManualGesture: @escaping () -> Void,
        onStatusChange: @escaping (MapLoadStatus) -> Void,
        onLongPress: @escaping (CLLocationCoordinate2D) -> Void,
        /// Tap simple sur la carte (Bloc 3) — coordonnée tapée + tolérance déjà convertie en
        /// mètres (dépend du zoom courant, voir `MLNMapView.metersPerPointAtLatitude(_:)`).
        /// La décision "est-ce assez près de la trace pour proposer une reprise ?" reste dans
        /// RideView (comme pour `onLongPress`), jamais dupliquée ici.
        onTrackTap: @escaping (CLLocationCoordinate2D, Double) -> Void
    )
}

enum MapEngine {
    case mapKit
    case mapLibre
}
