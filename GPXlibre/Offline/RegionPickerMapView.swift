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
        let mapView = MLNMapView(frame: .zero, styleJSON: MapEngineConstants.initialStyleJSON)
        mapView.delegate = context.coordinator
        mapView.showsUserLocation = true
        mapView.showsAttributionButton = true
        mapView.logoView.isHidden = true
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
