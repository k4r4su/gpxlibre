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
        /// Vue alternative 2D nord-en-haut (Bloc 2, Mode Nav) — le cap-en-haut perspective
        /// reste le défaut partout ; ceci force pitch 0 + nord en haut le temps du toggle.
        is2DNorthUp: Bool,
        isManualOverrideActive: Bool,
        /// Change à chaque tap +/- ou recentrage : force l'application immédiate de la
        /// caméra (animation courte) même pendant la fenêtre d'override manuel.
        cameraCommandToken: UUID?,
        detourRoute: DetourRoute?,
        /// "Aller à" universel (Bloc 4) : guidage parallèle, jamais un remplacement de la
        /// trace ou de la route Nav — toujours en pointillés cyan.
        goToGuidance: GoToGuidance?,
        /// Base partagée des points bloqués (Bloc 5) : marqueurs triangle rouge, opacité
        /// réduite au-delà de 90 j sans reconfirmation (voir SharedBlockage.isFaded).
        sharedBlockages: [SharedBlockage],
        /// Chevrons de direction par trace (spec "per-track-settings", DIRECTION_ARROW_SPACING_M) —
        /// orientés selon le sens déjà appliqué à `track.points` (voir GPXTrack.reordered).
        chevronSpacingMeters: Double,
        onManualGesture: @escaping () -> Void,
        onStatusChange: @escaping (MapLoadStatus) -> Void,
        onLongPress: @escaping (CLLocationCoordinate2D) -> Void
    )
}

enum MapEngine {
    case mapKit
    case mapLibre
}
