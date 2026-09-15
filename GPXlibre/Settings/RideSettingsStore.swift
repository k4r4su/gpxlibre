import Foundation

/// Réglages de l'app, persistés en UserDefaults. Toute modification prend effet immédiatement
/// (les vues Ride lisent ces valeurs @Published en continu, pas besoin de relancer l'app) —
/// sauf mention contraire explicite (ex : Zoom par défaut/preset auto-zoom, qui se prévisualisent
/// avant validation, voir NavigationSettingsView).
@MainActor
final class RideSettingsStore: ObservableObject {
    private enum Keys {
        static let zoomPreset = "settings.zoomPreset"
        static let flashCount = "settings.flashCount"
        static let northUp = "settings.mapOrientationNorthUp"
        static let keepAwake = "settings.keepScreenAwakeInRide"
        static let hasSeenOnboarding = "settings.hasSeenOnboarding"
        static let voiceGuidanceEnabled = "settings.voiceGuidanceEnabled"
        static let voiceGuidanceVolume = "settings.voiceGuidanceVolume"
        static let speedLimitAlertThreshold = "settings.speedLimitAlertThresholdKmh"
        static let traceWidthPreset = "settings.traceWidthPreset"
        static let traceColorPreset = "settings.traceColorPreset"
        static let mapThemePreset = "settings.mapThemePreset"
        static let trafficEnabled = "settings.trafficEnabled"
        static let speedUnit = "settings.speedUnit"
        static let shareBlockagesAnonymously = "settings.shareBlockagesAnonymously"
        static let sharedBlockageServerURL = "settings.sharedBlockageServerURL"
        static let turnMergeMinDistance = "settings.turnMergeMinDistanceMeters"
        static let rideAnchorYFraction = "settings.rideAnchorYFraction"
        static let controlsSide = "settings.controlsSide"
        static let roadbookEnabled = "settings.roadbookEnabled"
        static let roadbookFlashEnabled = "settings.roadbookFlashEnabled"
        static let roadbookUseCustomThresholds = "settings.roadbookUseCustomThresholds"
        static let roadbookWindowBeforeMeters = "settings.roadbookWindowBeforeMeters"
        static let roadbookWindowAfterMeters = "settings.roadbookWindowAfterMeters"
        static let roadbookLightThresholdDegrees = "settings.roadbookLightThresholdDegrees"
        static let roadbookMarkedThresholdDegrees = "settings.roadbookMarkedThresholdDegrees"
        static let roadbookHardThresholdDegrees = "settings.roadbookHardThresholdDegrees"
        static let roadbookUTurnThresholdDegrees = "settings.roadbookUTurnThresholdDegrees"
        static let defaultRideZoomCameraMeters = "settings.defaultRideZoomCameraMeters"
        static let autoZoomEnabled = "settings.autoZoomEnabled"
        static let autoZoomMinMeters = "settings.autoZoomMinMeters"
        static let autoZoomMaxMeters = "settings.autoZoomMaxMeters"
    }

    private let defaults: UserDefaults

