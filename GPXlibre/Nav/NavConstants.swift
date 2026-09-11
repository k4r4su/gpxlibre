import Foundation

enum NavConstants {
    // MARK: - Nominatim (géocodage)

    static let nominatimBaseURL = "https://nominatim.openstreetmap.org"
    /// ToS Nominatim : 1 requête/seconde max, User-Agent identifié obligatoire.
    static let nominatimMinIntervalSeconds: Double = 1.0
    static let nominatimResultLimit = 6

    // MARK: - Routage (OSRM public, profil "driving" = moto route)

    static let osrmProfile = "driving"

    // MARK: - Guidage vocal

    static let voiceAnnounceDistancesMeters: [Double] = [500, 100]
    static let maneuverPassedRadiusMeters: Double = 25

    // MARK: - Recalcul automatique (Mode Nav uniquement — jamais en Mode Trace)

    /// Écart à la route calculée au-delà duquel un recalcul est envisagé.
    static let offRouteDistanceThresholdMeters: Double = 30
    /// Durée de tolérance avant de recalculer réellement (silencieux, pas de notification).
    static let offRouteToleranceSeconds: Double = 30

    // MARK: - Favoris

    static let maxSavedFavorites = 8
}
