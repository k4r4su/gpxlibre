import SwiftUI
import MapLibre

/// Sous-classes vides pour distinguer les deux types d'annotation dans les callbacks de style
/// du delegate — même patron que `RegionPickerMapView`.
private final class RegionOutlinePolygon: MLNPolygon {}
private final class SelectionCirclePolygon: MLNPolygon {}

/// Carte MapLibre centrée par pan libre — la zone à télécharger est un CERCLE de rayon réglable
/// (slider, voir `CircleRegionPickerView`), TOUJOURS centré sur le centre de la carte — pas le
/// viewport visible entier comme `RegionPickerMapView` (spec "region-download-by-shape", it21,
/// remplace "region-download-by-place" : retour terrain "pas ultra fan de la recherche par nom
/// de lieu, je pense qu'il faudrait juste une carte avec un cercle qu'on peut agrandir/
/// réduire"). Affiche aussi le contour des zones DÉJÀ téléchargées (spec "offline-zones-outline",
/// it17, Bloc 1, même patron que `RegionPickerMapView`).
struct CircleRegionPickerMapView: UIViewRepresentable {
    @Binding var centerCoordinate: CLLocationCoordinate2D?
    var radiusMeters: Double
    var downloadedRegions: [DownloadedRegion] = []
    /// Fix "region-picker-atlantic-ocean-default" (it21) — même résolution que
    /// `RegionPickerMapView` (position GPS actuelle, sinon centre France), appliquée UNE SEULE
    /// FOIS dans `makeUIView`.
    var initialCenterCoordinate: CLLocationCoordinate2D

    func makeUIView(context: Context) -> MLNMapView {
        let mapView = MLNMapView(frame: .zero, styleJSON: MapEngineConstants.buildInitialStyleJSON())
        mapView.delegate = context.coordinator
        mapView.showsUserLocation = true
        mapView.showsAttributionButton = true
        mapView.logoView.isHidden = true
        // Zoom "ville" raisonnable — contrairement à RegionPickerMapView (zoom "pays", 5), un
        // cercle de rayon modeste (quelques km à quelques dizaines de km) se lit mieux d'entrée
        // à un niveau de zoom plus serré.
        mapView.setCenter(initialCenterCoordinate, zoomLevel: 10, animated: false)
        syncRegionOutlines(on: mapView, context: context)
        syncSelectionCircle(on: mapView, context: context, center: initialCenterCoordinate)
        return mapView
    }

    func updateUIView(_ mapView: MLNMapView, context: Context) {
        context.coordinator.onCenterChanged = { newCenter in
            centerCoordinate = newCenter
        }
        syncRegionOutlines(on: mapView, context: context)
        syncSelectionCircle(on: mapView, context: context, center: mapView.centerCoordinate)
    }

    /// Diff par signature (id+nombre de tuiles) — même patron que `RegionPickerMapView`.
    private func syncRegionOutlines(on mapView: MLNMapView, context: Context) {
        let coordinator = context.coordinator
        let signature = downloadedRegions.map { "\($0.id.uuidString)-\($0.tileCount)" }.joined(separator: "|")
        guard signature != coordinator.lastRegionsSignature else { return }
        coordinator.lastRegionsSignature = signature

        if !coordinator.regionOutlineAnnotations.isEmpty {
            mapView.removeAnnotations(coordinator.regionOutlineAnnotations)
            coordinator.regionOutlineAnnotations = []
        }

        let polygons: [RegionOutlinePolygon] = downloadedRegions.compactMap { region in
            guard let box = region.boundingBox else { return nil }
            let coordinates = [
                CLLocationCoordinate2D(latitude: box.maxLat, longitude: box.minLon),
                CLLocationCoordinate2D(latitude: box.maxLat, longitude: box.maxLon),
                CLLocationCoordinate2D(latitude: box.minLat, longitude: box.maxLon),
                CLLocationCoordinate2D(latitude: box.minLat, longitude: box.minLon),
            ]
            return RegionOutlinePolygon(coordinates: coordinates, count: UInt(coordinates.count))
        }
        guard !polygons.isEmpty else { return }
        mapView.addAnnotations(polygons)
        coordinator.regionOutlineAnnotations = polygons
    }

