import UIKit

/// Contraste tab bar (spec "fab-contrast") : le matériau translucide par défaut se prête mal
/// à la lecture au soleil — légèrement opacifiée (garde le flou, ajoute un voile) + texte
/// gras. Appliqué une fois au lancement (GPXlibreApp.init), affecte toute l'app.
enum TabBarAppearance {
    static func configure() {
        let appearance = UITabBarAppearance()
        appearance.configureWithDefaultBackground()
        appearance.backgroundEffect = UIBlurEffect(style: .systemMaterial)
        appearance.backgroundColor = UIColor.systemBackground.withAlphaComponent(0.35)

        let boldFont = UIFont.systemFont(ofSize: 11, weight: .bold)
        let attributesFor: (UIColor) -> [NSAttributedString.Key: Any] = { color in
            [.font: boldFont, .foregroundColor: color]
        }

        for layout in [appearance.stackedLayoutAppearance, appearance.inlineLayoutAppearance, appearance.compactInlineLayoutAppearance] {
            layout.normal.titleTextAttributes = attributesFor(.secondaryLabel)
            layout.selected.titleTextAttributes = attributesFor(.label)
        }

        UITabBar.appearance().standardAppearance = appearance
        UITabBar.appearance().scrollEdgeAppearance = appearance
    }
}
