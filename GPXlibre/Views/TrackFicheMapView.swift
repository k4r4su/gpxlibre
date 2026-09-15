import SwiftUI
import MapLibre
import CoreLocation

/// Fiche trace : carte unique fusionnant aperçu cartographique + sens de parcours — spec
/// "trace-fiche-map-ab-markers" (it17, Bloc 5, constaté sur capture du 14/09 : "la carte Apple
/// Maps et le schéma du sens sont séparés"). Remplace, dans TrackSettingsView, TrackMapView
/// (MapKit, "Apple Maps") ET TrackThumbnailView (Canvas, diagramme de sens séparé — fichier
/// conservé intact mais n'a plus de point d'entrée UI depuis ce bloc, voir TODO.md, même
/// patron que TrackDetailView/RideModeSegmentedControl). Une seule carte, même cartographie
/// VECTORIELLE que la Ride map (MapLibre, pas MapKit) : chevrons agrandis à taille FIXE (pas
/// liée au zoom réel — l'objectif est de montrer le sens à l'œil nu, pas de zoomer) et repères
/// A/B.
///
/// L'ordre des points (`orderedTrack`) est déjà résolu par l'appelant via
/// `GPXTrack.reordered(using:)` (déjà pur, déjà utilisé pour la miniature avant ce bloc) — ce
/// composant ne fait AUCUN recalcul GPX, juste du rendu. `isReversed` n'est là que pour la clé
/// de diff : l'id de la trace ne change pas quand on inverse le sens, donc `orderedTrack.id`
/// seul ne suffirait pas à détecter un changement de sens.
struct TrackFicheMapView: UIViewRepresentable {
    let orderedTrack: GPXTrack
    let isReversed: Bool
    let traceAppearance: TraceAppearance

    private static let trackSourceIdentifier = "fiche-track-source"
    private static let trackCasingLayerIdentifier = "fiche-track-casing-layer"
    private static let trackLayerIdentifier = "fiche-track-layer"
    private static let chevronSourceIdentifier = "fiche-chevron-source"
    private static let chevronLayerIdentifier = "fiche-chevron-layer"
    private static let chevronIconName = "fiche-chevron-icon"
    /// "quelques chevrons placés équitablement... moins dense que sur la ride map" (spec) —
    /// nettement moins que la densité réelle (voir DirectionChevronComputer.zoomSpacingTable,
    /// it17 Bloc 3), ce n'est qu'un aperçu.
    private static let chevronTargetCount = 6
    /// Candidats générés à un espacement fin puis sous-échantillonnés à `chevronTargetCount` —
    /// garantit assez de candidats même sur une trace courte.
    private static let chevronCandidateSpacingMeters: Double = 50
    private static let cameraEdgePadding = UIEdgeInsets(top: 32, left: 32, bottom: 32, right: 32)

    func makeUIView(context: Context) -> MLNMapView {
        let mapView = MLNMapView(frame: .zero, styleJSON: MapEngineConstants.buildInitialStyleJSON())
        mapView.delegate = context.coordinator
        mapView.showsUserLocation = false
        mapView.showsAttributionButton = true
        mapView.logoView.isHidden = true
        return mapView
    }

