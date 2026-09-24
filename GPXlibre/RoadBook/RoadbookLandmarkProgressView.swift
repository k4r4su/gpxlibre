import SwiftUI

/// Bandeau d'une ligne : état du chargement des repères (jalon it28). Barre déterministe pendant le
/// téléchargement (tronçons de trace reçus), étape "Analyse…", "Terminé", échec avec "Réessayer",
/// hors-ligne. Jamais bloquant : c'est un simple bandeau au-dessus des directions.
struct RoadbookLandmarkProgressView: View {
    let phase: RoadbookLandmarkLoadPhase
    let onRetry: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(spacing: 8) {
                icon
                Text(Self.message(for: phase))
                    .font(.footnote.weight(.semibold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                Spacer(minLength: 4)
                if phase == .failed {
                    Button("Réessayer", action: onRetry)
                        .font(.footnote.bold())
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                }
            }
            if let progress = phase.progress {
                ProgressView(value: progress)
                    .tint(.accentColor)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 7)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.primary.opacity(0.05))
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder
    private var icon: some View {
        switch phase {
        case .downloading, .analyzing:
            ProgressView().controlSize(.small)
        case .finished:
            Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
        case .failed:
            Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange)
        case .offline:
            Image(systemName: "wifi.slash").foregroundStyle(.secondary)
        case .idle:
            EmptyView()
        }
    }

    static func message(for phase: RoadbookLandmarkLoadPhase) -> String {
        switch phase {
        case .idle: return ""
        case .downloading(let completed, let total): return "Téléchargement des repères… \(completed)/\(total)"
        case .analyzing: return "Analyse des repères…"
        case .finished: return "Repères à jour"
        case .failed: return "Repères indisponibles (serveur OSM)"
        case .offline(let hasCachedData): return hasCachedData ? "Hors ligne — repères en cache" : "Hors ligne — repères indisponibles"
        }
    }
}
