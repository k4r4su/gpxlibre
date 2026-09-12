import SwiftUI

/// Toujours visible en Mode Nav ET Mode Trace actifs (spec Bloc 4). Action critique : label
/// texte permanent. La confirmation (1 geste) est portée par l'appelant (RideView).
struct RideStopButton: View {
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 2) {
                Image(systemName: "stop.fill")
                    .font(.system(size: 18, weight: .bold))
                Text("Stop")
                    .font(.system(size: 9, weight: .semibold))
            }
            .foregroundStyle(.white)
            .frame(width: RideConstants.glovedTapTargetSize, height: RideConstants.glovedTapTargetSize)
            .background(.gray.opacity(0.55), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
        .accessibilityLabel("Arrêter le guidage")
    }
}
