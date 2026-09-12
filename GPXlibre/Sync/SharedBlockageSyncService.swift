import Foundation
import CoreLocation

enum SharedBlockageSyncError: Error {
    case notConfigured
    case invalidURL
    case serverError(Int)
}

/// Cadre géographique (bbox) interrogé côté serveur — jamais l'ensemble de la base, voir
/// `GET /blockages` dans server/app.py.
struct SharedBlockageBBox: Equatable {
    let minLat: Double
    let minLon: Double
    let maxLat: Double
    let maxLon: Double

    /// Cadre autour d'une trace chargée, avec marge — la synchro doit couvrir toute la
    /// zone parcourue, pas seulement la position courante.
    static func around(trackPoints: [CLLocationCoordinate2D], paddingDegrees: Double = SharedBlockageConstants.bboxPaddingDegrees) -> SharedBlockageBBox? {
        guard !trackPoints.isEmpty else { return nil }
        let lats = trackPoints.map(\.latitude)
        let lons = trackPoints.map(\.longitude)
        guard let minLat = lats.min(), let maxLat = lats.max(), let minLon = lons.min(), let maxLon = lons.max() else { return nil }
        return SharedBlockageBBox(minLat: minLat - paddingDegrees, minLon: minLon - paddingDegrees, maxLat: maxLat + paddingDegrees, maxLon: maxLon + paddingDegrees)
    }

    /// Sans trace chargée : zone autour de la position courante.
    static func around(location: CLLocationCoordinate2D, paddingDegrees: Double = SharedBlockageConstants.bboxPaddingDegreesAroundLocation) -> SharedBlockageBBox {
        SharedBlockageBBox(
            minLat: location.latitude - paddingDegrees,
            minLon: location.longitude - paddingDegrees,
            maxLat: location.latitude + paddingDegrees,
            maxLon: location.longitude + paddingDegrees
        )
    }
}

/// Client HTTP du serveur Bloc 5 (server/app.py). Ne décide jamais du silence
/// offline-first : ça reste la responsabilité de l'appelant (SharedBlockageSyncCoordinator).
enum SharedBlockageSyncService {
    static func submit(_ report: SharedBlockageOutgoingReport, serverURLString: String) async throws -> SharedBlockage {
        guard !serverURLString.isEmpty else { throw SharedBlockageSyncError.notConfigured }
        guard let base = URL(string: serverURLString) else { throw SharedBlockageSyncError.invalidURL }
        let url = base.appendingPathComponent("blockages")

        var request = URLRequest(url: url, timeoutInterval: SharedBlockageConstants.requestTimeoutSeconds)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try SharedBlockageCoding.encoder.encode(report)

        let (data, response) = try await URLSession.shared.data(for: request)
        try validate(response)
        return try SharedBlockageCoding.decoder.decode(SharedBlockage.self, from: data)
    }

    static func fetch(bbox: SharedBlockageBBox, serverURLString: String) async throws -> [SharedBlockage] {
        guard !serverURLString.isEmpty else { throw SharedBlockageSyncError.notConfigured }
        guard var components = URLComponents(string: serverURLString) else { throw SharedBlockageSyncError.invalidURL }
        let trimmedPath = components.path.hasSuffix("/") ? String(components.path.dropLast()) : components.path
        components.path = trimmedPath + "/blockages"
        components.queryItems = [
            URLQueryItem(name: "min_lat", value: String(bbox.minLat)),
            URLQueryItem(name: "min_lon", value: String(bbox.minLon)),
            URLQueryItem(name: "max_lat", value: String(bbox.maxLat)),
            URLQueryItem(name: "max_lon", value: String(bbox.maxLon)),
        ]
        guard let url = components.url else { throw SharedBlockageSyncError.invalidURL }

        let request = URLRequest(url: url, timeoutInterval: SharedBlockageConstants.requestTimeoutSeconds)
        let (data, response) = try await URLSession.shared.data(for: request)
        try validate(response)
        return try SharedBlockageCoding.decoder.decode([SharedBlockage].self, from: data)
    }

    private static func validate(_ response: URLResponse) throws {
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw SharedBlockageSyncError.serverError((response as? HTTPURLResponse)?.statusCode ?? -1)
        }
    }
}
