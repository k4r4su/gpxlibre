import SwiftUI

/// Badge replié (toujours visible, vitesse actuelle) — tap pour déplier le panneau complet.
/// Masqué par défaut au sens où seul ce badge minimal apparaît ; le détail est un choix
/// explicite de l'utilisateur (tap), jamais imposé à l'écran.
struct RideStatsBadge: View {
    let currentSpeedKmh: Double
    let action: () -> Void

    @EnvironmentObject private var settings: RideSettingsStore

    var body: some View {
        Button(action: action) {
            VStack(spacing: 0) {
                Text("\(settings.speedUnit.roundedValue(fromKmh: currentSpeedKmh))")
                    .font(.system(size: 22, weight: .bold, design: .rounded))
                    .monospacedDigit()
                Text(settings.speedUnit.label)
                    .font(.system(size: 9))
            }
            .foregroundStyle(.white)
            .frame(width: 60, height: 60)
            .background(.black.opacity(0.6))
            .clipShape(Circle())
        }
        .accessibilityLabel("Vitesse \(settings.speedUnit.displayString(fromKmh: currentSpeedKmh)), toucher pour plus de mesures")
    }
}

struct RideStatsPanel: View {
    let currentSpeedKmh: Double
    let averageSpeedKmh: Double
    let maxSpeedKmh: Double
    let distanceRemainingMeters: Double?
    let percentComplete: Double?
    let estimatedArrivalDate: Date?
    let recordedPointsCount: Int
    let onCollapse: () -> Void
    let onEndRide: () -> Void

    @EnvironmentObject private var settings: RideSettingsStore

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
                .longPressTooltip("Replier les mesures")
            }
            HStack(spacing: 24) {
                stat("Vitesse", "\(settings.speedUnit.roundedValue(fromKmh: currentSpeedKmh))", unit: settings.speedUnit.label, emphasized: true)
                stat("Moyenne", "\(settings.speedUnit.roundedValue(fromKmh: averageSpeedKmh))", unit: settings.speedUnit.label)
                stat("Max", "\(settings.speedUnit.roundedValue(fromKmh: maxSpeedKmh))", unit: settings.speedUnit.label)
            }
            HStack(spacing: 24) {
                stat("Restant", distanceRemainingMeters.map(formattedDistance) ?? "—", unit: "")
                stat("Parcouru", percentComplete.map { "\(Int($0.rounded()))" } ?? "—", unit: percentComplete != nil ? "%" : "")
                stat("Arrivée", estimatedArrivalDate.map(Self.timeFormatter.string) ?? "—", unit: "")
            }
            Button(action: onEndRide) {
                Label("Terminer la sortie (\(recordedPointsCount) pts enregistrés)", systemImage: "flag.checkered")
                    .font(.caption.bold())
            }
            .buttonStyle(.bordered)
            .tint(.white)
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
