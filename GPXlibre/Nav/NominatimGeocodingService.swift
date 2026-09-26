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
        case .network: return String(localized: "Recherche impossible — vérifie ta connexion.", bundle: .appLanguage)
        case .noResults: return String(localized: "Aucun lieu trouvé.", bundle: .appLanguage)
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
    ///
    /// `nearCoordinate` (spec "poi-search-nominatim", it22, retour terrain : "ajouter la
    /// recherche par nom de commerce/service — pharmacie, supermarché, médecin") — Nominatim
    /// gère déjà ces requêtes génériques ("special phrases", ex. "pharmacie" → tag OSM
    /// `amenity=pharmacy`) via `/search`, mais SANS ancrage géographique une requête aussi
    /// générique renvoie des résultats dispersés dans le monde entier, inutilisables en
    /// pratique. `viewbox` (boîte englobante, PAS un simple point : Nominatim n'a pas de
    /// paramètre "rayon" natif) BIAISE la recherche vers cette zone SANS l'exclure (`bounded=0`,
    /// défaut Nominatim — volontairement PAS `bounded=1` : une vraie adresse lointaine bien
    /// formée, ex. "12 Rue de la Paix, Paris" cherchée alors que le rider est ailleurs, doit
    /// continuer à ressortir, juste pas prioritaire ; seule une requête générique SANS nom de
    /// lieu, type "pharmacie", tire un vrai bénéfice du biais). Repli honnête sur aucun biais si
    /// la position n'est pas encore connue (comportement identique à avant cette itération),
    /// jamais un crash/une erreur pour ça.
    func search(query: String, featureType: String? = nil, nearCoordinate: CLLocationCoordinate2D? = nil) async throws -> [GeocodingResult] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return [] }

        await respectRateLimit()

        var components = URLComponents(string: "\(NavConstants.nominatimBaseURL)/search")!
        var queryItems = [
            URLQueryItem(name: "q", value: trimmed),
            URLQueryItem(name: "format", value: "json"),
            // It31 : noms de lieux dans la langue de l'app.
            URLQueryItem(name: "accept-language", value: AppLanguageBundle.currentCode),
            URLQueryItem(name: "limit", value: "\(NavConstants.nominatimResultLimit)"),
        ]
        if let featureType {
            queryItems.append(URLQueryItem(name: "featureType", value: featureType))
        }
        if let nearCoordinate {
            let delta = NavConstants.nominatimProximityBiasDegrees
            let viewbox = [
                nearCoordinate.longitude - delta, nearCoordinate.latitude + delta,
                nearCoordinate.longitude + delta, nearCoordinate.latitude - delta,
            ].map { String($0) }.joined(separator: ",")
            queryItems.append(URLQueryItem(name: "viewbox", value: viewbox))
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
