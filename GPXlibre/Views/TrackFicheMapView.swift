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
    private static let cameraEdgePadding = UIEdgeInsets(top: 8, left: 8, bottom: 8, right: 8)
    /// CAMERA_GEOGRAPHIC_MARGIN_M (spec "trace-ab-line-invisible" / cadrage fiche trace, it19) :
    /// marge GÉOGRAPHIQUE (mètres réels autour de la trace), pas un padding écran — demande
    /// explicite du prompt ("marge d'environ 2 km de chaque côté par rapport aux limites de la
    /// trace"), remplace l'ancien `edgePadding` (32 pt écran, variait avec le zoom/la taille
    /// d'écran plutôt que de représenter une vraie distance). `cameraEdgePadding` ci-dessus
    /// devient un espace de confort minimal (évite que la trace touche pile le bord du cadre),
    /// pas le mécanisme de marge principal.
    static let cameraGeographicMarginMeters: Double = 2000

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
        /// monde") : `fitCamera` peut s'exécuter AVANT que SwiftUI ait fini de donner à la
        /// `MLNMapView` (créée `frame: .zero`, intégrée dans un `Form`/`List`) sa vraie taille de
        /// layout. `setVisibleCoordinateBounds` calculé sur une vue de taille nulle produit un
        /// zoom aberrant (quasi le monde entier — bug terrain confirmé par capture). On retient
        /// les coordonnées du dernier cadrage tenté et on le REJOUE une fois, dès que le premier
        /// rendu réel confirme une vue de taille non nulle — idempotent (mêmes bounds) si le
        /// premier appel avait déjà réussi.
        private var pendingCameraFitCoordinates: [CLLocationCoordinate2D]?
        private var didRetryCameraFit = false
        /// Repli si `sync` est appelé alors que `mapView.style` est encore `nil` — retenu pour
        /// être appliqué dès qu'un style existe (voir `sync`). Dans la pratique, `mapView.style`
        /// s'est avéré déjà disponible dès le tout premier appel (style JSON raster minimal
        /// embarqué, analysé quasi instantanément) — ce chemin est un filet de sécurité, pas le
        /// chemin normal.
        private var pendingSync: (track: GPXTrack, isReversed: Bool, appearance: TraceAppearance)?

        /// Fix "trace-fiche-map-never-renders" (bug terrain, it19-bis : "toujours rien" malgré
        /// deux correctifs précédents) — ROOT CAUSE trouvée en instrumentant le vrai code et en
        /// observant une vraie capture simulateur (pas en supposant) : `mapView(_:didFinish
        /// Loading:)` ne se déclenche JAMAIS pour cette carte, confirmé après 20 s d'attente —
        /// alors que `mapView.style` EST déjà disponible dès le tout premier appel de `sync`.
        /// Cause probable : cette `MLNMapView` vit dans un `Form`/`List` (contrairement à
        /// `RideMapLibreView`, plein écran, où ce délégué se déclenche normalement) — un détail
        /// du cycle de vie MapLibre/UIKit dans ce contexte précis, non élucidé plus avant (pas
        /// nécessaire : le fix ci-dessous n'en dépend plus du tout). Au lieu de dépendre de ce
        /// callback pour créer nos sources/couches (`setupLayers`), `sync` le fait directement
        /// dès que `mapView.style` est là — ce qui, empiriquement, est le cas dès le premier
        /// appel. `didFinishLoading` reste implémenté comme filet de sécurité redondant
        /// (`setupLayers` est désormais idempotent, voir plus bas) au cas où il se déclencherait
        /// malgré tout sur une autre version du SDK/de l'OS.
        func mapView(_ mapView: MLNMapView, didFinishLoading style: MLNStyle) {
            setupLayers(style: style)
            guard let pending = pendingSync else { return }
            pendingSync = nil
            apply(track: pending.track, isReversed: pending.isReversed, appearance: pending.appearance, on: mapView)
        }

        func sync(orderedTrack: GPXTrack, isReversed: Bool, traceAppearance: TraceAppearance, on mapView: MLNMapView) {
            guard let style = mapView.style else {
                pendingSync = (orderedTrack, isReversed, traceAppearance)
                return
            }
            setupLayers(style: style)
            guard orderedTrack.id != currentTrackID || isReversed != currentIsReversed else { return }
            apply(track: orderedTrack, isReversed: isReversed, appearance: traceAppearance, on: mapView)
        }

        private func apply(track: GPXTrack, isReversed: Bool, appearance: TraceAppearance, on mapView: MLNMapView) {
            // Le bookkeeping de dédup n'est marqué "posé" qu'APRÈS confirmation que le style/nos
            // couches existent bel et bien — jamais avant, pour ne jamais pouvoir verrouiller
            // `sync` sur un échec silencieux.
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
            guard let rawBounds = Self.boundingBox(of: coordinates) else { return }
            let bounds = Self.expandedBounds(rawBounds, byMeters: TrackFicheMapView.cameraGeographicMarginMeters)
            let mlnBounds = MLNCoordinateBounds(
                sw: CLLocationCoordinate2D(latitude: bounds.minLat, longitude: bounds.minLon),
                ne: CLLocationCoordinate2D(latitude: bounds.maxLat, longitude: bounds.maxLon)
            )
            mapView.setVisibleCoordinateBounds(mlnBounds, edgePadding: TrackFicheMapView.cameraEdgePadding, animated: false, completionHandler: nil)
        }

        /// Bbox brute (pas de marge) — extrait pour être testable indépendamment de MapLibre.
        static func boundingBox(of coordinates: [CLLocationCoordinate2D]) -> (minLat: Double, maxLat: Double, minLon: Double, maxLon: Double)? {
            guard let first = coordinates.first else { return nil }
            var minLat = first.latitude, maxLat = first.latitude
            var minLon = first.longitude, maxLon = first.longitude
            for coordinate in coordinates {
                minLat = min(minLat, coordinate.latitude)
                maxLat = max(maxLat, coordinate.latitude)
                minLon = min(minLon, coordinate.longitude)
                maxLon = max(maxLon, coordinate.longitude)
            }
            return (minLat, maxLat, minLon, maxLon)
        }

        /// Étend une bbox de `meters` dans les QUATRE directions cardinales (approximation
        /// équirectangulaire locale, même formule que `TrackProjector.distanceFromPointToSegment` :
        /// 111 320 m/° de latitude, corrigé par `cos(latitude)` pour la longitude — précise
        /// largement assez pour un cadrage caméra, jamais utilisée pour du routing/de la mesure
        /// fine). `internal static` pour la testabilité (même patron que
        /// `MapEngineConstants.patchedSymbolLayerForCapUp`).
        static func expandedBounds(
            _ bounds: (minLat: Double, maxLat: Double, minLon: Double, maxLon: Double),
            byMeters meters: Double
        ) -> (minLat: Double, maxLat: Double, minLon: Double, maxLon: Double) {
            let metersPerDegreeLat = 111_320.0
            let midLatitude = (bounds.minLat + bounds.maxLat) / 2
            let metersPerDegreeLon = max(111_320.0 * cos(midLatitude * .pi / 180), 1)
            let latMargin = meters / metersPerDegreeLat
            let lonMargin = meters / metersPerDegreeLon
            return (
                minLat: bounds.minLat - latMargin,
                maxLat: bounds.maxLat + latMargin,
                minLon: bounds.minLon - lonMargin,
                maxLon: bounds.maxLon + lonMargin
            )
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

        /// IDEMPOTENT (spec "trace-fiche-map-never-renders", it19-bis) : peut désormais être
        /// appelée à la fois depuis `sync` (chemin normal, voir plus haut) ET depuis
        /// `didFinishLoading` (filet de sécurité redondant) — sans ce garde, un double appel
        /// ferait planter `style.addSource`/`addLayer` sur un identifiant déjà existant.
        private func setupLayers(style: MLNStyle) {
            guard style.source(withIdentifier: TrackFicheMapView.trackSourceIdentifier) == nil else { return }
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
