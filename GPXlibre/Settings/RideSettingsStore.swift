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
    }
}
