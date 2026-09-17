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

    /// Spec "nav-classic-rebuild" (it21, test attendu "sans boucle de recalcul infinie") —
    /// délai minimum entre deux recalculs automatiques, EN PLUS des gardes isRecalculatingRoute/
    /// isRoutingInProgress (celles-ci empêchent un recalcul CONCURRENT ; celui-ci empêche un
    /// recalcul IMMÉDIAT si le nouvel itinéraire laisse quand même le rider hors-route).
    static let navRecomputeCooldownSeconds: Double = 30

    // MARK: - Favoris

    static let maxSavedFavorites = 8

    /// Spec "search-history" (it19, retour terrain "le menu Aller à est un peu vide, garder
    /// un historique des 5 dernières recherches") — voir NavSearchHistoryStore.
    static let maxSearchHistoryEntries = 5

    // MARK: - Limite de vitesse (OSM maxspeed via Overpass, silencieux si absent)

    static let speedLimitMinIntervalSeconds: Double = 20
    static let speedLimitSearchRadiusMeters: Double = 25
    static let speedLimitAlertThresholdOptionsKmh: [Int] = [5, 10, 15]
    static let speedLimitAlertThresholdDefaultKmh = 10
}
