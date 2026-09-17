import Foundation
import CoreLocation

/// Résultat d'un calcul d'itinéraire Valhalla complet (spec "nav-classic-rebuild", it21) — porte
/// à la fois ce dont la carte a besoin (coordonnées, comme l'ancien `NavRoute` OSRM) ET la liste
/// riche de manœuvres pour la bannière de guidage. Type DISTINCT de `NavRoute` (NavRoute.swift,
/// laissé intact pour `NavRoutingService`/OSRM, orphelin) plutôt qu'une extension du même type —
/// `RideSessionManager.requestNavRoute()` construit un `NavRoute` "fin" (coordonnées/totaux
/// uniquement, `maneuvers: []`) depuis ceci pour le rendu carte (`MapProvider`, signature
/// inchangée), et garde `ValhallaNavRoute.maneuvers` à part pour la bannière — voir Ride/CLAUDE.md.
struct ValhallaNavRoute {
    let coordinates: [CLLocationCoordinate2D]
    let maneuvers: [ValhallaNavManeuver]
    let totalDistanceMeters: Double
    let totalDurationSeconds: Double
    let destinationLabel: String
}

/// Calcul d'itinéraire turn-by-turn complet via Valhalla `/route` (spec "nav-classic-rebuild",
/// it21) — DISTINCT de `ValhallaRoutingService.route(...)` (it19/it20, point-à-point simple pour
/// le contournement/la reprise hors-trace, sans manœuvres) : cette requête demande le narratif
/// complet (`directions_type` par défaut, "instructions") en FRANÇAIS (`language: "fr-FR"`),
/// PAS de réduction `costing_options.auto.use_highways/use_tolls` — contrairement au détour/la
/// reprise, un "Aller à" classique doit pouvoir emprunter l'autoroute si c'est la route la plus
/// rapide, comme n'importe quel GPS grand public.
enum ValhallaNavigationService {
    static func route(
        from origin: CLLocationCoordinate2D,
        to destination: CLLocationCoordinate2D,
        destinationLabel: String,
        configuration: ValhallaConfiguration
    ) async throws -> ValhallaNavRoute {
        guard let url = ValhallaRoutingService.endpointURL(configuration.endpointURLString, path: "route") else {
            throw ValhallaRoutingError.invalidEndpoint
        }

        let body: [String: Any] = [
            "locations": [
                ["lat": origin.latitude, "lon": origin.longitude],
                ["lat": destination.latitude, "lon": destination.longitude],
            ],
            "costing": "auto",
            "units": "kilometers",
            "language": "fr-FR",
        ]

        var request = URLRequest(url: url, timeoutInterval: RideConstants.valhallaRequestTimeoutSeconds)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try? JSONSerialization.data(withJSONObject: body)
        ValhallaRoutingService.applyBasicAuth(to: &request, configuration: configuration)

        let data = try await ValhallaRoutingService.performRequest(request)
        guard let decoded = try? JSONDecoder().decode(ValhallaNavRouteResponse.self, from: data),
              let leg = decoded.trip.legs.first
        else { throw ValhallaRoutingError.noRoute }

        let coordinates = ValhallaRoutingService.decodePolyline6(leg.shape)
        guard !coordinates.isEmpty else { throw ValhallaRoutingError.noRoute }

        return ValhallaNavRoute(
            coordinates: coordinates,
            maneuvers: leg.maneuvers.map(\.asNavManeuver),
            // `units: "kilometers"` demandé ci-dessus → `summary.length` en km, converti en m
            // pour rester cohérent avec le reste de l'app (toutes les distances en mètres).
            totalDistanceMeters: decoded.trip.summary.length * 1000,
            totalDurationSeconds: decoded.trip.summary.time,
            destinationLabel: destinationLabel
        )
    }
}

/// Abstraction du calcul d'itinéraire Nav (même esprit que `RoutingProvider`/
/// `MapMatchingProvider`, it20) — permet à `RideSessionManager.navRoutingProvider` d'être
/// remplacé par un provider factice en test (voir `NavProgressTests`/`NavAutoRecomputeTests`),
/// sans jamais dépendre d'un vrai réseau Valhalla.
protocol NavRoutingProvider {
    func route(
        from origin: CLLocationCoordinate2D,
        to destination: CLLocationCoordinate2D,
        destinationLabel: String,
        configuration: ValhallaConfiguration
    ) async throws -> ValhallaNavRoute
}

