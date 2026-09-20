import SwiftUI
import MapKit

/// Mini-carte optionnelle du Road Book (spec "roadbook-mode", it23, point 1 : "utile en debug
/// de fiabilité de la feature et comme filet de sécurité visuel"). Volontairement légère
/// (MapKit, jamais une deuxième instance MapLibre) — même esprit que `CameraPreviewMapView`
/// (Settings/), mais fichier séparé plutôt que d'élargir sa signature : `CameraPreviewMapView`
/// est déjà partagée par 3 écrans Réglages avec un contrat fixe, et ce mini-map a un besoin
/// légèrement différent (position live optionnelle en mode Assisté GPS).
struct RoadbookMiniMapView: UIViewRepresentable {
    let track: GPXTrack
    let currentLocation: CLLocationCoordinate2D?

    func makeUIView(context: Context) -> MKMapView {
        let mapView = MKMapView()
        mapView.delegate = context.coordinator
        mapView.isUserInteractionEnabled = false
        mapView.pointOfInterestFilter = .excludingAll
        mapView.showsCompass = false
        mapView.showsScale = false

        let coordinates = track.points.map(\.coordinate)
        if coordinates.count > 1 {
            let polyline = MKPolyline(coordinates: coordinates, count: coordinates.count)
            mapView.addOverlay(polyline)
        }
        if let region = regionCoveringTrack(track) {
            mapView.setRegion(region, animated: false)
        }
        return mapView
    }

    func updateUIView(_ mapView: MKMapView, context: Context) {
        let annotationID = "roadbook-live-position"
        mapView.annotations.filter { $0.title == annotationID }.forEach { mapView.removeAnnotation($0) }
        if let currentLocation {
            let annotation = MKPointAnnotation()
            annotation.coordinate = currentLocation
            annotation.title = annotationID
            mapView.addAnnotation(annotation)
        }
    }

    private func regionCoveringTrack(_ track: GPXTrack) -> MKCoordinateRegion? {
        guard let bounding = track.boundingRegion else { return nil }
        return MKCoordinateRegion(
            center: bounding.center,
            span: MKCoordinateSpan(latitudeDelta: bounding.span.latDelta, longitudeDelta: bounding.span.lonDelta)
        )
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    final class Coordinator: NSObject, MKMapViewDelegate {
        func mapView(_ mapView: MKMapView, rendererFor overlay: MKOverlay) -> MKOverlayRenderer {
            guard let polyline = overlay as? MKPolyline else { return MKOverlayRenderer(overlay: overlay) }
            let renderer = MKPolylineRenderer(polyline: polyline)
            renderer.strokeColor = .systemOrange
            renderer.lineWidth = 4
            return renderer
        }

        func mapView(_ mapView: MKMapView, viewFor annotation: MKAnnotation) -> MKAnnotationView? {
            guard annotation.title == "roadbook-live-position" else { return nil }
            let view = MKAnnotationView(annotation: annotation, reuseIdentifier: "roadbook-live-position")
            view.image = UIImage(systemName: "location.north.circle.fill")?
                .withTintColor(.systemBlue, renderingMode: .alwaysOriginal)
            return view
        }
    }
}
