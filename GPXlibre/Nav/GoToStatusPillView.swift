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
            }
            Spacer()
            if isRequesting {
                ProgressView().tint(.white)
            }
            Button(action: onCancel) {
                Image(systemName: "xmark.circle.fill")
                    .foregroundStyle(.white.opacity(0.8))
            }
            .longPressTooltip("Annuler ce guidage")
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .ridePanelStyle(tint: .cyan, tintOpacity: 0.35)
        .padding(.horizontal)
        .transition(.ridePanel)
    }

    private var distanceText: String {
        guard let distanceMeters else { return "—" }
        return distanceMeters < 1000 ? "\(Int(distanceMeters.rounded())) m à vol d'oiseau" : String(format: "%.1f km à vol d'oiseau", distanceMeters / 1000)
    }
}
