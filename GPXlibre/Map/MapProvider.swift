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
        currentLocation: CLLocation?,
        headingDegrees: CLLocationDirection,
        cameraDistanceMeters: Double,
        northUp: Bool,
        /// Vue alternative 2D nord-en-haut (Bloc 2, Mode Nav) — le cap-en-haut perspective
        /// reste le défaut partout ; ceci force pitch 0 + nord en haut le temps du toggle.
        is2DNorthUp: Bool,
        isManualOverrideActive: Bool,
        detourRoute: DetourRoute?,
        onManualGesture: @escaping () -> Void,
        onStatusChange: @escaping (MapLoadStatus) -> Void,
        onLongPress: @escaping (CLLocationCoordinate2D) -> Void
    )
}

enum MapEngine {
    case mapKit
    case mapLibre
}
