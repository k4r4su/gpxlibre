import Foundation
import CoreLocation

/// Simplification assumée : l'API publique OSRM ne propose pas de profil "moto offroad".
/// "Route" utilise le profil voiture (routes revêtues), "Piste" utilise le profil vélo
/// (favorise les chemins/pistes) — le plus proche disponible sans clé ni hébergement.
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
        profile: DetourProfile
    ) async throws -> DetourRoute {
        var lastError: Error?
        for candidate in candidates {
            do {
                let coordinates = try await route(from: origin, to: candidate, profile: profile)
                return DetourRoute(coordinates: coordinates, mode: .routed(profile), targetCoordinate: candidate, startedAt: Date())
            } catch {
                lastError = error
                continue
            }
        }
        throw DetourRoutingError.network(lastError ?? DetourRoutingError.noReachableCandidate)
    }

    private static func route(
        from: CLLocationCoordinate2D,
        to: CLLocationCoordinate2D,
        profile: DetourProfile
    ) async throws -> [CLLocationCoordinate2D] {
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
