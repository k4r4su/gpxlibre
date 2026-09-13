import SwiftUI

/// Bannière latérale cap (spec "lateral-cap-banner-countdown", it12) — remplace, pour le cas
/// "virage à venir", le panneau roadbook qui occupait toute la largeur EN HAUT (voir
/// RoadbookPanelView, désormais réservé au cas "hors trace") : posée sur le CÔTÉ pour laisser
/// la trace visible droit devant en cap-en-haut. Translucide à dessein (`ridePanelStyle()` =
/// ultraThinMaterial + teinte 0.35, dans la fourchette 0.25-0.4 demandée) — le texte reste en
/// pleine opacité blanche, comme tous les autres panneaux de l'app (cohérence "panel-
/// consistency"). Layout ISOLÉ (fix "overlay-never-pushes") : posée dans son propre calque,
/// jamais dans `RideOverlayLayout.computeMapInsets` — aucune remontée d'ancre/zoom à son
/// apparition/disparition (voir RideView.lateralCapBannerLayer).
struct LateralCapBannerView: View {
    let direction: TurnDirection
    let distanceMeters: Double
    let sequenceIndex: Int
    let totalCount: Int

    private static let width: CGFloat = 92

    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: direction.systemImageName)
                .font(.system(size: 30, weight: .bold))
                .foregroundStyle(.white)
            Text(Self.steppedDistanceText(distanceMeters))
                .font(.system(size: 24, weight: .heavy, design: .rounded))
                .foregroundStyle(.white)
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            Label("\(sequenceIndex)/\(totalCount)", systemImage: "flag.fill")
                .font(.caption2.bold())
                .foregroundStyle(.white.opacity(0.85))
                .labelStyle(.titleAndIcon)
        }
        .frame(width: Self.width)
        .padding(.vertical, 14)
        .padding(.horizontal, 6)
        .ridePanelStyle()
    }

    /// Countdown par paliers (spec "lateral-cap-banner-countdown") : BANNER_COARSE_STEP_M
    /// (100 m) au-dessus de BANNER_FINE_THRESHOLD_M (150 m) — 600 → 500 → 400 → 300 → 200 →
    /// 150 — puis BANNER_FINE_STEP_M (10 m) en dessous — 150 → 140 → … → 0. Jamais un chiffre
    /// "sale" (587 m) qui bougerait à chaque fix GPS.
    static func steppedDistanceText(_ rawMeters: Double) -> String {
        let clamped = max(rawMeters, 0)
        let stepped: Int
        if clamped <= RideConstants.bannerFineThresholdMeters {
            stepped = Int((clamped / RideConstants.bannerFineStepMeters).rounded(.down)) * Int(RideConstants.bannerFineStepMeters)
        } else {
            stepped = Int((clamped / RideConstants.bannerCoarseStepMeters).rounded(.up)) * Int(RideConstants.bannerCoarseStepMeters)
        }
        return "\(stepped) m"
    }
}
