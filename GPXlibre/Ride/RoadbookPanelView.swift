import SwiftUI

/// Panneau roadbook en bas d'écran : flèche de direction, distance jusqu'au prochain
/// checkpoint, numéro / total. La flèche grossit à l'approche (< 30 m).
struct RoadbookPanelView: View {
    let checkpoint: Checkpoint?
    let totalCount: Int
    let distanceMeters: Double?
    let isClose: Bool

    var body: some View {
        HStack(spacing: 16) {
            Image(systemName: checkpoint?.direction.systemImageName ?? "checkmark.seal.fill")
                .font(.system(size: isClose ? 52 : 36, weight: .bold))
                .foregroundStyle(.white)
                .frame(width: 60, height: 60)
                .animation(.spring(response: 0.3, dampingFraction: 0.7), value: isClose)

            VStack(alignment: .leading, spacing: 2) {
                Text(distanceText)
                    .font(.system(.title2, design: .rounded).bold())
                    .foregroundStyle(.white)
                    .monospacedDigit()
                Text(subtitleText)
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.8))
            }

            Spacer()
        }
        .padding(16)
        .background(.black.opacity(0.6))
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .padding()
    }

    private var distanceText: String {
        guard let distanceMeters else { return "—" }
        if distanceMeters < 1000 {
            return "\(Int(distanceMeters.rounded())) m"
        }
        return String(format: "%.1f km", distanceMeters / 1000)
    }

    private var subtitleText: String {
        guard let checkpoint else { return totalCount == 0 ? "Aucun virage détecté" : "Trace terminée" }
        return "\(checkpoint.direction.label) · Checkpoint \(checkpoint.sequenceIndex)/\(totalCount)"
    }
}
