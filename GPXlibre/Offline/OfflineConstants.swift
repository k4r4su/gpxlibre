import Foundation

enum OfflineConstants {
    /// Largeur totale du corridor pré-caché autour d'une trace (±1 km de chaque côté = 2 km).
    static let corridorHalfWidthMeters: Double = 1000

    /// Échantillonnage le long de la trace pour le calcul du corridor (évite de traiter
    /// chaque point GPX brut sur une trace de 250 km).
    static let corridorSampleStepMeters: Double = 250

    static let corridorMinZoom = 10
    static let corridorMaxZoom = 15

    static let regionMinZoomSliderValue = 12
    static let regionMaxZoomSliderValue = 16

    /// Estimation grossière (tuiles OSM raster réelles : ~10-25 Ko selon la densité) —
    /// affichée avant téléchargement, jamais garantie au octet près.
    static let averageTileSizeBytes: Int64 = 16_000
    /// Débit moyen supposé pour l'estimation de durée (Wi-Fi correct).
    static let assumedDownloadThroughputBytesPerSecond: Double = 800_000

    /// Nombre de téléchargements de tuiles simultanés.
    static let concurrentDownloads = 6

    /// Au-delà de cette taille de cache, on propose un nettoyage (pas automatique).
    static let cacheCleanupSuggestionThresholdBytes: Int64 = 1_000_000_000

    static let cacheDirectoryName = "MapTiles"
}
