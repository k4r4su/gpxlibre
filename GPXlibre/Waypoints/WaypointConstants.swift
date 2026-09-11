import Foundation

enum WaypointConstants {
    /// Un waypoint roulant existant s'affiche sur une trace future si on en approche à moins
    /// de cette distance — première brique de mémoire communautaire locale (100% locale ici).
    static let proximityDisplayRadiusMeters: Double = 50

    /// Fenêtre pendant laquelle le bouton "note audio" reste proposé après la création
    /// d'un waypoint, avant de disparaître sans pénalité.
    static let audioPromptWindowSeconds: Double = 4
    static let maxAudioNoteDurationSeconds: Double = 15
}
