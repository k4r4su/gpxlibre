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
    let tileSource: TileSource
    let currentLocation: CLLocation?
    let headingDegrees: CLLocationDirection
    let cameraDistanceMeters: Double
    /// Zone caméra utile (spec "camera-inset") — voir MapProvider et RideOverlayLayout.
    let cameraContentInsetTop: Double
    let cameraContentInsetBottom: Double
    let cameraContentInsetLeft: Double
    let cameraContentInsetRight: Double
    let northUp: Bool
    let is2DNorthUp: Bool
    let isManualOverrideActive: Bool
    let cameraCommandToken: UUID?
    let detourRoute: DetourRoute?
    let goToGuidance: GoToGuidance?
    let sharedBlockages: [SharedBlockage]
    let chevronSpacingMeters: Double
    let onManualGesture: () -> Void
    let onStatusChange: (MapLoadStatus) -> Void
    let onLongPress: (CLLocationCoordinate2D) -> Void

    func makeUIView(context: Context) -> MLNMapView {
        let mapView = MLNMapView(frame: .zero, styleJSON: MapEngineConstants.buildInitialStyleJSON(source: tileSource))
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
        context.coordinator.currentTileSource = tileSource
        context.coordinator.onManualGesture = onManualGesture
        context.coordinator.onStatusChange = onStatusChange
        context.coordinator.onLongPress = onLongPress
        context.coordinator.armLoadWatchdog(for: mapView)
        onStatusChange(.loading)
        context.coordinator.updateContentInset(
            UIEdgeInsets(top: cameraContentInsetTop, left: cameraContentInsetLeft, bottom: cameraContentInsetBottom, right: cameraContentInsetRight),
            on: mapView
        )

        let longPress = UILongPressGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.longPressDetected))
        mapView.addGestureRecognizer(longPress)

        return mapView
    }

    func updateUIView(_ mapView: MLNMapView, context: Context) {
        context.coordinator.onManualGesture = onManualGesture
        context.coordinator.onStatusChange = onStatusChange
        context.coordinator.onLongPress = onLongPress

        if context.coordinator.currentTileSource != tileSource {
            // Changement de thème carte (#10) : source raster différente (Relief =
            // OpenTopoMap) — on recharge tout le style, ce qui redéclenche didFinishLoading
            // et réajoute trace/détour/route Nav automatiquement (code déjà générique).
            context.coordinator.currentTileSource = tileSource
            context.coordinator.armLoadWatchdog(for: mapView)
            onStatusChange(.loading)
            mapView.styleJSON = MapEngineConstants.buildInitialStyleJSON(source: tileSource)
        }

        context.coordinator.updateTraceAppearance(traceAppearance)
        context.coordinator.updateNightMode(traceAppearance.isNightMode && tileSource == .osmStandard)
        updateDetourShape(on: mapView, context: context)
        updateNavRouteShape(on: mapView, context: context)
        updateGoToShape(on: mapView, context: context)
        updateUserLocationHalo(on: mapView, context: context)
        context.coordinator.updateChevronShape(track: track, spacingMeters: chevronSpacingMeters, on: mapView)
        context.coordinator.syncSharedBlockageAnnotations(sharedBlockages, on: mapView)
        context.coordinator.updateContentInset(
            UIEdgeInsets(top: cameraContentInsetTop, left: cameraContentInsetLeft, bottom: cameraContentInsetBottom, right: cameraContentInsetRight),
            on: mapView
        )

        let isForcedCommand = context.coordinator.lastCameraCommandToken != cameraCommandToken
        context.coordinator.lastCameraCommandToken = cameraCommandToken
        guard let currentLocation, isForcedCommand || !isManualOverrideActive else { return }

        let heading = (northUp || is2DNorthUp) ? 0 : headingDegrees
        let pitch: CGFloat = is2DNorthUp ? 0 : CGFloat(RideConstants.cameraPitchDegrees)
        let offsetRatio = is2DNorthUp ? 0 : RideConstants.cameraCenterOffsetRatio
        let lookAheadCenter = RideMapView.lookAheadCoordinate(
            from: currentLocation.coordinate,
            headingDegrees: heading,
            forwardDistance: cameraDistanceMeters * offsetRatio
        )

        let camera = MLNMapCamera(
            lookingAtCenter: lookAheadCenter,
            acrossDistance: cameraDistanceMeters,
            pitch: pitch,
            heading: heading
        )

        // Animation courte pour un tap +/- ou un recentrage explicite ; lissage normal sinon.
        let duration = isForcedCommand ? RideConstants.manualZoomAnimationDurationSeconds : RideConstants.cameraAnimationDurationSeconds
        mapView.setCamera(camera, withDuration: duration, animationTimingFunction: CAMediaTimingFunction(name: .easeInEaseOut))
    }

    /// "Aller à" universel (Bloc 4) — guidage parallèle, jamais un remplacement de la trace
    /// ou de la route Nav, toujours rendu en pointillés cyan (voir didFinishLoading).
    private func updateGoToShape(on mapView: MLNMapView, context: Context) {
        guard let style = mapView.style,
              let source = style.source(withIdentifier: MapEngineConstants.goToSourceIdentifier) as? MLNShapeSource
        else { return }

        guard let goToGuidance, goToGuidance.coordinates.count > 1 else {
            source.shape = nil
            return
        }
        let coordinates = goToGuidance.coordinates
        source.shape = MLNPolyline(coordinates: coordinates, count: UInt(coordinates.count))
    }

    /// Halo de contraste (spec "fab-contrast") — même principe que le casing de la trace :
    /// un disque qui reste visible sur fond clair ET sur fond sombre, sous le point natif
    /// (celui-ci reste dessiné par MapLibre par-dessus, en UIView, donc toujours au-dessus).
    private func updateUserLocationHalo(on mapView: MLNMapView, context: Context) {
        guard let style = mapView.style,
              let source = style.source(withIdentifier: MapEngineConstants.userLocationHaloSourceIdentifier) as? MLNShapeSource
        else { return }

        guard let currentLocation else {
            source.shape = nil
            return
        }
        let point = MLNPointAnnotation()
        point.coordinate = currentLocation.coordinate
        source.shape = point
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
        private var sharedBlockages: [SharedBlockage] = []
        private var sharedBlockageAnnotations: [SharedBlockageMLNAnnotation] = []
        var traceAppearance = TraceAppearance()
        var lastCameraCommandToken: UUID?
        var currentTileSource: TileSource = .osmStandard
        private var currentContentInset: UIEdgeInsets?
        var onManualGesture: (() -> Void)?
        var onStatusChange: ((MapLoadStatus) -> Void)?
        var onLongPress: ((CLLocationCoordinate2D) -> Void)?

        private weak var trackCasingLayer: MLNLineStyleLayer?
        private weak var trackColorLayer: MLNLineStyleLayer?
        private weak var rasterLayer: MLNRasterStyleLayer?
        fileprivate weak var chevronLayerRef: MLNSymbolStyleLayer?
        /// Clé (trackID, nombre de points, espacement) — évite tout recalcul des chevrons
        /// tant que ni la trace ni l'espacement n'ont réellement changé (Bloc 6, performance :
        /// "jamais de rebuild en réponse aux updates CoreLocation").
        private var currentChevronKey: String?
        private var isNightMode = false

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

        /// Mode nuit : assombrit le fond raster OSM (pas de tuiles sombres dédiées, gratuites,
        /// disponibles) plutôt que de changer de source — même technique que beaucoup d'apps
        /// nav qui appliquent un filtre plutôt que d'héberger un second jeu de tuiles.
        func updateNightMode(_ nightMode: Bool) {
            guard nightMode != isNightMode else { return }
            isNightMode = nightMode
            rasterLayer?.maximumRasterBrightness = NSExpression(forConstantValue: nightMode ? 0.55 : 1.0)
            rasterLayer?.rasterSaturation = NSExpression(forConstantValue: nightMode ? -0.4 : 0.0)
        }

        /// Zone caméra utile (spec "camera-inset") : `centerCoordinate`/`lookingAtCenter` se
        /// recentrent sur le rectangle INSET, pas sur la vue pleine — c'est ce qui garantit que
        /// la position reste dans la zone visible réelle, jamais sous le roadbook/tab bar.
        func updateContentInset(_ inset: UIEdgeInsets, on mapView: MLNMapView) {
            guard currentContentInset != inset else { return }
            currentContentInset = inset
            mapView.contentInset = inset
        }

        /// Chevrons de direction (spec "per-track-settings") : recalculés UNIQUEMENT si la
        /// trace ou l'espacement a changé (clé trackID+nombre de points+espacement) — jamais
        /// à chaque frame/update de position (Bloc 6, performance).
        func updateChevronShape(track: GPXTrack?, spacingMeters: Double, on mapView: MLNMapView) {
            guard let style = mapView.style,
                  let source = style.source(withIdentifier: MapEngineConstants.chevronSourceIdentifier) as? MLNShapeSource
            else { return }

            guard let track, track.points.count > 1 else {
                if currentChevronKey != nil {
                    currentChevronKey = nil
                    source.shape = nil
                }
                return
            }

            let key = "\(track.id.uuidString)-\(track.points.count)-\(spacingMeters)"
            guard key != currentChevronKey else { return }
            currentChevronKey = key

            let chevrons = DirectionChevronComputer.chevrons(for: track.points, spacingMeters: spacingMeters)
            let features = chevrons.map { chevron -> MLNPointFeature in
                let feature = MLNPointFeature()
                feature.coordinate = chevron.coordinate
                feature.attributes = ["bearing": chevron.bearingDegrees]
                return feature
            }
            source.shape = MLNShapeCollectionFeature(shapes: features)
        }

        /// Petit chevron plein pointant vers le HAUT au repos (0°) — `icon-rotate` tourne en
        /// degrés horaires depuis le nord comme un cap boussole, donc l'icône doit être
        /// dessinée pointant nord pour que `bearing` (aussi un cap boussole) corresponde
        /// directement, sans décalage de 90°. Couleur de la trace + liseré sombre pour rester
        /// lisible sur fond clair ET sombre — même logique que le casing de la trace.
        static func chevronImage(color: UIColor) -> UIImage {
            let size = CGSize(width: 22, height: 22)
            let renderer = UIGraphicsImageRenderer(size: size)
            return renderer.image { _ in
                let path = UIBezierPath()
                path.move(to: CGPoint(x: size.width / 2, y: size.height * 0.18))
                path.addLine(to: CGPoint(x: size.width * 0.82, y: size.height * 0.78))
                path.addLine(to: CGPoint(x: size.width * 0.18, y: size.height * 0.78))
                path.close()
                color.setFill()
                path.fill()
                UIColor.black.withAlphaComponent(0.55).setStroke()
                path.lineWidth = 1.5
                path.stroke()
            }
        }

        /// Base partagée des points bloqués (Bloc 5) : indépendant du style (contrairement
        /// aux sources/couches trace-détour-route), donc jamais perturbé par un rechargement
        /// de style (changement de thème carte, #10) — pas besoin de re-synchroniser à
        /// `didFinishLoading` comme pour checkpoints/waypoints ci-dessus.
        func syncSharedBlockageAnnotations(_ blockages: [SharedBlockage], on mapView: MLNMapView) {
            guard sharedBlockages != blockages else { return }
            sharedBlockages = blockages
            mapView.removeAnnotations(sharedBlockageAnnotations)
            sharedBlockageAnnotations = blockages.map(SharedBlockageMLNAnnotation.init)
            mapView.addAnnotations(sharedBlockageAnnotations)
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

            rasterLayer = style.layer(withIdentifier: MapEngineConstants.rasterLayerIdentifier) as? MLNRasterStyleLayer
            if traceAppearance.isNightMode {
                isNightMode = false // force l'application au premier passage
                updateNightMode(true)
            }

            // Relief GPU (spec "hillshade-clean") : uniquement sous OSM standard — OpenTopoMap
            // a déjà son ombrage intégré, en ajouter un second serait redondant. Construit une
            // seule fois ici (le style entier se recharge de toute façon au changement de
            // thème, donc pas besoin d'un chemin de mise à jour séparé) ; jamais retouché par
            // la boucle de position ou de zoom.
            if currentTileSource == .osmStandard, let rasterLayer {
                let demOptions: [MLNTileSourceOption: Any] = [
                    .demEncoding: NSNumber(value: MLNDEMEncoding.terrarium.rawValue),
                    .maximumZoomLevel: MapEngineConstants.hillshadeMaxZoomLevel,
                ]
                let demSource = MLNRasterDEMSource(
                    identifier: MapEngineConstants.hillshadeSourceIdentifier,
                    tileURLTemplates: [MapEngineConstants.hillshadeDEMTileURLTemplate],
                    options: demOptions
                )
                style.addSource(demSource)
                let hillshadeLayer = MLNHillshadeStyleLayer(identifier: MapEngineConstants.hillshadeLayerIdentifier, source: demSource)
                hillshadeLayer.hillshadeExaggeration = NSExpression(forConstantValue: MapEngineConstants.hillshadeExaggerationDefault)
                style.insertLayer(hillshadeLayer, above: rasterLayer)
            }

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

            // "Aller à" universel (Bloc 4) : toujours cyan pointillé, jamais confondu avec la
            // trace (couleur choisie), la route Nav (bleu) ou le détour (rouge).
            let goToSource = MLNShapeSource(identifier: MapEngineConstants.goToSourceIdentifier, shape: nil, options: nil)
            style.addSource(goToSource)
            let goToLayer = MLNLineStyleLayer(identifier: MapEngineConstants.goToLayerIdentifier, source: goToSource)
            goToLayer.lineColor = NSExpression(forConstantValue: UIColor.systemCyan)
            goToLayer.lineWidth = NSExpression(forConstantValue: traceAppearance.lineWidth)
            goToLayer.lineDashPattern = NSExpression(forConstantValue: [6, 6])

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

            // Halo de contraste sous le point de position natif (spec "fab-contrast") : disque
            // blanc cerné d'un trait sombre, lisible sur fond clair ET sur fond sombre — le
            // point natif MapLibre (UIView) reste toujours rendu par-dessus.
            let haloSource = MLNShapeSource(identifier: MapEngineConstants.userLocationHaloSourceIdentifier, shape: nil, options: nil)
            style.addSource(haloSource)
            let haloLayer = MLNCircleStyleLayer(identifier: MapEngineConstants.userLocationHaloLayerIdentifier, source: haloSource)
            haloLayer.circleRadius = NSExpression(forConstantValue: 13)
            haloLayer.circleColor = NSExpression(forConstantValue: UIColor.white)
            haloLayer.circleStrokeColor = NSExpression(forConstantValue: UIColor.black.withAlphaComponent(0.55))
            haloLayer.circleStrokeWidth = NSExpression(forConstantValue: 3)
            style.addLayer(haloLayer)

            // Chevrons de direction par trace (spec "per-track-settings") : icône enregistrée
            // une fois, source vide au chargement — remplie par updateChevronShape (diff par
            // trace+espacement, jamais reconstruite par frame). Couleur trace + contour pour
            // rester lisible sur n'importe quel fond, cf. le casing de la trace.
            style.setImage(Self.chevronImage(color: traceAppearance.color), forName: MapEngineConstants.chevronIconName)
            let chevronSource = MLNShapeSource(identifier: MapEngineConstants.chevronSourceIdentifier, shape: nil, options: nil)
            style.addSource(chevronSource)
            let chevronLayer = MLNSymbolStyleLayer(identifier: MapEngineConstants.chevronLayerIdentifier, source: chevronSource)
            chevronLayer.iconImageName = NSExpression(forConstantValue: MapEngineConstants.chevronIconName)
            chevronLayer.iconRotation = NSExpression(forKeyPath: "bearing")
            chevronLayer.iconRotationAlignment = NSExpression(forConstantValue: "map")
            chevronLayer.iconAllowsOverlap = NSExpression(forConstantValue: true)
            chevronLayer.iconIgnoresPlacement = NSExpression(forConstantValue: true)
            chevronLayer.minimumZoomLevel = Float(MapEngineConstants.chevronMinZoom)
            style.addLayer(chevronLayer)
            chevronLayerRef = chevronLayer

            // Détour, route Nav et "Aller à" ajoutés après la trace : ils doivent rester
            // visibles au-dessus.
            style.addLayer(detourLayer)
            style.addLayer(navRouteLayer)
            style.addLayer(goToLayer)

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
            if let sharedBlockageAnnotation = annotation as? SharedBlockageMLNAnnotation {
                let view = annotationView(on: mapView, identifier: "sharedBlockage", annotation: sharedBlockageAnnotation, tint: .systemRed, systemImageName: "exclamationmark.triangle.fill", size: 30)
                view.alpha = sharedBlockageAnnotation.blockage.mapOpacity
                return view
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

final class SharedBlockageMLNAnnotation: NSObject, MLNAnnotation {
    let blockage: SharedBlockage
    var coordinate: CLLocationCoordinate2D { blockage.coordinate.coordinate }
    var title: String? { blockage.note ?? "Point bloqué signalé" }

    init(blockage: SharedBlockage) {
        self.blockage = blockage
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
