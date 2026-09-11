import SwiftUI
import MapKit

/// Encapsule MKMapView (plutôt que l'API `Map` SwiftUI iOS 17+) pour rester compatible iOS 16
/// et parce que ce même contrôle est réutilisable plus tard derrière CPMapTemplate (CarPlay).
struct TrackMapView: UIViewRepresentable {
    let track: GPXTrack
    let currentLocation: CLLocation?

    func makeUIView(context: Context) -> MKMapView {
        let mapView = MKMapView()
        mapView.delegate = context.coordinator
        mapView.showsUserLocation = true
        mapView.showsCompass = true
        mapView.showsScale = true
        mapView.pointOfInterestFilter = .excludingAll

        let coordinates = track.points.map(\.coordinate)
        if coordinates.count > 1 {
            let polyline = MKPolyline(coordinates: coordinates, count: coordinates.count)
            mapView.addOverlay(polyline)
            mapView.setVisibleMapRect(
                polyline.boundingMapRect,
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

        return mapView
    }

    func updateUIView(_ mapView: MKMapView, context: Context) {
        // Le tracé est statique pour une trace donnée ; seule la position de l'utilisateur
        // évolue, et MKMapView la suit déjà nativement via showsUserLocation.
    }

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    final class Coordinator: NSObject, MKMapViewDelegate {
        func mapView(_ mapView: MKMapView, rendererFor overlay: MKOverlay) -> MKOverlayRenderer {
            if let polyline = overlay as? MKPolyline {
                let renderer = MKPolylineRenderer(polyline: polyline)
                renderer.strokeColor = UIColor.systemOrange
                renderer.lineWidth = 4
                return renderer
            }
            return MKOverlayRenderer(overlay: overlay)
        }
    }
}
