import Foundation
import CoreLocation

/// Limite de vitesse OSM (tag `maxspeed`) via l'API publique Overpass. Silencieux si absent
/// (tag rare hors zones urbaines denses) — jamais d'erreur visible pour cette fonctionnalité
/// annexe. Débit volontairement faible (throttle interne) par courtoisie envers le service
/// public gratuit.
actor SpeedLimitService {
    static let shared = SpeedLimitService()

    private var lastRequestDate: Date?
    private var lastResult: (coordinate: CLLocationCoordinate2D, speedKmh: Int?)?

    func lookup(near coordinate: CLLocationCoordinate2D) async -> Int? {
        if let last = lastRequestDate, Date().timeIntervalSince(last) < NavConstants.speedLimitMinIntervalSeconds {
            return lastResult?.speedKmh
        }
        lastRequestDate = Date()

        let query = "[out:json][timeout:8];way(around:\(Int(NavConstants.speedLimitSearchRadiusMeters)),\(coordinate.latitude),\(coordinate.longitude))[highway][maxspeed];out tags 1;"
        guard let url = URL(string: "https://overpass-api.de/api/interpreter") else { return nil }

        var request = URLRequest(url: url, timeoutInterval: 10)
        request.httpMethod = "POST"
        request.setValue(MapEngineConstants.userAgent, forHTTPHeaderField: "User-Agent")
        request.httpBody = "data=\(query)".addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed).map { Data($0.utf8) }
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")

        do {
            let (data, _) = try await URLSession.shared.data(for: request)
            let decoded = try JSONDecoder().decode(OverpassResponse.self, from: data)
            let speed = decoded.elements.first?.tags.maxspeed.flatMap(Self.parseSpeedKmh)
            lastResult = (coordinate, speed)
            return speed
        } catch {
            // Silencieux par conception : une limite de vitesse manquante ne doit jamais
            // perturber le guidage.
            return nil
        }
    }

    private static func parseSpeedKmh(_ raw: String) -> Int? {
        // La plupart des tags sont numériques ("50"). Les zones nommées ("FR:urban", "walk",
        // etc.) sont ignorées — silencieuses plutôt que devinées.
        Int(raw.trimmingCharacters(in: .whitespaces))
    }
}

private struct OverpassResponse: Decodable {
    let elements: [OverpassElement]
}
private struct OverpassElement: Decodable {
    let tags: OverpassTags
}
private struct OverpassTags: Decodable {
    let maxspeed: String?
}
