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
            // Fix "panel-consistency" (Bug 6) : même matériau que les panneaux (ultraThinMaterial
            // sombre) — la forme reste un cercle (bouton, pas un panneau rectangulaire).
            .background(Color.black.opacity(0.35))
            .background(.ultraThinMaterial)
            .environment(\.colorScheme, .dark)
            .clipShape(Circle())
            .shadow(color: .black.opacity(0.28), radius: 10, x: 0, y: 4)
        }
        .accessibilityLabel(String(localized: "Vitesse \(settings.speedUnit.displayString(fromKmh: currentSpeedKmh)), toucher pour plus de mesures", bundle: .appLanguage))
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
    /// Enregistrement de la sortie (it30) : pause/reprise ici, état expliqué.
    let recordingState: RideRecorder.State
    let recordingStatus: String?
    let onToggleRecording: () -> Void
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
                .longPressTooltip(String(localized: "Replier les mesures", bundle: .appLanguage))
            }
            HStack(spacing: 24) {
                stat(String(localized: "Vitesse", bundle: .appLanguage), "\(settings.speedUnit.roundedValue(fromKmh: currentSpeedKmh))", unit: settings.speedUnit.label, emphasized: true)
                stat(String(localized: "Moyenne", bundle: .appLanguage), "\(settings.speedUnit.roundedValue(fromKmh: averageSpeedKmh))", unit: settings.speedUnit.label)
                stat(String(localized: "Max", bundle: .appLanguage), "\(settings.speedUnit.roundedValue(fromKmh: maxSpeedKmh))", unit: settings.speedUnit.label)
            }
            HStack(spacing: 24) {
                stat(String(localized: "Restant", bundle: .appLanguage), distanceRemainingMeters.map(formattedDistance) ?? "—", unit: "")
                stat(String(localized: "Parcouru", bundle: .appLanguage), percentComplete.map { "\(Int($0.rounded()))" } ?? "—", unit: percentComplete != nil ? "%" : "")
                stat(String(localized: "Arrivée", bundle: .appLanguage), estimatedArrivalDate.map(Self.timeFormatter.string) ?? "—", unit: "")
            }
            // Spec "nav-classic-rebuild" (it21) : "barre d'état... ETA, distance restante,
            // durée restante" — les trois premiers stats ci-dessus sont partagés Trace/Nav
            // (déjà écrits par les deux, voir RideSessionManager.updateNavProgress/
            // updateRideStats) ; "durée restante" (countdown, pas une heure d'horloge) manquait
            // et profite aux deux modes de la même façon, pas seulement au Mode Nav.
            if let estimatedArrivalDate {
                HStack(spacing: 24) {
                    stat(String(localized: "Durée restante", bundle: .appLanguage), remainingDurationText(until: estimatedArrivalDate), unit: "")
                }
            }
            if let recordingStatus {
                Text(recordingStatus)
                    .font(.caption2)
                    .foregroundStyle(.white.opacity(0.8))
                    .fixedSize(horizontal: false, vertical: true)
            }
            Button(action: onToggleRecording) {
                Label(recordingToggleTitle, systemImage: recordingState == .recording ? "pause.circle" : "record.circle")
                    .font(.caption.bold())
            }
            .buttonStyle(.bordered)
            .tint(recordingState == .recording ? .orange : .red)
            if recordedPointsCount > 0 {
                Button(action: onEndRide) {
                    Label("Terminer la sortie (\(recordedPointsCount) pts enregistrés)", systemImage: "flag.checkered")
                        .font(.caption.bold())
                }
                .buttonStyle(.bordered)
                .tint(.white)
            }
        }
        .padding(16)
        .ridePanelStyle()
    }

    private var recordingToggleTitle: String {
        switch recordingState {
        case .idle: return String(localized: "Démarrer l'enregistrement", bundle: .appLanguage)
        case .recording: return String(localized: "Mettre en pause", bundle: .appLanguage)
        case .paused: return String(localized: "Reprendre l'enregistrement", bundle: .appLanguage)
        }
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

    private func remainingDurationText(until arrival: Date) -> String {
        let minutes = Int((max(arrival.timeIntervalSinceNow, 0) / 60).rounded())
        guard minutes >= 60 else { return "\(minutes) min" }
        return "\(minutes / 60) h \(minutes % 60) min"
    }
}
