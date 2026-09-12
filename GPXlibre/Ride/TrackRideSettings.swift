import Foundation

/// Réglages PAR TRACE (spec "per-track-settings") — n'écrivent jamais le fichier GPX source :
/// sens de parcours, départ personnalisé, override couleur/épaisseur, espacement des chevrons
/// de direction. Les valeurs globales (Réglages) restent le défaut tant qu'aucun override
/// n'est défini ici.
struct TrackRideSettings: Codable, Equatable {
    var isReversed: Bool = false
    /// Index dans les points d'ORIGINE (avant inversion) — voir GPXTrack.reordered(using:).
    var customStartPointIndex: Int?
    var colorOverride: TraceColorPreset?
    var widthOverride: TraceWidthPreset?
    /// DIRECTION_ARROW_SPACING_M — espacement des chevrons de direction sur la trace.
    var chevronSpacingMeters: Double = RideConstants.directionArrowSpacingMetersDefault

    static let `default` = TrackRideSettings()

    var hasCustomStart: Bool { customStartPointIndex != nil }
}

/// Persiste les réglages par trace dans un unique fichier JSON (Documents/), clé = UUID de
/// la trace — mirroring DownloadedRegionStore/NavFavoritesStore.
@MainActor
final class TrackRideSettingsStore: ObservableObject {
    @Published private(set) var settingsByTrackID: [UUID: TrackRideSettings] = [:]

    private let fileManager = FileManager.default
    private var fileURL: URL {
        let docs = fileManager.urls(for: .documentDirectory, in: .userDomainMask)[0]
        return docs.appendingPathComponent("track-ride-settings.json")
    }

    init() {
        load()
    }

    func settings(for trackID: UUID) -> TrackRideSettings {
        settingsByTrackID[trackID] ?? .default
    }

    func setSettings(_ settings: TrackRideSettings, for trackID: UUID) {
        settingsByTrackID[trackID] = settings
        save()
    }

    private func load() {
        guard let data = try? Data(contentsOf: fileURL),
              let decoded = try? JSONDecoder().decode([UUID: TrackRideSettings].self, from: data) else { return }
        settingsByTrackID = decoded
    }

    private func save() {
        guard let data = try? JSONEncoder().encode(settingsByTrackID) else { return }
        try? data.write(to: fileURL)
    }
}
