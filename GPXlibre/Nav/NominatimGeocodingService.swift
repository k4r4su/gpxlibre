import Foundation
import CoreLocation

struct GeocodingResult: Identifiable, Equatable {
    let id = UUID()
    let displayName: String
    let coordinate: CLLocationCoordinate2D
    /// Emprise administrative si Nominatim en fournit une (résultat de type pays/région/ville) —
    /// `nil` pour un simple point d'intérêt/adresse (spec "region-download-by-place", it21,
    /// "Pays → téléchargement du pays entier" : couvre l'emprise RÉELLE plutôt qu'un rayon fixe
    /// autour du centroïde, qui n'aurait aucun sens pour un pays de forme irrégulière).
    let boundingBox: GeocodingBoundingBox?

    init(displayName: String, coordinate: CLLocationCoordinate2D, boundingBox: GeocodingBoundingBox? = nil) {
        self.displayName = displayName
        self.coordinate = coordinate
        self.boundingBox = boundingBox
    }

    static func == (lhs: GeocodingResult, rhs: GeocodingResult) -> Bool { lhs.id == rhs.id }
}

struct GeocodingBoundingBox: Equatable {
    let minLat: Double
    let maxLat: Double
    let minLon: Double
    let maxLon: Double

    init(minLat: Double, maxLat: Double, minLon: Double, maxLon: Double) {
        self.minLat = minLat
        self.maxLat = maxLat
        self.minLon = minLon
        self.maxLon = maxLon
    }

    /// Parse le tableau `boundingbox` de Nominatim (`[minLat, maxLat, minLon, maxLon]`, en
    /// chaînes) — extrait en initialiseur dédié (plutôt que codé en ligne dans le decode JSON)
    /// pour rester testable sans dépendre du JSON brut ni d'un vrai appel réseau, voir
    /// `GeocodingBoundingBoxTests`.
    init?(nominatimStrings: [String]?) {
        guard let box = nominatimStrings, box.count == 4,
              let minLat = Double(box[0]), let maxLat = Double(box[1]),
              let minLon = Double(box[2]), let maxLon = Double(box[3])
        else { return nil }
        self.minLat = minLat
        self.maxLat = maxLat
        self.minLon = minLon
        self.maxLon = maxLon
    }
}

private struct NominatimEntry: Decodable {
    let display_name: String
    let lat: String
    let lon: String
    let boundingbox: [String]?
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

    /// `featureType` (spec "region-download-by-place", it21) : valeur Nominatim optionnelle
    /// (`"country"`/`"state"`/`"city"`) pour biaiser les résultats côté serveur vers ce type de
    /// lieu — `nil` (défaut, appelants existants inchangés) laisse Nominatim trier librement,
    /// comme avant cette itération.
    func search(query: String, featureType: String? = nil) async throws -> [GeocodingResult] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return [] }

        await respectRateLimit()

        var components = URLComponents(string: "\(NavConstants.nominatimBaseURL)/search")!
        var queryItems = [
            URLQueryItem(name: "q", value: trimmed),
            URLQueryItem(name: "format", value: "json"),
            URLQueryItem(name: "limit", value: "\(NavConstants.nominatimResultLimit)"),
        ]
        if let featureType {
            queryItems.append(URLQueryItem(name: "featureType", value: featureType))
        }
        components.queryItems = queryItems
        guard let url = components.url else { throw GeocodingError.noResults }

        var request = URLRequest(url: url)
        request.setValue(MapEngineConstants.userAgent, forHTTPHeaderField: "User-Agent")

        do {
            let (data, _) = try await URLSession.shared.data(for: request)
            let entries = try JSONDecoder().decode([NominatimEntry].self, from: data)
            let results = entries.compactMap { entry -> GeocodingResult? in
                guard let lat = Double(entry.lat), let lon = Double(entry.lon) else { return nil }
                return GeocodingResult(
                    displayName: entry.display_name,
                    coordinate: CLLocationCoordinate2D(latitude: lat, longitude: lon),
                    boundingBox: GeocodingBoundingBox(nominatimStrings: entry.boundingbox)
                )
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
