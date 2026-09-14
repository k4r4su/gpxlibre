import Foundation

/// Constantes du roadbook rebuilt from scratch (spec "roadbook-angle-buckets-replay", it14,
/// Bloc 4) — regroupées ici plutôt que dans RideConstants.swift comme demandé explicitement
/// par le prompt d'itération ("Constantes exposées dans Config/NavigationConstants.swift").
/// Tout le reste des constantes Ride (hors roadbook) reste dans RideConstants.swift, inchangé.
enum NavigationConstants {

    // MARK: - Fenêtre de mesure de la tangente (ROADBOOK_WINDOW_BEFORE_M / AFTER_M)

    /// Distance (m) AVANT/APRÈS un point de la trace sur laquelle le cap entrant/sortant est
    /// mesuré (spec : "±40-80 m autour de la position") — ASYMÉTRIQUE par construction (avant
    /// ≠ après possibles), réglable indépendamment dans Réglages > Roadbook > Fenêtre de mesure
    /// (spec "roadbook-settings-wired", Bloc 5).
    static let roadbookWindowBeforeMetersDefault: Double = 60
    static let roadbookWindowAfterMetersDefault: Double = 60
    static let roadbookWindowRange: ClosedRange<Double> = 40...80

    // MARK: - Paliers d'angle (segmentation type Waze/MUTCD)

    /// < ce seuil : rien (tout droit, pas affiché).
    static let roadbookLightThresholdDegreesDefault: Double = 30
    /// [light, marked[ = virage léger ; [marked, hard[ = virage prononcé ; [hard, uTurn[ =
    /// virage fort ; ≥ uTurn = demi-tour.
    static let roadbookMarkedThresholdDegreesDefault: Double = 45
    static let roadbookHardThresholdDegreesDefault: Double = 90
    static let roadbookUTurnThresholdDegreesDefault: Double = 135

    // MARK: - Flash / mise en avant

    /// ROADBOOK_FLASH_M : distance (m) sous laquelle le prochain virage déclenche une brève
    /// mise en avant visuelle (voir RideSessionManager.updateRoadbookBanner) — distincte du
    /// countdown BANNER_* (RideConstants), qui continue de piloter l'affichage 600→0 m.
    static let roadbookFlashMeters: Double = 100

    // MARK: - Mode debug replay (spec Bloc 4 : "obligatoire pour valider les paliers sans
    // sortir en voiture")

    /// Multiplicateurs de vitesse de rejeu disponibles.
    static let debugReplaySpeedMultipliers: [Double] = [4, 8]
    /// Intervalle (s) entre deux points rejoués à vitesse ×1 — les points de la trace n'ont pas
    /// d'horodatage fiable (GPX importé), donc un intervalle FIXE est simulé puis divisé par le
    /// multiplicateur, plutôt que de dépendre d'un `time` GPX souvent absent/faux.
    static let debugReplayBaseIntervalSeconds: Double = 1.0
}
