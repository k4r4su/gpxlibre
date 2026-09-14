import SwiftUI
import MapLibre

struct SimpleBounds: Equatable {
    let minLat: Double
    let maxLat: Double
    let minLon: Double
    let maxLon: Double
}

/// Carte MapLibre pincée/zoomée librement par l'utilisateur pour cadrer la zone à
/// télécharger — le viewport visible sert de boîte englobante (pas de dessin manuel de
/// rectangle, on réutilise les gestes natifs de la carte).
struct RegionPickerMapView: UIViewRepresentable {
    @Binding var bounds: SimpleBounds?

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
        return mapView
    }

    func updateUIView(_ mapView: MLNMapView, context: Context) {
        context.coordinator.onBoundsChanged = { newBounds in
            bounds = newBounds
        }
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    final class Coordinator: NSObject, MLNMapViewDelegate {
        var onBoundsChanged: ((SimpleBounds) -> Void)?

        func mapView(_ mapView: MLNMapView, regionDidChangeWith reason: MLNCameraChangeReason, animated: Bool) {
            let b = mapView.visibleCoordinateBounds
            onBoundsChanged?(SimpleBounds(minLat: b.sw.latitude, maxLat: b.ne.latitude, minLon: b.sw.longitude, maxLon: b.ne.longitude))
        }

        func mapViewDidFinishLoadingMap(_ mapView: MLNMapView) {
            let b = mapView.visibleCoordinateBounds
            onBoundsChanged?(SimpleBounds(minLat: b.sw.latitude, maxLat: b.ne.latitude, minLon: b.sw.longitude, maxLon: b.ne.longitude))
        }
    }
}
