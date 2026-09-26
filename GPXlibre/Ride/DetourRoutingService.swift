import Foundation
import CoreLocation

/// Simplification assumée : l'API publique OSRM ne propose pas de profil "moto offroad".
/// "Route" utilise le profil voiture (routes revêtues), "Piste" utilise le profil vélo
/// (favorise les chemins/pistes) — le plus proche disponible sans clé ni hébergement.
///
/// Réutilisé pour le routing "hors-route" d'Aller à (spec "offroad-routing-preference", it13)
/// — remplace l'ancienne ligne droite ("vol d'oiseau") de GoToProfile.offroad, voir
/// RideSessionManager.startGoTo. Alternatives documentées si ce profil s'avère insuffisant en
/// usage réel (terrain très accidenté, pistes non cartographiées en highway=track/path sur
/// OSM) : (1) profil "foot" (piéton) du même serveur OSRM public — favorise encore plus les
/// sentiers/chemins, interdit totalement les grands axes, au prix d'une vitesse de référence
/// plus lente dans le calcul ; (2) une instance BRouter (auto-hébergée ou profils "trekking"/
/// "shortest" côté client) offre un vrai profil "moto trail"-like avec pondération fine par
/// type de surface (highway=track + tracktype + surface), mais demande soit un serveur dédié,
/// soit la lib BRouter embarquée (calcul local, pas d'API réseau) — piste à explorer si le
/// volume d'usage ou les retours terrain justifient l'investissement.
enum DetourProfile: String, CaseIterable {
    case route
    case offroad

    var displayName: String {
        switch self {
        case .route: return String(localized: "Route", bundle: .appLanguage)
        case .offroad: return String(localized: "Piste", bundle: .appLanguage)
        }
    }

    /// Plus `fileprivate` (spec "routing-provider-protocol", it20) : lu depuis
    /// `OSRMRoutingProvider` (RoutingProvider.swift), un fichier distinct désormais.
    var osrmProfile: String {
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

/// Point d'entrée du routage point-à-point pour le contournement/la reprise hors-trace/le
/// hors-route d'Aller à. Depuis it20 (spec "valhalla-live-routing"), délègue à un
/// `RoutingProvider` résolu par `RoutingProviderResolver` — voir RoutingProvider.swift pour le
/// détail de l'abstraction et du mécanisme de repli en chaîne.
enum DetourRoutingService {
    static func requestRoute(
        from origin: CLLocationCoordinate2D,
        candidates: [CLLocationCoordinate2D],
        profile: DetourProfile,
        valhalla: ValhallaConfiguration? = nil
    ) async throws -> DetourRoute {
        var lastError: Error?
        for candidate in candidates {
            do {
                let coordinates = try await route(from: origin, to: candidate, profile: profile, valhalla: valhalla)
                return DetourRoute(coordinates: coordinates, mode: .routed(profile), targetCoordinate: candidate, startedAt: Date())
            } catch {
                lastError = error
                continue
            }
        }
        throw DetourRoutingError.network(lastError ?? DetourRoutingError.noReachableCandidate)
    }

    /// Point-à-point simple (PAS de recherche multi-candidats comme `requestRoute` ci-dessus) —
    /// réutilisé par RideSessionManager.startGoTo pour le profil hors-route d'Aller à (spec
    /// "offroad-routing-preference", it13), donc internal plutôt que private désormais.
    ///
    /// `valhalla` (spec "valhalla-client-toggle", it19 ; branché réellement sur le guidage,
    /// it20) : `nil` tant que le toggle Réglages est désactivé (défaut) — comportement OSRM
    /// inchangé à l'identique. Non-nil : tente Valhalla EN PREMIER via `RoutingProviderResolver`,
    /// puis retombe automatiquement sur OSRM en cas d'échec (réseau, auth, serveur down) —
    /// désactiver le toggle plus tard revient donc instantanément et sans reste à ce même
    /// comportement OSRM, jamais de guidage cassé par un serveur Valhalla indisponible.
    static func route(
        from origin: CLLocationCoordinate2D,
        to destination: CLLocationCoordinate2D,
        profile: DetourProfile,
        valhalla: ValhallaConfiguration? = nil
    ) async throws -> [CLLocationCoordinate2D] {
        try await route(
            from: origin,
            to: destination,
            profile: profile,
            providers: RoutingProviderResolver.orderedProviders(valhallaEnabled: valhalla != nil, configuration: valhalla)
        )
    }

    /// `internal` uniquement pour la testabilité (spec "routing-provider-protocol", it20) —
    /// permet aux tests d'injecter des `RoutingProvider` factices (succès/échec contrôlés) pour
    /// vérifier le repli en chaîne SANS jamais dépendre d'un vrai réseau (ni OSRM, ni Valhalla).
    /// Aucun appelant réel ne passe `providers:` explicitement — toujours via l'overload
    /// ci-dessus, résolu depuis les Réglages.
    ///
    /// `activityMonitor` (spec "routing-active-service-indicator", it24, point 0) : injectable
    /// pour les tests (une instance FRAÎCHE, jamais `.shared`, voir `RoutingProviderTests`) —
    /// défaut `.shared` pour tout appelant réel, mis à jour sur CHAQUE succès (jamais sur un
    /// échec, voir `RoutingActivityMonitor`).
    static func route(
        from origin: CLLocationCoordinate2D,
        to destination: CLLocationCoordinate2D,
        profile: DetourProfile,
        providers: [RoutingProvider],
        activityMonitor: RoutingActivityMonitor = .shared
    ) async throws -> [CLLocationCoordinate2D] {
        var lastError: Error?
        for provider in providers {
            do {
                let result = try await provider.route(from: origin, to: destination, profile: profile)
                await activityMonitor.recordSuccess(provider: provider.kind)
                return result
            } catch {
                lastError = error
                continue
            }
        }
        throw lastError ?? URLError(.unknown)
    }
}
