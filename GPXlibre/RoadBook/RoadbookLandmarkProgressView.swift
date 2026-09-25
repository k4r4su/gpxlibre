import SwiftUI

/// Bandeau : état du chargement des repères (jalon it28). Barre déterministe pendant le
/// téléchargement (tronçons de trace reçus — seule cible connue d'avance), étape "Analyse…",
/// "Terminé", échec avec "Réessayer", hors-ligne. Depuis it29, une ligne de détail : éléments et
/// quantité reçus, débit, temps restant quand il est stable. Jamais bloquant.
struct RoadbookLandmarkProgressView: View {
    let phase: RoadbookLandmarkLoadPhase
    var stats: RoadbookLandmarkDownloadStats?
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
            if let progress = Self.determinateProgress(for: phase) {
                ProgressView(value: progress)
                    .tint(.accentColor)
            }
            if let stats, let detail = Self.detail(for: stats) {
                Text(detail)
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
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

    /// Barre seulement quand la cible est connue ET découpée : un seul tronçon passerait de 0 à
    /// 100 % d'un coup — pas de pourcentage fantaisiste, le détail (quantité, débit) suffit.
    static func determinateProgress(for phase: RoadbookLandmarkLoadPhase) -> Double? {
        guard case .downloading(_, let total) = phase, total > 1 else { return nil }
        return phase.progress
    }

    /// "412 éléments · 86 Ko · 24 Ko/s · ~20 s restantes" — chaque partie seulement si connue ;
    /// débit nul = le serveur calcule sa réponse ("attente du serveur").
    static func detail(for stats: RoadbookLandmarkDownloadStats) -> String? {
        var parts: [String] = []
        if stats.elementsReceived > 0 { parts.append("\(stats.elementsReceived) élément\(stats.elementsReceived > 1 ? "s" : "")") }
        if stats.bytesReceived > 0 { parts.append(byteString(stats.bytesReceived)) }
        if let retry = stats.retryInSeconds {
            parts.append(retry >= 1 ? "serveur saturé, nouvel essai dans \(Int(retry.rounded(.up))) s" : "serveur saturé, nouvel essai…")
        } else if let speed = stats.bytesPerSecond {
            parts.append(speed > 0 ? "\(byteString(Int(speed.rounded())))/s" : "attente du serveur")
        }
        if let remaining = stats.secondsRemaining { parts.append(remainingString(remaining)) }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    static func byteString(_ bytes: Int) -> String {
        if bytes < 1024 { return "\(bytes) o" }
        if bytes < 1024 * 1024 { return "\(Int((Double(bytes) / 1024).rounded())) Ko" }
        return String(format: "%.1f Mo", Double(bytes) / 1024 / 1024).replacingOccurrences(of: ".", with: ",")
    }

    /// Arrondi à 5 s (puis à la minute) : un affichage qui ne tressaute pas.
    static func remainingString(_ seconds: Double) -> String {
        if seconds < 5 { return "presque fini" }
        if seconds < 60 { return "~\(Int((seconds / 5).rounded(.up)) * 5) s restantes" }
        return "~\(Int((seconds / 60).rounded(.up))) min restantes"
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
