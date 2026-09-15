import SwiftUI

/// Bannière non bloquante en haut d'écran — détection automatique OU appui manuel sur
/// le bouton "Chemin bloqué" déclenchent le même flow.
struct BlockedPathBannerView: View {
    let onContourner: () -> Void
    let onIgnorer: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.yellow)
            Text("Portion bloquée ?")
                .font(.subheadline.bold())
                .foregroundStyle(.white)
            Spacer()
            Button(action: onContourner) {
                Label("Contourner", systemImage: "arrow.triangle.swap")
            }
            .font(.subheadline.bold())
            .buttonStyle(.borderedProminent)
            .tint(.orange)
            Button {
                onIgnorer()
            } label: {
                Image(systemName: "xmark")
                    .foregroundStyle(.white)
            }
            .longPressTooltip("Ignorer l'alerte")
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .ridePanelStyle()
        .padding(.horizontal)
        .transition(.ridePanel)
    }
}

/// Toujours visible en Ride, gros et utilisable avec des gants. Action critique (spec
/// Bloc 2) : label texte permanent, pas seulement un explicateur au long-press.
struct BlockedPathButton: View {
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 2) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 20, weight: .bold))
                Text("Bloqué")
                    .font(.system(size: 9, weight: .semibold))
            }
            .foregroundStyle(.white)
            .frame(width: 56, height: 56)
            .background(.red.opacity(0.85))
            .clipShape(Circle())
        }
        .accessibilityLabel("Chemin bloqué")
    }
}

/// Bandeau d'état pendant / après un détour actif — visible tant que le contournement
/// ou le guidage direct est en cours ; annulation manuelle possible en plus du retrait auto.
struct DetourStatusView: View {
    let detour: DetourRoute
    let isRequesting: Bool
    let onCancel: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: modeIcon)
                .foregroundStyle(.white)
            VStack(alignment: .leading, spacing: 2) {
                Text(modeLabel)
                    .font(.subheadline.bold())
                    .foregroundStyle(.white)
                Text("La trace d'origine reste affichée")
                    .font(.caption2)
                    .foregroundStyle(.white.opacity(0.75))
            }
            Spacer()
            Button(action: onCancel) {
                Label("Annuler", systemImage: "xmark.circle")
            }
            .font(.caption.bold())
            .buttonStyle(.bordered)
            .tint(.white)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .ridePanelStyle(tint: .red, tintOpacity: 0.5)
        .padding(.horizontal)
        .transition(.ridePanel)
    }

    private var modeLabel: String {
        switch detour.mode {
        case .routed(let profile): return "Détour (\(profile.displayName)) actif"
        case .direct: return "Rejoins ta trace — guidage direct"
        }
    }

    private var modeIcon: String {
        switch detour.mode {
        case .routed: return "arrow.triangle.swap"
        case .direct: return "location.north.line.fill"
        }
    }
}