    @Published var zoomPreset: ZoomPreset {
        didSet { defaults.set(zoomPreset.rawValue, forKey: Keys.zoomPreset) }
    }
    @Published var flashCount: Int {
        didSet { defaults.set(flashCount, forKey: Keys.flashCount) }
    }
    @Published var mapOrientationNorthUp: Bool {
        didSet { defaults.set(mapOrientationNorthUp, forKey: Keys.northUp) }
    }
    @Published var keepScreenAwakeInRide: Bool {
        didSet { defaults.set(keepScreenAwakeInRide, forKey: Keys.keepAwake) }
    }
    @Published var hasSeenOnboarding: Bool {
        didSet { defaults.set(hasSeenOnboarding, forKey: Keys.hasSeenOnboarding) }
    }
    /// Guidage vocal Mode Nav (item Réglages #9). Volume 0...1.
    @Published var voiceGuidanceEnabled: Bool {
        didSet { defaults.set(voiceGuidanceEnabled, forKey: Keys.voiceGuidanceEnabled) }
    }
    @Published var voiceGuidanceVolume: Double {
        didSet { defaults.set(voiceGuidanceVolume, forKey: Keys.voiceGuidanceVolume) }
    }
    /// Seuil d'alerte dépassement de vitesse, km/h (item Réglages #8).
    @Published var speedLimitAlertThresholdKmh: Int {
        didSet { defaults.set(speedLimitAlertThresholdKmh, forKey: Keys.speedLimitAlertThreshold) }
    }
    /// Rendu de la trace (items Réglages #13/14) — appliqué en direct partout (Ride, Biblio).
    @Published var traceWidthPreset: TraceWidthPreset {
        didSet { defaults.set(traceWidthPreset.rawValue, forKey: Keys.traceWidthPreset) }
    }
    @Published var traceColorPreset: TraceColorPreset {
        didSet { defaults.set(traceColorPreset.rawValue, forKey: Keys.traceColorPreset) }
    }
    /// Thème carte (item #10) : "OSM standard" = automatique, sinon force clair/sombre.
    @Published var mapThemePreset: MapThemePreset {
        didSet { defaults.set(mapThemePreset.rawValue, forKey: Keys.mapThemePreset) }
    }
    /// Trafic on/off (item #11, Bloc 4).
    @Published var trafficEnabled: Bool {
        didSet { defaults.set(trafficEnabled, forKey: Keys.trafficEnabled) }
    }
    /// Unité de vitesse affichée (item #12) — ne convertit que les vitesses, pas les distances.
    @Published var speedUnit: SpeedUnit {
        didSet { defaults.set(speedUnit.rawValue, forKey: Keys.speedUnit) }
    }
    /// Section "Avancé" (Bloc 5) — partage anonyme des points bloqués, ON par défaut.
    @Published var shareBlockagesAnonymously: Bool {
        didSet { defaults.set(shareBlockagesAnonymously, forKey: Keys.shareBlockagesAnonymously) }
    }
    /// URL de l'instance auto-hébergée du serveur `server/` — vide par défaut (voir
    /// SharedBlockageConstants), aucune tentative réseau tant qu'elle n'est pas renseignée.
    @Published var sharedBlockageServerURLString: String {
        didSet { defaults.set(sharedBlockageServerURLString, forKey: Keys.sharedBlockageServerURL) }
    }
    /// Distance de fusion des checkpoints trop rapprochés (item Réglages #15, spec
    /// "roadbook-declutter") — DISTINCT du rayon "checkpoint atteint", voir RideConstants.
    @Published var turnMergeMinDistanceMeters: Double {
        didSet { defaults.set(turnMergeMinDistanceMeters, forKey: Keys.turnMergeMinDistance) }
    }
    /// Position verticale du point bleu en mode suivi cap-en-haut (spec
    /// "ride-anchor-lowered-setting", it14) — voir RideConstants.rideAnchorYFractionDefault.
    @Published var rideAnchorYFraction: Double {
        didSet { defaults.set(rideAnchorYFraction, forKey: Keys.rideAnchorYFraction) }
    }
    /// Côté de la colonne de contrôles Ride (spec "controls-side-setting", it14, Bloc 2) — le
    /// badge vitesse permute automatiquement du côté opposé, voir RideView.
    @Published var controlsSide: ControlsSide {
        didSet { defaults.set(controlsSide.rawValue, forKey: Keys.controlsSide) }
    }

    // MARK: - Roadbook (spec "roadbook-settings-wired", it14, Bloc 5 — "l'ancien panneau
    // Réglages > Roadbook n'agit pas, renouvelle-le avec des réglages réellement branchés")

