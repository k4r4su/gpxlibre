import Foundation
import CoreLocation

struct TrafficSummary {
    /// Minutes de retard supplémentaire estimées par rapport à un trajet fluide.
    let extraDelayMinutes: Int
}

/// Bloc 4 (trafic) — voir TODO.md à la racine du projet pour l'activation complète.
/// Sans clé API TomTom (inscription développeur requise, hors de ce que l'agent peut
/// provisionner), ce service reste honnêtement silencieux : aucune donnée, pas d'erreur,
/// pas de section trafic affichée. Câblé et prêt dès qu'une clé est ajoutée.
enum TrafficService {
    /// Renseigner une clé TomTom gratuite (voir TODO.md) pour activer ce bloc.
    static let apiKey = ""

    static func trafficSummary(for route: NavRoute, networkMonitor: NetworkMonitor) async -> TrafficSummary? {
        guard !apiKey.isEmpty else { return nil }
        guard await MainActor.run(body: { networkMonitor.isReachable }) else { return nil }

        // Implémentation TomTom Traffic Flow/Incidents à brancher ici une fois la clé
        // renseignée — voir TODO.md pour l'appel exact et le format de réponse attendu.
        return nil
    }
}
