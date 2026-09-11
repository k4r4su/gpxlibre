import Foundation
import CoreLocation

struct NavManeuver {
    let coordinate: CLLocationCoordinate2D
    let type: String
    let modifier: String?
    let streetName: String
    /// Distance (m) de ce point de manœuvre jusqu'au suivant (utile pour l'affichage "dans Xm, tournez...").
    let distanceToNextMeters: Double

    var instructionText: String {
        let street = streetName.isEmpty ? "" : " sur \(streetName)"
        switch type {
        case "depart": return "Démarrez"
        case "arrive": return "Vous êtes arrivé"
        case "roundabout", "rotary": return "Prenez le rond-point\(street)"
        case "merge": return "Insérez-vous\(street)"
        case "fork": return direction(prefix: "Restez", street: street)
        case "end of road": return direction(prefix: "Tournez", street: street)
        case "new name": return "Continuez tout droit\(street)"
        case "turn": return direction(prefix: "Tournez", street: street)
        default: return direction(prefix: "Continuez", street: street)
        }
    }

    private func direction(prefix: String, street: String) -> String {
        switch modifier {
        case "left": return "\(prefix) à gauche\(street)"
        case "right": return "\(prefix) à droite\(street)"
        case "sharp left": return "\(prefix) fortement à gauche\(street)"
        case "sharp right": return "\(prefix) fortement à droite\(street)"
        case "slight left": return "\(prefix) légèrement à gauche\(street)"
        case "slight right": return "\(prefix) légèrement à droite\(street)"
        case "straight": return "Continuez tout droit\(street)"
        case "uturn": return "Faites demi-tour"
        default: return "\(prefix)\(street)"
        }
    }

    var systemImageName: String {
        switch modifier {
        case "left": return "arrow.turn.up.left"
        case "right": return "arrow.turn.up.right"
        case "sharp left": return "arrow.turn.up.left"
        case "sharp right": return "arrow.turn.up.right"
        case "slight left": return "arrow.up.left"
        case "slight right": return "arrow.up.right"
        case "uturn": return "arrow.uturn.up"
        default:
            if type == "arrive" { return "flag.checkered" }
            if type == "roundabout" || type == "rotary" { return "arrow.triangle.2.circlepath" }
            return "arrow.up"
        }
    }
}

struct NavRoute {
    let coordinates: [CLLocationCoordinate2D]
    let maneuvers: [NavManeuver]
    let totalDistanceMeters: Double
    let totalDurationSeconds: Double
    let destinationLabel: String
    /// Marqueur d'identité bon marché (plutôt qu'une égalité profonde sur `coordinates`) pour
    /// savoir si la carte doit redessiner l'overlay — change à chaque calcul/recalcul.
    let computedAt = Date()
}

enum NavRoutingError: Error, LocalizedError {
    case offline
    case network(Error)
    case noRoute

    var errorDescription: String? {
        switch self {
        case .offline: return "Routage impossible hors-ligne — le calcul d'itinéraire nécessite une connexion."
        case .network: return "Calcul d'itinéraire impossible — vérifie ta connexion."
        case .noRoute: return "Aucun itinéraire trouvé entre ces deux points."
        }
    }
}

/// Routage via l'API publique OSRM (profil "driving" = moto route). Hors-ligne : message
/// honnête, aucune tentative de contournement (voir NavRoutingError.offline).
enum NavRoutingService {
    static func route(
        from origin: CLLocationCoordinate2D,
        to destination: CLLocationCoordinate2D,
        destinationLabel: String,
        networkMonitor: NetworkMonitor
    ) async throws -> NavRoute {
        guard await MainActor.run(body: { networkMonitor.isReachable }) else {
            throw NavRoutingError.offline
        }

        let urlString = "\(RideConstants.osrmPublicBaseURL)/route/v1/\(NavConstants.osrmProfile)/"
            + "\(origin.longitude),\(origin.latitude);\(destination.longitude),\(destination.latitude)"
            + "?steps=true&overview=full&geometries=geojson"
        guard let url = URL(string: urlString) else { throw NavRoutingError.noRoute }

        var request = URLRequest(url: url, timeoutInterval: RideConstants.detourRoutingTimeoutSeconds)
        request.setValue(MapEngineConstants.userAgent, forHTTPHeaderField: "User-Agent")

        let data: Data
        do {
            (data, _) = try await URLSession.shared.data(for: request)
        } catch {
            throw NavRoutingError.network(error)
        }

        guard let decoded = try? JSONDecoder().decode(OSRMFullResponse.self, from: data),
              let route = decoded.routes.first, let leg = route.legs.first
        else { throw NavRoutingError.noRoute }

        let coordinates = route.geometry.coordinates.map { CLLocationCoordinate2D(latitude: $0[1], longitude: $0[0]) }
        let maneuvers = leg.steps.map { step in
            NavManeuver(
                coordinate: CLLocationCoordinate2D(latitude: step.maneuver.location[1], longitude: step.maneuver.location[0]),
                type: step.maneuver.type,
                modifier: step.maneuver.modifier,
                streetName: step.name,
                distanceToNextMeters: step.distance
            )
        }

        return NavRoute(
            coordinates: coordinates,
            maneuvers: maneuvers,
            totalDistanceMeters: route.distance,
            totalDurationSeconds: route.duration,
            destinationLabel: destinationLabel
        )
    }
}

private struct OSRMFullResponse: Decodable {
    let routes: [OSRMFullRoute]
}
private struct OSRMFullRoute: Decodable {
    let legs: [OSRMLeg]
    let geometry: OSRMFullGeometry
    let distance: Double
    let duration: Double
}
private struct OSRMLeg: Decodable {
    let steps: [OSRMStep]
}
private struct OSRMStep: Decodable {
    let maneuver: OSRMManeuver
    let name: String
    let distance: Double
}
private struct OSRMManeuver: Decodable {
    let type: String
    let modifier: String?
    let location: [Double]
}
private struct OSRMFullGeometry: Decodable {
    let coordinates: [[Double]]
}