    /// Activation globale — désactivé vide `checkpoints`/`inflectionPoints` (voir
    /// RideSessionManager.rebuildCheckpoints), sans jamais toucher la trace elle-même.
    @Published var roadbookEnabled: Bool {
        didSet { defaults.set(roadbookEnabled, forKey: Keys.roadbookEnabled) }
    }
    @Published var roadbookFlashEnabled: Bool {
        didSet { defaults.set(roadbookFlashEnabled, forKey: Keys.roadbookFlashEnabled) }
    }
    /// "Sensibilité (pré-réglage des seuils à 30/45/90/135 ou personnalisé)" — les 4 propriétés
    /// ci-dessous restent les valeurs EFFECTIVES en permanence (utilisées telles quelles par
    /// rebuildCheckpoints) ; ce booléen ne pilote que la possibilité de les ÉDITER dans
    /// Réglages (repasser à false les réinitialise aux défauts, voir NavigationSettingsView/
    /// SettingsView).
    @Published var roadbookUseCustomThresholds: Bool {
        didSet { defaults.set(roadbookUseCustomThresholds, forKey: Keys.roadbookUseCustomThresholds) }
    }
    @Published var roadbookWindowBeforeMeters: Double {
        didSet { defaults.set(roadbookWindowBeforeMeters, forKey: Keys.roadbookWindowBeforeMeters) }
    }
    @Published var roadbookWindowAfterMeters: Double {
        didSet { defaults.set(roadbookWindowAfterMeters, forKey: Keys.roadbookWindowAfterMeters) }
    }
    @Published var roadbookLightThresholdDegrees: Double {
        didSet { defaults.set(roadbookLightThresholdDegrees, forKey: Keys.roadbookLightThresholdDegrees) }
    }
    @Published var roadbookMarkedThresholdDegrees: Double {
        didSet { defaults.set(roadbookMarkedThresholdDegrees, forKey: Keys.roadbookMarkedThresholdDegrees) }
    }
    @Published var roadbookHardThresholdDegrees: Double {
        didSet { defaults.set(roadbookHardThresholdDegrees, forKey: Keys.roadbookHardThresholdDegrees) }
    }
    @Published var roadbookUTurnThresholdDegrees: Double {
        didSet { defaults.set(roadbookUTurnThresholdDegrees, forKey: Keys.roadbookUTurnThresholdDegrees) }
    }

    // MARK: - Zoom par défaut au démarrage (spec "default-zoom-preview", it14, Bloc 6)

    /// DEFAULT_RIDE_ZOOM réel (m), voir RideConstants.defaultRideZoomCameraMetersDefault —
    /// utilisé UNE fois par RideSessionManager.init comme point de départ avant que le zoom
    /// auto (vitesse) ne prenne le relais au premier fix GPS.
    @Published var defaultRideZoomCameraMeters: Double {
        didSet { defaults.set(defaultRideZoomCameraMeters, forKey: Keys.defaultRideZoomCameraMeters) }
    }

    // MARK: - Zoom automatique vitesse (spec "auto-zoom-speed-curve", it14, Bloc 7)

    @Published var autoZoomEnabled: Bool {
        didSet { defaults.set(autoZoomEnabled, forKey: Keys.autoZoomEnabled) }
    }
    @Published var autoZoomMinMeters: Double {
        didSet { defaults.set(autoZoomMinMeters, forKey: Keys.autoZoomMinMeters) }
    }
    @Published var autoZoomMaxMeters: Double {
        didSet { defaults.set(autoZoomMaxMeters, forKey: Keys.autoZoomMaxMeters) }
    }

    /// Repasse les 4 seuils à leurs défauts standards (30/45/90/135) — appelé quand l'utilisateur
    /// quitte le mode "personnalisé" (voir SettingsView), jamais automatiquement ailleurs.
    func resetRoadbookThresholdsToDefaults() {
        roadbookLightThresholdDegrees = NavigationConstants.roadbookLightThresholdDegreesDefault
        roadbookMarkedThresholdDegrees = NavigationConstants.roadbookMarkedThresholdDegreesDefault
        roadbookHardThresholdDegrees = NavigationConstants.roadbookHardThresholdDegreesDefault
        roadbookUTurnThresholdDegrees = NavigationConstants.roadbookUTurnThresholdDegreesDefault
    }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults

