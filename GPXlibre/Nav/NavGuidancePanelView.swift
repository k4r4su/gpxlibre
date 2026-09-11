import SwiftUI

/// Panneau de guidage tour-par-tour Mode Nav — instruction texte + flèche, distance jusqu'à
/// la manœuvre. Pendant du RoadbookPanelView côté Trace.
struct NavGuidancePanelView: View {
    let maneuver: NavManeuver?
    let distanceMeters: Double?
    let destinationLabel: String
    let isRecalculating: Bool

    var body: some View {
        HStack(spacing: 16) {
            Image(systemName: maneuver?.systemImageName ?? "location.north.line.fill")
                .font(.system(size: 36, weight: .bold))
                .foregroundStyle(.white)
                .frame(width: 60, height: 60)

            VStack(alignment: .leading, spacing: 2) {
                Text(distanceText)
                    .font(.system(.title2, design: .rounded).bold())
                    .foregroundStyle(.white)
                    .monospacedDigit()
                Text(maneuver?.instructionText ?? "Vers \(destinationLabel)")
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.85))
                    .lineLimit(1)
            }

            Spacer()

            if isRecalculating {
                ProgressView()
                    .tint(.white)
            }
        }
        .padding(16)
        .background(.blue.opacity(0.85))
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
}
