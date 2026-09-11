import SwiftUI
import MapLibre
import CoreLocation

/// Implémentation MapLibre (moteur actif par défaut, voir MapEngineConstants) : tuiles
/// raster OSM, trace + détour en sources vectorielles stylées localement, checkpoints en
/// annotations. Même contrat que RideMapView (MapKit), qui reste intact à côté.
struct RideMapLibreView: UIViewRepresentable, MapProvider {
    let track: GPXTrack
    let checkpoints: [Checkpoint]
    let waypoints: [RollingWaypoint]
    let currentLocation: CLLocation?
    let headingDegrees: CLLocationDirection
    let cameraDistanceMeters: Double
    let northUp: Bool
    let isManualOverrideActive: Bool
    let detourRoute: DetourRoute?
    let onManualGesture: () -> Void

    func makeUIView(context: Context) -> MLNMapView {
        let mapView = MLNMapView(frame: .zero, styleJSON: MapEngineConstants.initialStyleJSON)
        mapView.delegate = context.coordinator
        mapView.showsUserLocation = true
        mapView.userTrackingMode = .none
        mapView.showsCompassView = false
        mapView.showsScale = false
        mapView.showsAttributionButton = true
        mapView.logoView.isHidden = true

        context.coordinator.track = track
        context.coordinator.checkpoints = checkpoints
        context.coordinator.waypoints = waypoints
        context.coordinator.onManualGesture = onManualGesture

        return mapView
    }

    func updateUIView(_ mapView: MLNMapView, context: Context) {
        context.coordinator.onManualGesture = onManualGesture
        updateDetourShape(on: mapView, context: context)

        guard let currentLocation, !isManualOverrideActive else { return }

        let heading = northUp ? 0 : headingDegrees
        let lookAheadCenter = RideMapView.lookAheadCoordinate(
            from: currentLocation.coordinate,
            headingDegrees: heading,
            forwardDistance: cameraDistanceMeters * RideConstants.cameraCenterOffsetRatio
        )

        let camera = MLNMapCamera(
            lookingAtCenter: lookAheadCenter,
            acrossDistance: cameraDistanceMeters,
            pitch: CGFloat(RideConstants.cameraPitchDegrees),
            heading: heading
        )

        mapView.setCamera(camera, withDuration: RideConstants.cameraAnimationDurationSeconds, animationTimingFunction: CAMediaTimingFunction(name: .easeInEaseOut))
    }