        if let rawPreset = defaults.string(forKey: Keys.zoomPreset), let preset = ZoomPreset(rawValue: rawPreset) {
            zoomPreset = preset
        } else {
            zoomPreset = .normal
        }

        let storedFlash = defaults.integer(forKey: Keys.flashCount)
        flashCount = RideConstants.flashCountOptions.contains(storedFlash)
            ? storedFlash : RideConstants.flashCountDefault

        mapOrientationNorthUp = defaults.bool(forKey: Keys.northUp)
        keepScreenAwakeInRide = defaults.object(forKey: Keys.keepAwake) == nil
            ? true : defaults.bool(forKey: Keys.keepAwake)
        hasSeenOnboarding = defaults.bool(forKey: Keys.hasSeenOnboarding)

        voiceGuidanceEnabled = defaults.object(forKey: Keys.voiceGuidanceEnabled) == nil
            ? true : defaults.bool(forKey: Keys.voiceGuidanceEnabled)
        let storedVolume = defaults.object(forKey: Keys.voiceGuidanceVolume) as? Double
        voiceGuidanceVolume = storedVolume ?? 1.0

        let storedThresholdKmh = defaults.integer(forKey: Keys.speedLimitAlertThreshold)
        speedLimitAlertThresholdKmh = NavConstants.speedLimitAlertThresholdOptionsKmh.contains(storedThresholdKmh)
            ? storedThresholdKmh : NavConstants.speedLimitAlertThresholdDefaultKmh

        if let rawWidth = defaults.string(forKey: Keys.traceWidthPreset), let preset = TraceWidthPreset(rawValue: rawWidth) {
            traceWidthPreset = preset
        } else {
            traceWidthPreset = .gantsEpais
        }
        if let rawColor = defaults.string(forKey: Keys.traceColorPreset), let preset = TraceColorPreset(rawValue: rawColor) {
            traceColorPreset = preset
        } else {
            traceColorPreset = .orange
        }

        if let rawTheme = defaults.string(forKey: Keys.mapThemePreset), let preset = MapThemePreset(rawValue: rawTheme) {
            mapThemePreset = preset
        } else {
            // Spec "map-color-flavors" (it19) : migration silencieuse — un utilisateur qui avait
            // "osmStandard"/"clair"/"sombre" (valeurs retirées) retombe ici, comme un premier
            // lancement (même patron que LibraryStore.legacySelectedTrackKey).
            mapThemePreset = .standard
        }
        trafficEnabled = defaults.object(forKey: Keys.trafficEnabled) == nil
            ? true : defaults.bool(forKey: Keys.trafficEnabled)
        if let rawUnit = defaults.string(forKey: Keys.speedUnit), let unit = SpeedUnit(rawValue: rawUnit) {
            speedUnit = unit
        } else {
            speedUnit = .kmh
        }

        shareBlockagesAnonymously = defaults.object(forKey: Keys.shareBlockagesAnonymously) == nil
            ? true : defaults.bool(forKey: Keys.shareBlockagesAnonymously)
        sharedBlockageServerURLString = defaults.string(forKey: Keys.sharedBlockageServerURL) ?? SharedBlockageConstants.defaultServerURLString

        let storedMergeDistance = defaults.double(forKey: Keys.turnMergeMinDistance)
        turnMergeMinDistanceMeters = RideConstants.turnMergeMinDistanceMetersOptions.contains(storedMergeDistance)
            ? storedMergeDistance : RideConstants.turnMergeMinDistanceMetersDefault

