import SwiftUI

/// Panneau "hors trace" EN HAUT d'écran, pleine largeur (fix "overlay-layout-grid", Bug 3) —
/// le cas "virage à venir" est désormais porté par la bannière latérale (spec
/// "lateral-cap-banner-countdown", it12, voir LateralCapBannerView) pour laisser la trace
/// visible droit devant ; ce panneau ne reste utilisé QUE pour l'alerte "hors trace", assez
/// importante pour rester en haut, pleine largeur, impossible à manquer.
struct RoadbookPanelView: View {
    /// Cap vers le point de reprise, RELATIF au cap actuel (spec Bloc 2 "resync-hysteresis") —
    /// 0° = droit devant à l'écran, cohérent avec la caméra cap-en-haut.
    let offTrackInfo: OffTrackInfo

    struct OffTrackInfo {
        let relativeBearingDegrees: Double
        let distanceMeters: Double?
    }

    /// Discret à dessein : ne doit pas alarmer comme "Portion bloquée ?" (qui reste séparé,
    /// après 30 s/200 m) — juste indiquer qu'on attend un retour sur trace.
    var body: some View {
        HStack(spacing: 16) {
            Image(systemName: "location.north.line.fill")
                .font(.system(size: 32, weight: .bold))
                .rotationEffect(.degrees(offTrackInfo.relativeBearingDegrees))
                .foregroundStyle(.white.opacity(0.85))
                .frame(width: 64, height: 64)

            VStack(alignment: .leading, spacing: 2) {
                Text("Hors trace")
                    .font(.system(.title3, design: .rounded).bold())
                    .foregroundStyle(.white)
                if let distance = offTrackInfo.distanceMeters {
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
}
