import SwiftUI
import CoreLocation

/// Enveloppe déplaçable de `RoadbookMiniMapView` (spec "roadbook-mode", it23quinquies, retour
/// terrain : "il faudrait pouvoir la changer à la volée, comme une fenêtre qui s'affiche par
/// dessus et qu'on peut déplacer suivant la préférence de l'utilisateur") — position persistée
/// en FRACTION (0...1) de la zone disponible (`RideSettingsStore.
/// roadbookMiniMapPositionXFraction/YFraction`), jamais en points absolus : reste cohérente si
/// l'orientation ou la taille d'écran change entre deux sessions.
///
/// Contrôles +/- de zoom intégrés (retour terrain : "essaye de faire en sorte qu'on voit les
/// 400 mètres de chaque côté... ou fait que ce paramètre soit changeable") — directement sur la
/// mini-carte plutôt que dans un réglage séparé, pour un ajustement immédiat pendant la lecture.
struct RoadbookDraggableMiniMap: View {
    let track: GPXTrack
    let currentLocation: CLLocationCoordinate2D?
    let containerSize: CGSize
    @Binding var spanMeters: Double
    @Binding var positionXFraction: Double
    @Binding var positionYFraction: Double

    @State private var dragTranslation: CGSize = .zero

    private var mapSize: CGSize {
        CGSize(width: containerSize.width * 0.4, height: containerSize.height * 0.16)
    }

    var body: some View {
        let halfWidth = mapSize.width / 2
        let halfHeight = mapSize.height / 2
        let baseX = positionXFraction * containerSize.width
        let baseY = positionYFraction * containerSize.height
        let liveX = clamp(baseX + dragTranslation.width, min: halfWidth, max: containerSize.width - halfWidth)
        let liveY = clamp(baseY + dragTranslation.height, min: halfHeight, max: containerSize.height - halfHeight)

        ZStack(alignment: .topTrailing) {
            RoadbookMiniMapView(track: track, currentLocation: currentLocation, spanMeters: spanMeters)

            zoomControls
                .padding(4)

            Image(systemName: "arrow.up.and.down.and.arrow.left.and.right")
                .font(.system(size: 9, weight: .bold))
                .foregroundStyle(.white)
                .padding(4)
                .background(.black.opacity(0.4), in: Circle())
                .padding(4)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
        .frame(width: mapSize.width, height: mapSize.height)
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).stroke(.white.opacity(0.5), lineWidth: 1.5))
        .shadow(color: .black.opacity(0.3), radius: 6, x: 0, y: 3)
        .position(x: liveX, y: liveY)
        .gesture(
            DragGesture()
                .onChanged { value in dragTranslation = value.translation }
                .onEnded { value in
                    let finalX = clamp(baseX + value.translation.width, min: halfWidth, max: containerSize.width - halfWidth)
                    let finalY = clamp(baseY + value.translation.height, min: halfHeight, max: containerSize.height - halfHeight)
                    positionXFraction = containerSize.width > 0 ? finalX / containerSize.width : positionXFraction
                    positionYFraction = containerSize.height > 0 ? finalY / containerSize.height : positionYFraction
                    dragTranslation = .zero
                }
        )
    }

    private var zoomControls: some View {
        VStack(spacing: 4) {
            zoomButton(systemImage: "plus") {
                spanMeters = clamp(spanMeters - RoadBookConstants.miniMapSpanMetersStep, min: RoadBookConstants.miniMapSpanMetersRange.lowerBound, max: RoadBookConstants.miniMapSpanMetersRange.upperBound)
            }
            zoomButton(systemImage: "minus") {
                spanMeters = clamp(spanMeters + RoadBookConstants.miniMapSpanMetersStep, min: RoadBookConstants.miniMapSpanMetersRange.lowerBound, max: RoadBookConstants.miniMapSpanMetersRange.upperBound)
            }
        }
    }

    /// "+" RAPPROCHE (span plus petit), "-" ÉLOIGNE (span plus grand) — convention zoom
    /// habituelle, inversée par rapport à la variation brute de `spanMeters`.
    private func zoomButton(systemImage: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(.white)
                .frame(width: 18, height: 18)
                .background(.black.opacity(0.45), in: Circle())
        }
        .buttonStyle(.plain)
    }

    private func clamp(_ value: CGFloat, min minValue: CGFloat, max maxValue: CGFloat) -> CGFloat {
        Swift.min(Swift.max(value, minValue), maxValue)
    }

    private func clamp(_ value: Double, min minValue: Double, max maxValue: Double) -> Double {
        Swift.min(Swift.max(value, minValue), maxValue)
    }
}
