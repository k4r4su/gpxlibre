import XCTest
@testable import GPXlibre

/// Vérification directe des 3 branches de résolution (spec "vector-pmtiles", it11) — pas
/// d'accès disque réel, `fileExists` est injecté.
final class MapSourceResolverTests: XCTestCase {
    private let fakeLocalURL = URL(fileURLWithPath: "/tmp/fake-region.pmtiles")

    func testLocalPackagePresentAlwaysWinsRegardlessOfNetwork() {
        let selectionOnline = MapSourceResolver.resolve(
            activeVectorPackageFileURL: fakeLocalURL,
            isNetworkReachable: true,
            themePreset: .osmStandard,
            fileExists: { _ in true }
        )
        XCTAssertEqual(selectionOnline, .vectorLocal(fileURL: fakeLocalURL))

        let selectionOffline = MapSourceResolver.resolve(
            activeVectorPackageFileURL: fakeLocalURL,
            isNetworkReachable: false,
            themePreset: .osmStandard,
            fileExists: { _ in true }
        )
        XCTAssertEqual(selectionOffline, .vectorLocal(fileURL: fakeLocalURL))
    }

    func testNoLocalPackageButNetworkReachableUsesHostedVector() {
        let selection = MapSourceResolver.resolve(
            activeVectorPackageFileURL: nil,
            isNetworkReachable: true,
            themePreset: .osmStandard,
            fileExists: { _ in false }
        )
        XCTAssertEqual(selection, .vectorHosted)
    }

    func testNoLocalPackageAndNoNetworkFallsBackToRasterUnchanged() {
        let selection = MapSourceResolver.resolve(
            activeVectorPackageFileURL: nil,
            isNetworkReachable: false,
            themePreset: .relief,
            fileExists: { _ in false }
        )
        XCTAssertEqual(selection, .raster(.active(for: .relief)))
    }

    /// Fix "map-theme-binding" (it13) : avant ce fix, cette combinaison (réseau joignable)
    /// retombait systématiquement sur `.vectorHosted`, quel que soit le thème demandé — Relief
    /// et Sombre n'avaient donc AUCUN effet visible dans le cas normal (réseau disponible).
    func testReliefThemeForcesRasterEvenWithNetworkReachable() {
        let selection = MapSourceResolver.resolve(
            activeVectorPackageFileURL: nil,
            isNetworkReachable: true,
            themePreset: .relief,
            fileExists: { _ in false }
        )
        XCTAssertEqual(selection, .raster(.openTopoMap))
    }

    /// Même fix : Sombre doit aussi forcer le raster (seul chemin où le filtre de nuit
    /// s'applique réellement, voir RideMapLibreView.updateNightMode) — y compris quand un
    /// paquet vectoriel local est actif (celui-ci n'a, lui non plus, qu'une variante claire).
    func testSombreThemeForcesRasterEvenWithLocalVectorPackageActive() {
        let selection = MapSourceResolver.resolve(
            activeVectorPackageFileURL: fakeLocalURL,
            isNetworkReachable: true,
            themePreset: .sombre,
            fileExists: { _ in true }
        )
        XCTAssertEqual(selection, .raster(.osmStandard))
    }

    /// Paquet sélectionné mais fichier disparu du disque (suppression manuelle, etc.) — ne
    /// doit jamais planter ni pointer vers un fichier absent, juste retomber sur les branches
    /// suivantes comme si aucun paquet n'était actif.
    func testLocalPackageReferencedButFileMissingFallsThrough() {
        let selectionOnline = MapSourceResolver.resolve(
            activeVectorPackageFileURL: fakeLocalURL,
            isNetworkReachable: true,
            themePreset: .osmStandard,
            fileExists: { _ in false }
        )
        XCTAssertEqual(selectionOnline, .vectorHosted)

        let selectionOffline = MapSourceResolver.resolve(
            activeVectorPackageFileURL: fakeLocalURL,
            isNetworkReachable: false,
            themePreset: .osmStandard,
            fileExists: { _ in false }
        )
        XCTAssertEqual(selectionOffline, .raster(.active(for: .osmStandard)))
    }
}
