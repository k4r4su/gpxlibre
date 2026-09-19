import SwiftUI

/// Bannière latérale de guidage de liaison (spec "rejoin-trace-guidance-banner", it18, Bloc 5) —
/// affichée pendant un recalcul automatique (spec "link-recompute-on-divergence", Bloc 3,
/// `ResumeGuidance.isAutomatic`) : même design colonne/translucide que `LateralCapBannerView`
/// (largeur fixe 92 pt, ISOLÉE, fix "overlay-never-pushes"), teinte indigo-lite pour distinguer
/// visuellement "liaison temporaire vers la trace" de "virage sur la trace elle-même" (orange/
/// rouge selon palier) — REJOINDRE_GUIDANCE_BANNER (RideConstants) peut la désactiver sans
/// toucher au recalcul lui-même. Distance mise à jour EN CONTINU par l'appelant (jamais stale,
/// voir RideSessionManager.resumeGuidanceLiveDistanceMeters), pas de détail de manœuvre
/// intermédiaire du tracé de liaison (simplification assumée, voir TODO.md).
struct RejoinGuidanceBannerView: View {
    let distanceMeters: Double
    /// Fix "rejoin-icon-dynamic-bearing" (it22, retour terrain : "l'icône a un statique, elle
    /// doit devenir dynamique et refléter la vraie direction à prendre") — cap relatif (0° =
    /// droit devant l'écran, cohérent avec la caméra cap-en-haut) vers le point de jonction,
    /// même calcul/patron que `OffTrackChipView.relativeBearingDegrees` (rotation continue d'un
    /// seul symbole, pas un jeu d'icônes discret gauche/droite/tout-droit — cohérent avec le
    /// reste de l'app). `nil` tant qu'aucune position n'est disponible (repli sur l'icône fixe
    /// non tournée, jamais un crash).
    let relativeBearingDegrees: Double?

    private static let width: CGFloat = 92

    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: "arrow.triangle.merge")
                .font(.system(size: 26, weight: .bold))
                .foregroundStyle(.white)
                .rotationEffect(.degrees(relativeBearingDegrees ?? 0))
            Text("Rejoindre\nla trace")
                .font(.system(size: 12, weight: .bold, design: .rounded))
                .foregroundStyle(.white)
                .multilineTextAlignment(.center)
                .lineLimit(2)
            Text(Self.distanceText(distanceMeters))
                .font(.system(size: 18, weight: .heavy, design: .rounded))
                .foregroundStyle(.white)
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        .frame(width: Self.width)
        .padding(.vertical, 12)
        .padding(.horizontal, 6)
        .ridePanelStyle(tint: .indigo, tintOpacity: 0.4)
    }

    static func distanceText(_ meters: Double) -> String {
        meters < 1000 ? "\(Int(meters.rounded())) m" : String(format: "%.1f km", meters / 1000)
    }
}
