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
    /// "Choisir le début" (spec "per-track-settings") : quand non-nil, un tap sur la carte
    /// remonte l'INDEX du point de la trace le plus proche (pas juste la coordonnée brute —
    /// le départ personnalisé doit toujours tomber exactement sur un point existant de la
    /// trace, jamais un point inventé à côté).
    var onPickStartIndex: ((Int) -> Void)?
    /// Affiche un marqueur distinct au point de départ actuellement retenu (origine ou
    /// personnalisé) — purement visuel.
    var startIndexToHighlight: Int?

    func makeUIView(context: Context) -> MKMapView {
        let mapView = MKMapView()
        mapView.delegate = context.coordinator
        mapView.showsUserLocation = true
        mapView.showsCompass = true
        mapView.showsScale = true
        mapView.pointOfInterestFilter = .excludingAll

        if onPickStartIndex != nil {
            let tap = UITapGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.handleTap))
            mapView.addGestureRecognizer(tap)
            context.coordinator.track = track
            context.coordinator.onPickStartIndex = onPickStartIndex
        }

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
        context.coordinator.track = track
        context.coordinator.onPickStartIndex = onPickStartIndex
        syncStartHighlight(on: mapView, context: context)
    }

    private func syncStartHighlight(on mapView: MKMapView, context: Context) {
        guard context.coordinator.highlightedIndex != startIndexToHighlight else { return }
        context.coordinator.highlightedIndex = startIndexToHighlight
        if let existing = context.coordinator.startAnnotation {
            mapView.removeAnnotation(existing)
            context.coordinator.startAnnotation = nil
        }
        guard let index = startIndexToHighlight, track.points.indices.contains(index) else { return }
        let annotation = TrackStartAnnotation()
        annotation.coordinate = track.points[index].coordinate
        annotation.title = "Départ"
        mapView.addAnnotation(annotation)
        context.coordinator.startAnnotation = annotation
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
        var track: GPXTrack?
        var onPickStartIndex: ((Int) -> Void)?
        var startAnnotation: TrackStartAnnotation?
        var highlightedIndex: Int?

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

        func mapView(_ mapView: MKMapView, viewFor annotation: MKAnnotation) -> MKAnnotationView? {
            // Uniquement le marqueur de départ personnalisé — les waypoints de la trace
            // gardent leur pin par défaut MapKit (aucun delegate avant cet ajout).
            guard annotation is TrackStartAnnotation else { return nil }
            let identifier = "start"
            let view = mapView.dequeueReusableAnnotationView(withIdentifier: identifier) as? MKMarkerAnnotationView
                ?? MKMarkerAnnotationView(annotation: annotation, reuseIdentifier: identifier)
            view.annotation = annotation
            view.markerTintColor = .systemGreen
            view.glyphImage = UIImage(systemName: "flag.checkered")
            view.canShowCallout = true
            return view
        }

        /// "Choisir le début" (spec "per-track-settings") : capture le point de la trace le
        /// plus proche du tap — jamais une coordonnée arbitraire à côté de la trace.
        @objc func handleTap(_ gesture: UITapGestureRecognizer) {
            guard let mapView = gesture.view as? MKMapView, let track, !track.points.isEmpty else { return }
            let point = gesture.location(in: mapView)
            let tapped = mapView.convert(point, toCoordinateFrom: mapView)
            var bestIndex = 0
            var bestDistance = Double.greatestFiniteMagnitude
            for (index, trackPoint) in track.points.enumerated() {
                let distance = RoadbookAnalyzer.distanceMeters(tapped, trackPoint.coordinate)
                if distance < bestDistance {
                    bestDistance = distance
                    bestIndex = index
                }
            }
            guard bestDistance <= RideConstants.customStartPickRadiusMeters else { return }
            onPickStartIndex?(bestIndex)
        }
    }
}

/// Marqueur du départ personnalisé (spec "Choisir le début") — sous-classe distincte pour ne
/// jamais affecter le style des annotations waypoints de la trace (celles-ci gardent le pin
/// par défaut MapKit).
final class TrackStartAnnotation: MKPointAnnotation {}
