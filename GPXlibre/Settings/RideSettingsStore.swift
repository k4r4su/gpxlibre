import Foundation

/// Les 7 réglages de l'app, persistés en UserDefaults. Toute modification prend effet
/// immédiatement (les vues Ride lisent ces valeurs @Published en continu, pas besoin
/// de relancer l'app).
@MainActor
final class RideSettingsStore: ObservableObject {
    private enum Keys {
        static let zoomPreset = "settings.zoomPreset"
        static let turnThreshold = "settings.turnThresholdDegrees"
        static let alertDistance = "settings.checkpointAlertDistanceMeters"
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
    }

    private let defaults: UserDefaults

    @Published var zoomPreset: ZoomPreset {
        didSet { defaults.set(zoomPreset.rawValue, forKey: Keys.zoomPreset) }
    }
    @Published var turnThresholdDegrees: Double {
        didSet { defaults.set(turnThresholdDegrees, forKey: Keys.turnThreshold) }
    }
    @Published var checkpointAlertDistanceMeters: Double {
        didSet { defaults.set(checkpointAlertDistanceMeters, forKey: Keys.alertDistance) }
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

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults

        if let rawPreset = defaults.string(forKey: Keys.zoomPreset), let preset = ZoomPreset(rawValue: rawPreset) {
            zoomPreset = preset
        } else {
            zoomPreset = .normal
        }

        let storedThreshold = defaults.double(forKey: Keys.turnThreshold)
        turnThresholdDegrees = RideConstants.turnThresholdDegreesOptions.contains(storedThreshold)
            ? storedThreshold : RideConstants.turnThresholdDegreesDefault

        let storedAlert = defaults.double(forKey: Keys.alertDistance)
        checkpointAlertDistanceMeters = RideConstants.alertDistanceOptions.contains(storedAlert)
            ? storedAlert : RideConstants.alertDistanceDefaultMeters

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
            mapThemePreset = .osmStandard
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
    }
}
