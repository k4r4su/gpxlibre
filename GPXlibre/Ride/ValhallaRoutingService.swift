import Foundation
import CoreLocation

/// Configuration d'une instance Valhalla auto-hébergée — endpoint (Réglages, non sensible) +
/// identifiants Basic Auth (Keychain, voir ValhallaKeychainStore). `nil` côté appelant tant que
/// `RideSettingsStore.valhallaEnabled` est désactivé (défaut) : voir
/// `RideSessionManager.currentValhallaConfiguration`.
struct ValhallaConfiguration {
    let endpointURLString: String
    let username: String
    let password: String
}

enum ValhallaRoutingError: Error, LocalizedError {
    case invalidEndpoint
    case network(Error)
    case server(String)
    case noRoute

    var errorDescription: String? {
        switch self {
        case .invalidEndpoint: return "URL du serveur Valhalla invalide."
        case .network(let error):
            // Retour terrain (it19) : "problème de timeout" signalé sans plus de détail —
            // localizedDescription seul ("Please try again") ne dit pas s'il s'agit d'un vrai
            // délai dépassé (-1001), d'un hôte injoignable (-1004), d'un TLS refusé (-1200),
            // etc. Domaine + code exposés pour un diagnostic immédiat sans Charles/Proxyman.
            let nsError = error as NSError
            return "Valhalla injoignable : \(error.localizedDescription) (\(nsError.domain) \(nsError.code))"
        case .server(let message): return "Erreur Valhalla : \(message)"
        case .noRoute: return "Aucun itinéraire retourné par Valhalla."
        }
    }
}

/// Client pour une instance Valhalla auto-hébergée (spec "valhalla-client-toggle", it19) —
/// endpoint et identifiants entièrement configurables (Réglages > Avancé), AUCUNE instance
/// publique connue/codée en dur, jamais sollicité tant que le toggle est désactivé. `/route`
/// et `/status` uniquement pour cette itération (priorité explicite du propriétaire) — pas
/// d'isochrones/matrix/optimized_route/etc.
///
/// Utilisé par `DetourRoutingService.route(...)` comme backend alternatif à OSRM (repli
/// automatique vers OSRM en cas d'échec Valhalla, jamais un guidage cassé par un serveur
/// indisponible) — jamais par `NavRoutingService` (Mode Nav "Aller à" a besoin des manœuvres
/// turn-by-turn détaillées ; leur vocabulaire Valhalla diffère trop d'OSRM pour être mappé
/// fidèlement dans le périmètre de cette itération, voir TODO.md).
enum ValhallaRoutingService {
    /// Coûtage Valhalla le plus proche du profil demandé — même logique de repli qu'OSRM
    /// (`DetourProfile.osrmProfile`) : pas de profil "moto" dédié dans les moteurs standards,
    /// "auto" pour route revêtue, "bicycle" pour favoriser pistes/chemins.
    private static func costing(for profile: DetourProfile) -> String {
        switch profile {
        case .route: return "auto"
        case .offroad: return "bicycle"
        }
    }

    static func route(
        from origin: CLLocationCoordinate2D,
        to destination: CLLocationCoordinate2D,
        profile: DetourProfile,
        configuration: ValhallaConfiguration
    ) async throws -> [CLLocationCoordinate2D] {
        guard let url = endpointURL(configuration.endpointURLString, path: "route") else {
            throw ValhallaRoutingError.invalidEndpoint
        }
        var body: [String: Any] = [
            "locations": [
                ["lat": origin.latitude, "lon": origin.longitude],
                ["lat": destination.latitude, "lon": destination.longitude],
            ],
            "costing": costing(for: profile),
            "units": "kilometers",
        ]
        // Spec "valhalla-live-routing" (it20) : le costing "auto" par défaut privilégie
        // l'autoroute la plus rapide, peu pertinent pour un contournement/une reprise moto —
        // le profil `.offroad` (costing "bicycle") évite déjà nativement l'autoroute, donc
        // seul `.route` a besoin de ce réglage.
        if profile == .route {
            body["costing_options"] = [
                "auto": [
                    "use_highways": RideConstants.valhallaAutoCostingUseHighways,
                    "use_tolls": RideConstants.valhallaAutoCostingUseTolls,
                ],
            ]
        }

        var request = URLRequest(url: url, timeoutInterval: RideConstants.valhallaRequestTimeoutSeconds)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try? JSONSerialization.data(withJSONObject: body)
        applyBasicAuth(to: &request, configuration: configuration)

        let data = try await performRequest(request)
        guard let decoded = try? JSONDecoder().decode(ValhallaRouteResponse.self, from: data) else {
            throw ValhallaRoutingError.noRoute
        }
        let coordinates = decoded.trip.legs.flatMap { decodePolyline6($0.shape) }
        guard !coordinates.isEmpty else { throw ValhallaRoutingError.noRoute }
        return coordinates
    }

