import SwiftUI

/// Flash plein écran, impossible à rater, déclenché à l'approche d'un checkpoint.
/// `trigger` change de valeur à chaque déclenchement ; le nombre de flashs est relu
/// en direct depuis les Réglages à chaque déclenchement.
struct FlashOverlayView: View {
    let trigger: UUID?
    let flashCount: Int

    @State private var isVisible = false

    var body: some View {
        Rectangle()
            .fill(Color.white)
            .opacity(isVisible ? 1 : 0)
            .ignoresSafeArea()
            .allowsHitTesting(false)
            .onChange(of: trigger) { newValue in
                guard newValue != nil else { return }
                runFlashSequence(count: flashCount)
            }
    }

    private func runFlashSequence(count: Int) {
        Task { @MainActor in
            for _ in 0..<max(count, 1) {
                withAnimation(.linear(duration: RideConstants.flashOnDurationSeconds)) { isVisible = true }
                try? await Task.sleep(nanoseconds: UInt64(RideConstants.flashOnDurationSeconds * 1_000_000_000))
                withAnimation(.linear(duration: RideConstants.flashOffDurationSeconds)) { isVisible = false }
                try? await Task.sleep(nanoseconds: UInt64(RideConstants.flashOffDurationSeconds * 1_000_000_000))
            }
        }
    }
}
