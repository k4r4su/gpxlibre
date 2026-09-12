import SwiftUI

/// Panneau roadbook EN HAUT d'écran, pleine largeur (fix "overlay-layout-grid", Bug 3 — déplacé
/// du bas, où il se confondait avec la tab bar et masquait la position, Bug 2) : flèche très
/// grande à gauche, distance énorme au centre, compteur compact "⚑ N/M" à droite — plus de
/// ligne "Gauche · Checkpoint 12/196" redondante (l'icône donne déjà la direction, le badge
/// donne déjà le compte). Mini preview du virage suivant en dessous, en gris, pour que le
/// motard voie qu'il y en a un deuxième sans avoir à lire.
struct RoadbookPanelView: View {
    let checkpoint: Checkpoint?
    let nextCheckpoint: Checkpoint?
    let totalCount: Int
    let distanceMeters: Double?
    let isClose: Bool
    /// Bloc 2 "resync-hysteresis" : quand non-nil, remplace l'affichage normal — le roadbook
    /// est en pause (hors trace), plus de rappel d'un checkpoint déjà largué.
    let offTrackInfo: OffTrackInfo?

    struct OffTrackInfo {
        /// Cap vers le point de reprise, RELATIF au cap actuel (0 = droit devant à l'écran).
        let relativeBearingDegrees: Double
        let distanceMeters: Double?
    }

    var body: some View {
        if let offTrackInfo {
            offTrackBody(offTrackInfo)
        } else {
            onTrackBody
        }
    }

    /// Discret à dessein : ne doit pas alarmer comme "Portion bloquée ?" (qui reste séparé,
    /// après 30 s/200 m) — juste indiquer qu'on attend un retour sur trace.
    private func offTrackBody(_ info: OffTrackInfo) -> some View {
        HStack(spacing: 16) {
            Image(systemName: "location.north.line.fill")
                .font(.system(size: 32, weight: .bold))
                .rotationEffect(.degrees(info.relativeBearingDegrees))
                .foregroundStyle(.white.opacity(0.85))
                .frame(width: 64, height: 64)

            VStack(alignment: .leading, spacing: 2) {
                Text("Hors trace")
                    .font(.system(.title3, design: .rounded).bold())
                    .foregroundStyle(.white)
                if let distance = info.distanceMeters {
                    Text("Reprise à \(offTrackDistanceText(distance))")
                        .font(.caption)
                        .foregroundStyle(.white.opacity(0.75))
                }
            }
            Spacer(minLength: 8)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .ridePanelStyle()
        .padding(.horizontal, 12)
    }

    private func offTrackDistanceText(_ meters: Double) -> String {
        meters < 1000 ? "\(Int(meters.rounded())) m" : String(format: "%.1f km", meters / 1000)
    }

    private var onTrackBody: some View {
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
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .ridePanelStyle()
        .padding(.horizontal, 12)
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
