import Foundation
import CoreLocation

/// Simplification assumée : l'API publique OSRM ne propose pas de profil "moto offroad".
/// "Route" utilise le profil voiture (routes revêtues), "Piste" utilise le profil vélo
/// (favorise les chemins/pistes) — le plus proche disponible sans clé ni hébergement.
///
/// Réutilisé pour le routing "hors-route" d'Aller à (spec "offroad-routing-preference", it13)
/// — remplace l'ancienne ligne droite ("vol d'oiseau") de GoToProfile.offroad, voir
/// RideSessionManager.startGoTo. Alternatives documentées si ce profil s'avère insuffisant en
/// usage réel (terrain très accidenté, pistes non cartographiées en highway=track/path sur
/// OSM) : (1) profil "foot" (piéton) du même serveur OSRM public — favorise encore plus les
/// sentiers/chemins, interdit totalement les grands axes, au prix d'une vitesse de référence
/// plus lente dans le calcul ; (2) une instance BRouter (auto-hébergée ou profils "trekking"/
/// "shortest" côté client) offre un vrai profil "moto trail"-like avec pondération fine par
/// type de surface (highway=track + tracktype + surface), mais demande soit un serveur dédié,
/// soit la lib BRouter embarquée (calcul local, pas d'API réseau) — piste à explorer si le
/// volume d'usage ou les retours terrain justifient l'investissement.
enum DetourProfile: String, CaseIterable {
    case route
    case offroad

    var displayName: String {
        switch self {
        case .route: return "Route"
        case .offroad: return "Piste"
        }
    }

    fileprivate var osrmProfile: String {
        switch self {
        case .route: return "driving"
        case .offroad: return "cycling"
        }
    }
}

enum DetourMode {
    case routed(DetourProfile)
    case direct
}

struct DetourRoute {
    let coordinates: [CLLocationCoordinate2D]
    let mode: DetourMode
    let targetCoordinate: CLLocationCoordinate2D
    let startedAt: Date
}

enum DetourRoutingError: Error {
    case noReachableCandidate
    case network(Error)
}

/// Appelle l'API publique de démonstration OSRM (gratuite, sans clé, usage raisonnable).
/// À remplacer par une instance auto-hébergée en cas de montée en charge (voir doc OSRM).
enum DetourRoutingService {
    static func requestRoute(
        from origin: CLLocationCoordinate2D,
        candidates: [CLLocationCoordinate2D],
        profile: DetourProfile,
        valhalla: ValhallaConfiguration? = nil
    ) async throws -> DetourRoute {
        var lastError: Error?
        for candidate in candidates {
            do {
                let coordinates = try await route(from: origin, to: candidate, profile: profile, valhalla: valhalla)
                return DetourRoute(coordinates: coordinates, mode: .routed(profile), targetCoordinate: candidate, startedAt: Date())
            } catch {
                lastError = error
                continue
            }
        }
        throw DetourRoutingError.network(lastError ?? DetourRoutingError.noReachableCandidate)
    }

    /// Point-à-point simple (PAS de recherche multi-candidats comme `requestRoute` ci-dessus) —
    /// réutilisé par RideSessionManager.startGoTo pour le profil hors-route d'Aller à (spec
    /// "offroad-routing-preference", it13), donc internal plutôt que private désormais.
    ///
    /// `valhalla` (spec "valhalla-client-toggle", it19) : `nil` tant que le toggle Réglages est
    /// désactivé (défaut) — comportement OSRM inchangé à l'identique. Non-nil : tente Valhalla
    /// EN PREMIER, puis retombe automatiquement sur OSRM en cas d'échec (réseau, auth, serveur
    /// down) — désactiver le toggle plus tard revient donc instantanément et sans reste à ce
    /// même comportement OSRM, jamais de guidage cassé par un serveur Valhalla indisponible.
    static func route(
        from: CLLocationCoordinate2D,
        to: CLLocationCoordinate2D,
        profile: DetourProfile,
        valhalla: ValhallaConfiguration? = nil
    ) async throws -> [CLLocationCoordinate2D] {
        if let valhalla, let coordinates = try? await ValhallaRoutingService.route(from: from, to: to, profile: profile, configuration: valhalla) {
            return coordinates
        }

        let urlString = "\(RideConstants.osrmPublicBaseURL)/route/v1/\(profile.osrmProfile)/"
            + "\(from.longitude),\(from.latitude);\(to.longitude),\(to.latitude)"
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

private struct OSRMResponse: Decodable {
    let routes: [OSRMRoute]
}
private struct OSRMRoute: Decodable {
    let geometry: OSRMGeometry
}
private struct OSRMGeometry: Decodable {
    let coordinates: [[Double]]
}