    private func updateDetourShape(on mapView: MLNMapView, context: Context) {
        guard let style = mapView.style,
              let source = style.source(withIdentifier: MapEngineConstants.detourSourceIdentifier) as? MLNShapeSource
        else { return }

        guard let detourRoute, detourRoute.coordinates.count > 1 else {
            source.shape = nil
            return
        }
        let coordinates = detourRoute.coordinates
        source.shape = MLNPolyline(coordinates: coordinates, count: UInt(coordinates.count))
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    final class Coordinator: NSObject, MLNMapViewDelegate {
        var track: GPXTrack?
        var checkpoints: [Checkpoint] = []
        var waypoints: [RollingWaypoint] = []
        var onManualGesture: (() -> Void)?

        private static let gestureReasonMask: MLNCameraChangeReason = [
            .gesturePan, .gesturePinch, .gestureRotate, .gestureZoomIn, .gestureZoomOut, .gestureOneFingerZoom, .gestureTilt,
        ]

        func mapView(_ mapView: MLNMapView, didFinishLoading style: MLNStyle) {
            // Le fond raster OSM (source + couche) est déjà défini dans le style JSON initial
            // (MapEngineConstants.initialStyleJSON) — tileSize 256 non pilotable depuis l'API
            // Swift MLNRasterTileSource(tileURLTemplates:options:), d'où ce choix.
            guard let track else { return }

            let trackCoordinates = track.points.map(\.coordinate)
            let trackShape = MLNPolyline(coordinates: trackCoordinates, count: UInt(trackCoordinates.count))
            let trackSource = MLNShapeSource(identifier: MapEngineConstants.trackSourceIdentifier, shape: trackShape, options: nil)
            style.addSource(trackSource)
            let trackLayer = MLNLineStyleLayer(identifier: MapEngineConstants.trackLayerIdentifier, source: trackSource)
            trackLayer.lineColor = NSExpression(forConstantValue: UIColor.systemOrange)
            trackLayer.lineWidth = NSExpression(forConstantValue: 5)
            style.addLayer(trackLayer)

            let detourSource = MLNShapeSource(identifier: MapEngineConstants.detourSourceIdentifier, shape: nil, options: nil)
            style.addSource(detourSource)
            let detourLayer = MLNLineStyleLayer(identifier: MapEngineConstants.detourLayerIdentifier, source: detourSource)
            detourLayer.lineColor = NSExpression(forConstantValue: UIColor.systemRed)
            detourLayer.lineWidth = NSExpression(forConstantValue: 5)
            detourLayer.lineDashPattern = NSExpression(forConstantValue: [10, 8])
            style.addLayer(detourLayer)

            mapView.addAnnotations(checkpoints.map(CheckpointMLNAnnotation.init))
            mapView.addAnnotations(waypoints.map(RollingWaypointMLNAnnotation.init))
        }

        func mapView(_ mapView: MLNMapView, regionWillChangeWith reason: MLNCameraChangeReason, animated: Bool) {
            guard !reason.intersection(Self.gestureReasonMask).isEmpty else { return }
            onManualGesture?()
        }

        func mapView(_ mapView: MLNMapView, viewFor annotation: MLNAnnotation) -> MLNAnnotationView? {
            if let checkpointAnnotation = annotation as? CheckpointMLNAnnotation {
                return annotationView(on: mapView, identifier: "checkpoint", annotation: checkpointAnnotation, tint: .systemRed, systemImageName: checkpointAnnotation.checkpoint.direction.systemImageName, size: 34)
            }
            if let waypointAnnotation = annotation as? RollingWaypointMLNAnnotation {
                return annotationView(on: mapView, identifier: "waypoint", annotation: waypointAnnotation, tint: .systemBlue, systemImageName: waypointAnnotation.waypoint.category.systemImageName, size: 28)
            }
            return nil
        }

        private func annotationView(
            on mapView: MLNMapView,
            identifier: String,
            annotation: MLNAnnotation,
            tint: UIColor,
            systemImageName: String,
            size: CGFloat
        ) -> MLNAnnotationView {
            let view = mapView.dequeueReusableAnnotationView(withIdentifier: identifier) ?? MLNAnnotationView(reuseIdentifier: identifier)
            view.frame = CGRect(x: 0, y: 0, width: size, height: size)
            view.subviews.forEach { $0.removeFromSuperview() }

            let background = UIView(frame: view.bounds)
            background.backgroundColor = tint
            background.layer.cornerRadius = view.bounds.width / 2
            view.addSubview(background)

            let imageView = UIImageView(frame: view.bounds.insetBy(dx: size * 0.2, dy: size * 0.2))
            imageView.image = UIImage(systemName: systemImageName)
            imageView.contentMode = .scaleAspectFit
            imageView.tintColor = .white
            view.addSubview(imageView)

            return view
        }
    }
}

final class CheckpointMLNAnnotation: NSObject, MLNAnnotation {
    let checkpoint: Checkpoint
    var coordinate: CLLocationCoordinate2D { checkpoint.coordinate }

    init(checkpoint: Checkpoint) {
        self.checkpoint = checkpoint
    }
}

final class RollingWaypointMLNAnnotation: NSObject, MLNAnnotation {
    let waypoint: RollingWaypoint
    var coordinate: CLLocationCoordinate2D { waypoint.coordinate.coordinate }
    var title: String? { waypoint.category.label }

    init(waypoint: RollingWaypoint) {
        self.waypoint = waypoint
    }
}
