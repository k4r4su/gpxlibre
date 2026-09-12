import Foundation

/// Grille FIGÉE des zones d'overlays flottants du mode Ride (itération 9, "stabilisation UI") —
/// SEUL endroit qui documente les zones ; RideView ne fait qu'appliquer ce qui est décrit ici.
/// Aucun élément flottant ne doit être positionné ailleurs que dans une zone décrite ci-dessous.
///
/// Repères (portrait — device de référence iPhone 13 Pro) :
/// ```
/// ┌───────────────────────────────────────┐
/// │ (safe area haut : heure/cap, natif OS) │
/// │  [Segmented Trace/Nav]         [🔍]    │  topBar
/// │  [Bannière éphémère (1 max)]           │  bannerZone
/// │  [Roadbook / guidage Nav, PLEINE LARGEUR]│ directionPanelZone
/// ├─────────────────────────────────────────┤
/// │                                         │
/// │              (carte, vide)              │  centerZone — rien n'y flotte jamais
/// │                                         │
/// │                              [recentrer]│  bottomRight (colonne, 12pt)
/// │                                     [+] │
/// │                                     [−] │
/// │                                  [Stop] │
/// │                                [Bloqué] │
/// │ [vitesse]                               │  bottomLeft
/// ├─────────────────────────────────────────┤
/// │ (tab bar, natif OS — RIEN d'autre ici)  │  tabBarZone
/// └───────────────────────────────────────┘
/// ```
///
/// ## Ancrage de la position (fix "position-anchor", Bug 2)
/// Zone haute inviolable = safe area + topBar + bannière (si visible) + panneau de direction
/// (si visible) + marge. Zone basse inviolable = safe area + tab bar + marge (le panneau de
/// direction est en HAUT désormais — la tab bar seule ferme la zone basse, spec Bug 3). Le
/// marqueur de position s'ancre à `RideConstants.positionAnchorRatio` (60-65 %) DEPUIS LE HAUT
/// de la zone libre restante entre ces deux exclusions — un calcul EXACT via `contentInset`
/// (pas une heuristique de décalage géographique) : MapLibre centre toujours `lookingAtCenter`
/// au milieu du rectangle défini par `contentInset` ; pour le faire apparaître à `ratio` du
/// haut de la zone visible plutôt qu'au centre (0.5), on agrandit `contentInset.top` de
/// `(2×ratio − 1) × hauteurVisible` — voir `computeMapInsets`. Recalculé à CHAQUE render (les
/// booléens viennent de @Published state) : aucune exception panneau/bannière/mode.
enum RideOverlayLayout {
    static let topBarHeight: Double = 56
    static let bannerHeight: Double = 64
    static let directionPanelHeight: Double = 132
    static let cameraInsetMarginTopPoints: Double = 16
    static let cameraInsetMarginBottomPoints: Double = 16
    /// Espacement uniforme de la colonne bas-droite (spec Bug 3).
    static let rightStackSpacing: Double = 12
    static let landscapeSidePanelWidth: Double = 100

    /// Toutes les marges nécessaires en un seul calcul (single source of truth, Bug 3/Bug 2) :
    /// `uiTop`/`uiBottom` positionnent les overlays SwiftUI (topBar/panneaux), `cameraTop`/
    /// `cameraBottom` alimentent `MLNMapView.contentInset` (voir RideMapLibreView).
    struct MapInsets {
        var uiTop: Double
        var uiBottom: Double
        var cameraTop: Double
        var cameraBottom: Double
        var cameraLeft: Double
        var cameraRight: Double
    }

    static func computeMapInsets(
        safeAreaTop: Double,
        safeAreaBottom: Double,
        screenHeight: Double,
        hasDirectionPanel: Bool,
        hasBanner: Bool,
        isLandscape: Bool,
        positionAnchorRatio: Double
    ) -> MapInsets {
        let side = isLandscape ? landscapeSidePanelWidth : 0
        let uiTop = safeAreaTop + topBarHeight
            + (hasBanner ? bannerHeight : 0)
            + (hasDirectionPanel ? directionPanelHeight : 0)
            + cameraInsetMarginTopPoints
        let uiBottom = safeAreaBottom + cameraInsetMarginBottomPoints

        let visibleHeight = max(screenHeight - uiTop - uiBottom, 1)
        let ratio = min(max(positionAnchorRatio, 0.5), 0.9)
        // cameraTop = uiTop + (2×ratio − 1) × visibleHeight — dérivation dans le commentaire
        // de tête. Jamais < uiTop (jamais moins que le vrai recouvrement UI).
        let cameraTop = max(uiTop + (2 * ratio - 1) * visibleHeight, uiTop)

        return MapInsets(
            uiTop: uiTop,
            uiBottom: uiBottom,
            cameraTop: cameraTop,
            cameraBottom: uiBottom,
            cameraLeft: side,
            cameraRight: side
        )
    }
}
