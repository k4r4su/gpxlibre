import SwiftUI
import CoreLocation

/// Contrat commun aux moteurs de carte du mode Ride. MapLibre (`RideMapLibreView`) est le
/// moteur actif par défaut (tuiles OSM, hors-ligne à terme) ; MapKit (`RideMapView`) reste
/// dans le projet, conforme au même contrat, pour comparaison — ni supprimé, ni désactivé,
/// juste non sélectionné (voir `MapEngineConstants.active`).
protocol MapProvider: View {
    init(
        track: GPXTrack,
        checkpoints: [Checkpoint],
        waypoints: [RollingWaypoint],
        currentLocation: CLLocation?,
        headingDegrees: CLLocationDirection,
        cameraDistanceMeters: Double,
        northUp: Bool,
        isManualOverrideActive: Bool,
        detourRoute: DetourRoute?,
        onManualGesture: @escaping () -> Void,
        onStatusChange: @escaping (MapLoadStatus) -> Void
    )
}

enum MapEngine {
    case mapKit
    case mapLibre
}
