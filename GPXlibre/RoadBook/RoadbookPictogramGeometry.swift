import Foundation

/// Géométrie PURE des pictogrammes enrichis (spec "roadbook-route-aware-maneuvers", it24,
/// point 2 — retour terrain : "Rond-point : pictogramme circulaire avec la sortie à prendre
/// surlignée à la bonne position, piloté par roundabout_exit_count — pas une flèche courbe
/// générique") — partagée entre le rendu SwiftUI (`RoadbookPictograms.swift`) et le rendu Core
/// Graphics du PDF (`RoadbookPDFExporter`), pour que les deux dessinent EXACTEMENT la même forme
/// à partir des mêmes données. Aucun dessin ici, uniquement des angles/positions — testable sans
/// jamais instancier une vue.
enum RoadbookPictogramGeometry {
    /// Angle (degrés, 0 = tout droit/12h, sens HORAIRE positif) de la sortie prise dans un
    /// rond-point, à partir de son RANG (`Checkpoint.roundaboutExitCount`, Valhalla
    /// `roundabout_exit_count`) — Valhalla ne fournit JAMAIS la géométrie réelle des sorties
    /// intermédiaires, seulement ce rang : convention visuelle fixe
    /// (`RoadBookConstants.roundaboutExitSpacingDegrees` par sortie), pas une mesure topologique
    /// réelle. `nil`/`0`/négatif retombent sur la 1ʳᵉ sortie plutôt que de produire un angle nul
    /// ou négatif absurde à l'affichage.
    static func roundaboutExitAngleDegrees(exitCount: Int?) -> Double {
        let index = max(1, exitCount ?? 1)
        return Double(index) * RoadBookConstants.roundaboutExitSpacingDegrees
    }

    /// Rangs de sortie à afficher en discret (traits fins) AVANT la sortie prise — permet au
    /// pictogramme de montrer "il faut compter cette sortie-ci" plutôt qu'une sortie unique sans
    /// contexte. Plafonné pour ne jamais dessiner un pictogramme illisible sur un très grand
    /// rang (rond-point à répétition mal détecté plutôt qu'une vraie longue liste de sorties).
    static func skippedExitRanks(exitCount: Int?) -> [Int] {
        let index = max(1, exitCount ?? 1)
        guard index > 1 else { return [] }
        return Array(1..<min(index, 7))
    }
}
