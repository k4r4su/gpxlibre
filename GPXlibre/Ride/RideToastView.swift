import SwiftUI

/// Toast bref, centré en haut sous la safe area, auto-masqué (spec "stop-guidance-semantics",
/// it14, Bloc 3 : confirmation "Guidage arrêté"). Générique — réutilisable pour tout message
/// bref futur, pas spécifique au Stop.
private struct RideToastModifier: ViewModifier {
    let message: String?
    @State private var visibleMessage: String?
    @State private var dismissTask: Task<Void, Never>?

    func body(content: Content) -> some View {
        content.overlay(alignment: .top) {
            if let visibleMessage {
                Text(visibleMessage)
                    .font(.subheadline.bold())
                    .foregroundStyle(.white)
                    .padding(.horizontal, 18)
                    .padding(.vertical, 10)
                    .ridePanelStyle()
                    .padding(.top, 8)
                    .transition(.ridePanel)
                    .allowsHitTesting(false)
            }
        }
        .animation(.ridePanel, value: visibleMessage)
        .onChange(of: message) { newValue in
            guard let newValue else { return }
            visibleMessage = newValue
            dismissTask?.cancel()
            dismissTask = Task { @MainActor in
                try? await Task.sleep(nanoseconds: 2_000_000_000)
                guard !Task.isCancelled else { return }
                visibleMessage = nil
            }
        }
    }
}

extension View {
    func rideToast(message: String?) -> some View {
        modifier(RideToastModifier(message: message))
    }
}
