import SwiftUI
import CoreLocation

/// Carte "Reprendre la trace ici" (Bloc 3, itération 10) — réutilise le mécanisme de
/// bannière déjà isolé (`RideView.activeBanner`/`bannerView`, zone haute figée depuis it9) :
/// aucune nouvelle zone d'overlay, donc aucun risque de reflow des autres contrôles
/// (fix "overlay-never-pushes", Bloc 2).
struct ResumeGuidanceCardView: View {
    let guidance: ResumeGuidance
    let isRequesting: Bool
    let routingError: String?
    let birdDistanceMeters: Double?
    let relativeBearingDegrees: Double?
    let onConfirm: () -> Void
    let onCancel: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 12) {
                if let relativeBearingDegrees, !guidance.isRouted {
                    Image(systemName: "location.north.line.fill")
                        .foregroundStyle(.white)
                        .rotationEffect(.degrees(relativeBearingDegrees))
                } else {
                    Image(systemName: guidance.isRouted ? "location.north.line.fill" : "mappin.circle.fill")
                        .foregroundStyle(.white)
                }
                Text(guidance.phase == .active ? "Reprise en cours" : "Reprendre la trace ici ?")
                    .font(.subheadline.bold())
                    .foregroundStyle(.white)
                Spacer()
                if isRequesting {
                    ProgressView().tint(.white)
                }
            }

            Text(infoText)
                .font(.caption)
                .foregroundStyle(.white.opacity(0.85))
                .fixedSize(horizontal: false, vertical: true)

            HStack {
                Spacer()
                if guidance.phase == .previewing {
                    Button(action: onConfirm) {
                        Label("Reprendre ici", systemImage: "arrow.triangle.merge")
                    }
                    .font(.caption.bold())
                    .buttonStyle(.borderedProminent)
                    .tint(.white)
                    .foregroundStyle(.blue)
                }
                Button(action: onCancel) {
                    Label(guidance.phase == .active ? "Annuler la reprise" : "Annuler", systemImage: "xmark.circle")
                }
                .font(.caption.bold())
                .buttonStyle(.bordered)
                .tint(.white)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .ridePanelStyle(tint: .blue, tintOpacity: 0.45)
        .padding(.horizontal)
        .transition(.ridePanel)
    }

    private var infoText: String {
        var parts: [String] = []
        if let birdDistanceMeters {
            parts.append(String(localized: "\(formattedDistance(birdDistanceMeters)) à vol d'oiseau", bundle: .appLanguage))
        }
        if guidance.isRouted, let routeDistanceMeters = guidance.routeDistanceMeters {
            parts.append(String(localized: "\(formattedDistance(routeDistanceMeters)) par la route", bundle: .appLanguage))
        } else if let routingError {
            parts.append(routingError)
        } else if isRequesting {
            parts.append("Calcul de l'itinéraire…")
        }
        return parts.joined(separator: " · ")
    }

    private func formattedDistance(_ meters: Double) -> String {
        meters < 1000 ? "\(Int(meters.rounded())) m" : String(format: "%.1f km", meters / 1000)
    }
}
