import SwiftUI
import MapLibre
import CoreLocation

/// Implémentation MapLibre (moteur actif par défaut, voir MapEngineConstants) : tuiles
/// raster OSM, trace + détour + route Nav en sources vectorielles stylées localement,
/// checkpoints/waypoints en annotations. Même contrat que RideMapView (MapKit), conservé
/// à côté.
///
/// Robustesse fond de carte : le style principal est construit via JSONSerialization
/// (jamais par interpolation de string — un ancien bug produisait du JSON invalide et le
/// style échouait à charger silencieusement, écran noir sans aucune erreur visible). Si le
/// style principal échoue à charger OU n'a pas fini de charger en 5 s, on bascule sur le
/// style de secours embarqué (fallback-style.json) et on remonte un état d'erreur visible
/// via `onStatusChange`.
struct RideMapLibreView: UIViewRepresentable, MapProvider {
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
    let detourRoute: DetourRoute?
    let onManualGesture: () -> Void
    let onStatusChange: (MapLoadStatus) -> Void
    let onLongPress: (CLLocationCoordinate2D) -> Void

    func makeUIView(context: Context) -> MLNMapView {
        let mapView = MLNMapView(frame: .zero, styleJSON: MapEngineConstants.buildInitialStyleJSON())
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
        context.coordinator.traceAppearance = traceAppearance
        context.coordinator.onManualGesture = onManualGesture
        context.coordinator.onStatusChange = onStatusChange
        context.coordinator.onLongPress = onLongPress
        context.coordinator.armLoadWatchdog(for: mapView)
        onStatusChange(.loading)

        let longPress = UILongPressGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.longPressDetected))
        mapView.addGestureRecognizer(longPress)

        return mapView
    }

    func updateUIView(_ mapView: MLNMapView, context: Context) {
        context.coordinator.onManualGesture = onManualGesture
        context.coordinator.onStatusChange = onStatusChange
        context.coordinator.onLongPress = onLongPress
        context.coordinator.updateTraceAppearance(traceAppearance)
        updateDetourShape(on: mapView, context: context)
        updateNavRouteShape(on: mapView, context: context)

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

    private func updateNavRouteShape(on mapView: MLNMapView, context: Context) {
        guard let style = mapView.style,
              let source = style.source(withIdentifier: MapEngineConstants.navRouteSourceIdentifier) as? MLNShapeSource
        else { return }

        guard let navRoute, navRoute.coordinates.count > 1 else {
            source.shape = nil
            return
        }
        let coordinates = navRoute.coordinates
        source.shape = MLNPolyline(coordinates: coordinates, count: UInt(coordinates.count))
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    final class Coordinator: NSObject, MLNMapViewDelegate {
        var track: GPXTrack?
        var checkpoints: [Checkpoint] = []
        var waypoints: [RollingWaypoint] = []
        var traceAppearance = TraceAppearance()
        var onManualGesture: (() -> Void)?
        var onStatusChange: ((MapLoadStatus) -> Void)?
        var onLongPress: ((CLLocationCoordinate2D) -> Void)?

        private weak var trackCasingLayer: MLNLineStyleLayer?
        private weak var trackColorLayer: MLNLineStyleLayer?

        private var loadWatchdog: Timer?
        private var didAttemptFallback = false
        private var didFinishLoadingOnce = false

        private static let gestureReasonMask: MLNCameraChangeReason = [
            .gesturePan, .gesturePinch, .gestureRotate, .gestureZoomIn, .gestureZoomOut, .gestureOneFingerZoom, .gestureTilt,
        ]

        @objc func longPressDetected(_ gesture: UILongPressGestureRecognizer) {
            guard gesture.state == .began, let mapView = gesture.view as? MLNMapView else { return }
            let point = gesture.location(in: mapView)
            let coordinate = mapView.convert(point, toCoordinateFrom: mapView)
            onLongPress?(coordinate)
        }

        /// Les propriétés de style MapLibre sont mutables en direct (contrairement aux
        /// MKOverlayRenderer de MapKit, mis en cache) : pas besoin de retirer/recréer la
        /// couche pour appliquer un nouveau réglage — Bloc 3, "appliqué en direct".
        func updateTraceAppearance(_ appearance: TraceAppearance) {
            guard appearance != traceAppearance else { return }
            traceAppearance = appearance
            trackCasingLayer?.lineColor = NSExpression(forConstantValue: appearance.casingColor)
            trackCasingLayer?.lineWidth = NSExpression(forConstantValue: appearance.casingWidth)
            trackColorLayer?.lineColor = NSExpression(forConstantValue: appearance.color)
            trackColorLayer?.lineWidth = NSExpression(forConstantValue: appearance.lineWidth)
        }

        /// Si le style n'a pas fini de charger en `styleLoadTimeoutSeconds`, on n'attend pas
        /// un écran noir muet : on bascule sur le secours et on prévient l'utilisateur.
        func armLoadWatchdog(for mapView: MLNMapView) {
            loadWatchdog?.invalidate()
            didFinishLoadingOnce = false
            loadWatchdog = Timer.scheduledTimer(withTimeInterval: MapEngineConstants.styleLoadTimeoutSeconds, repeats: false) { [weak self, weak mapView] _ in
                guard let self, let mapView, !self.didFinishLoadingOnce else { return }
                print("[MapLibre] Timeout : le style n'a pas fini de charger en \(MapEngineConstants.styleLoadTimeoutSeconds)s.")
                self.onStatusChange?(.failed("Carte non chargée — vérifie ta connexion"))
                self.switchToFallbackStyle(on: mapView)
            }
        }

        private func switchToFallbackStyle(on mapView: MLNMapView) {
            guard !didAttemptFallback else {
                print("[MapLibre] Le style de secours a lui aussi échoué à charger.")
                return
            }
            didAttemptFallback = true
            guard let url = Bundle.main.url(forResource: MapEngineConstants.fallbackStyleResourceName, withExtension: "json") else {
                print("[MapLibre] ERREUR : fallback-style.json introuvable dans le bundle.")
                return
            }
            print("[MapLibre] Bascule sur le style de secours embarqué : \(url.lastPathComponent)")
            mapView.styleURL = url
        }

        func mapView(_ mapView: MLNMapView, didFinishLoading style: MLNStyle) {
            didFinishLoadingOnce = true
            loadWatchdog?.invalidate()
            print("[MapLibre] Style chargé avec succès (\(style.sources.count) source(s)).")
            onStatusChange?(.loaded)

            let detourSource = MLNShapeSource(identifier: MapEngineConstants.detourSourceIdentifier, shape: nil, options: nil)
            style.addSource(detourSource)
            let detourLayer = MLNLineStyleLayer(identifier: MapEngineConstants.detourLayerIdentifier, source: detourSource)
            detourLayer.lineColor = NSExpression(forConstantValue: UIColor.systemRed)
            // Le détour DOIT être plus visible que la trace : 50% plus épais, toujours en
            // pointillés rouges, jamais confondu avec elle.
            detourLayer.lineWidth = NSExpression(forConstantValue: traceAppearance.detourLineWidth)
            detourLayer.lineDashPattern = NSExpression(forConstantValue: [10, 8])

            let navRouteSource = MLNShapeSource(identifier: MapEngineConstants.navRouteSourceIdentifier, shape: nil, options: nil)
            style.addSource(navRouteSource)
            let navRouteLayer = MLNLineStyleLayer(identifier: MapEngineConstants.navRouteLayerIdentifier, source: navRouteSource)
            navRouteLayer.lineColor = NSExpression(forConstantValue: UIColor.systemBlue)
            navRouteLayer.lineWidth = NSExpression(forConstantValue: traceAppearance.lineWidth)

            if let track, track.points.count > 1 {
                let trackCoordinates = track.points.map(\.coordinate)
                let trackShape = MLNPolyline(coordinates: trackCoordinates, count: UInt(trackCoordinates.count))
                let trackSource = MLNShapeSource(identifier: MapEngineConstants.trackSourceIdentifier, shape: trackShape, options: nil)
                style.addSource(trackSource)

                // Casing d'abord (dessous), couleur ensuite (dessus) — lisibilité par contraste.
                let casingLayer = MLNLineStyleLayer(identifier: "\(MapEngineConstants.trackLayerIdentifier)-casing", source: trackSource)
                casingLayer.lineColor = NSExpression(forConstantValue: traceAppearance.casingColor)
                casingLayer.lineWidth = NSExpression(forConstantValue: traceAppearance.casingWidth)
                style.addLayer(casingLayer)
                trackCasingLayer = casingLayer

                let colorLayer = MLNLineStyleLayer(identifier: MapEngineConstants.trackLayerIdentifier, source: trackSource)
                colorLayer.lineColor = NSExpression(forConstantValue: traceAppearance.color)
                colorLayer.lineWidth = NSExpression(forConstantValue: traceAppearance.lineWidth)
                style.addLayer(colorLayer)
                trackColorLayer = colorLayer
            }

            // Détour et route Nav ajoutés après la trace : ils doivent rester visibles au-dessus.
            style.addLayer(detourLayer)
            style.addLayer(navRouteLayer)

            mapView.addAnnotations(checkpoints.map(CheckpointMLNAnnotation.init))
            mapView.addAnnotations(waypoints.map(RollingWaypointMLNAnnotation.init))
        }

        /// Erreur de chargement du style (JSON invalide, réseau, etc.) — toujours loguée et
        /// toujours remontée à l'UI, jamais avalée silencieusement.
        func mapViewDidFailLoadingMap(_ mapView: MLNMapView, withError error: Error) {
            print("[MapLibre] ERREUR de chargement du style : \(error.localizedDescription)")
            onStatusChange?(.failed("Carte non chargée — vérifie ta connexion"))
            switchToFallbackStyle(on: mapView)
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
