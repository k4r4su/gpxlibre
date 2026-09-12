import Foundation

/// Grille documentée des zones d'overlays flottants du mode Ride (itération "camera-inset" +
/// "overlay-grid") — chaque élément flottant a UNE zone fixe assignée ci-dessous, jamais deux
/// éléments dans la même zone en même temps (sauf la pile de bannières, volontairement limitée
/// à 1 visible à la fois par RideView). Un nouvel élément flottant doit d'abord obtenir une
/// zone ici avant d'être ajouté à RideView.
///
/// Repères (portrait) :
/// ```
/// ┌───────────────────────────────────────┐
/// │ (safe area haut : heure/cap, natif OS) │
/// │  [Segmented Trace/Nav]         [🔍]    │  topBar
/// │  [Bannière éphémère (1 max)]           │  bannerStack
/// ├─────────────────────────────────────────┤
/// │                                    [🏍] │  topRight (badge vitesse, fixe)
/// │  [Point]                     [+]        │  midLeft / midRight
/// │                               [-]       │
/// │  [Bloqué]                [recentrer]    │
/// │                              [Stop]     │
/// ├─────────────────────────────────────────┤
/// │       [Roadbook / guidage Nav]          │  bottomPanel
/// ├─────────────────────────────────────────┤
/// │ (tab bar, natif OS)                     │
/// └───────────────────────────────────────┘
/// ```
/// En paysage, les mêmes zones logiques s'appliquent ; `landscapeSidePanelWidth` réserve une
/// marge latérale pour que les panneaux flottants gauche/droite ne rognent jamais la carte
/// utile ni ne se recouvrent entre eux.
enum RideOverlayLayout {
    /// Segmented control + bouton recherche, replié contre le haut.
    static let topBarHeight: Double = 56
    /// Bannière éphémère unique (blocage / erreur carte / alerte partagée / guidage "Aller à")
    /// — une seule visible à la fois, voir RideView.activeBanner.
    static let bannerHeight: Double = 64
    /// Roadbook (Trace) ou panneau de guidage Nav — même gabarit dans les deux modes.
    static let bottomPanelHeight: Double = 108
    /// Marge de respiration entre la zone utile caméra et le contenu réel des panneaux.
    static let cameraInsetMarginPoints: Double = 12
    /// Empilement vertical de la colonne droite (stop / recentrer / +− / bloqué), spec Bloc 2.
    static let rightStackSpacing: Double = 12
    /// Largeur réservée aux panneaux flottants latéraux en paysage (contrôles droite, waypoints
    /// gauche) — évite qu'ils rognent le cadrage caméra ou se chevauchent près des bords.
    static let landscapeSidePanelWidth: Double = 100

    /// Zone caméra utile (spec "camera-inset") : exclut tout ce qui recouvre visuellement la
    /// carte. `safeAreaTop`/`safeAreaBottom` viennent de la geometry SwiftUI (varient par
    /// device : notch, Dynamic Island, tab bar + home indicator) — jamais codés en dur ici.
    static func cameraContentInsetTop(safeAreaTop: Double) -> Double {
        safeAreaTop + topBarHeight + cameraInsetMarginPoints
    }

    static func cameraContentInsetBottom(safeAreaBottom: Double, hasBottomPanel: Bool) -> Double {
        safeAreaBottom + (hasBottomPanel ? bottomPanelHeight : 0) + cameraInsetMarginPoints
    }

    static func cameraContentInsetSide(isLandscape: Bool) -> Double {
        isLandscape ? landscapeSidePanelWidth : 0
    }

    /// Regroupe les 4 marges caméra pour éviter un appel à 4 paramètres partout où c'est utilisé.
    struct CameraContentInset {
        var top: Double
        var bottom: Double
        var left: Double
        var right: Double
    }

    static func cameraContentInset(safeAreaTop: Double, safeAreaBottom: Double, hasBottomPanel: Bool, isLandscape: Bool) -> CameraContentInset {
        let side = cameraContentInsetSide(isLandscape: isLandscape)
        return CameraContentInset(
            top: cameraContentInsetTop(safeAreaTop: safeAreaTop),
            bottom: cameraContentInsetBottom(safeAreaBottom: safeAreaBottom, hasBottomPanel: hasBottomPanel),
            left: side,
            right: side
        )
    }
}
