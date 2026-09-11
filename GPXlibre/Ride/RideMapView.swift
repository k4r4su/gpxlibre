import SwiftUI
import MapKit

/// Caméra Ride en perspective : pitch fixe, la position est décalée vers le bas de l'écran
/// (regard vers l'avant), cap en haut par défaut. Le pinch manuel est détecté et remonté
/// via `onManualGesture` pour suspendre temporairement le zoom auto (voir RideSessionManager).
/// Implémentation MapKit — conservée intacte pour comparaison (voir MapProvider).
/// MapLibre (RideMapLibreView) est le moteur actif par défaut depuis l'axe maplibre-migration.
struct RideMapView: UIViewRepresentable, MapProvider {
    let track: GPXTrack?
    let checkpoints: [Checkpoint]
    let waypoints: [RollingWaypoint]
    let navRoute: NavRoute?
    let traceAppearance: TraceAppearance
    let currentLocation: CLLocation?
    let headingDegrees: CLLocationDirection
    let cameraDistanceMeters: Double
    let northUp: Bool
    let isManualOverrideActive: Bool
    /// Détour temporaire (contournement en ligne ou guidage direct) superposé à la trace
    /// d'origine, qui reste affichée et n'est jamais modifiée ni retirée.
    let detourRoute: DetourRoute?
    let onManualGesture: () -> Void
    let onStatusChange: (MapLoadStatus) -> Void
    let onLongPress: (CLLocationCoordinate2D) -> Void

