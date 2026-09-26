import SwiftUI
import MapKit

/// Caméra Ride 2D (spec "2d-only", it11 — plus de perspective/pitch nulle part) : cap en haut
/// par défaut, position réelle centrée (l'ancrage vertical vient de RideOverlayLayout côté
/// MapLibre ; MapKit n'a pas d'équivalent persistant, voir cameraContentInset* ci-dessous).
/// Le pinch manuel est détecté et remonté via `onManualGesture` pour suspendre temporairement
/// le zoom auto (voir RideSessionManager).
/// Implémentation MapKit — conservée intacte pour comparaison (voir MapProvider).
/// MapLibre (RideMapLibreView) est le moteur actif par défaut depuis l'axe maplibre-migration.
struct RideMapView: UIViewRepresentable, MapProvider {
    let track: GPXTrack?
    let checkpoints: [Checkpoint]
    let waypoints: [RollingWaypoint]
    let navRoute: NavRoute?
    let traceAppearance: TraceAppearance
    /// MapKit n'a pas de tuiles OpenTopoMap natives : thème Relief rendu via un MKTileOverlay
    /// qui remplace le fond Apple Plans (canReplaceMapContent) — implémentation de comparaison
    /// uniquement, MapLibre reste le moteur actif et le vrai chemin testé/mis en cache.
    /// Spec "vector-pmtiles" (it11) : MapKit n'a pas d'équivalent vectoriel PMTiles — un
    /// `mapSource` vectoriel (hébergé ou local) retombe ici sur le raster OSM standard
    /// (`comparisonTileSource`), décision de scope assumée (comparaison uniquement, jamais
    /// obligée à la parité, voir CLAUDE.md).
    let mapSource: MapSourceSelection
    private var comparisonTileSource: TileSource {
        if case .raster(let tileSource) = mapSource { return tileSource }
        return .osmStandard
    }
    let currentLocation: CLLocation?
    let headingDegrees: CLLocationDirection
    let cameraDistanceMeters: Double
    /// Zone caméra utile (spec "camera-inset") — MapKit n'a pas d'équivalent persistant de
    /// `MLNMapView.contentInset` pour une caméra continue (`MKMapCamera`) : la seule API
    /// d'edge-padding de MapKit (`setVisibleMapRect:edgePadding:`) est un cadrage ponctuel,
    /// pas un suivi continu. Ces valeurs sont donc acceptées pour respecter le contrat
    /// MapProvider mais ignorées ici — implémentation de comparaison uniquement, voir
    /// RideMapLibreView pour le vrai comportement (moteur actif).
    let cameraContentInsetTop: Double
    let cameraContentInsetBottom: Double
    let cameraContentInsetLeft: Double
    let cameraContentInsetRight: Double
    let northUp: Bool
    let is2DNorthUp: Bool
    let isManualOverrideActive: Bool
    let cameraCommandToken: UUID?
    /// Détour temporaire (contournement en ligne ou guidage direct) superposé à la trace
    /// d'origine, qui reste affichée et n'est jamais modifiée ni retirée.
    let detourRoute: DetourRoute?
    let goToGuidance: GoToGuidance?
    let resumeGuidance: ResumeGuidance?
    let sharedBlockages: [SharedBlockage]
    /// Chevrons de direction (spec "per-track-settings") — comparaison uniquement, non
    /// implémenté ici (pas de couche symbole data-driven équivalente sans complexité
    /// disproportionnée pour un moteur non actif) ; voir RideMapLibreView.
    let chevronSpacingMeters: Double
    let onManualGesture: () -> Void
    let onStatusChange: (MapLoadStatus) -> Void
    let onLongPress: (CLLocationCoordinate2D) -> Void
    let onTrackTap: (CLLocationCoordinate2D, Double) -> Void

