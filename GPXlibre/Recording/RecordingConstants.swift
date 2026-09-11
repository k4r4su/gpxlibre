import Foundation

enum RecordingConstants {
    /// Un point est enregistré dès que l'un des deux seuils est atteint (le plus fréquent
    /// des deux déclenche l'enregistrement).
    static let minIntervalSeconds: Double = 5
    static let minDistanceMeters: Double = 15
}
