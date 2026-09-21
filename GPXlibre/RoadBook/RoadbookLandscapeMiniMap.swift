import SwiftUI
import CoreLocation

/// Mini-carte PAYSAGE (spec "roadbook-ui-redesign", it25, point 2) — retour terrain détaillé :
/// "mini-carte réduite à une bande illisible" en paysage. Root cause : `RoadbookDraggableMiniMap`
/// dimensionne sa taille en FRACTION de `containerSize` (0.4×largeur, 0.16×hauteur) — sur un
/// écran deux fois moins haut qu'en portrait, 0.16×hauteur produit un bandeau écrasé illisible.
///
/// Taille FIXE en points (`RoadBookConstants.miniMapLandscapeWidth/Height`) plutôt qu'une
/// fraction, ancrée dans un coin dédié via `.overlay(alignment:)` (respecte nativement les
/// safe areas — jamais besoin de recalculer une position à la main pour éviter la tab bar,
/// contrairement au système de glisser en fraction de `RoadbookDraggableMiniMap`, pensé pour le
/// portrait). PAS déplaçable/zoomable en paysage — simplicité assumée plutôt qu'étendre le
/// système de glisser à une seconde orientation sans pouvoir le vérifier sur device.
///
/// `nil` (rien affiché) si le conteneur est trop court pour un rendu propre
/// (`RoadBookConstants.miniMapLandscapeMinContainerHeight`) — demande explicite de la fiche :
/// "masquée en paysage si le format ne permet pas un rendu propre, pas de compromis à moitié
/// cassé". Voir `RoadBookTabView`, seul appelant, pour ce garde.
struct RoadbookLandscapeMiniMap: View {
    let track: GPXTrack
    let currentLocation: CLLocationCoordinate2D?
    let spanMeters: Double

    var body: some View {
        RoadbookMiniMapView(track: track, currentLocation: currentLocation, spanMeters: spanMeters)
            .frame(width: RoadBookConstants.miniMapLandscapeWidth, height: RoadBookConstants.miniMapLandscapeHeight)
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).stroke(.white.opacity(0.5), lineWidth: 1.5))
            .shadow(color: .black.opacity(0.3), radius: 6, x: 0, y: 3)
    }
}