    func makeUIView(context: Context) -> MKMapView {
        let mapView = MKMapView()
        mapView.delegate = context.coordinator
        mapView.showsUserLocation = true
        mapView.showsCompass = false
        mapView.showsScale = false
        mapView.pointOfInterestFilter = .excludingAll
        // Spec "2d-only" (it11) : même nettoyage que côté MapLibre (pitchEnabled = false) —
        // pas de geste natif à deux doigts qui inclinerait la caméra.
        mapView.isPitchEnabled = false

        mapView.addAnnotations(checkpoints.map(CheckpointAnnotation.init))
        mapView.addAnnotations(waypoints.map(RollingWaypointAnnotation.init))

        // Les tuiles Apple Plans sont gérées nativement par MapKit, pas de style JSON
        // maison ici : la classe de bug corrigée côté MapLibre ne s'applique pas.
        onStatusChange(.loaded)

        context.coordinator.onManualGesture = onManualGesture
        context.coordinator.onLongPress = onLongPress
        context.coordinator.onTrackTap = onTrackTap
        let pinch = UIPinchGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.gestureDetected))
        pinch.delegate = context.coordinator
        mapView.addGestureRecognizer(pinch)
        let pan = UIPanGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.gestureDetected))
        pan.delegate = context.coordinator
        mapView.addGestureRecognizer(pan)
        let longPress = UILongPressGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.longPressDetected))
        mapView.addGestureRecognizer(longPress)
        // Bloc 3 "resume-at-point" — implémentation de comparaison (MapLibre reste le moteur
        // testé) : un simple tap, sans conflit avec le double-tap-zoom natif de MapKit
        // (nombre de taps différent, pas besoin du require(toFail:) documenté côté MapLibre).
        let trackTap = UITapGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.trackTapDetected))
        mapView.addGestureRecognizer(trackTap)

        syncTrackOverlays(on: mapView, context: context)
        syncNavRouteOverlay(on: mapView, context: context)
        syncGoToOverlay(on: mapView, context: context)
        syncReliefOverlay(on: mapView, context: context)

        return mapView
    }

    /// Relief (comparaison MapKit uniquement) : overlay OpenTopoMap plein écran si le thème
    /// actif est Relief, retiré sinon.
    private func syncReliefOverlay(on mapView: MKMapView, context: Context) {
        let coordinator = context.coordinator
        let tileSource = comparisonTileSource
        guard coordinator.currentTileSource != tileSource else { return }
        coordinator.currentTileSource = tileSource

        if let existing = coordinator.reliefOverlay {
            mapView.removeOverlay(existing)
            coordinator.reliefOverlay = nil
        }
        guard tileSource == .openTopoMap else { return }
        let overlay = MKTileOverlay(urlTemplate: "https://a.tile.opentopomap.org/{z}/{x}/{y}.png")
        overlay.canReplaceMapContent = true
        overlay.maximumZ = tileSource.maxZoomLevel
        mapView.addOverlay(overlay, level: .aboveLabels)
        coordinator.reliefOverlay = overlay
    }

    func updateUIView(_ mapView: MKMapView, context: Context) {
        context.coordinator.onManualGesture = onManualGesture
        context.coordinator.onLongPress = onLongPress
        syncTrackOverlays(on: mapView, context: context)
        syncNavRouteOverlay(on: mapView, context: context)
        syncGoToOverlay(on: mapView, context: context)
        syncReliefOverlay(on: mapView, context: context)
        updateDetourOverlay(on: mapView, context: context)
        updateResumeOverlay(on: mapView, context: context)
        syncSharedBlockageAnnotations(on: mapView, context: context)
        mapView.overrideUserInterfaceStyle = traceAppearance.isNightMode ? .dark : .light

        let isForcedCommand = context.coordinator.lastCameraCommandToken != cameraCommandToken
        context.coordinator.lastCameraCommandToken = cameraCommandToken
        guard let currentLocation, isForcedCommand || !isManualOverrideActive else { return }

        let heading = (northUp || is2DNorthUp) ? 0 : headingDegrees
        // Spec "2d-only" (it11) : plus de pitch, plus de décalage "regarder devant soi" —
        // lookingAtCenter est toujours la position réelle, comme côté MapLibre.
        let camera = MKMapCamera(
            lookingAtCenter: currentLocation.coordinate,
            fromDistance: cameraDistanceMeters,
            pitch: 0,
            heading: heading
        )

        // Animation courte pour un tap +/- ou un recentrage explicite ; lissage normal sinon.
        let duration = isForcedCommand ? RideConstants.manualZoomAnimationDurationSeconds : RideConstants.cameraAnimationDurationSeconds
        UIView.animate(withDuration: duration, delay: 0, options: [.allowUserInteraction, .curveEaseInOut]) {
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

    /// "Aller à" universel (Bloc 4) — guidage parallèle, jamais un remplacement de la trace
    /// ou de la route Nav, toujours en pointillés cyan (voir rendererFor overlay:).
    private func syncGoToOverlay(on mapView: MKMapView, context: Context) {
        let coordinator = context.coordinator
        guard coordinator.currentGoToComputedAt != goToGuidance?.computedAt else { return }

        if let existing = coordinator.goToOverlay { mapView.removeOverlay(existing) }
        coordinator.goToOverlay = nil
        coordinator.currentGoToComputedAt = goToGuidance?.computedAt

        guard let guidance = goToGuidance, guidance.coordinates.count > 1 else { return }
        let overlay = GoToPolyline(coordinates: guidance.coordinates, count: guidance.coordinates.count)
        mapView.addOverlay(overlay)
        coordinator.goToOverlay = overlay
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

    /// "Reprendre la trace ici" (Bloc 3, comparaison) — pin toujours visible (même en mode
    /// dégradé), tracé pointillé bleu seulement si une route a été calculée.
    private func updateResumeOverlay(on mapView: MKMapView, context: Context) {
        let coordinator = context.coordinator
        if let existing = coordinator.resumeOverlay {
            mapView.removeOverlay(existing)
            coordinator.resumeOverlay = nil
        }
        if let existingPin = coordinator.resumePinAnnotation {
            mapView.removeAnnotation(existingPin)
            coordinator.resumePinAnnotation = nil
        }
        guard let resumeGuidance else { return }
        let pin = ResumePinAnnotation(coordinate: resumeGuidance.pinCoordinate)
        mapView.addAnnotation(pin)
        coordinator.resumePinAnnotation = pin

        guard resumeGuidance.routeCoordinates.count > 1 else { return }
        let overlay = ResumePolyline(coordinates: resumeGuidance.routeCoordinates, count: resumeGuidance.routeCoordinates.count)
        coordinator.resumeOverlay = overlay
        mapView.addOverlay(overlay)
    }

    /// Base partagée des points bloqués (Bloc 5) — implémentation de comparaison, même
    /// contrat que côté MapLibre (voir RideMapLibreView.syncSharedBlockageAnnotations).
    private func syncSharedBlockageAnnotations(on mapView: MKMapView, context: Context) {
        let coordinator = context.coordinator
        guard coordinator.currentSharedBlockages != sharedBlockages else { return }
        coordinator.currentSharedBlockages = sharedBlockages
        mapView.removeAnnotations(coordinator.sharedBlockageAnnotations)
        coordinator.sharedBlockageAnnotations = sharedBlockages.map(SharedBlockageAnnotation.init)
        mapView.addAnnotations(coordinator.sharedBlockageAnnotations)
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    final class Coordinator: NSObject, MKMapViewDelegate, UIGestureRecognizerDelegate {
        var onManualGesture: (() -> Void)?
        var onLongPress: ((CLLocationCoordinate2D) -> Void)?
        var onTrackTap: ((CLLocationCoordinate2D, Double) -> Void)?
        var detourOverlay: DetourPolyline?
        var traceAppearance = TraceAppearance()
        var currentTileSource: TileSource = .osmStandard
        var reliefOverlay: MKTileOverlay?
        var lastCameraCommandToken: UUID?
        var currentTrackID: UUID?
        var traceCasingOverlay: TraceCasingPolyline?
        var traceColorOverlay: TraceColorPolyline?
        var navRouteOverlay: NavRoutePolyline?
        var currentNavRouteComputedAt: Date?
        var goToOverlay: GoToPolyline?
        var currentGoToComputedAt: Date?
        var currentSharedBlockages: [SharedBlockage] = []
        var sharedBlockageAnnotations: [SharedBlockageAnnotation] = []
        var resumeOverlay: ResumePolyline?
        var resumePinAnnotation: ResumePinAnnotation?

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

        /// Bloc 3 "resume-at-point" (comparaison) — MapKit n'a pas d'équivalent direct de
        /// `metersPerPointAtLatitude(_:)` : mesure la distance réelle entre deux points-écran
        /// voisins pour en déduire l'échelle courante, valable à tout niveau de zoom.
        @objc func trackTapDetected(_ gesture: UITapGestureRecognizer) {
            guard gesture.state == .ended, let mapView = gesture.view as? MKMapView else { return }
            let point = gesture.location(in: mapView)
            let coordinate = mapView.convert(point, toCoordinateFrom: mapView)
            let offsetCoordinate = mapView.convert(CGPoint(x: point.x + 1, y: point.y), toCoordinateFrom: mapView)
            let metersPerPoint = RoadbookAnalyzer.distanceMeters(coordinate, offsetCoordinate)
            onTrackTap?(coordinate, metersPerPoint * RideConstants.resumeTapToleranceScreenPoints)
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
                // Fix "nav-route-overlay" (Bug 1) : même couleur distincte que MapLibre (moteur
                // actif), pas un bleu système générique proche d'autres éléments UIKit.
                let renderer = MKPolylineRenderer(polyline: navPolyline)
                renderer.strokeColor = MapEngineConstants.navRouteColor(isNightMode: traceAppearance.isNightMode)
                renderer.lineWidth = traceAppearance.lineWidth
                return renderer
            }
            if let goToPolyline = overlay as? GoToPolyline {
                let renderer = MKPolylineRenderer(polyline: goToPolyline)
                renderer.strokeColor = .systemCyan
                renderer.lineWidth = traceAppearance.lineWidth
                renderer.lineDashPattern = [6, 6]
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
            if let resume = overlay as? ResumePolyline {
                // "Reprendre ici" (Bloc 3) : bleu pointillé distinct de la trace, du détour
                // (rouge) et de "Aller à" (cyan).
                let renderer = MKPolylineRenderer(polyline: resume)
                renderer.strokeColor = .systemBlue
                renderer.lineWidth = traceAppearance.detourLineWidth
                renderer.lineDashPattern = [8, 4]
                return renderer
            }
            if let polyline = overlay as? MKPolyline {
                let renderer = MKPolylineRenderer(polyline: polyline)
                renderer.strokeColor = UIColor.systemOrange
                renderer.lineWidth = 5
                return renderer
            }
            if let tileOverlay = overlay as? MKTileOverlay {
                return MKTileOverlayRenderer(tileOverlay: tileOverlay)
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
            if let resumePin = annotation as? ResumePinAnnotation {
                let identifier = "resumePin"
                let view = mapView.dequeueReusableAnnotationView(withIdentifier: identifier) as? MKMarkerAnnotationView
                    ?? MKMarkerAnnotationView(annotation: resumePin, reuseIdentifier: identifier)
                view.annotation = resumePin
                view.markerTintColor = .systemBlue
                view.glyphImage = UIImage(systemName: "mappin")
                view.displayPriority = .required
                view.canShowCallout = false
                return view
            }
            if let sharedBlockageAnnotation = annotation as? SharedBlockageAnnotation {
                let identifier = "sharedBlockage"
                let view = mapView.dequeueReusableAnnotationView(withIdentifier: identifier) as? MKMarkerAnnotationView
                    ?? MKMarkerAnnotationView(annotation: sharedBlockageAnnotation, reuseIdentifier: identifier)
                view.annotation = sharedBlockageAnnotation
                view.markerTintColor = .systemRed
                view.glyphImage = UIImage(systemName: "exclamationmark.triangle.fill")
                view.displayPriority = .defaultLow
                view.canShowCallout = true
                view.alpha = sharedBlockageAnnotation.blockage.mapOpacity
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

/// "Aller à" universel (Bloc 4) — pointillés cyan, jamais confondu avec la trace, la route
/// Nav ou le détour.
final class GoToPolyline: MKPolyline {}

/// "Reprendre la trace ici" (Bloc 3) — pointillés bleus, jamais confondus avec la trace, le
/// détour (rouge) ou "Aller à" (cyan).
final class ResumePolyline: MKPolyline {}

final class ResumePinAnnotation: NSObject, MKAnnotation {
    let coordinate: CLLocationCoordinate2D
    var title: String? { "Reprendre ici" }

    init(coordinate: CLLocationCoordinate2D) {
        self.coordinate = coordinate
    }
}

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

final class SharedBlockageAnnotation: NSObject, MKAnnotation {
    let blockage: SharedBlockage
    var coordinate: CLLocationCoordinate2D { blockage.coordinate.coordinate }
    var title: String? { blockage.note ?? String(localized: "Point bloqué signalé", bundle: .appLanguage) }

    init(blockage: SharedBlockage) {
        self.blockage = blockage
    }
}
