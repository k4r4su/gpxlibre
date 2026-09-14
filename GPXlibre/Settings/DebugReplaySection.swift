#if DEBUG
import SwiftUI

/// UI du mode debug replay (spec "roadbook-angle-buckets-replay", it14, Bloc 4) — dans
/// Réglages > Avancé (section repliée par défaut, "menu caché" demandé). Rejoue la trace
/// ACTIVE (celle du Ride) à x4/x8 à travers `RideSessionManager.handle(location:)` — après
/// un lancement, ouvrir l'onglet Ride pour observer la bannière/les épingles réagir en direct.
struct DebugReplaySection: View {
    @EnvironmentObject private var library: LibraryStore
    @EnvironmentObject private var rideSession: RideSessionManager
    @StateObject private var driver = DebugReplayDriver()
    /// Spec "replay-marker-heading-x2" (it17, Bloc 4) — activé par défaut : l'intérêt premier
    /// du replay est justement de voir les virages comme en conduite réelle (cap-en-haut).
    @State private var forceHeadingUp = true

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Mode debug replay (build DEBUG uniquement)")
                .font(.caption.bold())
            if let track = library.activeTrack {
                Text("Trace : \(track.name)")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                if driver.isPlaying {
                    Text("Point \(driver.currentPointIndex + 1)/\(driver.totalPointCount)")
                        .font(.caption2.monospacedDigit())
                        .foregroundStyle(.secondary)
                    Button("Arrêter le replay", role: .destructive) { driver.stop() }
                } else {
                    Toggle("Cap en haut pendant le replay", isOn: $forceHeadingUp)
                        .font(.caption2)
                    ForEach(NavigationConstants.debugReplaySpeedMultipliers, id: \.self) { multiplier in
                        Button("Rejouer à ×\(Int(multiplier))") {
                            driver.start(track: track, speedMultiplier: multiplier, session: rideSession, forceHeadingUp: forceHeadingUp)
                        }
                    }
                }
            } else {
                Text("Aucune trace active — sélectionne-en une dans Bibliothèque d'abord.")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 4)
    }
}
#endif
