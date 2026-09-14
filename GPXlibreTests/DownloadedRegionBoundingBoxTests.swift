import XCTest
@testable import GPXlibre

/// Spec "offline-zones-outline" (it17, Bloc 1) : `DownloadedRegion.boundingBox` dérive un
/// rectangle englobant depuis la liste de tuiles — seul repli disponible, la géométrie exacte
/// (corridor non rectangulaire, ou zone manuelle) n'est jamais stockée telle quelle.
final class DownloadedRegionBoundingBoxTests: XCTestCase {
    private func makeRegion(tiles: [DownloadedRegion.TileKey]) -> DownloadedRegion {
        DownloadedRegion(id: UUID(), name: "Test", kind: .customArea, trackID: nil, tiles: tiles, createdAt: Date(), isComplete: true)
    }

    func testBoundingBoxIsNilForARegionWithNoTiles() {
        let region = makeRegion(tiles: [])
        XCTAssertNil(region.boundingBox)
    }

    /// Une seule tuile : la bbox doit être exactement celle de cette tuile (coin NO à coin SE).
    func testBoundingBoxOfASingleTileMatchesItsOwnCorners() {
        let region = makeRegion(tiles: [.init(TileCoordinate(z: 10, x: 512, y: 340))])
        let box = region.boundingBox!
        let expectedNW = TileCoordinate.northWestCorner(z: 10, x: 512, y: 340)
        let expectedSE = TileCoordinate.northWestCorner(z: 10, x: 513, y: 341)

        XCTAssertEqual(box.maxLat, expectedNW.latitude, accuracy: 0.0001)
        XCTAssertEqual(box.minLon, expectedNW.longitude, accuracy: 0.0001)
        XCTAssertEqual(box.minLat, expectedSE.latitude, accuracy: 0.0001)
        XCTAssertEqual(box.maxLon, expectedSE.longitude, accuracy: 0.0001)
    }

    /// Plusieurs tuiles CONTIGUËS au même zoom : la bbox doit couvrir l'ensemble, pas juste
    /// une seule tuile.
    func testBoundingBoxOfMultipleTilesCoversTheWholeGrid() {
        var tiles: [DownloadedRegion.TileKey] = []
        for x in 512...514 {
            for y in 340...341 {
                tiles.append(.init(TileCoordinate(z: 10, x: x, y: y)))
            }
        }
        let region = makeRegion(tiles: tiles)
        let box = region.boundingBox!
        let expectedNW = TileCoordinate.northWestCorner(z: 10, x: 512, y: 340)
        let expectedSE = TileCoordinate.northWestCorner(z: 10, x: 515, y: 342)

        XCTAssertEqual(box.maxLat, expectedNW.latitude, accuracy: 0.0001)
        XCTAssertEqual(box.minLon, expectedNW.longitude, accuracy: 0.0001)
        XCTAssertEqual(box.minLat, expectedSE.latitude, accuracy: 0.0001)
        XCTAssertEqual(box.maxLon, expectedSE.longitude, accuracy: 0.0001)
    }

    /// Un corridor réel couvre plusieurs niveaux de zoom (10 à 15, spec CorridorPrecacheEstimator)
    /// — la bbox doit se baser sur le zoom le PLUS BAS uniquement, jamais mélanger les niveaux
    /// (des x/y de zooms différents ne sont pas comparables entre eux).
    func testBoundingBoxUsesOnlyTheLowestZoomLevelPresent() {
        let coarse = DownloadedRegion.TileKey(TileCoordinate(z: 10, x: 512, y: 340))
        // Beaucoup de tuiles fines à z=15, dont certaines hors de l'étendue de la tuile z=10
        // ci-dessus si elles étaient (incorrectement) mélangées dans le calcul.
        let fine = (0..<50).map { i in DownloadedRegion.TileKey(TileCoordinate(z: 15, x: 16384 + i, y: 10880)) }
        let region = makeRegion(tiles: [coarse] + fine)

        let box = region.boundingBox!
        let expectedNW = TileCoordinate.northWestCorner(z: 10, x: 512, y: 340)
        let expectedSE = TileCoordinate.northWestCorner(z: 10, x: 513, y: 341)
        XCTAssertEqual(box.maxLat, expectedNW.latitude, accuracy: 0.0001, "doit ignorer les tuiles z=15, se baser uniquement sur z=10")
        XCTAssertEqual(box.minLon, expectedNW.longitude, accuracy: 0.0001)
        XCTAssertEqual(box.minLat, expectedSE.latitude, accuracy: 0.0001)
        XCTAssertEqual(box.maxLon, expectedSE.longitude, accuracy: 0.0001)
    }
}
