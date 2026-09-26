import SwiftUI

/// Statut du guidage "Aller à" en cours (pointillés cyan sur la carte) — distance à vol
/// d'oiseau jusqu'à la vraie destination, quel que soit le profil.
struct GoToStatusPillView: View {
    let guidance: GoToGuidance
    let distanceMeters: Double?
    let isRequesting: Bool
    let onCancel: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: guidance.profile.systemImageName)
                .foregroundStyle(.white)
            VStack(alignment: .leading, spacing: 2) {
                Text("\(guidance.profile.label) → \(guidance.destinationLabel)")
                    .font(.caption.bold())
                    .foregroundStyle(.white)
                    .lineLimit(1)
                Text(distanceText)
                    .font(.subheadline.bold())
                    .foregroundStyle(.white)
                    .monospacedDigit()
                // Estimations distance/durée du TRACÉ (spec "offroad-routing-preference", it13)
                // — distinctes de la ligne ci-dessus (distance RESTANTE à vol d'oiseau jusqu'à
                // la destination, qui continue de baisser en roulant).
                Text(routeSummaryText)
                    .font(.caption2)
                    .foregroundStyle(.white.opacity(0.8))
                    .monospacedDigit()
            }
            Spacer()
            if isRequesting {
                ProgressView().tint(.white)
            }
            Button(action: onCancel) {
                Image(systemName: "xmark.circle.fill")
                    .foregroundStyle(.white.opacity(0.8))
            }
            .longPressTooltip(String(localized: "Annuler ce guidage", bundle: .appLanguage))
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .ridePanelStyle(tint: .cyan, tintOpacity: 0.35)
        .padding(.horizontal)
        .transition(.ridePanel)
    }

    private var distanceText: String {
        guard let distanceMeters else { return "—" }
        return distanceMeters < 1000 ? String(localized: "\(Int(distanceMeters.rounded())) m à vol d'oiseau", bundle: .appLanguage) : String(format: "%.1f km à vol d'oiseau", distanceMeters / 1000)
    }

    /// Estimation simple (vitesse moyenne par profil, PAS un ETA OSRM réel — voir
    /// GoToGuidance.estimatedDurationMinutes) de la longueur totale du tracé affiché.
    private var routeSummaryText: String {
        let distance = guidance.routeDistanceMeters
        let distanceText = distance < 1000 ? "\(Int(distance.rounded())) m" : String(format: "%.1f km", distance / 1000)
        return String(localized: "Itinéraire ≈ \(distanceText) · ~\(max(Int(guidance.estimatedDurationMinutes.rounded()), 1)) min", bundle: .appLanguage)
    }
}
