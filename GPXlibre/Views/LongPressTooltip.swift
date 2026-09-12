import SwiftUI
import UIKit

/// Explicateur générique pour tout bouton à icône seule qui ne peut pas porter de label
/// visible en permanence (contrainte d'espace) : long-press → infobulle 1 ligne + haptique
/// légère. Réutilisé sur tous les écrans (Ride, Biblio, Réglages) — voir chaque appelant.
private struct LongPressTooltipModifier: ViewModifier {
    let text: String
    @State private var isShowingTooltip = false
    private let hapticGenerator = UIImpactFeedbackGenerator(style: .light)

    func body(content: Content) -> some View {
        content
            .onLongPressGesture(minimumDuration: 0.35) {
                hapticGenerator.impactOccurred()
                withAnimation(.easeOut(duration: 0.15)) { isShowingTooltip = true }
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.8) {
                    withAnimation(.easeIn(duration: 0.2)) { isShowingTooltip = false }
                }
            }
            .overlay(alignment: .top) {
                if isShowingTooltip {
                    Text(text)
                        .font(.caption2.bold())
                        .foregroundStyle(.white)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background(.black.opacity(0.85), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                        .fixedSize()
                        .offset(y: -38)
                        .transition(.opacity.combined(with: .scale(scale: 0.9)))
                        .zIndex(1)
                }
            }
            .accessibilityLabel(text)
    }
}

extension View {
    /// Explicateur 1 ligne sur long-press, avec haptique légère — pour un bouton à icône
    /// seule qui n'a pas la place pour un label texte permanent.
    func longPressTooltip(_ text: String) -> some View {
        modifier(LongPressTooltipModifier(text: text))
    }
}
