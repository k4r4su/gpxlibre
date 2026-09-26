import Foundation

/// Spec "controls-side-setting" (it14, Bloc 2) — côté de la colonne de contrôles Ride
/// (+/−/Stop/Bloqué + bannière roadbook empilée au-dessus). Le badge vitesse (bas-gauche par
/// défaut) bascule TOUJOURS du côté opposé : les deux permutent ensemble, jamais de
/// chevauchement possible (voir RideView.bottomControlsColumn/speedoBadgeLayer).
enum ControlsSide: String, CaseIterable, Identifiable, Codable {
    case left, right

    var id: String { rawValue }

    var label: String {
        switch self {
        case .left: return String(localized: "Gauche", bundle: .appLanguage)
        case .right: return String(localized: "Droite", bundle: .appLanguage)
        }
    }
}
