import Foundation

enum WaypointConstants {
    /// Un waypoint roulant existant s'affiche sur une trace future si on en approche à moins
    /// de cette distance — première brique de mémoire communautaire locale (100% locale ici).
    static let proximityDisplayRadiusMeters: Double = 50
}
