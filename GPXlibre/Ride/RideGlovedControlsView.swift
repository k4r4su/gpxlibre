import SwiftUI

/// Zoom +/- par paliers discrets + recentrage — cibles ≥56pt, coins arrondis, fond flouté,
/// pensés pour rester utilisables à une main, avec des gants, sans dépendre du pinch.
struct RideGlovedZoomControls: View {
    let onZoomIn: () -> Void
    let onZoomOut: () -> Void

    var body: some View {
        VStack(spacing: 14) {
            glovedButton(systemImage: "plus", label: nil, action: onZoomIn)
            glovedButton(systemImage: "minus", label: nil, action: onZoomOut)
        }
    }

    private func glovedButton(systemImage: String, label: String?, action: @escaping () -> Void) -> some View {
        let explanation = systemImage == "plus" ? String(localized: "Zoomer", bundle: .appLanguage) : String(localized: "Dézoomer", bundle: .appLanguage)
        return Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: 22, weight: .bold))
                .foregroundStyle(.white)
                .frame(width: RideConstants.glovedTapTargetSize, height: RideConstants.glovedTapTargetSize)
                .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                .background(.black.opacity(0.25), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
        .longPressTooltip(explanation)
    }
}

/// Visible uniquement quand la caméra a dérivé de la position (drag/pinch) — masqué sinon
/// pour ne pas surcharger l'écran.
struct RideRecenterButton: View {
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 2) {
                Image(systemName: "scope")
                    .font(.system(size: 20, weight: .bold))
                Text("me recentrer")
                    .font(.system(size: 10, weight: .semibold))
            }
            .foregroundStyle(.white)
            .frame(width: RideConstants.glovedTapTargetSize + 8, height: RideConstants.glovedTapTargetSize + 8)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            .background(.blue.opacity(0.35), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        }
        .accessibilityLabel("Me recentrer sur ma position, reprendre le cap")
        .transition(.scale.combined(with: .opacity))
    }
}
