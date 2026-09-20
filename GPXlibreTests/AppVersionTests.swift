import XCTest
@testable import GPXlibre

/// Fix "splash-version-robustness" (it23, point 3) — garde-fou pour que la version affichée
/// (splash + tout futur second endroit) reste TOUJOURS lue dynamiquement depuis
/// `CFBundleShortVersionString`, jamais recopiée en dur : ces tests injectent un dictionnaire
/// arbitraire pour vérifier que changer la version change bien le texte produit, sans dépendre
/// du vrai Info.plist du bundle de test.
final class AppVersionTests: XCTestCase {
    func testShortVersionReadsFromInfoDictionary() {
        XCTAssertEqual(AppVersion.shortVersion(infoDictionary: ["CFBundleShortVersionString": "0.0.23"]), "0.0.23")
    }

    func testDisplayTextWrapsShortVersionWithLabel() {
        XCTAssertEqual(AppVersion.displayText(infoDictionary: ["CFBundleShortVersionString": "0.0.23"]), "Version 0.0.23")
    }

    /// Repli honnête (jamais un crash) si la clé est absente — ne devrait jamais arriver en
    /// pratique (Xcode l'injecte toujours depuis MARKETING_VERSION), mais un dictionnaire vide
    /// est un état plausible en test.
    func testMissingKeyFallsBackToZeroVersionRatherThanCrashing() {
        XCTAssertEqual(AppVersion.shortVersion(infoDictionary: [:]), "0.0.0")
        XCTAssertEqual(AppVersion.shortVersion(infoDictionary: nil), "0.0.0")
    }

    /// Coeur du garde-fou : deux dictionnaires différents DOIVENT produire des textes
    /// différents — si ce test échouait, ce serait le signe qu'une valeur est devenue figée
    /// (codée en dur) quelque part entre la lecture et l'affichage.
    func testDifferentVersionsProduceDifferentDisplayText() {
        let v1 = AppVersion.displayText(infoDictionary: ["CFBundleShortVersionString": "0.0.22"])
        let v2 = AppVersion.displayText(infoDictionary: ["CFBundleShortVersionString": "0.0.23"])
        XCTAssertNotEqual(v1, v2)
    }
}
