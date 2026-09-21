import Foundation
import CoreLocation

/// Abstraction commune aux deux moteurs de routage point-à-point (spec "valhalla-live-routing",
/// it20 — branche RÉELLEMENT Valhalla sur le guidage, jusqu'ici limité au bouton "Tester la
/// connexion") : même signature qu'avant ce fichier
/// (`DetourRoutingService.route(from:to:profile:valhalla:)`), donc AUCUN appelant existant
/// (`ResumeGuidance`/`requestResume`, `requestDetour`/`requestDirectDetour`, `startGoTo` profil
/// `.offroad`) n'a besoin de changer. Le mécanisme de repli (tenter Valhalla, retomber sur OSRM
/// en cas d'échec) vit désormais ICI, dans `DetourRoutingService.route(...providers:)`, plutôt
/// que dispersé/dupliqué dans chaque appelant.
protocol RoutingProvider {
    /// Spec "routing-active-service-indicator" (it24, point 0) — identifie quel backend répond,
    /// pour `RoutingActivityMonitor` (mis à jour par `DetourRoutingService.route` sur un succès).
    var kind: RoutingActivityProvider { get }

    func route(
        from origin: CLLocationCoordinate2D,
        to destination: CLLocationCoordinate2D,
        profile: DetourProfile
    ) async throws -> [CLLocationCoordinate2D]
}

/// API publique de démonstration OSRM (gratuite, sans clé, usage raisonnable) — TOUJOURS le
/// dernier maillon de la chaîne de repli (voir `RoutingProviderResolver`), jamais désactivable :
/// c'est le comportement historique de l'app, garanti même si Valhalla n'est pas configuré du
/// tout ou devient injoignable.
struct OSRMRoutingProvider: RoutingProvider {
    let kind: RoutingActivityProvider = .osrm

    func route(
        from origin: CLLocationCoordinate2D,
        to destination: CLLocationCoordinate2D,
        profile: DetourProfile
    ) async throws -> [CLLocationCoordinate2D] {
        let urlString = "\(RideConstants.osrmPublicBaseURL)/route/v1/\(profile.osrmProfile)/"
            + "\(origin.longitude),\(origin.latitude);\(destination.longitude),\(destination.latitude)"
            + "?overview=full&geometries=geojson"
        guard let url = URL(string: urlString) else { throw URLError(.badURL) }

        var request = URLRequest(url: url, timeoutInterval: RideConstants.detourRoutingTimeoutSeconds)
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            throw URLError(.badServerResponse)
        }

        let decoded = try JSONDecoder().decode(OSRMResponse.self, from: data)
        guard let geometry = decoded.routes.first?.geometry.coordinates, !geometry.isEmpty else {
            throw URLError(.cannotParseResponse)
        }
        return geometry.map { CLLocationCoordinate2D(latitude: $0[1], longitude: $0[0]) }
    }
}

/// Backend auto-hébergé optionnel (spec "valhalla-client-toggle", it19 ; branché réellement sur
/// le guidage en it20) — voir `ValhallaRoutingService` pour le détail de l'appel HTTP.
struct ValhallaProvider: RoutingProvider {
    let kind: RoutingActivityProvider = .valhalla
    let configuration: ValhallaConfiguration

    func route(
        from origin: CLLocationCoordinate2D,
        to destination: CLLocationCoordinate2D,
        profile: DetourProfile
    ) async throws -> [CLLocationCoordinate2D] {
        try await ValhallaRoutingService.route(from: origin, to: destination, profile: profile, configuration: configuration)
    }
}

/// Résolution PURE (aucun réseau, aucun état mutable) de l'ordre des providers à essayer — même
/// patron que `MapSourceResolver` (it11). Valhalla, quand activé ET configuré (endpoint non
/// vide), est toujours tenté EN PREMIER, mais OSRM reste systématiquement le dernier maillon :
/// désactiver le toggle Réglages revient donc instantanément et sans reste au comportement
/// historique, aucun état ne dépend de Valhalla ailleurs.
enum RoutingProviderResolver {
    static func orderedProviders(valhallaEnabled: Bool, configuration: ValhallaConfiguration?) -> [RoutingProvider] {
        guard valhallaEnabled, let configuration else { return [OSRMRoutingProvider()] }
        return [ValhallaProvider(configuration: configuration), OSRMRoutingProvider()]
    }
}

private struct OSRMResponse: Decodable {
    let routes: [OSRMRoute]
}
private struct OSRMRoute: Decodable {
    let geometry: OSRMGeometry
}
private struct OSRMGeometry: Decodable {
    let coordinates: [[Double]]
}
