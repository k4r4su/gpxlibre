import SwiftUI

/// Bandeau visible en cas d'échec de chargement de la carte — jamais un écran noir muet.
struct MapLoadWarningBannerView: View {
    let message: String

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "wifi.exclamationmark")
                .foregroundStyle(.white)
            Text(message)
                .font(.subheadline.bold())
                .foregroundStyle(.white)
            Spacer()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .ridePanelStyle(tint: .red, tintOpacity: 0.55)
        .padding(.horizontal)
        .transition(.ridePanel)
    }
}
