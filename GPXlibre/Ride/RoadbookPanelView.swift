import SwiftUI

/// Panneau roadbook en bas d'écran (spec "roadbook-declutter") : flèche très grande à gauche,
/// distance énorme au centre, compteur compact "⚑ N/M" à droite — plus de ligne "Gauche ·
/// Checkpoint 12/196" redondante (l'icône donne déjà la direction, le badge donne déjà le
/// compte). Mini preview du virage suivant en dessous, en gris, pour que le motard voie qu'il
/// y en a un deuxième sans avoir à lire.
struct RoadbookPanelView: View {
    let checkpoint: Checkpoint?
    let nextCheckpoint: Checkpoint?
    let totalCount: Int
    let distanceMeters: Double?
    let isClose: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 16) {
                Image(systemName: checkpoint?.direction.systemImageName ?? "checkmark.seal.fill")
                    .font(.system(size: isClose ? 58 : 44, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(width: 64, height: 64)
                    .animation(.spring(response: 0.3, dampingFraction: 0.7), value: isClose)

                Text(distanceText)
                    .font(.system(size: 40, weight: .heavy, design: .rounded))
                    .foregroundStyle(.white)
                    .monospacedDigit()
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)

                Spacer(minLength: 8)

                if let checkpoint {
                    Label("\(checkpoint.sequenceIndex)/\(totalCount)", systemImage: "flag.fill")
                        .font(.caption.bold())
                        .foregroundStyle(.white.opacity(0.85))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(.white.opacity(0.15))
                        .clipShape(Capsule())
                }
            }

            // Ligne secondaire supprimée par défaut (direction + compte déjà donnés par
            // l'icône et le badge) — gardée uniquement quand elle apporte une info réelle.
            if checkpoint == nil {
                Text(totalCount == 0 ? "Aucun virage détecté" : "Trace terminée")
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.8))
            }

            if let checkpoint, let nextCheckpoint {
                HStack(spacing: 8) {
                    Image(systemName: nextCheckpoint.direction.systemImageName)
                        .font(.system(size: 15, weight: .semibold))
                    Text(nextDistanceText(from: checkpoint, to: nextCheckpoint))
                        .font(.caption.bold())
                        .monospacedDigit()
                    Text("ensuite")
                        .font(.caption2)
                }
                .foregroundStyle(.white.opacity(0.5))
            }
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

    /// Distance fixe entre deux checkpoints de la trace (pas une mesure GPS live) — suffisant
    /// pour un aperçu glanceable, pas pour un guidage précis.
    private func nextDistanceText(from checkpoint: Checkpoint, to next: Checkpoint) -> String {
        let meters = RoadbookAnalyzer.distanceMeters(checkpoint.coordinate, next.coordinate)
        return meters < 1000 ? "\(Int(meters.rounded())) m" : String(format: "%.1f km", meters / 1000)
    }
}
