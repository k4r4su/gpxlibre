import XCTest
@testable import GPXlibre

/// Vérification directe des branches de résolution (spec "vector-pmtiles", it11 ; flavors de
/// couleur, it19) — pas d'accès disque réel, `fileExists` est injecté.
final class MapSourceResolverTests: XCTestCase {
    private let fakeLocalURL = URL(fileURLWithPath: "/tmp/fake-region.pmtiles")

    func testLocalPackagePresentAlwaysWinsRegardlessOfNetwork() {
        let selectionOnline = MapSourceResolver.resolve(
            activeVectorPackageFileURL: fakeLocalURL,
            isNetworkReachable: true,
            themePreset: .standard,
            fileExists: { _ in true }
        )
        XCTAssertEqual(selectionOnline, .vectorLocal(fileURL: fakeLocalURL, flavor: .standard))

        let selectionOffline = MapSourceResolver.resolve(
            activeVectorPackageFileURL: fakeLocalURL,
            isNetworkReachable: false,
            themePreset: .standard,
            fileExists: { _ in true }
        )
        XCTAssertEqual(selectionOffline, .vectorLocal(fileURL: fakeLocalURL, flavor: .standard))
    }

    func testNoLocalPackageButNetworkReachableUsesHostedVector() {
        let selection = MapSourceResolver.resolve(
            activeVectorPackageFileURL: nil,
            isNetworkReachable: true,
            themePreset: .standard,
            fileExists: { _ in false }
        )
        XCTAssertEqual(selection, .vectorHosted(flavor: .standard))
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
    /// n'avait donc AUCUN effet visible dans le cas normal (réseau disponible).
    func testReliefThemeForcesRasterEvenWithNetworkReachable() {
        let selection = MapSourceResolver.resolve(
            activeVectorPackageFileURL: nil,
            isNetworkReachable: true,
            themePreset: .relief,
            fileExists: { _ in false }
        )
        XCTAssertEqual(selection, .raster(.openTopoMap))
    }

    /// Spec "map-color-flavors" (it19) : un thème vectoriel (Standard/Contraste élevé/Terreux)
    /// transporte sa palette jusque dans la sélection résolue, hébergé ET local.
    func testColorFlavorThemesCarryTheirFlavorThroughVectorHostedAndLocal() {
        let hosted = MapSourceResolver.resolve(
            activeVectorPackageFileURL: nil,
            isNetworkReachable: true,
            themePreset: .hauteContraste,
            fileExists: { _ in false }
        )
        XCTAssertEqual(hosted, .vectorHosted(flavor: .hauteContraste))

        let local = MapSourceResolver.resolve(
            activeVectorPackageFileURL: fakeLocalURL,
            isNetworkReachable: false,
            themePreset: .terreux,
            fileExists: { _ in true }
        )
        XCTAssertEqual(local, .vectorLocal(fileURL: fakeLocalURL, flavor: .terreux))
    }

    /// Paquet sélectionné mais fichier disparu du disque (suppression manuelle, etc.) — ne
    /// doit jamais planter ni pointer vers un fichier absent, juste retomber sur les branches
    /// suivantes comme si aucun paquet n'était actif.
    func testLocalPackageReferencedButFileMissingFallsThrough() {
        let selectionOnline = MapSourceResolver.resolve(
            activeVectorPackageFileURL: fakeLocalURL,
            isNetworkReachable: true,
            themePreset: .standard,
            fileExists: { _ in false }
        )
        XCTAssertEqual(selectionOnline, .vectorHosted(flavor: .standard))

        let selectionOffline = MapSourceResolver.resolve(
            activeVectorPackageFileURL: fakeLocalURL,
            isNetworkReachable: false,
            themePreset: .standard,
            fileExists: { _ in false }
        )
        XCTAssertEqual(selectionOffline, .raster(.active(for: .standard)))
    }
}
