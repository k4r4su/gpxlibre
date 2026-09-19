import XCTest
@testable import GPXlibre

/// Spec "satellite-sentinel2" (it22) — garde-fou contre le piège documenté dans
/// `GPXlibre/Offline/CLAUDE.md` : le gabarit EOX a un ordre de jetons z/y/x (pas z/x/y comme
/// les autres sources), une régression silencieuse (tuiles x/y interverties, aucune erreur
/// réseau visible) est possible si quelqu'un "corrige" l'ordre vers la convention habituelle.
final class TileSourceTests: XCTestCase {
    func testSatelliteHostMatchesBackToTileSource() {
        XCTAssertEqual(TileSource.matching(host: "tiles.maps.eox.at"), .satellite)
    }

    func testActiveForSatelliteThemeReturnsSatelliteSource() {
        XCTAssertEqual(TileSource.active(for: .satellite), .satellite)
    }

    func testActiveForOtherThemesUnaffectedBySatelliteAddition() {
        XCTAssertEqual(TileSource.active(for: .standard), .osmStandard)
        XCTAssertEqual(TileSource.active(for: .hauteContraste), .osmStandard)
        XCTAssertEqual(TileSource.active(for: .terreux), .osmStandard)
        XCTAssertEqual(TileSource.active(for: .relief), .openTopoMap)
    }

    /// Vérifie l'ordre EXACT des jetons dans le gabarit brut (avant toute substitution) : le
    /// chemin doit contenir "{z}/{y}/{x}", jamais "{z}/{x}/{y}" — c'est cet ordre inversé (vs.
    /// osm/opentopo) qui fait la particularité de ce service, confirmé contre la vraie
    /// WMTSCapabilities.xml d'EOX (jamais deviné).
    func testSatelliteTemplateUsesZYXTokenOrderNotZXY() {
        guard let template = TileSource.satellite.tileURLTemplates.first else {
            return XCTFail("Aucun gabarit d'URL pour la source satellite")
        }
        XCTAssertTrue(
            template.contains("/{z}/{y}/{x}."),
            "Le gabarit EOX doit garder l'ordre z/y/x (WMTS), pas z/x/y : \(template)"
        )
        XCTAssertFalse(template.contains("/{z}/{x}/{y}."))
    }

    /// Substitution par nom (jamais par position) : reproduit exactement la logique de
    /// `TileDownloadQueue.fetch` pour vérifier qu'une tuile z/x/y donnée produit bien une URL où
    /// {y} et {x} finissent dans le bon ordre dans le chemin, quel que soit leur ordre dans le
    /// gabarit d'origine.
    func testSatelliteTemplateSubstitutionProducesCorrectlyOrderedURL() {
        guard let template = TileSource.satellite.tileURLTemplates.first else {
            return XCTFail("Aucun gabarit d'URL pour la source satellite")
        }
        let urlString = template
            .replacingOccurrences(of: "{z}", with: "9")
            .replacingOccurrences(of: "{x}", with: "265")
            .replacingOccurrences(of: "{y}", with: "178")
        XCTAssertEqual(
            urlString,
            "https://tiles.maps.eox.at/wmts/1.0.0/s2cloudless-2024_3857/default/g/9/178/265.jpg"
        )
    }

    func testSatelliteCacheFolderIsIsolatedFromOtherSources() {
        let names = TileSource.allCases.map(\.cacheFolderName)
        XCTAssertEqual(Set(names).count, names.count, "Chaque source doit avoir son propre sous-dossier de cache")
        XCTAssertEqual(TileSource.satellite.cacheFolderName, "satellite")
    }
}
