import XCTest
@testable import GPXlibre

/// Spec "recording-density-setting" (it19, retour terrain "alléger le fichier GPX final") —
/// `précis` doit reproduire EXACTEMENT les seuils codés en dur d'avant ce réglage (5 s / 15 m),
/// sinon toute sortie enregistrée avec les réglages par défaut changerait de densité sans que
/// l'utilisateur n'ait rien demandé : régression silencieuse la plus probable sur ce genre de
/// refactor "constante → preset".
final class RecordingDensityPresetTests: XCTestCase {
    func testPrecisMatchesTheOriginalHardcodedDefaults() {
        XCTAssertEqual(RecordingDensityPreset.precis.minIntervalSeconds, 5)
        XCTAssertEqual(RecordingDensityPreset.precis.minDistanceMeters, 15)
    }

    func testEachPresetIsStrictlyLighterThanTheNext() {
        let presets: [RecordingDensityPreset] = [.precis, .leger, .tresLeger]
        for (lighter, denser) in zip(presets.dropFirst(), presets) {
            XCTAssertGreaterThan(lighter.minIntervalSeconds, denser.minIntervalSeconds)
            XCTAssertGreaterThan(lighter.minDistanceMeters, denser.minDistanceMeters)
        }
    }

    @MainActor
    func testSettingPersistsAcrossStoreInstances() {
        let suite = "RecordingDensityPresetTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }

        let first = RideSettingsStore(defaults: defaults)
        XCTAssertEqual(first.recordingDensityPreset, .precis, "défaut inchangé tant que l'utilisateur n'a rien réglé")
        first.recordingDensityPreset = .tresLeger

        let second = RideSettingsStore(defaults: defaults)
        XCTAssertEqual(second.recordingDensityPreset, .tresLeger, "le choix doit survivre à une nouvelle instance (persistance UserDefaults)")
    }
}
