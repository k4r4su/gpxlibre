import SwiftUI

/// Chip hors-trace compact (spec "offtrack-compact-chip", it18, Bloc 1) — remplace
/// `RoadbookPanelView` (bandeau plein-largeur EN HAUT, ~40 % de l'écran) : capture terrain du
/// 15/09/2026, "bloque la vue du prochain virage surtout en paysage". Posé dans la MÊME colonne
/// latérale que `LateralCapBannerView` (largeur fixe 92 pt, ISOLÉ, fix "overlay-never-pushes") —
/// les deux sont mutuellement exclusifs (hors-trace vs virage à venir sur trace), donc jamais
/// empilés, jamais de reflow des boutons en dessous.
///
/// Titre seul par défaut ("Hors trace") — la distance de reprise ne s'affiche qu'après
/// `RideConstants.offTrackChipDistanceDelaySeconds` (30 s) sans retour sur trace, pour rester
/// aussi discret que possible tant que ça peut se résorber tout seul.
struct OffTrackChipView: View {
    let relativeBearingDegrees: Double
    let distanceMeters: Double?
    /// Depuis quand `isOffTrackPaused` est vrai en continu — `nil` tant qu'inconnu (ne doit
    /// jamais arriver en pratique, RideSessionManager le renseigne dès l'entrée en hors-trace).
    let pausedSinceDate: Date?

    private static let width: CGFloat = 92

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            VStack(spacing: 6) {
                Image(systemName: "location.north.line.fill")
                    .font(.system(size: 26, weight: .bold))
                    .rotationEffect(.degrees(relativeBearingDegrees))
                    .foregroundStyle(.white.opacity(0.9))
                Text("Hors trace")
                    .font(.system(size: 13, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                if shouldShowDistance(now: context.date), let distanceMeters {
                    Text(Self.distanceText(distanceMeters))
                        .font(.system(size: 15, weight: .heavy, design: .rounded))
                        .foregroundStyle(.white.opacity(0.85))
                        .monospacedDigit()
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                }
            }
            .frame(width: Self.width)
            .padding(.vertical, 12)
            .padding(.horizontal, 6)
            .ridePanelStyle()
        }
    }

    func shouldShowDistance(now: Date) -> Bool {
        guard let pausedSinceDate else { return false }
        return now.timeIntervalSince(pausedSinceDate) >= RideConstants.offTrackChipDistanceDelaySeconds
    }

    static func distanceText(_ meters: Double) -> String {
        meters < 1000 ? "\(Int(meters.rounded())) m" : String(format: "%.1f km", meters / 1000)
    }
}
