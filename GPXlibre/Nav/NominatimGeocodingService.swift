import Foundation
import CoreLocation

struct GeocodingResult: Identifiable, Equatable {
    let id = UUID()
    let displayName: String
    let coordinate: CLLocationCoordinate2D

    static func == (lhs: GeocodingResult, rhs: GeocodingResult) -> Bool { lhs.id == rhs.id }
}

private struct NominatimEntry: Decodable {
    let display_name: String
    let lat: String
    let lon: String
}

enum GeocodingError: Error, LocalizedError {
    case network(Error)
    case noResults

    var errorDescription: String? {
        switch self {
        case .network: return "Recherche impossible — vérifie ta connexion."
        case .noResults: return "Aucun lieu trouvé."
        }
    }
}

/// Géocodage via Nominatim (OSM public, gratuit). ToS : 1 req/s max, User-Agent identifié —
/// un seul appel à la fois est autorisé ici, les appels rapprochés sont retardés en interne.
actor NominatimGeocodingService {
    static let shared = NominatimGeocodingService()

    private var lastRequestDate: Date?

    func search(query: String) async throws -> [GeocodingResult] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return [] }

        await respectRateLimit()

        var components = URLComponents(string: "\(NavConstants.nominatimBaseURL)/search")!
        components.queryItems = [
            URLQueryItem(name: "q", value: trimmed),
            URLQueryItem(name: "format", value: "json"),
            URLQueryItem(name: "limit", value: "\(NavConstants.nominatimResultLimit)"),
        ]
        guard let url = components.url else { throw GeocodingError.noResults }

        var request = URLRequest(url: url)
        request.setValue(MapEngineConstants.userAgent, forHTTPHeaderField: "User-Agent")

        do {
            let (data, _) = try await URLSession.shared.data(for: request)
            let entries = try JSONDecoder().decode([NominatimEntry].self, from: data)
            let results = entries.compactMap { entry -> GeocodingResult? in
                guard let lat = Double(entry.lat), let lon = Double(entry.lon) else { return nil }
                return GeocodingResult(displayName: entry.display_name, coordinate: CLLocationCoordinate2D(latitude: lat, longitude: lon))
            }
            guard !results.isEmpty else { throw GeocodingError.noResults }
            return results
        } catch let error as GeocodingError {
            throw error
        } catch {
            throw GeocodingError.network(error)
        }
    }

    private func respectRateLimit() async {
        defer { lastRequestDate = Date() }
        guard let last = lastRequestDate else { return }
        let elapsed = Date().timeIntervalSince(last)
        let remaining = NavConstants.nominatimMinIntervalSeconds - elapsed
        guard remaining > 0 else { return }
        try? await Task.sleep(nanoseconds: UInt64(remaining * 1_000_000_000))
    }
}
