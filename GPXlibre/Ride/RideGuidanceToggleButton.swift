import SwiftUI

/// Bouton unique Pause/Play (spec "guidance-toggle-stop-pause-play", it15, Bloc 3) — remplace
/// l'empilement Stop + icône Play séparée d'it14 (retour terrain : "pile surpoids visuel").
/// Tap court = pause/reprise du guidage (`isGuidanceStopped`, léger, réversible sans reset).
/// Stop défini : menu contextuel (appui long, item destructif) plutôt qu'un second appui long
/// direct — ce bouton garde un LABEL TEXTE visible en permanence (Pause/Reprendre), donc il
/// n'a jamais fait partie de la convention `.longPressTooltip` (réservée aux boutons à icône
/// SEULE, voir LongPressTooltip.swift) : pas de conflit à réutiliser l'appui long ici pour
/// autre chose qu'une infobulle, contrairement à Recentrer/Bloqué/etc.
struct RideGuidanceToggleButton: View {
    let isStopped: Bool
    let onPause: () -> Void
    let onResume: () -> Void
    let onDefiniteStop: () -> Void

    var body: some View {
        Button {
            if isStopped {
                onResume()
            } else {
                onPause()
            }
        } label: {
            VStack(spacing: 2) {
                Image(systemName: isStopped ? "play.fill" : "pause.fill")
                    .font(.system(size: 18, weight: .bold))
                Text(isStopped ? "Reprendre" : "Pause")
                    .font(.system(size: 9, weight: .semibold))
            }
            .foregroundStyle(.white)
            .frame(width: RideConstants.glovedTapTargetSize, height: RideConstants.glovedTapTargetSize)
            .background((isStopped ? Color.green : Color.gray).opacity(0.55), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
        .contextMenu {
            Button(role: .destructive, action: onDefiniteStop) {
                Label("Arrêter le guidage", systemImage: "stop.fill")
            }
        }
        .accessibilityLabel(isStopped ? "Reprendre guidage" : "Pause guidage")
        .accessibilityHint(isStopped ? "" : "Rester appuyé pour arrêter le guidage définitivement")
        .accessibilityAction(named: "Arrêter guidage", onDefiniteStop)
    }
}
