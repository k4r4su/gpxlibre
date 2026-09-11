import SwiftUI
import MapKit

/// Encapsule MKMapView (plutôt que l'API `Map` SwiftUI iOS 17+) pour rester compatible iOS 16
/// et parce que ce même contrôle est réutilisable plus tard derrière CPMapTemplate (CarPlay).
/// Rendu de la trace (épaisseur/couleur/casing) partagé avec le Ride — Bloc 3 : réglages
/// appliqués en direct, y compris dans cet aperçu Bibliothèque.
struct TrackMapView: UIViewRepresentable {
    let track: GPXTrack
    let currentLocation: CLLocation?
    let traceAppearance: TraceAppearance

    func makeUIView(context: Context) -> MKMapView {
        let mapView = MKMapView()
        mapView.delegate = context.coordinator
        mapView.showsUserLocation = true
        mapView.showsCompass = true
        mapView.showsScale = true
        mapView.pointOfInterestFilter = .excludingAll

        let coordinates = track.points.map(\.coordinate)
        if coordinates.count > 1 {
            let bounding = MKPolyline(coordinates: coordinates, count: coordinates.count).boundingMapRect
            mapView.setVisibleMapRect(
                bounding,
                edgePadding: UIEdgeInsets(top: 40, left: 40, bottom: 40, right: 40),
                animated: false
            )
        } else if let region = track.boundingRegion {
            mapView.setRegion(
                MKCoordinateRegion(
                    center: region.center,
                    span: MKCoordinateSpan(latitudeDelta: region.span.latDelta, longitudeDelta: region.span.lonDelta)
                ),
                animated: false
            )
        }

        if !track.waypoints.isEmpty {
            let annotations = track.waypoints.map { point -> MKPointAnnotation in
                let annotation = MKPointAnnotation()
                annotation.coordinate = point.coordinate
                return annotation
            }
            mapView.addAnnotations(annotations)
        }

        syncTrackOverlays(on: mapView, context: context)

        return mapView
    }

    func updateUIView(_ mapView: MKMapView, context: Context) {
        // La position évolue nativement via showsUserLocation ; seul le rendu de la trace a
        // besoin d'être resynchronisé quand l'utilisateur change épaisseur/couleur.
        syncTrackOverlays(on: mapView, context: context)
    }

    private func syncTrackOverlays(on mapView: MKMapView, context: Context) {
        let coordinator = context.coordinator
        guard coordinator.traceAppearance != traceAppearance else { return }

        if let casing = coordinator.casingOverlay { mapView.removeOverlay(casing) }
        if let colored = coordinator.colorOverlay { mapView.removeOverlay(colored) }
        coordinator.traceAppearance = traceAppearance

        let coordinates = track.points.map(\.coordinate)
        guard coordinates.count > 1 else { return }
        let casing = TraceCasingPolyline(coordinates: coordinates, count: coordinates.count)
        let colored = TraceColorPolyline(coordinates: coordinates, count: coordinates.count)
        mapView.addOverlay(casing)
        mapView.addOverlay(colored)
        coordinator.casingOverlay = casing
        coordinator.colorOverlay = colored
    }

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    final class Coordinator: NSObject, MKMapViewDelegate {
        var traceAppearance = TraceAppearance()
        var casingOverlay: TraceCasingPolyline?
        var colorOverlay: TraceColorPolyline?

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
            return MKOverlayRenderer(overlay: overlay)
        }
    }
}
