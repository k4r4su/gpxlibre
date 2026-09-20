import SwiftUI
import MapKit

/// Mini-carte optionnelle du Road Book (spec "roadbook-mode", it23, point 1 : "utile en debug
/// de fiabilité de la feature et comme filet de sécurité visuel"). Volontairement légère
/// (MapKit, jamais une deuxième instance MapLibre) — même esprit que `CameraPreviewMapView`
/// (Settings/), mais fichier séparé plutôt que d'élargir sa signature : `CameraPreviewMapView`
/// est déjà partagée par 3 écrans Réglages avec un contrat fixe, et ce mini-map a un besoin
/// légèrement différent (position live optionnelle en mode Assisté GPS).
///
/// Fix "roadbook-focused-next-turn" (it23ter, retour terrain : "la map peut être zoomée pour
/// afficher 2 km carré autour du point actuel... un aperçu pour voir qu'on est bien sur la
/// trace ou non, pas la trace complète") — quand une position live est disponible, la caméra
/// reste centrée dessus à une portée FIXE (`spanMeters`, voir `RoadBookConstants.
/// miniMapSpanMeters`), recalculée à chaque mise à jour de position. Sans position (trace
/// affichée sans GPS), repli sur l'ancien comportement : cadrer la trace entière une fois au
/// montage — mieux que rien tant qu'aucune position n'est connue.
struct RoadbookMiniMapView: UIViewRepresentable {
    let track: GPXTrack
    let currentLocation: CLLocationCoordinate2D?
    var spanMeters: Double = RoadBookConstants.miniMapSpanMeters

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
        if let currentLocation {
            mapView.setRegion(region(centeredOn: currentLocation), animated: false)
        } else if let region = regionCoveringTrack(track) {
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
            mapView.setRegion(region(centeredOn: currentLocation), animated: true)
        }
    }

    /// Approximation équirectangulaire (même formule que `CameraPreviewMapView`/
    /// `TileCoordinate.boundingBox`) — suffisante pour un simple ressenti visuel de zoom, pas
    /// besoin d'une projection exacte pour un aperçu de 2 km.
    private func region(centeredOn coordinate: CLLocationCoordinate2D) -> MKCoordinateRegion {
        let latDelta = spanMeters / 111_320
        let lonDelta = latDelta / max(cos(coordinate.latitude * .pi / 180), 0.2)
        return MKCoordinateRegion(center: coordinate, span: MKCoordinateSpan(latitudeDelta: latDelta, longitudeDelta: lonDelta))
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
