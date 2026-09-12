import Foundation

/// Grille documentée des zones d'overlays flottants du mode Ride (itérations "camera-inset" +
/// "overlay-grid" + fix "camera-inset-tracking") — chaque élément flottant a UNE zone fixe
/// assignée ci-dessous, jamais deux éléments dans la même zone en même temps (sauf la pile de
/// bannières, volontairement limitée à 1 visible à la fois par RideView). Un nouvel élément
/// flottant doit d'abord obtenir une zone ici avant d'être ajouté à RideView.
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
///
/// ## Fix "camera-inset-tracking"
/// La marge caméra a besoin de la VRAIE safe area (encoche/Dynamic Island en haut ; tab bar +
/// home indicator combinés en bas — ce dernier chiffre est injecté par SwiftUI comme safe area
/// supplémentaire pour le contenu d'un onglet de TabView). Deux approches se sont révélées
/// fausses avant celle-ci : un lookup UIKit sur la fenêtre (`UIWindow.safeAreaInsets`) ne voit
/// PAS la hauteur de la tab bar (injectée plus bas dans la hiérarchie, pas au niveau fenêtre) ;
/// un `GeometryReader` qui ignore lui-même la safe area pour "forcer" `safeAreaInsets` à
/// rapporter la vraie valeur s'est avéré peu fiable dans ce contexte précis (vérifié
/// visuellement : le segmented control se retrouvait sous l'encoche). La méthode fiable
/// retenue (voir RideView.rideContent) : un GeometryReader qui respecte NORMALEMENT la safe
/// area, dont on compare `frame(in: .global)` à `UIScreen.main.bounds` — son bord haut/bas
/// tombe exactement sur la vraie limite de safe area, sans ambiguïté. Seule `mapLayer` ignore
/// la safe area (pour le plein écran) ; le reste de l'UI l'évite normalement, comme avant.
enum RideOverlayLayout {
    /// Segmented control + bouton recherche, replié contre le haut.
    static let topBarHeight: Double = 56
    /// Bannière éphémère unique (blocage / erreur carte / alerte partagée / guidage "Aller à")
    /// — une seule visible à la fois, voir RideView.activeBanner.
    static let bannerHeight: Double = 64
    /// Roadbook (Trace) ou panneau de guidage Nav — même gabarit dans les deux modes.
    static let bottomPanelHeight: Double = 108
    /// Marges de respiration entre la zone utile caméra et le contenu réel des panneaux —
    /// valeurs distinctes haut/bas (spec fix "camera-inset-tracking").
    static let cameraInsetMarginTopPoints: Double = 16
    static let cameraInsetMarginBottomPoints: Double = 24
    /// Empilement vertical de la colonne droite (stop / recentrer / +− / bloqué), spec Bloc 2.
    static let rightStackSpacing: Double = 12
    /// Largeur réservée aux panneaux flottants latéraux en paysage (contrôles droite, waypoints
    /// gauche) — évite qu'ils rognent le cadrage caméra ou se chevauchent près des bords.
    static let landscapeSidePanelWidth: Double = 100

    /// Les 4 marges caméra (contentInset) + les valeurs de safe area brutes qui ont servi à les
    /// calculer, pour que RideView puisse repositionner ses propres overlays cohéremment
    /// (single source of truth demandée par le fix "camera-inset-tracking").
    struct MapInsets {
        var safeAreaTop: Double
        var safeAreaBottom: Double
        var cameraTop: Double
        var cameraBottom: Double
        var cameraLeft: Double
        var cameraRight: Double
    }

    /// Fonction UNIQUE de calcul des marges caméra — utilisée à la fois par le suivi caméra
    /// continu et par "me recentrer" (RideMapLibreView.updateUIView, un seul appel à
    /// contentInset, aucune logique dupliquée). `hasBanner` fait grandir la marge haute quand
    /// une bannière est affichée ; `hasBottomPanel` fait grandir la marge basse quand le
    /// roadbook/guidage Nav est affiché — recalculée à chaque apparition/disparition puisque
    /// RideView repasse ici à chaque render (ces deux booléens viennent de @Published state).
    static func computeMapInsets(
        safeAreaTop: Double,
        safeAreaBottom: Double,
        hasBottomPanel: Bool,
        hasBanner: Bool,
        isLandscape: Bool
    ) -> MapInsets {
        let side = isLandscape ? landscapeSidePanelWidth : 0
        let top = safeAreaTop + topBarHeight + (hasBanner ? bannerHeight : 0) + cameraInsetMarginTopPoints
        let bottom = safeAreaBottom + (hasBottomPanel ? bottomPanelHeight : 0) + cameraInsetMarginBottomPoints
        return MapInsets(
            safeAreaTop: safeAreaTop,
            safeAreaBottom: safeAreaBottom,
            cameraTop: top,
            cameraBottom: bottom,
            cameraLeft: side,
            cameraRight: side
        )
    }
}