struct ValhallaNavRoutingProvider: NavRoutingProvider {
    func route(
        from origin: CLLocationCoordinate2D,
        to destination: CLLocationCoordinate2D,
        destinationLabel: String,
        configuration: ValhallaConfiguration
    ) async throws -> ValhallaNavRoute {
        try await ValhallaNavigationService.route(from: origin, to: destination, destinationLabel: destinationLabel, configuration: configuration)
    }
}

private struct ValhallaNavRouteResponse: Decodable {
    let trip: ValhallaNavTrip
}
private struct ValhallaNavTrip: Decodable {
    let summary: ValhallaNavSummary
    let legs: [ValhallaNavLeg]
}
private struct ValhallaNavSummary: Decodable {
    let time: Double
    let length: Double
}
private struct ValhallaNavLeg: Decodable {
    let shape: String
    let maneuvers: [ValhallaNavManeuverResponse]
}

private struct ValhallaSignElement: Decodable {
    let text: String
}
private struct ValhallaSign: Decodable {
    let exitNumberElements: [ValhallaSignElement]?
    let exitBranchElements: [ValhallaSignElement]?
    let exitTowardElements: [ValhallaSignElement]?
    let exitNameElements: [ValhallaSignElement]?

    enum CodingKeys: String, CodingKey {
        case exitNumberElements = "exit_number_elements"
        case exitBranchElements = "exit_branch_elements"
        case exitTowardElements = "exit_toward_elements"
        case exitNameElements = "exit_name_elements"
    }

    var asNavSignInfo: NavSignInfo {
        NavSignInfo(
            exitNumbers: (exitNumberElements ?? []).map(\.text),
            exitBranches: (exitBranchElements ?? []).map(\.text),
            exitTowards: (exitTowardElements ?? []).map(\.text),
            exitNames: (exitNameElements ?? []).map(\.text)
        )
    }
}

/// Décodage brut d'une manœuvre Valhalla — voir `ValhallaNavManeuver` pour le modèle exposé au
/// reste de l'app (ce type intermédiaire existe uniquement pour porter les `CodingKeys`
/// snake_case sans les mélanger à la logique métier).
private struct ValhallaNavManeuverResponse: Decodable {
    let type: Int
    let instruction: String
    let verbalTransitionAlertInstruction: String?
    let verbalPreTransitionInstruction: String?
    let verbalPostTransitionInstruction: String?
    let streetNames: [String]?
    let time: Double
    let length: Double
    let beginShapeIndex: Int
    let endShapeIndex: Int
    let verbalMultiCue: Bool?
    let roundaboutExitCount: Int?
    let sign: ValhallaSign?

    enum CodingKeys: String, CodingKey {
        case type, instruction, time, length, sign
        case verbalTransitionAlertInstruction = "verbal_transition_alert_instruction"
        case verbalPreTransitionInstruction = "verbal_pre_transition_instruction"
        case verbalPostTransitionInstruction = "verbal_post_transition_instruction"
        case streetNames = "street_names"
        case beginShapeIndex = "begin_shape_index"
        case endShapeIndex = "end_shape_index"
        case verbalMultiCue = "verbal_multi_cue"
        case roundaboutExitCount = "roundabout_exit_count"
    }

    /// Type inconnu (future valeur Valhalla non documentée, voir ValhallaManeuverType) → `.none`
    /// plutôt que de faire échouer le décodage de TOUTE la réponse pour une seule manœuvre.
    var asNavManeuver: ValhallaNavManeuver {
        ValhallaNavManeuver(
            type: ValhallaManeuverType(rawValue: type) ?? .none,
            instruction: instruction,
            verbalTransitionAlertInstruction: verbalTransitionAlertInstruction,
            verbalPreTransitionInstruction: verbalPreTransitionInstruction,
            verbalPostTransitionInstruction: verbalPostTransitionInstruction,
            streetNames: streetNames ?? [],
            lengthMeters: length * 1000,
            timeSeconds: time,
            beginShapeIndex: beginShapeIndex,
            endShapeIndex: endShapeIndex,
            isMultiCue: verbalMultiCue ?? false,
            roundaboutExitCount: roundaboutExitCount,
            sign: sign?.asNavSignInfo
        )
    }
}
