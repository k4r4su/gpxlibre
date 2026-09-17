import SwiftUI

/// Panneau de guidage tour-par-tour Mode Nav, EN HAUT pleine largeur (fix
/// "overlay-layout-grid", Bug 3) — instruction texte + flèche, distance jusqu'à la manœuvre.
/// Pendant du RoadbookPanelView côté Trace, même style (fix "panel-consistency", Bug 6).
///
/// Spec "nav-classic-rebuild" (it21) : `maneuver` est désormais un `ValhallaNavManeuver` — son
/// `instruction` est déjà un texte français complet composé par Valhalla lui-même (requête
/// `language: "fr-FR"`), plus besoin de synthétiser une phrase depuis un `type`/`modifier` OSRM
/// brut comme le faisait l'ancien `NavManeuver.instructionText`.
struct NavGuidancePanelView: View {
    let maneuver: ValhallaNavManeuver?
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
                HStack(spacing: 8) {
                    Text(distanceText)
                        .font(.system(.title2, design: .rounded).bold())
                        .foregroundStyle(.white)
                        .monospacedDigit()
                    // "roundabout_exit_count → Numéro de sortie affiché dans l'icône rond-point"
                    // — Valhalla compose déjà ce numéro dans `instruction` en français
                    // ("...prenez la 2ème sortie..."), ce badge est un rappel visuel compact en
                    // plus, pas un doublon nécessaire au texte.
                    if let exitCount = maneuver?.roundaboutExitCount, maneuver?.type.isRoundabout == true {
                        Text("Sortie \(exitCount)")
                            .font(.caption2.bold())
                            .foregroundStyle(.white)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(.white.opacity(0.25))
                            .clipShape(Capsule())
                    }
                }
                Text(maneuver?.instruction ?? "Vers \(destinationLabel)")
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.85))
                    .lineLimit(1)
                if let street = maneuver?.displayStreetName, !street.isEmpty {
                    Text(street)
                        .font(.caption2)
                        .foregroundStyle(.white.opacity(0.65))
                        .lineLimit(1)
                }
            }

            Spacer()

            if isRecalculating {
                ProgressView()
                    .tint(.white)
            }
        }
        .padding(16)
        .ridePanelStyle(tint: .blue, tintOpacity: 0.45)
        .padding(.horizontal, 12)
    }

    private var distanceText: String {
        guard let distanceMeters else { return "—" }
        if distanceMeters < 1000 {
            return "\(Int(distanceMeters.rounded())) m"
        }
        return String(format: "%.1f km", distanceMeters / 1000)
    }
}

/// Bannière secondaire "puis..." (spec "nav-classic-rebuild", P1) — visible UNIQUEMENT quand
/// Valhalla signale un enchaînement rapproché (`verbal_multi_cue` sur la manœuvre courante,
/// voir RideView.directionPanelLayer) : deux manœuvres trop proches pour laisser le temps de
/// réagir à la première seule, ex. "tournez à droite PUIS immédiatement à gauche".
struct NavSecondaryBannerView: View {
    let maneuver: ValhallaNavManeuver

    var body: some View {
        HStack(spacing: 10) {
            Text("Puis")
                .font(.caption.bold())
                .foregroundStyle(.white.opacity(0.7))
            Image(systemName: maneuver.systemImageName)
                .font(.system(size: 18, weight: .bold))
                .foregroundStyle(.white)
            Text(maneuver.instruction)
                .font(.caption)
                .foregroundStyle(.white.opacity(0.9))
                .lineLimit(1)
            Spacer()
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .ridePanelStyle(tint: .blue, tintOpacity: 0.3)
        .padding(.horizontal, 24)
    }
}
