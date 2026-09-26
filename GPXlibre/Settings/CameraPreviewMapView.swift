import SwiftUI
import MapKit

/// Carte de prévisualisation partagée par les 3 réglages "Réglages > Navigation" qui demandent
/// un "preview live/direct de la carte derrière le sheet" (spec it14, Blocs 1/6/7) : position
/// du point bleu, zoom par défaut, courbe de zoom automatique. Volontairement légère (MapKit,
/// comme TrackMapView) plutôt qu'une deuxième instance MapLibre — ce n'est qu'un aperçu, jamais
/// la vraie carte Ride.
///
/// Utilise la trace active de la bibliothèque si elle existe, sinon une trace d'exemple en
/// mémoire (petite courbe en S) — ces réglages doivent rester utilisables même sans trace
/// chargée (ex : premier lancement, avant tout import).
struct CameraPreviewMapView: UIViewRepresentable {
    let track: GPXTrack
    /// Portée caméra approximative (m) à représenter — convertie en `MKCoordinateRegion` par
    /// approximation simple (pas besoin de la précision exacte de `MLNMapCamera.acrossDistance`
    /// ici, juste un ressenti visuel correct du niveau de zoom).
    let spanMeters: Double
    var animated: Bool = true

    static let sampleTrack: GPXTrack = {
        // Petite courbe en S, ~1.2 km, juste assez pour donner un ressenti de virage aux
        // aperçus — jamais affichée ailleurs que dans ces réglages.
        let base = CLLocationCoordinate2D(latitude: 45.188, longitude: 5.724)
        var points: [GPXPoint] = []
        for i in 0...24 {
            let t = Double(i) / 24
            let lat = base.latitude + t * 0.010
            let lon = base.longitude + sin(t * .pi * 1.6) * 0.006
            points.append(GPXPoint(latitude: lat, longitude: lon))
        }
        return GPXTrack(id: UUID(), name: String(localized: "Aperçu", bundle: .appLanguage), fileName: "preview.gpx", importDate: Date(), points: points, waypoints: [])
    }()

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
        applyRegion(on: mapView, animated: false)
        return mapView
    }

    func updateUIView(_ mapView: MKMapView, context: Context) {
        applyRegion(on: mapView, animated: animated)
    }

    private func applyRegion(on mapView: MKMapView, animated: Bool) {
        guard let center = track.boundingRegion?.center else { return }
        // Approximation : 1 m ≈ 1/111_320° de latitude ; la portée demandée devient le
        // "diamètre" visible (latitudeDelta), la longitude compensée par cos(latitude).
        let latDelta = spanMeters / 111_320
        let lonDelta = latDelta / max(cos(center.latitude * .pi / 180), 0.2)
        let region = MKCoordinateRegion(center: center, span: MKCoordinateSpan(latitudeDelta: latDelta, longitudeDelta: lonDelta))
        mapView.setRegion(region, animated: animated)
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
    }
}

/// Superpose un point façon "position GPS" à une fraction verticale donnée de la zone carte —
/// utilisé UNIQUEMENT par l'aperçu "Position point bleu" (Bloc 1) : ceci ne reproduit PAS le
/// calcul exact de `RideOverlayLayout.computeMapInsets` (contentInset MapLibre), c'est un
/// repère visuel honnête de "où le point se trouvera à l'écran", pas une simulation physique.
struct AnchorFractionOverlay: View {
    let fraction: Double

    var body: some View {
        GeometryReader { geometry in
            ZStack {
                Circle()
                    .fill(.blue.opacity(0.25))
                    .frame(width: 44, height: 44)
                Circle()
                    .fill(.blue)
                    .frame(width: 16, height: 16)
                    .overlay(Circle().stroke(.white, lineWidth: 3))
            }
            .position(x: geometry.size.width / 2, y: geometry.size.height * fraction)
            .allowsHitTesting(false)
        }
    }
}
