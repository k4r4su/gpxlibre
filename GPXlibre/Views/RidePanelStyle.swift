import SwiftUI

/// Style visuel COMMUN à tous les panneaux/bannières flottants du mode Ride (fix
/// "panel-consistency", Bug 6) — même corner radius (16), même matériau (ultraThinMaterial,
/// variante SOMBRE forcée quel que soit le thème système, pour rester lisible au soleil avec
/// du texte blanc), même ombre. Une teinte sémantique (rouge = bloqué, bleu = Nav, etc.) reste
/// possible SOUS le matériau, jamais à sa place.
struct RidePanelStyle: ViewModifier {
    var tint: Color
    var tintOpacity: Double

    static let cornerRadius: CGFloat = 16

    func body(content: Content) -> some View {
        content
            .background(tint.opacity(tintOpacity))
            .background(.ultraThinMaterial)
            .environment(\.colorScheme, .dark)
            .clipShape(RoundedRectangle(cornerRadius: Self.cornerRadius, style: .continuous))
            .shadow(color: .black.opacity(0.28), radius: 10, x: 0, y: 4)
    }
}

extension View {
    /// `tint` = teinte sémantique optionnelle (rouge/bleu/cyan/orange...) ; laisser au défaut
    /// pour un panneau neutre (roadbook, guidage Nav).
    func ridePanelStyle(tint: Color = .black, tintOpacity: Double = 0.35) -> some View {
        modifier(RidePanelStyle(tint: tint, tintOpacity: tintOpacity))
    }
}

/// Apparition standard de TOUS les panneaux (fix "panel-consistency", Bug 6) : fondu + léger
/// slide, 200 ms — jamais une apparition brute. À utiliser avec `.transition(.ridePanel)` sur
/// le panneau et un `.animation(_, value:)` sur la condition qui le montre/masque.
extension AnyTransition {
    static var ridePanel: AnyTransition {
        .move(edge: .top).combined(with: .opacity)
    }
}

extension Animation {
    static var ridePanel: Animation {
        .easeInOut(duration: 0.2)
    }
}