    /// Diff par signature (centre+rayon) — jamais retiré/reposé à chaque frame, même patron que
    /// `syncRegionOutlines` ci-dessus.
    private func syncSelectionCircle(on mapView: MLNMapView, context: Context, center: CLLocationCoordinate2D) {
        let coordinator = context.coordinator
        let signature = "\(center.latitude)-\(center.longitude)-\(radiusMeters)"
        guard signature != coordinator.lastSelectionSignature else { return }
        coordinator.lastSelectionSignature = signature

        if let existing = coordinator.selectionAnnotation {
            mapView.removeAnnotations([existing])
        }
        let coordinates = Self.circlePoints(center: center, radiusMeters: radiusMeters)
        let polygon = SelectionCirclePolygon(coordinates: coordinates, count: UInt(coordinates.count))
        mapView.addAnnotation(polygon)
        coordinator.selectionAnnotation = polygon
    }

    /// Approximation équirectangulaire (même formule que `TileCoordinate.boundingBox`), 36
    /// segments — suffisant pour un AFFICHAGE visuel. Le calcul réel des tuiles à télécharger
    /// (voir `OfflineTileEstimator`/`CircleRegionPickerView.currentBounds`) reste basé sur la
    /// vraie bounding box géographique, indépendant de ce dessin.
    private static func circlePoints(center: CLLocationCoordinate2D, radiusMeters: Double, segments: Int = 36) -> [CLLocationCoordinate2D] {
        let metersPerDegreeLat = 111_320.0
        let metersPerDegreeLon = 111_320.0 * max(cos(center.latitude * .pi / 180), 0.01)
        return (0..<segments).map { i in
            let angle = Double(i) / Double(segments) * 2 * .pi
            let dLat = (radiusMeters * cos(angle)) / metersPerDegreeLat
            let dLon = (radiusMeters * sin(angle)) / metersPerDegreeLon
            return CLLocationCoordinate2D(latitude: center.latitude + dLat, longitude: center.longitude + dLon)
        }
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    final class Coordinator: NSObject, MLNMapViewDelegate {
        var onCenterChanged: ((CLLocationCoordinate2D) -> Void)?
        var regionOutlineAnnotations: [MLNPolygon] = []
        var lastRegionsSignature: String?
        var selectionAnnotation: MLNPolygon?
        var lastSelectionSignature: String?

        func mapView(_ mapView: MLNMapView, regionDidChangeWith reason: MLNCameraChangeReason, animated: Bool) {
            onCenterChanged?(mapView.centerCoordinate)
        }

        func mapViewDidFinishLoadingMap(_ mapView: MLNMapView) {
            onCenterChanged?(mapView.centerCoordinate)
        }

        // MARK: - Style (cercle de sélection en bleu, contours de zones déjà téléchargées en
        // ambré — même styles que `RegionPickerMapView` pour ces derniers).

        func mapView(_ mapView: MLNMapView, strokeColorForShapeAnnotation annotation: MLNShape) -> UIColor {
            if annotation is SelectionCirclePolygon { return .systemBlue }
            if annotation is RegionOutlinePolygon { return .systemOrange }
            return .black
        }

        func mapView(_ mapView: MLNMapView, fillColorForPolygonAnnotation annotation: MLNPolygon) -> UIColor {
            if annotation is SelectionCirclePolygon { return UIColor.systemBlue.withAlphaComponent(0.15) }
            if annotation is RegionOutlinePolygon { return UIColor.systemOrange.withAlphaComponent(0.12) }
            return .clear
        }

        func mapView(_ mapView: MLNMapView, alphaForShapeAnnotation annotation: MLNShape) -> CGFloat {
            (annotation is SelectionCirclePolygon || annotation is RegionOutlinePolygon) ? 0.7 : 1
        }
    }
}
