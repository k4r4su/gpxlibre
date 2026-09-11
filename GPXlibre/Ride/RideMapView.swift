import SwiftUI
import MapKit

/// Caméra Ride en perspective : pitch fixe, la position est décalée vers le bas de l'écran
/// (regard vers l'avant), cap en haut par défaut. Le pinch manuel est détecté et remonté
/// via `onManualGesture` pour suspendre temporairement le zoom auto (voir RideSessionManager).
struct RideMapView: UIViewRepresentable {
    let track: GPXTrack
    let checkpoints: [Checkpoint]
    let currentLocation: CLLocation?
    let headingDegrees: CLLocationDirection
    let cameraDistanceMeters: Double
    let northUp: Bool
    let isManualOverrideActive: Bool
    let onManualGesture: () -> Void

    func makeUIView(context: Context) -> MKMapView {
        let mapView = MKMapView()
        mapView.delegate = context.coordinator
        mapView.showsUserLocation = true
        mapView.showsCompass = false
        mapView.showsScale = false
        mapView.pointOfInterestFilter = .excludingAll

        if track.points.count > 1 {
            let polyline = MKPolyline(coordinates: track.points.map(\.coordinate), count: track.points.count)
            mapView.addOverlay(polyline)
        }
        mapView.addAnnotations(checkpoints.map(CheckpointAnnotation.init))

        context.coordinator.onManualGesture = onManualGesture
        let pinch = UIPinchGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.gestureDetected))
        pinch.delegate = context.coordinator
        mapView.addGestureRecognizer(pinch)
        let pan = UIPanGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.gestureDetected))
        pan.delegate = context.coordinator
        mapView.addGestureRecognizer(pan)

        return mapView
    }

    func updateUIView(_ mapView: MKMapView, context: Context) {
        context.coordinator.onManualGesture = onManualGesture
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

        @objc func gestureDetected(_ gesture: UIGestureRecognizer) {
            guard gesture.state == .began || gesture.state == .changed else { return }
            onManualGesture?()
        }

        func gestureRecognizer(
            _ gestureRecognizer: UIGestureRecognizer,
            shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer
        ) -> Bool { true }

        func mapView(_ mapView: MKMapView, rendererFor overlay: MKOverlay) -> MKOverlayRenderer {
            if let polyline = overlay as? MKPolyline {
                let renderer = MKPolylineRenderer(polyline: polyline)
                renderer.strokeColor = UIColor.systemOrange
                renderer.lineWidth = 5
                return renderer
            }
            return MKOverlayRenderer(overlay: overlay)
        }

        func mapView(_ mapView: MKMapView, viewFor annotation: MKAnnotation) -> MKAnnotationView? {
            guard let checkpointAnnotation = annotation as? CheckpointAnnotation else { return nil }
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
    }
}

final class CheckpointAnnotation: NSObject, MKAnnotation {
    let checkpoint: Checkpoint
    var coordinate: CLLocationCoordinate2D { checkpoint.coordinate }

    init(checkpoint: Checkpoint) {
        self.checkpoint = checkpoint
    }
}
