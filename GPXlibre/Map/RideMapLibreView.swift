import SwiftUI
import MapLibre
import CoreLocation

/// Spec "replay-marker-heading-x2" (it17, Bloc 4) : passé par `.environment(...)` plutôt
/// qu'en paramètre d'init — `RideMapLibreView` conforme à `MapProvider`, dont l'init requis
/// par le protocole a une signature EXACTE et fixe (voir MapProvider.swift) ; y ajouter un
/// paramètre casse la conformité (le memberwise init synthétisé ne correspond plus). Lu via
/// `context.environment` dans `updateUIView`, patron standard pour un `UIViewRepresentable`
/// qui a besoin d'une donnée sans toucher à son init.
private struct DebugReplayMarkerActiveKey: EnvironmentKey {
    static let defaultValue = false
}

extension EnvironmentValues {
    var isDebugReplayMarkerActive: Bool {
        get { self[DebugReplayMarkerActiveKey.self] }
        set { self[DebugReplayMarkerActiveKey.self] = newValue }
    }
}

/// Spec "slope-warning-native" (it19) — mêmes raisons que `isDebugReplayMarkerActive` ci-dessus :
/// `RideMapLibreView` conforme à `MapProvider`, dont l'init a une signature fixe (voir
/// MapProvider.swift) — y ajouter un paramètre casse la conformité, donc passé par
/// `.environment(...)` plutôt qu'en paramètre d'init.
private struct SlopeWarningsEnabledKey: EnvironmentKey {
    static let defaultValue = false
}
private struct SlopeWarningThresholdPercentKey: EnvironmentKey {
    static let defaultValue = RideConstants.slopeWarningThresholdPercentDefault
}

extension EnvironmentValues {
    var slopeWarningsEnabled: Bool {
        get { self[SlopeWarningsEnabledKey.self] }
        set { self[SlopeWarningsEnabledKey.self] = newValue }
    }
    var slopeWarningThresholdPercent: Double {
        get { self[SlopeWarningThresholdPercentKey.self] }
        set { self[SlopeWarningThresholdPercentKey.self] = newValue }
    }
}

/// Spec "nav-classic-rebuild" (it21, "tracé de progression... distinction parcouru/restant") —
/// même contrainte `MapProvider` (signature fixe) que les clés ci-dessus : nombre de
/// coordonnées de `navRoute.coordinates` déjà parcourues, `nil`/`0` tant qu'aucune projection
/// n'a pu être calculée (comportement identique à avant it21, une seule couleur).
private struct NavRouteTraveledCoordinateCountKey: EnvironmentKey {
    static let defaultValue: Int? = nil
}