    /// Vérification de connectivité (bouton "Tester la connexion", Réglages) — endpoint/
    /// identifiants tels que saisis À L'INSTANT, indépendamment du toggle `valhallaEnabled`
    /// (on doit pouvoir tester AVANT d'activer).
    static func checkStatus(configuration: ValhallaConfiguration) async throws -> String {
        guard let url = endpointURL(configuration.endpointURLString, path: "status") else {
            throw ValhallaRoutingError.invalidEndpoint
        }
        var request = URLRequest(url: url, timeoutInterval: RideConstants.valhallaRequestTimeoutSeconds)
        applyBasicAuth(to: &request, configuration: configuration)

        let data = try await performRequest(request)
        guard let decoded = try? JSONDecoder().decode(ValhallaStatusResponse.self, from: data) else {
            throw ValhallaRoutingError.server("réponse /status illisible")
        }
        return decoded.version ?? "connecté"
    }

    /// Plus `private` (spec "valhalla-map-matching-direction-change", it20) : réutilisées telles
    /// quelles par `ValhallaMapMatchingService` (`/trace_route`) — même gestion d'erreur réseau/
    /// HTTP, même construction d'URL/Basic Auth, pas de duplication entre les deux clients du
    /// même serveur.
    static func performRequest(_ request: URLRequest) async throws -> Data {
        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await URLSession.shared.data(for: request)
        } catch {
            throw ValhallaRoutingError.network(error)
        }
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            throw ValhallaRoutingError.server("HTTP \((response as? HTTPURLResponse)?.statusCode ?? -1)")
        }
        return data
    }

    static func endpointURL(_ endpointURLString: String, path: String) -> URL? {
        let trimmed = endpointURLString.hasSuffix("/") ? String(endpointURLString.dropLast()) : endpointURLString
        guard !trimmed.isEmpty else { return nil }
        return URL(string: "\(trimmed)/\(path)")
    }

    static func applyBasicAuth(to request: inout URLRequest, configuration: ValhallaConfiguration) {
        guard !configuration.username.isEmpty || !configuration.password.isEmpty else { return }
        let raw = "\(configuration.username):\(configuration.password)"
        let encoded = Data(raw.utf8).base64EncodedString()
        request.setValue("Basic \(encoded)", forHTTPHeaderField: "Authorization")
    }

    /// Décodage polyline PRÉCISION 6 (facteur 1e6, PAS 1e5 comme Google Maps/OSRM) — format
    /// utilisé par Valhalla pour `trip.legs[].shape` (voir doc Valhalla, "Encoded Polyline
    /// Algorithm Format" appliqué avec un facteur de précision de 6 décimales). Fonction pure,
    /// testée directement par round-trip encode/decode (voir ValhallaPolylineTests) — aucun
    /// réseau nécessaire pour vérifier sa correction.
    static func decodePolyline6(_ encoded: String) -> [CLLocationCoordinate2D] {
        let bytes = Array(encoded.utf8)
        var coordinates: [CLLocationCoordinate2D] = []
        var index = 0
        var latitude = 0
        var longitude = 0

        while index < bytes.count {
            latitude += decodeNextValue(bytes, index: &index)
            longitude += decodeNextValue(bytes, index: &index)
            coordinates.append(CLLocationCoordinate2D(latitude: Double(latitude) / 1e6, longitude: Double(longitude) / 1e6))
        }
        return coordinates
    }

    private static func decodeNextValue(_ bytes: [UInt8], index: inout Int) -> Int {
        var shift = 0
        var result = 0
        var byte: Int
        repeat {
            byte = Int(bytes[index]) - 63
            index += 1
            result |= (byte & 0x1f) << shift
            shift += 5
        } while byte >= 0x20
        return (result & 1) != 0 ? ~(result >> 1) : (result >> 1)
    }
}

private struct ValhallaRouteResponse: Decodable {
    let trip: ValhallaTrip
}
private struct ValhallaTrip: Decodable {
    let legs: [ValhallaLeg]
}
private struct ValhallaLeg: Decodable {
    let shape: String
}
private struct ValhallaStatusResponse: Decodable {
    let version: String?
}
