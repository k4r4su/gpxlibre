import Foundation
import CoreLocation

/// "Aller à" universel (Bloc 4) : guidage PARALLÈLE, jamais un remplacement de la trace
/// sacrée ni du Mode Nav principal — toujours en pointillés cyan, distinct de la trace
/// (orange) et du détour (rouge).
enum GoToProfile: String, CaseIterable, Identifiable {
    case route, offroad, mixed

    var id: String { rawValue }

    var label: String {
        switch self {
        case .route: return "Itinéraire"
        // Renommé "Vol d'oiseau" → "Piste" (spec "offroad-routing-preference", it13) : ce
        // profil ne trace plus une ligne droite, voir RideSessionManager.startGoTo — le
        // libellé doit refléter le routing hors-route réel (même terme que
        // DetourProfile.offroad.displayName, pour rester cohérent dans toute l'app).
        case .offroad: return "Piste"
        case .mixed: return "Mixte"
        }
    }

    var systemImageName: String {
        switch self {
        case .route: return "road.lanes"
        case .offroad: return "mountain.2.fill"
        case .mixed: return "arrow.triangle.branch"
        }
    }
}

struct GoToGuidance {
    let coordinates: [CLLocationCoordinate2D]
    let profile: GoToProfile
    let destinationCoordinate: CLLocationCoordinate2D
    let destinationLabel: String
    let computedAt = Date()

    /// Distance le long du tracé réel (spec "offroad-routing-preference", it13, "Estimations
    /// distance/durée affichées") — DISTINCTE de `RideSessionManager.goToDistanceRemainingMeters`
    /// (distance restante à vol d'oiseau jusqu'à la destination, affichée séparément dans
    /// GoToStatusPillView) : celle-ci est la longueur TOTALE du guidage au moment du calcul.
    var routeDistanceMeters: Double {
        guard coordinates.count > 1 else { return 0 }
        var total: Double = 0
        for i in 1..<coordinates.count {
            total += RoadbookAnalyzer.distanceMeters(coordinates[i - 1], coordinates[i])
        }
        return total
    }

    /// Estimation simple à vitesse moyenne assumée par profil — PAS la durée OSRM réelle
    /// (jamais parsée ici, voir DetourRoutingService : seule la géométrie est extraite de la
    /// réponse). Suffisant pour une estimation affichée, pas pour un ETA précis.
    var estimatedDurationMinutes: Double {
        let averageSpeedKmh: Double
        switch profile {
        case .route: averageSpeedKmh = 70
        case .offroad: averageSpeedKmh = 30
        case .mixed: averageSpeedKmh = 50
        }
        return (routeDistanceMeters / 1000) / averageSpeedKmh * 60
    }
}