extension EnvironmentValues {
    var navRouteTraveledCoordinateCount: Int? {
        get { self[NavRouteTraveledCoordinateCountKey.self] }
        set { self[NavRouteTraveledCoordinateCountKey.self] = newValue }
    }
}

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
    let mapSource: MapSourceSelection
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
    let resumeGuidance: ResumeGuidance?
    let sharedBlockages: [SharedBlockage]
    let chevronSpacingMeters: Double
    let onManualGesture: () -> Void
    let onStatusChange: (MapLoadStatus) -> Void
    let onLongPress: (CLLocationCoordinate2D) -> Void
    let onTrackTap: (CLLocationCoordinate2D, Double) -> Void

    func makeUIView(context: Context) -> MLNMapView {
        let mapView = MLNMapView(frame: .zero, styleJSON: MapEngineConstants.buildStyleJSON(for: mapSource))
        mapView.delegate = context.coordinator
        mapView.showsUserLocation = true
        mapView.userTrackingMode = .none
        mapView.showsCompassView = false
        mapView.showsScale = false
        mapView.showsAttributionButton = true
        mapView.logoView.isHidden = true
        // Spec "2d-only" (it11) : plus de vue perspective nulle part — on désactive le geste
        // natif à deux doigts qui inclinerait la caméra, pas seulement la valeur par défaut.
        mapView.isPitchEnabled = false

        context.coordinator.track = track
        context.coordinator.checkpoints = checkpoints
        context.coordinator.waypoints = waypoints
        context.coordinator.traceAppearance = traceAppearance
        context.coordinator.currentMapSource = mapSource
        context.coordinator.onManualGesture = onManualGesture
        context.coordinator.onStatusChange = onStatusChange
        context.coordinator.onLongPress = onLongPress
        context.coordinator.onTrackTap = onTrackTap
        context.coordinator.armLoadWatchdog(for: mapView)
        onStatusChange(.loading)
        context.coordinator.updateContentInset(
            UIEdgeInsets(top: cameraContentInsetTop, left: cameraContentInsetLeft, bottom: cameraContentInsetBottom, right: cameraContentInsetRight),
            on: mapView
        )

        let longPress = UILongPressGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.longPressDetected))
        mapView.addGestureRecognizer(longPress)

        // Tap simple sur la trace (Bloc 3, "resume-at-point") : notre propre reconnaisseur
        // bloquerait par défaut ceux intégrés à MLNMapView (double-tap zoom, sélection
        // d'annotation) — pattern documenté dans MLNMapView.h, `require(toFail:)` sur chacun
        // des UITapGestureRecognizer déjà présents pour ne jamais leur voler le geste.
        let trackTap = UITapGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.trackTapDetected))
        for recognizer in mapView.gestureRecognizers ?? [] where recognizer is UITapGestureRecognizer {
            trackTap.require(toFail: recognizer)
        }
        mapView.addGestureRecognizer(trackTap)

        return mapView
    }

    func updateUIView(_ mapView: MLNMapView, context: Context) {
        context.coordinator.onManualGesture = onManualGesture
        context.coordinator.onStatusChange = onStatusChange
        context.coordinator.onLongPress = onLongPress
        context.coordinator.onTrackTap = onTrackTap

        if context.coordinator.currentMapSource != mapSource {
            // Changement de fond de carte (thème raster #10 OU bascule raster/vectoriel,
            // spec "vector-pmtiles" it11) — on recharge tout le style, ce qui redéclenche
            // didFinishLoading et réajoute trace/détour/route Nav automatiquement (code déjà
            // générique). La caméra (position/zoom) n'est JAMAIS touchée par ce bloc — aucun
            // risque de saut, même garantie que le changement de thème existant.
            context.coordinator.currentMapSource = mapSource
            context.coordinator.armLoadWatchdog(for: mapView)
            onStatusChange(.loading)
            mapView.styleJSON = MapEngineConstants.buildStyleJSON(for: mapSource)
        }

        context.coordinator.updateTraceAppearance(traceAppearance)
        // Décision de scope (it11) : le dimming nuit (filtre luminosité/saturation) ne
        // s'applique qu'au raster OSM standard — le style vectoriel embarqué n'a qu'une
        // variante claire pour l'instant (voir docs/tuile-sources.md).
        context.coordinator.updateNightMode(traceAppearance.isNightMode && mapSource == .raster(.osmStandard))
        context.coordinator.updateTrackShape(track, on: mapView)
        updateDetourShape(on: mapView, context: context)
        updateNavRouteShape(on: mapView, context: context)
        updateGoToShape(on: mapView, context: context)
        updateResumeShape(on: mapView, context: context)
        context.coordinator.updateChevronShape(track: track, configuredSpacingMeters: chevronSpacingMeters, on: mapView)
        context.coordinator.updateSlopeWarnings(
            track: track,
            enabled: context.environment.slopeWarningsEnabled,
            thresholdPercent: context.environment.slopeWarningThresholdPercent,
            on: mapView
        )
        context.coordinator.syncSharedBlockageAnnotations(sharedBlockages, on: mapView)
        context.coordinator.updateDebugReplayMarker(
            coordinate: context.environment.isDebugReplayMarkerActive ? currentLocation?.coordinate : nil,
            on: mapView
        )
        context.coordinator.updateContentInset(
            UIEdgeInsets(top: cameraContentInsetTop, left: cameraContentInsetLeft, bottom: cameraContentInsetBottom, right: cameraContentInsetRight),
            on: mapView
        )

        let isForcedCommand = context.coordinator.lastCameraCommandToken != cameraCommandToken
        context.coordinator.lastCameraCommandToken = cameraCommandToken
        guard let currentLocation, isForcedCommand || !isManualOverrideActive else { return }

        let heading = (northUp || is2DNorthUp) ? 0 : headingDegrees
        // Fix "explore-zoom-anchoring" (it14, Bloc 11, bug terrain confirmé : "pan carte puis
        // tap +/- revient sur la position GPS au lieu de zoomer le secteur") : un tap +/- (ou
        // recentrage) pendant l'exploration (drag actif, isManualOverrideActive) doit zoomer
        // AUTOUR DU CENTRE ÉCRAN ACTUEL, pas re-sauter sur le GPS — seul `recenterCamera()`
        // doit ramener sur la position réelle, et il le fait déjà en désarmant
        // `isManualOverrideActive` avant ce point (voir RideSessionManager.recenterCamera),
        // donc cette branche ne le concerne jamais. En suivi normal (non exploré),
        // `mapView.camera.centerCoordinate` vaut de toute façon déjà `currentLocation.coordinate`
        // (dernière caméra appliquée) : comportement inchangé dans ce cas.
        let lookingAtCenter = (isForcedCommand && isManualOverrideActive)
            ? mapView.camera.centerCoordinate
            : currentLocation.coordinate
        // Spec "2d-only" (it11) : la vue reste TOUJOURS plate, plus de pitch pilotable — la
        // carte ne bascule plus jamais en perspective, y compris en Ride cap-en-haut.
        // Fix "position-anchor" (Bug 2) : plus de décalage géographique heuristique vers
        // l'avant — lookingAtCenter est la position réelle EN SUIVI ; tout l'ancrage vertical
        // (POSITION_ANCHOR_RATIO) vient de `contentInset.top`, déjà appliqué via
        // `updateContentInset` ci-dessus. Voir RideOverlayLayout.computeMapInsets.
        let camera = MLNMapCamera(
            lookingAtCenter: lookingAtCenter,
            acrossDistance: cameraDistanceMeters,
            pitch: 0,
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

    /// "Reprendre la trace ici" (Bloc 3) — mutation de `.shape` uniquement (même patron que
    /// le détour/la route Nav), jamais de reconstruction de couche. Le pin reste visible même
    /// en mode dégradé (pas de route calculée, `routeCoordinates` vide) ; seul le tracé
    /// pointillé disparaît dans ce cas.
    private func updateResumeShape(on mapView: MLNMapView, context: Context) {
        guard let style = mapView.style,
              let routeSource = style.source(withIdentifier: MapEngineConstants.resumeRouteSourceIdentifier) as? MLNShapeSource,
              let pinSource = style.source(withIdentifier: MapEngineConstants.resumePinSourceIdentifier) as? MLNShapeSource
        else { return }

        guard let resumeGuidance else {
            routeSource.shape = nil
            pinSource.shape = nil
            return
        }

        if resumeGuidance.routeCoordinates.count > 1 {
            routeSource.shape = MLNPolyline(coordinates: resumeGuidance.routeCoordinates, count: UInt(resumeGuidance.routeCoordinates.count))
        } else {
            routeSource.shape = nil
        }
        let pin = MLNPointAnnotation()
        pin.coordinate = resumeGuidance.pinCoordinate
        pinSource.shape = pin
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

    /// Spec "nav-classic-rebuild" (it21) : distinction visuelle parcouru/restant — DEUX
    /// features dans la MÊME source (`traveled: true/false` en attribut), filtrées chacune par
    /// un `NSPredicate` sur sa propre couche (`navRouteTraveledLayer`/`navRouteColorLayer`,
    /// voir `syncNavRouteLayers`) — plutôt qu'une expression de couleur data-driven (API
    /// `NSExpression` TERNARY jamais éprouvée ailleurs dans ce fichier, contrairement à
    /// `.predicate`, déjà bien établi côté MapLibre). Toujours DEUX features même sans
    /// progression connue (`traveled: false` partout) : un seul code path, pas de branche
    /// spéciale "pas encore de split".
    private func updateNavRouteShape(on mapView: MLNMapView, context: Context) {
        guard let style = mapView.style,
              let source = style.source(withIdentifier: MapEngineConstants.navRouteSourceIdentifier) as? MLNShapeSource
        else { return }

        guard let navRoute, navRoute.coordinates.count > 1 else {
            source.shape = nil
            return
        }
        let coordinates = navRoute.coordinates
        let traveledCount = min(max(context.environment.navRouteTraveledCoordinateCount ?? 0, 0), coordinates.count)

        guard traveledCount > 1, traveledCount < coordinates.count else {
            // Rien parcouru (départ) ou plus rien à distinguer (arrivée) — une seule feature,
            // jamais "traveled".
            let feature = MLNPolylineFeature(coordinates: coordinates, count: UInt(coordinates.count))
            feature.attributes = ["traveled": false]
            source.shape = feature
            return
        }

        // Chevauche d'UN point (traveledCount - 1) pour que les deux segments se rejoignent
        // visuellement sans discontinuité au point de jonction.
        let traveledCoordinates = Array(coordinates[0..<traveledCount])
        let remainingCoordinates = Array(coordinates[(traveledCount - 1)...])
        let traveledFeature = MLNPolylineFeature(coordinates: traveledCoordinates, count: UInt(traveledCoordinates.count))
        traveledFeature.attributes = ["traveled": true]
        let remainingFeature = MLNPolylineFeature(coordinates: remainingCoordinates, count: UInt(remainingCoordinates.count))
        remainingFeature.attributes = ["traveled": false]
        source.shape = MLNShapeCollectionFeature(shapes: [traveledFeature, remainingFeature])
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
        var currentMapSource: MapSourceSelection = .raster(.osmStandard)
        private var currentContentInset: UIEdgeInsets?
        var onManualGesture: (() -> Void)?
        var onStatusChange: ((MapLoadStatus) -> Void)?
        var onLongPress: ((CLLocationCoordinate2D) -> Void)?
        var onTrackTap: ((CLLocationCoordinate2D, Double) -> Void)?

        private weak var trackSourceRef: MLNShapeSource?
        private weak var trackCasingLayer: MLNLineStyleLayer?
        private weak var trackColorLayer: MLNLineStyleLayer?
        private weak var navRouteCasingLayer: MLNLineStyleLayer?
        private weak var navRouteColorLayer: MLNLineStyleLayer?
        private weak var navRouteTraveledLayer: MLNLineStyleLayer?
        private weak var detourLayerRef: MLNLineStyleLayer?
        private weak var goToLayerRef: MLNLineStyleLayer?
        private weak var resumeRouteCasingLayer: MLNLineStyleLayer?
        private weak var resumeRouteColorLayer: MLNLineStyleLayer?
        private weak var resumePinLayerRef: MLNCircleStyleLayer?
        private weak var rasterLayer: MLNRasterStyleLayer?
        fileprivate weak var chevronLayerRef: MLNSymbolStyleLayer?
        /// Fix "chevrons-live-refresh" (it13, bug terrain critique) : comparaison par VALEUR
        /// complète (même patron que `updateTrackShape`/`newTrack != track`), jamais une clé
        /// string — l'ancienne clé `"\(id)-\(points.count)-\(spacing)"` était aveugle à l'ORDRE
        /// des points : un toggle de sens (A→B/B→A) ou un nouveau départ personnalisé ne change
        /// ni l'id, ni le nombre de points, ni l'espacement, donc les chevrons ne se
        /// recalculaient JAMAIS après un changement de sens sur la carte réelle (seule la
        /// miniature Bibliothèque, fix "biblio-direction-live-refresh" it12, était concernée —
        /// la carte Ride elle-même ne l'avait jamais été, non vérifiée tactilement avant ce
        /// retour terrain). `GPXTrack: Hashable` compare `points` en entier, donc sensible à
        /// l'ordre — exactement ce qu'il faut ici.
        private var currentChevronTrack: GPXTrack?
        private var currentChevronSpacing: Double?
        /// Mémoïsation (spec "slope-warning-native", it19) — même patron que les chevrons :
        /// ne recalcule que si la trace, l'activation ou le seuil ont réellement changé, jamais
        /// à chaque fix GPS.
        private var currentSlopeWarningTrack: GPXTrack?
        private var currentSlopeWarningEnabled: Bool?
        private var currentSlopeWarningThreshold: Double?
        private var isNightMode = false
        /// Référence faible au style courant (fix "chevrons-live-refresh") : permet de
        /// régénérer l'icône chevron (couleur) depuis `updateTraceAppearance`, qui n'avait
        /// auparavant aucun moyen d'atteindre `style.setImage` — l'icône restait figée dans
        /// l'ancienne couleur après un changement de couleur de trace, même si la ligne
        /// elle-même se mettait à jour en direct.
        private weak var styleRef: MLNStyle?

        private var loadWatchdog: Timer?
        private var didAttemptFallback = false
        private var didFinishLoadingOnce = false

        // Spec "2d-only" (it11) : plus de .gestureTilt — le pitch est désactivé
        // (mapView.pitchEnabled = false), cette raison ne peut plus jamais se produire.
        private static let gestureReasonMask: MLNCameraChangeReason = [
            .gesturePan, .gesturePinch, .gestureRotate, .gestureZoomIn, .gestureZoomOut, .gestureOneFingerZoom,
        ]

        @objc func longPressDetected(_ gesture: UILongPressGestureRecognizer) {
            guard gesture.state == .began, let mapView = gesture.view as? MLNMapView else { return }
            let point = gesture.location(in: mapView)
            let coordinate = mapView.convert(point, toCoordinateFrom: mapView)
            onLongPress?(coordinate)
        }

        /// Bloc 3 "resume-at-point" : la coordonnée SEULE ne suffit pas à décider si le tap
        /// est "sur la trace" — la tolérance en points-écran dépend du zoom courant, convertie
        /// ici en mètres via `metersPerPointAtLatitude(_:)` (le test de proximité à la trace
        /// reste dans RideView, comme pour `onLongPress` — pas de décision dupliquée ici).
        @objc func trackTapDetected(_ gesture: UITapGestureRecognizer) {
            guard gesture.state == .ended, let mapView = gesture.view as? MLNMapView else { return }
            let point = gesture.location(in: mapView)
            let coordinate = mapView.convert(point, toCoordinateFrom: mapView)
            let toleranceMeters = mapView.metersPerPoint(atLatitude: coordinate.latitude) * RideConstants.resumeTapToleranceScreenPoints
            onTrackTap?(coordinate, toleranceMeters)
        }

        /// Les propriétés de style MapLibre sont mutables en direct (contrairement aux
        /// MKOverlayRenderer de MapKit, mis en cache) : pas besoin de retirer/recréer la
        /// couche pour appliquer un nouveau réglage — Bloc 3, "appliqué en direct".
        func updateTraceAppearance(_ appearance: TraceAppearance) {
            guard appearance != traceAppearance else { return }
            // Fix "chevrons-live-refresh" (it13) : l'icône chevron est une image bitmap générée
            // une fois (didFinishLoading) — un changement de COULEUR ne la régénère jamais
            // autrement, contrairement aux couches de ligne ci-dessous (mutées en direct).
            let colorChanged = appearance.colorPreset != traceAppearance.colorPreset
            traceAppearance = appearance
            trackCasingLayer?.lineColor = NSExpression(forConstantValue: appearance.casingColor)
            trackCasingLayer?.lineWidth = NSExpression(forConstantValue: appearance.casingWidth)
            trackColorLayer?.lineColor = NSExpression(forConstantValue: appearance.color)
            trackColorLayer?.lineWidth = NSExpression(forConstantValue: appearance.lineWidth)
            // Fix "nav-route-overlay" (Bug 1) : épaisseur réglable "même logique que la trace"
            // — la route Nav, le détour et "Aller à" suivent aussi l'épaisseur/contour choisis,
            // en mutant les couches existantes (jamais de reconstruction, jamais de flash).
            navRouteCasingLayer?.lineColor = NSExpression(forConstantValue: appearance.casingColor)
            navRouteCasingLayer?.lineWidth = NSExpression(forConstantValue: appearance.casingWidth)
            navRouteColorLayer?.lineWidth = NSExpression(forConstantValue: appearance.lineWidth)
            navRouteTraveledLayer?.lineWidth = NSExpression(forConstantValue: appearance.lineWidth)
            detourLayerRef?.lineWidth = NSExpression(forConstantValue: appearance.detourLineWidth)
            goToLayerRef?.lineWidth = NSExpression(forConstantValue: appearance.goToLineWidth)
            // "Reprendre ici" (Bloc 3) : même classe de poids visuel que le détour.
            resumeRouteCasingLayer?.lineColor = NSExpression(forConstantValue: appearance.casingColor)
            resumeRouteCasingLayer?.lineWidth = NSExpression(forConstantValue: appearance.casingWidth)
            resumeRouteColorLayer?.lineWidth = NSExpression(forConstantValue: appearance.detourLineWidth)
            if colorChanged {
                styleRef?.setImage(Self.chevronImage(color: appearance.color), forName: MapEngineConstants.chevronIconName)
            }
        }

        private func applyTrackShape(_ track: GPXTrack?, to source: MLNShapeSource) {
            guard let track, track.points.count > 1 else {
                source.shape = nil
                return
            }
            let coordinates = track.points.map(\.coordinate)
            source.shape = MLNPolyline(coordinates: coordinates, count: UInt(coordinates.count))
        }

        /// Trace principale (Mode Trace) — pur consommateur réactif de `track`, donc de
        /// `activeTrackID`/`isDisplayed` (fix "trace-render-state-channel") : mutation directe
        /// de `.shape` à chaque update, jamais de rebuild de source/couche. Dédupliqué sur
        /// l'égalité de valeur de `GPXTrack` (Hashable) — `RideView` reconstruit un `GPXTrack`
        /// via `reordered(using:)` à CHAQUE update de position, mais son contenu ne change que
        /// si la trace active ou son réglage de sens/départ change réellement, donc ce garde
        /// évite de reconstruire un `MLNPolyline` à chaque fix GPS.
        func updateTrackShape(_ newTrack: GPXTrack?, on mapView: MLNMapView) {
            guard let style = mapView.style,
                  let source = trackSourceRef ?? (style.source(withIdentifier: MapEngineConstants.trackSourceIdentifier) as? MLNShapeSource)
            else { return }
            guard newTrack != track else { return }
            track = newTrack
            applyTrackShape(newTrack, to: source)
        }

        /// Mode nuit : assombrit le fond raster OSM (pas de tuiles sombres dédiées, gratuites,
        /// disponibles) plutôt que de changer de source — même technique que beaucoup d'apps
        /// nav qui appliquent un filtre plutôt que d'héberger un second jeu de tuiles.
        func updateNightMode(_ nightMode: Bool) {
            guard nightMode != isNightMode else { return }
            isNightMode = nightMode
            rasterLayer?.maximumRasterBrightness = NSExpression(forConstantValue: nightMode ? 0.55 : 1.0)
            rasterLayer?.rasterSaturation = NSExpression(forConstantValue: nightMode ? -0.4 : 0.0)
            // Fix "nav-route-overlay" (Bug 1) : couleur "bleu nuit / cyan clair" selon le thème
            // — mutation de couche existante, jamais de reconstruction.
            navRouteColorLayer?.lineColor = NSExpression(forConstantValue: MapEngineConstants.navRouteColor(isNightMode: nightMode))
        }

        /// Zone caméra utile (spec "camera-inset") : `centerCoordinate`/`lookingAtCenter` se
        /// recentrent sur le rectangle INSET, pas sur la vue pleine — c'est ce qui garantit que
        /// la position reste dans la zone visible réelle, jamais sous le roadbook/tab bar.
        func updateContentInset(_ inset: UIEdgeInsets, on mapView: MLNMapView) {
            guard currentContentInset != inset else { return }
            currentContentInset = inset
            mapView.contentInset = inset
        }

        /// Espacement CONFIGURÉ (réglage par trace, it11) — distinct de `currentChevronSpacing`
        /// ci-dessus qui stocke l'espacement EFFECTIF (après combinaison avec le zoom, spec
        /// "chevrons-zoom-adaptive", it17, Bloc 3). Permet à `regionIsChangingWith` de
        /// recalculer l'effectif à chaque changement de zoom sans redemander à SwiftUI.
        private var chevronConfiguredSpacingMeters: Double?

        /// Chevrons de direction (spec "per-track-settings" ; densité adaptative au zoom, spec
        /// "chevrons-zoom-adaptive", it17, Bloc 3) : recalculés UNIQUEMENT si la trace ou
        /// l'espacement EFFECTIF a changé — jamais à chaque frame/update de position (Bloc 6,
        /// performance). L'espacement effectif combine le réglage par trace et le zoom courant
        /// (`DirectionChevronComputer.adaptiveSpacingMeters`, le plus GRAND des deux) — plus
        /// aucun `minimumZoomLevel` sur la couche (bug corrigé : coupure binaire au zoom 14,
        /// remplacée par un espacement croissant mais jamais nul).
        func updateChevronShape(track: GPXTrack?, configuredSpacingMeters: Double, on mapView: MLNMapView) {
            guard let style = mapView.style,
                  let source = style.source(withIdentifier: MapEngineConstants.chevronSourceIdentifier) as? MLNShapeSource
            else { return }

            guard let track, track.points.count > 1 else {
                if currentChevronTrack != nil {
                    currentChevronTrack = nil
                    currentChevronSpacing = nil
                    chevronConfiguredSpacingMeters = nil
                    source.shape = nil
                }
                return
            }

            chevronConfiguredSpacingMeters = configuredSpacingMeters
            let effectiveSpacing = DirectionChevronComputer.adaptiveSpacingMeters(
                configuredSpacingMeters: configuredSpacingMeters,
                zoomLevel: mapView.zoomLevel
            )

            guard track != currentChevronTrack || effectiveSpacing != currentChevronSpacing else { return }
            currentChevronTrack = track
            currentChevronSpacing = effectiveSpacing

            let chevrons = DirectionChevronComputer.chevrons(for: track.points, spacingMeters: effectiveSpacing)
            let features = chevrons.map { chevron -> MLNPointFeature in
                let feature = MLNPointFeature()
                feature.coordinate = chevron.coordinate
                feature.attributes = ["bearing": chevron.bearingDegrees]
                return feature
            }
            source.shape = MLNShapeCollectionFeature(shapes: features)
        }

        /// Redéclenché en continu pendant un pincement/pan (spec "chevrons-zoom-adaptive", it17,
        /// Bloc 3, "sans saut" demandé par la checklist terrain) — le dedup ci-dessus
        /// (`effectiveSpacing != currentChevronSpacing`) limite le vrai recalcul aux SEULES
        /// transitions de palier (table à ~6 valeurs), jamais à chaque frame malgré la fréquence
        /// d'appel de ce delegate pendant un geste.
        func mapView(_ mapView: MLNMapView, regionIsChangingWith reason: MLNCameraChangeReason) {
            guard let track = currentChevronTrack, let configuredSpacing = chevronConfiguredSpacingMeters else { return }
            updateChevronShape(track: track, configuredSpacingMeters: configuredSpacing, on: mapView)
        }

        /// Avertissements de pente (spec "slope-warning-native", it19) : symboles PONCTUELS
        /// (jamais un dégradé continu) recalculés uniquement si la trace, l'activation ou le
        /// seuil ont changé — mémoïsation identique au patron des chevrons. Ne dépend jamais du
        /// zoom (contrairement aux chevrons) : la densité de pentes fortes réelles n'a aucune
        /// raison de varier avec l'affichage.
        func updateSlopeWarnings(track: GPXTrack?, enabled: Bool, thresholdPercent: Double, on mapView: MLNMapView) {
            guard let style = mapView.style,
                  let source = style.source(withIdentifier: MapEngineConstants.slopeWarningSourceIdentifier) as? MLNShapeSource
            else { return }

            guard enabled, let track, track.points.count > 1 else {
                if currentSlopeWarningTrack != nil || currentSlopeWarningEnabled == true {
                    source.shape = nil
                    currentSlopeWarningTrack = nil
                    currentSlopeWarningEnabled = enabled
                    currentSlopeWarningThreshold = thresholdPercent
                }
                return
            }

            guard track != currentSlopeWarningTrack || enabled != currentSlopeWarningEnabled || thresholdPercent != currentSlopeWarningThreshold else { return }
            currentSlopeWarningTrack = track
            currentSlopeWarningEnabled = enabled
            currentSlopeWarningThreshold = thresholdPercent

            let warnings = SlopeAnalyzer.steepGradeWarnings(
                for: track.points,
                thresholdPercent: thresholdPercent,
                minSegmentMeters: RideConstants.slopeWarningMinSegmentMeters,
                minMarkerSpacingMeters: RideConstants.slopeWarningMinMarkerSpacingMeters
            )
            let features = warnings.map { warning -> MLNPointFeature in
                let feature = MLNPointFeature()
                feature.coordinate = warning.coordinate
                feature.attributes = [
                    "iconName": warning.isClimbing ? MapEngineConstants.slopeWarningClimbIconName : MapEngineConstants.slopeWarningDescentIconName,
                ]
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

        /// Symbole "panneau routier de signalisation de pente" (spec "slope-warning-native",
        /// it19, "dans l'esprit d'un panneau routier") : triangle jaune/noir façon panneau de
        /// danger français, avec une rampe diagonale — montante (bas-gauche → haut-droite) pour
        /// une montée, descendante (haut-gauche → bas-droite) pour une descente. `iconRotation
        /// Alignment: viewport` (voir setupLayers) : reste lisible à l'écran quel que soit le
        /// cap, comme un vrai panneau routier planté au bord de la route ne tourne jamais avec
        /// la caméra.
        static func slopeWarningImage(isClimbing: Bool) -> UIImage {
            let size = CGSize(width: 32, height: 32)
            let renderer = UIGraphicsImageRenderer(size: size)
            return renderer.image { _ in
                let triangle = UIBezierPath()
                triangle.move(to: CGPoint(x: size.width / 2, y: size.height * 0.06))
                triangle.addLine(to: CGPoint(x: size.width * 0.95, y: size.height * 0.92))
                triangle.addLine(to: CGPoint(x: size.width * 0.05, y: size.height * 0.92))
                triangle.close()
                UIColor.systemYellow.setFill()
                triangle.fill()
                UIColor.black.setStroke()
                triangle.lineWidth = 2.5
                triangle.stroke()

                let ramp = UIBezierPath()
                if isClimbing {
                    ramp.move(to: CGPoint(x: size.width * 0.26, y: size.height * 0.78))
                    ramp.addLine(to: CGPoint(x: size.width * 0.74, y: size.height * 0.40))
                } else {
                    ramp.move(to: CGPoint(x: size.width * 0.26, y: size.height * 0.40))
                    ramp.addLine(to: CGPoint(x: size.width * 0.74, y: size.height * 0.78))
                }
                ramp.lineWidth = 3
                ramp.lineCapStyle = .round
                UIColor.black.setStroke()
                ramp.stroke()
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
            styleRef = style
            // Fix "chevrons-live-refresh" (it13) : un rechargement de style (changement de
            // thème/fond de carte) recrée la source chevron VIDE ci-dessous — sans ce reset, la
            // mémoisation (track+espacement inchangés) aurait fait sauter le premier
            // `updateChevronShape` qui suit, laissant la couche nouvellement créée vide.
            currentChevronTrack = nil
            currentChevronSpacing = nil

            rasterLayer = style.layer(withIdentifier: MapEngineConstants.rasterLayerIdentifier) as? MLNRasterStyleLayer
            if traceAppearance.isNightMode {
                isNightMode = false // force l'application au premier passage
                updateNightMode(true)
            }

            // Relief GPU (spec "hillshade-clean", étendu "vector-pmtiles" it11) : sous OSM
            // standard ET sous le fond vectoriel (contours/relief lisibles, demandé) —
            // JAMAIS sous OpenTopoMap, qui a déjà son propre ombrage intégré (redondant/terne
            // sinon). Ancre d'insertion différente selon le fond : juste au-dessus du calque
            // raster côté raster, juste au-dessus du calque "background" du style vectoriel
            // (avant tout landuse/route) côté vectoriel. Construit une seule fois ici (le
            // style entier se recharge de toute façon au changement de fond) ; jamais retouché
            // par la boucle de position ou de zoom.
            let hillshadeAnchorLayer: MLNStyleLayer? = {
                switch currentMapSource {
                case .raster(.osmStandard): return rasterLayer
                case .raster(.openTopoMap): return nil
                case .vectorHosted, .vectorLocal: return style.layer(withIdentifier: MapEngineConstants.vectorBackgroundLayerIdentifier)
                }
            }()
            if let hillshadeAnchorLayer {
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
                style.insertLayer(hillshadeLayer, above: hillshadeAnchorLayer)
            }

            let detourSource = MLNShapeSource(identifier: MapEngineConstants.detourSourceIdentifier, shape: nil, options: nil)
            style.addSource(detourSource)
            let detourLayer = MLNLineStyleLayer(identifier: MapEngineConstants.detourLayerIdentifier, source: detourSource)
            detourLayer.lineColor = NSExpression(forConstantValue: UIColor.systemRed)
            // Le détour DOIT être plus visible que la trace : 50% plus épais, toujours en
            // pointillés rouges, jamais confondu avec elle.
            detourLayer.lineWidth = NSExpression(forConstantValue: traceAppearance.detourLineWidth)
            detourLayer.lineDashPattern = NSExpression(forConstantValue: [10, 8])
            detourLayerRef = detourLayer

            // Route Nav (fix "nav-route-overlay") : même construction casing+couleur que la
            // trace (contour de contraste identique), sur la MÊME source — un recalcul
            // d'itinéraire ne fait que remplacer `source.shape` (voir updateNavRouteShape),
            // jamais reconstruire les couches, donc aucun flash.
            let navRouteSource = MLNShapeSource(identifier: MapEngineConstants.navRouteSourceIdentifier, shape: nil, options: nil)
            style.addSource(navRouteSource)
            let navRouteCasingLayer = MLNLineStyleLayer(identifier: MapEngineConstants.navRouteCasingLayerIdentifier, source: navRouteSource)
            navRouteCasingLayer.lineColor = NSExpression(forConstantValue: traceAppearance.casingColor)
            navRouteCasingLayer.lineWidth = NSExpression(forConstantValue: traceAppearance.casingWidth)
            style.addLayer(navRouteCasingLayer)
            self.navRouteCasingLayer = navRouteCasingLayer

            let navRouteLayer = MLNLineStyleLayer(identifier: MapEngineConstants.navRouteLayerIdentifier, source: navRouteSource)
            navRouteLayer.lineColor = NSExpression(forConstantValue: MapEngineConstants.navRouteColor(isNightMode: isNightMode))
            navRouteLayer.lineWidth = NSExpression(forConstantValue: traceAppearance.lineWidth)
            // Spec "nav-classic-rebuild" (it21) : cette couche ne montre que la portion RESTANTE
            // (voir updateNavRouteShape, attribut "traveled" posé sur chaque feature).
            navRouteLayer.predicate = NSPredicate(format: "traveled == NO")
            navRouteColorLayer = navRouteLayer

            let navRouteTraveledLayer = MLNLineStyleLayer(identifier: MapEngineConstants.navRouteTraveledLayerIdentifier, source: navRouteSource)
            navRouteTraveledLayer.lineColor = NSExpression(forConstantValue: MapEngineConstants.navRouteTraveledColor)
            navRouteTraveledLayer.lineWidth = NSExpression(forConstantValue: traceAppearance.lineWidth)
            navRouteTraveledLayer.predicate = NSPredicate(format: "traveled == YES")
            self.navRouteTraveledLayer = navRouteTraveledLayer

            // "Aller à" universel (Bloc 4) : toujours cyan pointillé, jamais confondu avec la
            // trace (couleur choisie), la route Nav (bleu) ou le détour (rouge).
            let goToSource = MLNShapeSource(identifier: MapEngineConstants.goToSourceIdentifier, shape: nil, options: nil)
            style.addSource(goToSource)
            let goToLayer = MLNLineStyleLayer(identifier: MapEngineConstants.goToLayerIdentifier, source: goToSource)
            goToLayer.lineColor = NSExpression(forConstantValue: UIColor.systemCyan)
            goToLayer.lineWidth = NSExpression(forConstantValue: traceAppearance.goToLineWidth)
            // Fix "temp-trace-dash-readability" (it13, terrain : "dashes trop espacés...
            // illisible de loin") : motif resserré ratio ~2:1 (était [6,6], ratio 1:1, et ces
            // unités multiplient la largeur de trait — un espacement énorme à l'écran).
            goToLayer.lineDashPattern = NSExpression(forConstantValue: [2, 1])
            goToLayerRef = goToLayer

            // "Reprendre la trace ici" (Bloc 3) : bleu pointillé distinct de la trace, du
            // détour (rouge) et de "Aller à" (cyan) — même construction casing+couleur que
            // la trace/route Nav, sur sa propre source (un recalcul ne fait que remplacer
            // .shape, voir updateResumeShape). Pin séparé (cercle) : reste visible même en
            // mode dégradé, quand routeCoordinates est vide (pas de réseau).
            let resumeRouteSource = MLNShapeSource(identifier: MapEngineConstants.resumeRouteSourceIdentifier, shape: nil, options: nil)
            style.addSource(resumeRouteSource)
            let resumeCasingLayer = MLNLineStyleLayer(identifier: MapEngineConstants.resumeRouteCasingLayerIdentifier, source: resumeRouteSource)
            resumeCasingLayer.lineColor = NSExpression(forConstantValue: traceAppearance.casingColor)
            resumeCasingLayer.lineWidth = NSExpression(forConstantValue: traceAppearance.casingWidth)
            style.addLayer(resumeCasingLayer)
            resumeRouteCasingLayer = resumeCasingLayer

            let resumeColorLayer = MLNLineStyleLayer(identifier: MapEngineConstants.resumeRouteLayerIdentifier, source: resumeRouteSource)
            resumeColorLayer.lineColor = NSExpression(forConstantValue: UIColor.systemBlue)
            resumeColorLayer.lineWidth = NSExpression(forConstantValue: traceAppearance.detourLineWidth)
            resumeColorLayer.lineDashPattern = NSExpression(forConstantValue: [8, 4])
            style.addLayer(resumeColorLayer)
            resumeRouteColorLayer = resumeColorLayer

            let resumePinSource = MLNShapeSource(identifier: MapEngineConstants.resumePinSourceIdentifier, shape: nil, options: nil)
            style.addSource(resumePinSource)
            let resumePinLayer = MLNCircleStyleLayer(identifier: MapEngineConstants.resumePinLayerIdentifier, source: resumePinSource)
            resumePinLayer.circleRadius = NSExpression(forConstantValue: 9)
            resumePinLayer.circleColor = NSExpression(forConstantValue: UIColor.systemBlue)
            resumePinLayer.circleStrokeColor = NSExpression(forConstantValue: UIColor.white)
            resumePinLayer.circleStrokeWidth = NSExpression(forConstantValue: 2)
            style.addLayer(resumePinLayer)
            resumePinLayerRef = resumePinLayer

            // Source/couches TOUJOURS créées, même sans trace au premier chargement du style
            // (ex : premier montage en Mode Nav) — fix "trace-render-state-channel" : avant ce
            // fix, tout ce bloc était sauté si `track` était nil à CE moment précis, et plus
            // aucun mécanisme ne recréait la source ensuite. Résultat : une trace activée APRÈS
            // coup (retour Mode Trace, ou changement de trace active) ne s'affichait jamais,
            // silencieusement — carte vide ou ancienne trace figée. `updateTrackShape` (appelée
            // depuis `updateUIView`) est désormais le SEUL point qui peuple `.shape`, en pur
            // consommateur réactif de `track` (donc de `activeTrackID`/`isDisplayed` via
            // RideView) — jamais de reconstruction de source/couche après ce premier chargement.
            let trackSource = MLNShapeSource(identifier: MapEngineConstants.trackSourceIdentifier, shape: nil, options: nil)
            style.addSource(trackSource)
            trackSourceRef = trackSource

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

            applyTrackShape(track, to: trackSource)

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
            // Fix "chevrons-zoom-adaptive" (it17, Bloc 3) : PLUS de minimumZoomLevel — c'était
            // la cause du bug (coupure binaire au zoom 14). La densité (quelles features
            // existent dans la source) est désormais pilotée par le zoom courant via
            // updateChevronShape/adaptiveSpacingMeters ; la couche elle-même reste visible à
            // tout niveau de zoom.
            style.addLayer(chevronLayer)
            chevronLayerRef = chevronLayer

            // Avertissements de pente (spec "slope-warning-native", it19) : deux icônes
            // (montée/descente, `iconName` par feature — même patron `forKeyPath` que le
            // `bearing` des chevrons), symboles ponctuels jamais un dégradé continu.
            style.setImage(Self.slopeWarningImage(isClimbing: true), forName: MapEngineConstants.slopeWarningClimbIconName)
            style.setImage(Self.slopeWarningImage(isClimbing: false), forName: MapEngineConstants.slopeWarningDescentIconName)
            let slopeWarningSource = MLNShapeSource(identifier: MapEngineConstants.slopeWarningSourceIdentifier, shape: nil, options: nil)
            style.addSource(slopeWarningSource)
            let slopeWarningLayer = MLNSymbolStyleLayer(identifier: MapEngineConstants.slopeWarningLayerIdentifier, source: slopeWarningSource)
            slopeWarningLayer.iconImageName = NSExpression(forKeyPath: "iconName")
            slopeWarningLayer.iconRotationAlignment = NSExpression(forConstantValue: "viewport")
            slopeWarningLayer.iconAllowsOverlap = NSExpression(forConstantValue: true)
            slopeWarningLayer.iconIgnoresPlacement = NSExpression(forConstantValue: true)
            style.addLayer(slopeWarningLayer)

            // Détour, route Nav et "Aller à" ajoutés après la trace : ils doivent rester
            // visibles au-dessus.
            style.addLayer(detourLayer)
            style.addLayer(navRouteTraveledLayer)
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

        /// Marqueur replay debug (spec "replay-marker-heading-x2", it17, Bloc 4) — `MLNPoint
        /// Annotation` du SDK directement (pas de sous-classe dédiée) : c'est le seul usage de
        /// cette classe concrète sur cette carte, donc `annotation is MLNPointAnnotation` dans
        /// `viewFor annotation` reste sans ambiguïté. Repositionné en mutant `.coordinate` sur
        /// l'annotation déjà ajoutée (déplacement fluide géré nativement par le SDK, propriété
        /// `(nonatomic, assign)` vérifiée dans MLNPointAnnotation.h) plutôt que retiré/reposé à
        /// chaque fix — sinon un clignotement à chaque position durant tout le replay.
        private var debugReplayMarkerAnnotation: MLNPointAnnotation?

        func updateDebugReplayMarker(coordinate: CLLocationCoordinate2D?, on mapView: MLNMapView) {
            guard let coordinate else {
                if let existing = debugReplayMarkerAnnotation {
                    mapView.removeAnnotation(existing)
                    debugReplayMarkerAnnotation = nil
                }
                return
            }
            if let existing = debugReplayMarkerAnnotation {
                existing.coordinate = coordinate
            } else {
                let marker = MLNPointAnnotation()
                marker.coordinate = coordinate
                mapView.addAnnotation(marker)
                debugReplayMarkerAnnotation = marker
            }
        }

        /// Rond blanc 16 pt, léger contour + ombre portée (spec : "14 à 18 pt, contour discret")
        /// — volontairement PAS le style icône-dans-cercle-coloré des checkpoints/waypoints
        /// (`annotationView(on:...)` ci-dessous) : un simple marqueur de position, pas un point
        /// d'intérêt catégorisé.
        private func debugReplayMarkerView(on mapView: MLNMapView) -> MLNAnnotationView {
            let size: CGFloat = 16
            let identifier = "debugReplayMarker"
            let view = mapView.dequeueReusableAnnotationView(withIdentifier: identifier) ?? MLNAnnotationView(reuseIdentifier: identifier)
            view.frame = CGRect(x: 0, y: 0, width: size, height: size)
            view.subviews.forEach { $0.removeFromSuperview() }

            let dot = UIView(frame: view.bounds)
            dot.backgroundColor = .white
            dot.layer.cornerRadius = size / 2
            dot.layer.borderWidth = 1.5
            dot.layer.borderColor = UIColor.black.withAlphaComponent(0.35).cgColor
            dot.layer.shadowColor = UIColor.black.cgColor
            dot.layer.shadowOpacity = 0.4
            dot.layer.shadowRadius = 2
            dot.layer.shadowOffset = CGSize(width: 0, height: 1)
            view.addSubview(dot)

            return view
        }

        func mapView(_ mapView: MLNMapView, viewFor annotation: MLNAnnotation) -> MLNAnnotationView? {
            if annotation is MLNPointAnnotation {
                return debugReplayMarkerView(on: mapView)
            }
            if let checkpointAnnotation = annotation as? CheckpointMLNAnnotation {
                // Icône par PALIER (spec "roadbook-angle-buckets-replay", it14) — cohérente
                // avec la bannière latérale, voir LateralCapBannerView.
                let checkpoint = checkpointAnnotation.checkpoint
                return annotationView(on: mapView, identifier: "checkpoint", annotation: checkpointAnnotation, tint: .systemRed, systemImageName: checkpoint.tier.systemImageName(direction: checkpoint.direction), size: 34)
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