    func makeUIView(context: Context) -> MKMapView {
        let mapView = MKMapView()
        mapView.delegate = context.coordinator
        mapView.showsUserLocation = true
        mapView.showsCompass = false
        mapView.showsScale = false
        mapView.pointOfInterestFilter = .excludingAll

        mapView.addAnnotations(checkpoints.map(CheckpointAnnotation.init))
        mapView.addAnnotations(waypoints.map(RollingWaypointAnnotation.init))

        // Les tuiles Apple Plans sont gérées nativement par MapKit, pas de style JSON
        // maison ici : la classe de bug corrigée côté MapLibre ne s'applique pas.
        onStatusChange(.loaded)

        context.coordinator.onManualGesture = onManualGesture
        context.coordinator.onLongPress = onLongPress
        let pinch = UIPinchGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.gestureDetected))
        pinch.delegate = context.coordinator
        mapView.addGestureRecognizer(pinch)
        let pan = UIPanGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.gestureDetected))
        pan.delegate = context.coordinator
        mapView.addGestureRecognizer(pan)
        let longPress = UILongPressGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.longPressDetected))
        mapView.addGestureRecognizer(longPress)

        syncTrackOverlays(on: mapView, context: context)
        syncNavRouteOverlay(on: mapView, context: context)

        return mapView
    }

    func updateUIView(_ mapView: MKMapView, context: Context) {
        context.coordinator.onManualGesture = onManualGesture
        context.coordinator.onLongPress = onLongPress
        syncTrackOverlays(on: mapView, context: context)
        syncNavRouteOverlay(on: mapView, context: context)
        updateDetourOverlay(on: mapView, context: context)
        guard let currentLocation, !isManualOverrideActive else { return }

        let heading = northUp ? 0 : headingDegrees
        let lookAheadCenter = Self.lookAheadCoordinate(
            from: currentLocation.coordinate,
            headingDegrees: heading,
            forwardDistance: cameraDistanceMeters * RideConstants.cameraCenterOffsetRatio
        )

        let camera = MKMapCamera(
            lookingAtCenter: lookAheadCenter,
            fromDistance: cameraDistanceMeters,
            pitch: RideConstants.cameraPitchDegrees,
            heading: heading
        )

        UIView.animate(withDuration: RideConstants.cameraAnimationDurationSeconds, delay: 0, options: [.allowUserInteraction, .curveEaseInOut]) {
            mapView.camera = camera
        }
    }

    /// Trace en deux overlays (casing sombre/clair dessous, couleur choisie dessus) — la
    /// lisibilité vient du contraste de contour, pas de la seule couleur (Bloc 3). Recréés
    /// dès que la trace ou l'apparence change, pour un réglage appliqué en direct sans
    /// recharger la trace (aucun cache de renderer ne serait sinon rafraîchi).
    private func syncTrackOverlays(on mapView: MKMapView, context: Context) {
        let coordinator = context.coordinator
        guard coordinator.currentTrackID != track?.id || coordinator.traceAppearance != traceAppearance else { return }

        if let casing = coordinator.traceCasingOverlay { mapView.removeOverlay(casing) }
        if let colored = coordinator.traceColorOverlay { mapView.removeOverlay(colored) }
        coordinator.traceCasingOverlay = nil
        coordinator.traceColorOverlay = nil
        coordinator.traceAppearance = traceAppearance
        coordinator.currentTrackID = track?.id

        guard let track, track.points.count > 1 else { return }
        let coordinates = track.points.map(\.coordinate)
        let casing = TraceCasingPolyline(coordinates: coordinates, count: coordinates.count)
        let colored = TraceColorPolyline(coordinates: coordinates, count: coordinates.count)
        mapView.addOverlay(casing)
        mapView.addOverlay(colored)
        coordinator.traceCasingOverlay = casing
        coordinator.traceColorOverlay = colored
    }

    /// Route Mode Nav — remplacée à chaque nouveau calcul/recalcul (identifiée via `computedAt`).
    private func syncNavRouteOverlay(on mapView: MKMapView, context: Context) {
        let coordinator = context.coordinator
        guard coordinator.currentNavRouteComputedAt != navRoute?.computedAt else { return }

        if let existing = coordinator.navRouteOverlay { mapView.removeOverlay(existing) }
        coordinator.navRouteOverlay = nil
        coordinator.currentNavRouteComputedAt = navRoute?.computedAt

        guard let route = navRoute, route.coordinates.count > 1 else { return }
        let overlay = NavRoutePolyline(coordinates: route.coordinates, count: route.coordinates.count)
        mapView.addOverlay(overlay)
        coordinator.navRouteOverlay = overlay
    }

    private func updateDetourOverlay(on mapView: MKMapView, context: Context) {
        if let existing = context.coordinator.detourOverlay {
            mapView.removeOverlay(existing)
            context.coordinator.detourOverlay = nil
        }
        guard let detourRoute, detourRoute.coordinates.count > 1 else { return }
        let overlay = DetourPolyline(coordinates: detourRoute.coordinates, count: detourRoute.coordinates.count)
        context.coordinator.detourOverlay = overlay
        mapView.addOverlay(overlay)
    }

    /// Point projeté à `forwardDistance` mètres dans la direction `headingDegrees`,
    /// utilisé comme centre caméra pour que la position réelle apparaisse plus bas à l'écran.
    static func lookAheadCoordinate(
        from coordinate: CLLocationCoordinate2D,
        headingDegrees: Double,
        forwardDistance: Double
    ) -> CLLocationCoordinate2D {
        let earthRadiusMeters = 6_371_000.0
        let bearing = headingDegrees * .pi / 180
        let lat1 = coordinate.latitude * .pi / 180
        let lon1 = coordinate.longitude * .pi / 180
        let angularDistance = forwardDistance / earthRadiusMeters

        let lat2 = asin(sin(lat1) * cos(angularDistance) + cos(lat1) * sin(angularDistance) * cos(bearing))
        let lon2 = lon1 + atan2(
            sin(bearing) * sin(angularDistance) * cos(lat1),
            cos(angularDistance) - sin(lat1) * sin(lat2)
        )

        return CLLocationCoordinate2D(latitude: lat2 * 180 / .pi, longitude: lon2 * 180 / .pi)
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    final class Coordinator: NSObject, MKMapViewDelegate, UIGestureRecognizerDelegate {
        var onManualGesture: (() -> Void)?
        var onLongPress: ((CLLocationCoordinate2D) -> Void)?
        var detourOverlay: DetourPolyline?
        var traceAppearance = TraceAppearance()
        var currentTrackID: UUID?
        var traceCasingOverlay: TraceCasingPolyline?
        var traceColorOverlay: TraceColorPolyline?
        var navRouteOverlay: NavRoutePolyline?
        var currentNavRouteComputedAt: Date?

        @objc func gestureDetected(_ gesture: UIGestureRecognizer) {
            guard gesture.state == .began || gesture.state == .changed else { return }
            onManualGesture?()
        }

        @objc func longPressDetected(_ gesture: UILongPressGestureRecognizer) {
            guard gesture.state == .began, let mapView = gesture.view as? MKMapView else { return }
            let point = gesture.location(in: mapView)
            let coordinate = mapView.convert(point, toCoordinateFrom: mapView)
            onLongPress?(coordinate)
        }

        func gestureRecognizer(
            _ gestureRecognizer: UIGestureRecognizer,
            shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer
        ) -> Bool { true }

        func mapView(_ mapView: MKMapView, rendererFor overlay: MKOverlay) -> MKOverlayRenderer {
            if let casing = overlay as? TraceCasingPolyline {
                let renderer = MKPolylineRenderer(polyline: casing)
                renderer.strokeColor = traceAppearance.casingColor
                renderer.lineWidth = traceAppearance.casingWidth
                return renderer
            }
            if let colored = overlay as? TraceColorPolyline {
                let renderer = MKPolylineRenderer(polyline: colored)
                renderer.strokeColor = traceAppearance.color
                renderer.lineWidth = traceAppearance.lineWidth
                return renderer
            }
            if let navPolyline = overlay as? NavRoutePolyline {
                let renderer = MKPolylineRenderer(polyline: navPolyline)
                renderer.strokeColor = .systemBlue
                renderer.lineWidth = traceAppearance.lineWidth
                return renderer
            }
            if let detour = overlay as? DetourPolyline {
                let renderer = MKPolylineRenderer(polyline: detour)
                renderer.strokeColor = UIColor.systemRed
                // Le détour DOIT être plus visible que la trace : 50% plus épais, toujours en
                // pointillés rouges, jamais confondu avec elle.
                renderer.lineWidth = traceAppearance.detourLineWidth
                renderer.lineDashPattern = [10, 8]
                return renderer
            }
            if let polyline = overlay as? MKPolyline {
                let renderer = MKPolylineRenderer(polyline: polyline)
                renderer.strokeColor = UIColor.systemOrange
                renderer.lineWidth = 5
                return renderer
            }
            return MKOverlayRenderer(overlay: overlay)
        }

        func mapView(_ mapView: MKMapView, viewFor annotation: MKAnnotation) -> MKAnnotationView? {
            if let checkpointAnnotation = annotation as? CheckpointAnnotation {
                let identifier = "checkpoint"
                let view = mapView.dequeueReusableAnnotationView(withIdentifier: identifier) as? MKMarkerAnnotationView
                    ?? MKMarkerAnnotationView(annotation: checkpointAnnotation, reuseIdentifier: identifier)
                view.annotation = checkpointAnnotation
                view.markerTintColor = .systemRed
                view.glyphImage = UIImage(systemName: checkpointAnnotation.checkpoint.direction.systemImageName)
                view.displayPriority = .required
                view.canShowCallout = false
                return view
            }
            if let waypointAnnotation = annotation as? RollingWaypointAnnotation {
                let identifier = "waypoint"
                let view = mapView.dequeueReusableAnnotationView(withIdentifier: identifier) as? MKMarkerAnnotationView
                    ?? MKMarkerAnnotationView(annotation: waypointAnnotation, reuseIdentifier: identifier)
                view.annotation = waypointAnnotation
                view.markerTintColor = .systemBlue
                view.glyphImage = UIImage(systemName: waypointAnnotation.waypoint.category.systemImageName)
                view.displayPriority = .defaultLow
                view.canShowCallout = true
                return view
            }
            return nil
        }
    }
}

/// Sous-classe distincte pour styler le détour différemment de la trace d'origine
/// (pointillés rouges) sans jamais toucher à l'overlay de la trace elle-même.
final class DetourPolyline: MKPolyline {}

/// Contour ("casing") de la trace, rendu sous la couleur choisie par l'utilisateur.
final class TraceCasingPolyline: MKPolyline {}
/// Ligne colorée de la trace (couleur choisie par l'utilisateur, Bloc 3).
final class TraceColorPolyline: MKPolyline {}

/// Route calculée en Mode Nav — bleu classique, jamais confondue avec la trace sacrée.
final class NavRoutePolyline: MKPolyline {}

final class CheckpointAnnotation: NSObject, MKAnnotation {
    let checkpoint: Checkpoint
    var coordinate: CLLocationCoordinate2D { checkpoint.coordinate }

    init(checkpoint: Checkpoint) {
        self.checkpoint = checkpoint
    }
}

final class RollingWaypointAnnotation: NSObject, MKAnnotation {
    let waypoint: RollingWaypoint
    var coordinate: CLLocationCoordinate2D { waypoint.coordinate.coordinate }
    var title: String? { waypoint.category.label }

    init(waypoint: RollingWaypoint) {
        self.waypoint = waypoint
    }
}