        let anchorRange = RideConstants.rideAnchorYFractionRange
        let storedAnchor = defaults.object(forKey: Keys.rideAnchorYFraction) as? Double
        rideAnchorYFraction = storedAnchor.map { min(max($0, anchorRange.lowerBound), anchorRange.upperBound) }
            ?? RideConstants.rideAnchorYFractionDefault

        if let rawSide = defaults.string(forKey: Keys.controlsSide), let side = ControlsSide(rawValue: rawSide) {
            controlsSide = side
        } else {
            controlsSide = .right
        }

        roadbookEnabled = defaults.object(forKey: Keys.roadbookEnabled) == nil
            ? true : defaults.bool(forKey: Keys.roadbookEnabled)
        roadbookFlashEnabled = defaults.object(forKey: Keys.roadbookFlashEnabled) == nil
            ? true : defaults.bool(forKey: Keys.roadbookFlashEnabled)
        roadbookUseCustomThresholds = defaults.bool(forKey: Keys.roadbookUseCustomThresholds)

        let windowRange = NavigationConstants.roadbookWindowRange
        let storedWindowBefore = defaults.object(forKey: Keys.roadbookWindowBeforeMeters) as? Double
        roadbookWindowBeforeMeters = storedWindowBefore.map { min(max($0, windowRange.lowerBound), windowRange.upperBound) }
            ?? NavigationConstants.roadbookWindowBeforeMetersDefault
        let storedWindowAfter = defaults.object(forKey: Keys.roadbookWindowAfterMeters) as? Double
        roadbookWindowAfterMeters = storedWindowAfter.map { min(max($0, windowRange.lowerBound), windowRange.upperBound) }
            ?? NavigationConstants.roadbookWindowAfterMetersDefault

        let storedLight = defaults.object(forKey: Keys.roadbookLightThresholdDegrees) as? Double
        roadbookLightThresholdDegrees = storedLight ?? NavigationConstants.roadbookLightThresholdDegreesDefault
        let storedMarked = defaults.object(forKey: Keys.roadbookMarkedThresholdDegrees) as? Double
        roadbookMarkedThresholdDegrees = storedMarked ?? NavigationConstants.roadbookMarkedThresholdDegreesDefault
        let storedHard = defaults.object(forKey: Keys.roadbookHardThresholdDegrees) as? Double
        roadbookHardThresholdDegrees = storedHard ?? NavigationConstants.roadbookHardThresholdDegreesDefault
        let storedUTurn = defaults.object(forKey: Keys.roadbookUTurnThresholdDegrees) as? Double
        roadbookUTurnThresholdDegrees = storedUTurn ?? NavigationConstants.roadbookUTurnThresholdDegreesDefault

        let zoomRange = RideConstants.defaultRideZoomRange
        let storedDefaultZoom = defaults.object(forKey: Keys.defaultRideZoomCameraMeters) as? Double
        defaultRideZoomCameraMeters = storedDefaultZoom.map { min(max($0, zoomRange.lowerBound), zoomRange.upperBound) }
            ?? RideConstants.defaultRideZoomCameraMetersDefault

        autoZoomEnabled = defaults.object(forKey: Keys.autoZoomEnabled) == nil
            ? true : defaults.bool(forKey: Keys.autoZoomEnabled)
        let boundsRange = RideConstants.autoZoomBoundsRange
        let storedMin = defaults.object(forKey: Keys.autoZoomMinMeters) as? Double
        autoZoomMinMeters = storedMin.map { min(max($0, boundsRange.lowerBound), boundsRange.upperBound) }
            ?? RideConstants.autoZoomMinMetersDefault
        let storedMax = defaults.object(forKey: Keys.autoZoomMaxMeters) as? Double
        autoZoomMaxMeters = storedMax.map { min(max($0, boundsRange.lowerBound), boundsRange.upperBound) }
            ?? RideConstants.autoZoomMaxMetersDefault
    }
}
