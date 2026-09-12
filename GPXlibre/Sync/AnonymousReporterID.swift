import Foundation

/// Identifiant anonyme rotatif — jamais un compte, jamais lié à un identifiant Apple/
/// Google, jamais transmis ailleurs qu'au serveur de points bloqués. Stocké uniquement en
/// local (UserDefaults) et régénéré après `rotationIntervalDays` (spec Bloc 5 : "IDs
/// anonymes rotatifs stockés localement").
enum AnonymousReporterID {
    private static let idKey = "sync.anonymousReporterID"
    private static let createdAtKey = "sync.anonymousReporterID.createdAt"
    static let rotationIntervalDays: Double = 30

    static func current(defaults: UserDefaults = .standard) -> String {
        let createdAt = defaults.object(forKey: createdAtKey) as? Date
        let isStale = createdAt.map { Date().timeIntervalSince($0) / 86400 > rotationIntervalDays } ?? true
        if let existing = defaults.string(forKey: idKey), !isStale {
            return existing
        }
        let fresh = UUID().uuidString
        defaults.set(fresh, forKey: idKey)
        defaults.set(Date(), forKey: createdAtKey)
        return fresh
    }
}
