import MapLibre
import Foundation

/// Configuration one-shot au lancement — respecte la politique d'usage des tuiles OSM
/// (User-Agent identifiant l'app plutôt qu'un client générique).
enum MapLibreBootstrap {
    static func configure() {
        let configuration = URLSessionConfiguration.default
        configuration.httpAdditionalHeaders = ["User-Agent": MapEngineConstants.userAgent]
        // Intercepte les tuiles OSM pour servir depuis le cache disque hors-ligne (axe offline-cache).
        configuration.protocolClasses = [TileCacheURLProtocol.self] + (configuration.protocolClasses ?? [])
        MLNNetworkConfiguration.sharedManager.sessionConfiguration = configuration
    }
}