    func updateUIView(_ mapView: MLNMapView, context: Context) {
        context.coordinator.sync(orderedTrack: orderedTrack, isReversed: isReversed, traceAppearance: traceAppearance, on: mapView)
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    final class Coordinator: NSObject, MLNMapViewDelegate {
        private var currentTrackID: UUID?
        private var currentIsReversed: Bool?
        private var startAnnotation: MLNPointAnnotation?
        private var endAnnotation: MLNPointAnnotation?
        /// Fix "trace-sheet-auto-frame" (it18, Bloc 6, bug terrain : "la carte reste centrée
        /// monde") : `fitCamera` était déjà appelé dans `apply(track:...)`, mais celui-ci peut
        /// s'exécuter dès `didFinishLoading` (style JSON embarqué, chargement quasi instantané,
        /// pas d'attente réseau) — potentiellement AVANT que SwiftUI ait fini de donner à la
        /// `MLNMapView` (créée `frame: .zero`) sa vraie taille de layout. `setVisibleCoordinate
        /// Bounds` calculé sur une vue de taille nulle produit un zoom aberrant (quasi le monde
        /// entier). On retient les coordonnées du dernier cadrage tenté et on le REJOUE une
        /// fois, dès que le premier rendu réel confirme une vue de taille non nulle — idempotent
        /// (mêmes bounds) si le premier appel avait déjà réussi.
        private var pendingCameraFitCoordinates: [CLLocationCoordinate2D]?
        private var didRetryCameraFit = false
        /// Le style se charge de façon asynchrone — si `sync` est appelé avant
        /// `didFinishLoading`, on retient la dernière demande pour l'appliquer dès que les
        /// sources/couches existent, plutôt que de la perdre silencieusement.
        private var pendingSync: (track: GPXTrack, isReversed: Bool, appearance: TraceAppearance)?

        func mapView(_ mapView: MLNMapView, didFinishLoading style: MLNStyle) {
            setupLayers(style: style)
            guard let pending = pendingSync else { return }
            pendingSync = nil
            currentTrackID = nil
            apply(track: pending.track, isReversed: pending.isReversed, appearance: pending.appearance, on: mapView)
        }

        /// Fix "trace-ab-line-invisible" (bug terrain : "les pastilles A/B apparaissent, pas le
        /// tracé") — root cause : `mapView.style` peut devenir non-nil DÈS que le JSON est
        /// analysé, un instant AVANT que `didFinishLoading` (qui seul appelle `setupLayers`, donc
        /// crée `trackSourceIdentifier`) ne soit invoqué — un vrai gap documenté du cycle de vie
        /// MapLibre/Mapbox GL, d'autant plus probable ici que le style est un JSON raster minimal
        /// embarqué (quasi instantané à analyser). Si `sync` tombait dans cette fenêtre, l'ancien
        /// garde `mapView.style != nil` prenait le chemin "direct apply" AVANT que la source
        /// existe : `apply` marquait quand même `currentTrackID`/`currentIsReversed` comme
        /// "déjà posé" (voir plus bas), verrouillant `sync` pour de bon sur ce couple (id,
        /// isReversed) — plus aucun nouvel essai possible ensuite, y compris une fois
        /// `didFinishLoading` réellement passé. Les annotations A/B, elles, ne dépendent pas du
        /// style (mapView.addAnnotations fonctionne dès l'instanciation), d'où le symptôme exact
        /// rapporté : pastilles visibles, ligne jamais posée. Fix : vérifier l'existence RÉELLE de
        /// notre source (donc que `setupLayers` a bien tourné) plutôt que la seule non-nullité de
        /// `mapView.style`.
        func sync(orderedTrack: GPXTrack, isReversed: Bool, traceAppearance: TraceAppearance, on mapView: MLNMapView) {
            guard let style = mapView.style, style.source(withIdentifier: TrackFicheMapView.trackSourceIdentifier) != nil else {
                pendingSync = (orderedTrack, isReversed, traceAppearance)
                return
            }
            guard orderedTrack.id != currentTrackID || isReversed != currentIsReversed else { return }
            apply(track: orderedTrack, isReversed: isReversed, appearance: traceAppearance, on: mapView)
        }

        private func apply(track: GPXTrack, isReversed: Bool, appearance: TraceAppearance, on mapView: MLNMapView) {
            // Filet de sécurité supplémentaire (défense en profondeur) : le bookkeeping de dédup
            // n'est marqué "posé" qu'APRÈS confirmation que le style/nos couches existent bel et
            // bien — jamais avant, pour ne plus jamais pouvoir verrouiller `sync` sur un échec
            // silencieux (voir commentaire ci-dessus, cause racine réelle déjà neutralisée par le
            // garde de `sync`, mais ce filet reste correct même si une autre voie d'appel futur
            // contournait ce garde).
            guard let style = mapView.style, track.points.count > 1 else { return }
            currentTrackID = track.id
            currentIsReversed = isReversed

            let coordinates = track.points.map(\.coordinate)

            if let source = style.source(withIdentifier: TrackFicheMapView.trackSourceIdentifier) as? MLNShapeSource {
                source.shape = MLNPolyline(coordinates: coordinates, count: UInt(coordinates.count))
            }
            if let casingLayer = style.layer(withIdentifier: TrackFicheMapView.trackCasingLayerIdentifier) as? MLNLineStyleLayer {
                casingLayer.lineColor = NSExpression(forConstantValue: appearance.casingColor)
                casingLayer.lineWidth = NSExpression(forConstantValue: appearance.casingWidth)
            }
            if let colorLayer = style.layer(withIdentifier: TrackFicheMapView.trackLayerIdentifier) as? MLNLineStyleLayer {
                colorLayer.lineColor = NSExpression(forConstantValue: appearance.color)
                colorLayer.lineWidth = NSExpression(forConstantValue: appearance.lineWidth)
            }

            style.setImage(Self.chevronImage(color: appearance.color), forName: TrackFicheMapView.chevronIconName)
            if let chevronSource = style.source(withIdentifier: TrackFicheMapView.chevronSourceIdentifier) as? MLNShapeSource {
                let candidates = DirectionChevronComputer.chevrons(for: track.points, spacingMeters: TrackFicheMapView.chevronCandidateSpacingMeters)
                let subset = DirectionChevronComputer.evenlySpacedSubset(candidates, targetCount: TrackFicheMapView.chevronTargetCount)
                let features = subset.map { chevron -> MLNPointFeature in
                    let feature = MLNPointFeature()
                    feature.coordinate = chevron.coordinate
                    feature.attributes = ["bearing": chevron.bearingDegrees]
                    return feature
                }
                chevronSource.shape = MLNShapeCollectionFeature(shapes: features)
            }

            if let startAnnotation { mapView.removeAnnotation(startAnnotation) }
            if let endAnnotation { mapView.removeAnnotation(endAnnotation) }
            let start = MLNPointAnnotation()
            start.coordinate = coordinates[0]
            start.title = "A"
            let end = MLNPointAnnotation()
            end.coordinate = coordinates[coordinates.count - 1]
            end.title = "B"
            mapView.addAnnotations([start, end])
            startAnnotation = start
            endAnnotation = end

            fitCamera(coordinates: coordinates, on: mapView)
        }

        private func fitCamera(coordinates: [CLLocationCoordinate2D], on mapView: MLNMapView) {
            pendingCameraFitCoordinates = coordinates
            didRetryCameraFit = false
            applyCameraFit(coordinates: coordinates, on: mapView)
        }

        private func applyCameraFit(coordinates: [CLLocationCoordinate2D], on mapView: MLNMapView) {
            guard let first = coordinates.first else { return }
            var minLat = first.latitude, maxLat = first.latitude
            var minLon = first.longitude, maxLon = first.longitude
            for coordinate in coordinates {
                minLat = min(minLat, coordinate.latitude)
                maxLat = max(maxLat, coordinate.latitude)
                minLon = min(minLon, coordinate.longitude)
                maxLon = max(maxLon, coordinate.longitude)
            }
            let bounds = MLNCoordinateBounds(
                sw: CLLocationCoordinate2D(latitude: minLat, longitude: minLon),
                ne: CLLocationCoordinate2D(latitude: maxLat, longitude: maxLon)
            )
            mapView.setVisibleCoordinateBounds(bounds, edgePadding: TrackFicheMapView.cameraEdgePadding, animated: false, completionHandler: nil)
        }

        /// Fix "trace-sheet-auto-frame" : rejoue le cadrage une seule fois dès que la vue a une
        /// taille réelle — couvre le cas où `fitCamera` a été appelé pendant que `mapView.bounds`
        /// était encore `.zero` (voir commentaire sur `pendingCameraFitCoordinates`).
        func mapViewDidFinishRenderingMap(_ mapView: MLNMapView, fullyRendered: Bool) {
            guard !didRetryCameraFit, mapView.bounds.width > 0, mapView.bounds.height > 0,
                  let coordinates = pendingCameraFitCoordinates
            else { return }
            didRetryCameraFit = true
            applyCameraFit(coordinates: coordinates, on: mapView)
        }

        private func setupLayers(style: MLNStyle) {
            let trackSource = MLNShapeSource(identifier: TrackFicheMapView.trackSourceIdentifier, shape: nil, options: nil)
            style.addSource(trackSource)
            let casingLayer = MLNLineStyleLayer(identifier: TrackFicheMapView.trackCasingLayerIdentifier, source: trackSource)
            casingLayer.lineJoin = NSExpression(forConstantValue: "round")
            casingLayer.lineCap = NSExpression(forConstantValue: "round")
            style.addLayer(casingLayer)
            let colorLayer = MLNLineStyleLayer(identifier: TrackFicheMapView.trackLayerIdentifier, source: trackSource)
            colorLayer.lineJoin = NSExpression(forConstantValue: "round")
            colorLayer.lineCap = NSExpression(forConstantValue: "round")
            style.addLayer(colorLayer)

            let chevronSource = MLNShapeSource(identifier: TrackFicheMapView.chevronSourceIdentifier, shape: nil, options: nil)
            style.addSource(chevronSource)
            let chevronLayer = MLNSymbolStyleLayer(identifier: TrackFicheMapView.chevronLayerIdentifier, source: chevronSource)
            chevronLayer.iconImageName = NSExpression(forConstantValue: TrackFicheMapView.chevronIconName)
            chevronLayer.iconRotation = NSExpression(forKeyPath: "bearing")
            chevronLayer.iconRotationAlignment = NSExpression(forConstantValue: "map")
            chevronLayer.iconAllowsOverlap = NSExpression(forConstantValue: true)
            chevronLayer.iconIgnoresPlacement = NSExpression(forConstantValue: true)
            style.addLayer(chevronLayer)
        }

        /// Chevron AGRANDI (40 pt, contre 22 pt sur la Ride map, `RideMapLibreView.chevronImage`
        /// — dupliqué ici volontairement plutôt que partagé entre les deux Coordinators de
        /// fichiers différents, non couplage délibéré pour un si petit dessin) — taille absolue
        /// CONSTANTE quel que soit le zoom d'ajustement automatique : comportement par défaut
        /// d'une icône MapLibre tant qu'aucune expression liée au zoom n'est ajoutée à
        /// `iconScale`/`iconSize` (ce qui n'est pas le cas ici), donc rien à faire de plus.
        private static func chevronImage(color: UIColor) -> UIImage {
            let size = CGSize(width: 40, height: 40)
            let renderer = UIGraphicsImageRenderer(size: size)
            return renderer.image { _ in
                let path = UIBezierPath()
                path.move(to: CGPoint(x: size.width / 2, y: size.height * 0.15))
                path.addLine(to: CGPoint(x: size.width * 0.85, y: size.height * 0.8))
                path.addLine(to: CGPoint(x: size.width * 0.15, y: size.height * 0.8))
                path.close()
                color.setFill()
                path.fill()
                UIColor.black.withAlphaComponent(0.55).setStroke()
                path.lineWidth = 2
                path.stroke()
            }
        }

        /// Repères A (vert) / B (rouge) — spec : "pastille verte au point de départ... pastille
        /// rouge au point d'arrivée". `MLNPointAnnotation.title` ("A"/"B") sert uniquement de
        /// clé de distinction ici, jamais affiché comme callout (pas de tap géré sur cette
        /// carte de simple aperçu).
        func mapView(_ mapView: MLNMapView, viewFor annotation: MLNAnnotation) -> MLNAnnotationView? {
            guard let point = annotation as? MLNPointAnnotation, let title = point.title else { return nil }
            let isStart = title == "A"
            let identifier = isStart ? "ficheStart" : "ficheEnd"
            let size: CGFloat = 26
            let view = mapView.dequeueReusableAnnotationView(withIdentifier: identifier) ?? MLNAnnotationView(reuseIdentifier: identifier)
            view.frame = CGRect(x: 0, y: 0, width: size, height: size)
            view.subviews.forEach { $0.removeFromSuperview() }

            let background = UIView(frame: view.bounds)
            background.backgroundColor = isStart ? .systemGreen : .systemRed
            background.layer.cornerRadius = size / 2
            background.layer.borderWidth = 2
            background.layer.borderColor = UIColor.white.cgColor
            view.addSubview(background)

            let label = UILabel(frame: view.bounds)
            label.text = title
            label.textAlignment = .center
            label.textColor = .white
            label.font = .systemFont(ofSize: 13, weight: .bold)
            view.addSubview(label)

            return view
        }
    }
}
