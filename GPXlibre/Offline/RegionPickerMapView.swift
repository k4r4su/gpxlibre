import SwiftUI
import MapLibre

struct SimpleBounds: Equatable {
    let minLat: Double
    let maxLat: Double
    let minLon: Double
    let maxLon: Double
}

/// Marque les polygones de contour de zones hors-ligne (spec "offline-zones-outline", it17,
/// Bloc 1) — sous-classe vide, sert uniquement à distinguer nos annotations de toute autre
/// dans les callbacks de style du delegate (aucune autre annotation sur cette carte aujourd'hui,
/// mais évite un style par défaut incorrect si une autre en apparaît plus tard).
private final class RegionOutlinePolygon: MLNPolygon {}

/// Carte MapLibre pincée/zoomée librement par l'utilisateur pour cadrer la zone à
/// télécharger — le viewport visible sert de boîte englobante (pas de dessin manuel de
/// rectangle, on réutilise les gestes natifs de la carte). Affiche aussi le contour des zones
/// DÉJÀ téléchargées (spec "offline-zones-outline", it17, Bloc 1) — pour voir sa couverture
/// existante en cadrant une nouvelle zone.
struct RegionPickerMapView: UIViewRepresentable {
    @Binding var bounds: SimpleBounds?
    var downloadedRegions: [DownloadedRegion] = []

    func makeUIView(context: Context) -> MLNMapView {
        let mapView = MLNMapView(frame: .zero, styleJSON: MapEngineConstants.buildInitialStyleJSON())
        mapView.delegate = context.coordinator
        mapView.showsUserLocation = true
        mapView.showsAttributionButton = true
        mapView.logoView.isHidden = true
        // Fix "region-picker-huge-bbox-crash" (bug terrain, it16) : sans caméra initiale,
        // MapLibre démarre en vue "monde" (zoom ~0) — le tout premier bounds rapporté à
        // updateEstimate() couvrirait la planète. Zoom "pays" raisonnable en attendant que
        // l'utilisateur cadre sa vraie zone ; le garde-fou de compte O(1) reste la protection
        // réelle (voir OfflineConstants.regionTileCountHardCap), ceci n'est qu'un confort pour
        // éviter le message "zone trop grande" à chaque ouverture de l'écran.
        mapView.setZoomLevel(5, animated: false)
        syncRegionOutlines(on: mapView, context: context)
        return mapView
    }

    func updateUIView(_ mapView: MLNMapView, context: Context) {
        context.coordinator.onBoundsChanged = { newBounds in
            bounds = newBounds
        }
        syncRegionOutlines(on: mapView, context: context)
    }

    /// Diff par signature (id+nombre de tuiles) — jamais retiré/reposé à chaque frame ; changé
    /// seulement si une zone a été ajoutée/supprimée/complétée depuis le dernier passage,
    /// même patron que `updateChevronShape`/`updateTrackShape` ailleurs dans l'app.
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

    func makeCoordinator() -> Coordinator { Coordinator() }

    final class Coordinator: NSObject, MLNMapViewDelegate {
        var onBoundsChanged: ((SimpleBounds) -> Void)?
        var regionOutlineAnnotations: [MLNPolygon] = []
        var lastRegionsSignature: String?

        func mapView(_ mapView: MLNMapView, regionDidChangeWith reason: MLNCameraChangeReason, animated: Bool) {
            let b = mapView.visibleCoordinateBounds
            onBoundsChanged?(SimpleBounds(minLat: b.sw.latitude, maxLat: b.ne.latitude, minLon: b.sw.longitude, maxLon: b.ne.longitude))
        }

        func mapViewDidFinishLoadingMap(_ mapView: MLNMapView) {
            let b = mapView.visibleCoordinateBounds
            onBoundsChanged?(SimpleBounds(minLat: b.sw.latitude, maxLat: b.ne.latitude, minLon: b.sw.longitude, maxLon: b.ne.longitude))
        }

        // MARK: - Style du contour (spec "offline-zones-outline", it17, Bloc 1) : "contour fin
        // ambré semi-transparent" — trait ambré, remplissage très léger pour rester lisible
        // sans masquer la carte en dessous.

        func mapView(_ mapView: MLNMapView, strokeColorForShapeAnnotation annotation: MLNShape) -> UIColor {
            guard annotation is RegionOutlinePolygon else { return .black }
            return UIColor.systemOrange
        }

        func mapView(_ mapView: MLNMapView, fillColorForPolygonAnnotation annotation: MLNPolygon) -> UIColor {
            guard annotation is RegionOutlinePolygon else { return .clear }
            return UIColor.systemOrange.withAlphaComponent(0.12)
        }

        func mapView(_ mapView: MLNMapView, alphaForShapeAnnotation annotation: MLNShape) -> CGFloat {
            guard annotation is RegionOutlinePolygon else { return 1 }
            return 0.7
        }

        // Pas de `lineWidthForPolylineAnnotation` : vérifié contre le header vendored
        // (MLNMapViewDelegate.h) — son paramètre est typé `MLNPolyline`, jamais appelé pour un
        // `MLNPolygon` (classe distincte, pas une sous-classe) ; l'épaisseur du contour d'un
        // polygone n'est pas personnalisable via cette API legacy, reste au défaut du SDK.
    }
}
