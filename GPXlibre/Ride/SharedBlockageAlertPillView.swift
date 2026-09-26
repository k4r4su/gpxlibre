import SwiftUI

/// Alerte quand la trace chargée passe à moins de 300 m d'un point bloqué connu de la
/// base partagée (Bloc 5) — distincte de BlockedPathBannerView (détection GPS temps réel
/// de blocage en cours) : ceci prévient AVANT d'arriver, à partir de signalements d'autres
/// utilisateurs.
struct SharedBlockageAlertPillView: View {
    let blockage: SharedBlockage
    let onDismiss: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)
            VStack(alignment: .leading, spacing: 2) {
                Text("Point bloqué signalé sur ta route")
                    .font(.subheadline.bold())
                    .foregroundStyle(.white)
                if let note = blockage.note {
                    Text(note)
                        .font(.caption2)
                        .foregroundStyle(.white.opacity(0.8))
                        .lineLimit(1)
                }
            }
            Spacer()
            Button {
                onDismiss()
            } label: {
                Image(systemName: "xmark")
                    .foregroundStyle(.white)
            }
            .longPressTooltip(String(localized: "Masquer cette alerte", bundle: .appLanguage))
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .ridePanelStyle(tint: .orange, tintOpacity: 0.5)
        .padding(.horizontal)
        .transition(.ridePanel)
    }
}
