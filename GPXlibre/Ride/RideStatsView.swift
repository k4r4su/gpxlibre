import SwiftUI

/// Badge replié (toujours visible, vitesse actuelle) — tap pour déplier le panneau complet.
/// Masqué par défaut au sens où seul ce badge minimal apparaît ; le détail est un choix
/// explicite de l'utilisateur (tap), jamais imposé à l'écran.
struct RideStatsBadge: View {
    let currentSpeedKmh: Double
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 0) {
                Text("\(Int(currentSpeedKmh.rounded()))")
                    .font(.system(size: 22, weight: .bold, design: .rounded))
                    .monospacedDigit()
                Text("km/h")
                    .font(.system(size: 9))
            }
            .foregroundStyle(.white)
            .frame(width: 60, height: 60)
            .background(.black.opacity(0.6))
            .clipShape(Circle())
        }
        .accessibilityLabel("Vitesse \(Int(currentSpeedKmh)) km/h, toucher pour plus de mesures")
    }
}

struct RideStatsPanel: View {
    let currentSpeedKmh: Double
    let averageSpeedKmh: Double
    let maxSpeedKmh: Double
    let distanceRemainingMeters: Double?
    let percentComplete: Double?
    let estimatedArrivalDate: Date?
    let onCollapse: () -> Void

    private static let timeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.timeStyle = .short
        return formatter
    }()

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Mesures")
                    .font(.headline)
                    .foregroundStyle(.white)
                Spacer()
                Button(action: onCollapse) {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.white.opacity(0.7))
                }
            }
            HStack(spacing: 24) {
                stat("Vitesse", "\(Int(currentSpeedKmh.rounded()))", unit: "km/h", emphasized: true)
                stat("Moyenne", "\(Int(averageSpeedKmh.rounded()))", unit: "km/h")
                stat("Max", "\(Int(maxSpeedKmh.rounded()))", unit: "km/h")
            }
            HStack(spacing: 24) {
                stat("Restant", distanceRemainingMeters.map(formattedDistance) ?? "—", unit: "")
                stat("Parcouru", percentComplete.map { "\(Int($0.rounded()))" } ?? "—", unit: percentComplete != nil ? "%" : "")
                stat("Arrivée", estimatedArrivalDate.map(Self.timeFormatter.string) ?? "—", unit: "")
            }
        }
        .padding(16)
        .background(.black.opacity(0.7))
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
    }

    private func stat(_ title: String, _ value: String, unit: String, emphasized: Bool = false) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(unit.isEmpty ? value : "\(value) \(unit)")
                .font(.system(size: emphasized ? 22 : 17, weight: .bold, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(.white)
            Text(title)
                .font(.caption2)
                .foregroundStyle(.white.opacity(0.7))
        }
    }

    private func formattedDistance(_ meters: Double) -> String {
        meters < 1000 ? "\(Int(meters.rounded()))m" : String(format: "%.1fkm", meters / 1000)
    }
}
