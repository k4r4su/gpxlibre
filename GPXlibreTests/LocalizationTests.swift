import XCTest
@testable import GPXlibre

/// It31, point 4 — traductions FR (défaut) / EN / DE / ES / IT. La complétude par rapport au CODE
/// se vérifie avec `scripts/l10n_check.py` (extraction par le compilateur) ; ici : règles de langue,
/// cohérence des fichiers, bascule en direct.
@MainActor
final class LocalizationTests: XCTestCase {
    private let languages = ["en", "de", "es", "it"]

    override func tearDown() {
        // Les autres tests attendent le français (voir GPXlibreApp : langue forcée sous XCTest).
        AppLanguageBundle.apply(AppLanguage.fallbackCode)
        super.tearDown()
    }

    // MARK: - Choix de la langue

    func testAutomaticUsesThePrimaryDeviceLanguageWhenSupported() {
        XCTAssertEqual(AppLanguage.automatic.resolvedCode(preferredLanguages: ["de-CH", "fr-FR"]), "de")
        XCTAssertEqual(AppLanguage.automatic.resolvedCode(preferredLanguages: ["en-GB"]), "en")
        XCTAssertEqual(AppLanguage.automatic.resolvedCode(preferredLanguages: ["es-MX"]), "es")
        XCTAssertEqual(AppLanguage.automatic.resolvedCode(preferredLanguages: ["it-IT"]), "it")
        XCTAssertEqual(AppLanguage.automatic.resolvedCode(preferredLanguages: ["fr-BE"]), "fr")
    }

    /// Appareil en suédois (même avec l'anglais en 2e langue) : repli sur le français.
    func testAnUnsupportedDeviceLanguageFallsBackToFrench() {
        XCTAssertEqual(AppLanguage.automatic.resolvedCode(preferredLanguages: ["sv-SE", "en-US"]), "fr")
        XCTAssertEqual(AppLanguage.automatic.resolvedCode(preferredLanguages: ["pt-BR"]), "fr")
        XCTAssertEqual(AppLanguage.automatic.resolvedCode(preferredLanguages: []), "fr")
    }

    func testAForcedLanguageWinsOverTheDevice() {
        XCTAssertEqual(AppLanguage.es.resolvedCode(preferredLanguages: ["de-DE"]), "es")
        XCTAssertEqual(AppLanguage.fr.resolvedCode(preferredLanguages: ["en-US"]), "fr")
    }

    func testTheLanguageSettingPersists() throws {
        let suite = "LocalizationTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        XCTAssertEqual(RideSettingsStore(defaults: defaults).appLanguage, .automatic)
        RideSettingsStore(defaults: defaults).appLanguage = .it
        XCTAssertEqual(RideSettingsStore(defaults: defaults).appLanguage, .it)
    }

    // MARK: - Fichiers de traduction

    private func entries(_ language: String, table: String) throws -> [String: String] {
        let path = try XCTUnwrap(Bundle.main.path(forResource: table, ofType: "strings", inDirectory: nil, forLocalization: language), "\(language)/\(table)")
        return try XCTUnwrap(NSDictionary(contentsOfFile: path) as? [String: String])
    }

    func testAllLanguagesTranslateExactlyTheSameKeysWithTheSameVariables() throws {
        let reference = try entries("en", table: "Localizable")
        XCTAssertGreaterThan(reference.count, 550)
        func variables(_ text: String) -> [String] {
            let regex = try? NSRegularExpression(pattern: "%(?:\\d+\\$)?(?:lld|@|\\.\\d+f|%)")
            let range = NSRange(text.startIndex..., in: text)
            return (regex?.matches(in: text, range: range) ?? []).compactMap { Range($0.range, in: text).map { String(text[$0]) } }.sorted()
        }
        for language in languages {
            let table = try entries(language, table: "Localizable")
            XCTAssertEqual(Set(table.keys), Set(reference.keys), language)
            for (key, value) in table {
                XCTAssertFalse(value.isEmpty, "\(language): \(key)")
                XCTAssertEqual(variables(value), variables(key), "\(language): \(key) → \(value)")
            }
        }
    }

    /// Libellés de repères stockés en clé française dans le cache : traduits dans chaque langue.
    func testEveryRuntimeLandmarkLabelIsTranslated() throws {
        for language in languages {
            let table = try entries(language, table: "Localizable")
            for key in L10n.dynamicKeys {
                XCTAssertNotNil(table[key], "\(language): \(key)")
            }
            XCTAssertNotNil(try entries(language, table: "Recording")["Enregistrer"], language)
        }
    }

    // MARK: - Bascule en direct

    func testSwitchingLanguageChangesTextsImmediately() {
        AppLanguageBundle.apply("en")
        XCTAssertEqual(String(localized: "Réglages", bundle: .appLanguage), "Settings")
        XCTAssertEqual(L10n.dynamic("Pont"), "Bridge")
        XCTAssertEqual(L10n.dynamic("Moulin du Bas"), "Moulin du Bas", "un nom propre OSM reste tel quel")
        XCTAssertEqual(RoadbookTier.hard.label, "Sharp turn")
        XCTAssertEqual(String(localized: "Enregistrer", bundle: .appLanguage), "Save")
        XCTAssertEqual(String(localized: "Enregistrer", table: "Recording", bundle: .appLanguage), "Record")

        AppLanguageBundle.apply("de")
        XCTAssertEqual(String(localized: "Réglages", bundle: .appLanguage), "Einstellungen")
        XCTAssertEqual(RoadbookLandmarkCategory.church.localizedGenericLabel, "Kirche")

        AppLanguageBundle.apply("fr")
        XCTAssertEqual(String(localized: "Réglages", bundle: .appLanguage), "Réglages")
        XCTAssertEqual(RoadbookLandmarkCategory.church.localizedGenericLabel, "Église")
    }

    func testLandmarkLabelsAreTranslatedAtDisplayTimeNotInTheCache() {
        let info = RoadbookLandmarkInfo(category: .bridge, label: "Pont", side: nil)
        AppLanguageBundle.apply("it")
        XCTAssertEqual(info.displayLabel, "Ponte")
        XCTAssertEqual(info.label, "Pont", "la donnée reste la clé française")
        AppLanguageBundle.apply("es")
        XCTAssertEqual(RoadbookLandmarkInfo(category: .church, label: "Église Saint-Martin", side: .right).displayLabel, "Église Saint-Martin a la derecha")
    }

    func testDatesFollowTheAppLanguage() {
        let track = GPXTrack(id: UUID(), name: "T", fileName: "t.gpx", importDate: Date(timeIntervalSince1970: 1_700_000_000), points: [], waypoints: [])
        AppLanguageBundle.apply("en")
        XCTAssertTrue(track.displayDateLabel.hasPrefix("Imported on"), track.displayDateLabel)
        XCTAssertTrue(track.displayDateLabel.contains("Nov"), track.displayDateLabel)
        AppLanguageBundle.apply("fr")
        XCTAssertTrue(track.displayDateLabel.contains("nov."), track.displayDateLabel)
    }
}
