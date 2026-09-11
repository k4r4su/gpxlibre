import MapLibre
import Foundation

/// Configuration one-shot au lancement — respecte la politique d'usage des tuiles OSM
/// (User-Agent identifiant l'app plutôt qu'un client générique).
enum MapLibreBootstrap {
    static func configure() {
        let configuration = URLSessionConfiguration.default
        configuration.httpAdditionalHeaders = ["User-Agent": MapEngineConstants.userAgent]
        MLNNetworkConfiguration.sharedManager.sessionConfiguration = configuration
    }
}
