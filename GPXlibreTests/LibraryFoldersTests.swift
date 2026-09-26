import XCTest
@testable import GPXlibre

/// It31 — dossiers de la Bibliothèque : purement organisationnels. Dossier et `UserDefaults`
/// dédiés, jamais les vraies données de l'app.
@MainActor
final class LibraryFoldersTests: XCTestCase {
    private var directory: URL!
    private var suiteName: String!
    private var defaults: UserDefaults!

    override func setUp() {
        super.setUp()
        directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        suiteName = "LibraryFoldersTests.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: directory)
        defaults.removePersistentDomain(forName: suiteName)
        super.tearDown()
    }

    private func makeLibrary() -> LibraryStore {
        LibraryStore(tracksDirectoryOverride: directory, defaults: defaults)
    }

    @discardableResult
    private func importTrack(_ name: String, into library: LibraryStore) throws -> GPXTrack {
        let gpx = """
        <?xml version="1.0"?>
        <gpx><trk><name>\(name)</name><trkseg>
        <trkpt lat="45.0" lon="5.0"></trkpt><trkpt lat="45.01" lon="5.01"></trkpt>
        </trkseg></trk></gpx>
        """
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let url = directory.appendingPathComponent("\(UUID().uuidString)-src.gpx")
        try gpx.write(to: url, atomically: true, encoding: .utf8)
        library.importTrack(from: url)
        return try XCTUnwrap(library.tracks.first { $0.name == name })
    }

    /// Migration : une Bibliothèque d'avant it31 (aucun `folders.json`) → toutes les traces dans
    /// "Non classé", aucune perdue, aucune orpheline.
    func testExistingTracksMigrateToUnclassifiedWithoutLoss() throws {
        let before = makeLibrary()
        let names = ["A", "B", "C"]
        for name in names { try importTrack(name, into: before) }
        XCTAssertFalse(FileManager.default.fileExists(atPath: directory.appendingPathComponent("folders.json").path))

        let relaunched = makeLibrary()

        XCTAssertTrue(relaunched.folders.isEmpty)
        XCTAssertEqual(Set(relaunched.tracks(inFolder: nil).map(\.name)), Set(names))
        XCTAssertEqual(relaunched.tracks.count, names.count)
    }

    /// Supprimer un dossier non vide : ses traces sont conservées, de retour dans "Non classé".
    func testDeletingANonEmptyFolderKeepsItsTracksInUnclassified() throws {
        let library = makeLibrary()
        let a = try importTrack("A", into: library)
        let b = try importTrack("B", into: library)
        let folder = try XCTUnwrap(library.createFolder(named: "Alsace"))
        library.move(trackID: a.id, toFolder: folder.id)
        library.move(trackID: b.id, toFolder: folder.id)
        XCTAssertEqual(library.tracks(inFolder: folder.id).count, 2)

        library.deleteFolder(folder.id)

        XCTAssertTrue(library.folders.isEmpty)
        XCTAssertEqual(library.tracks.count, 2, "aucune trace supprimée")
        XCTAssertEqual(Set(library.tracks(inFolder: nil).map(\.id)), [a.id, b.id])
        XCTAssertEqual(Set(makeLibrary().tracks(inFolder: nil).map(\.id)), [a.id, b.id], "persisté")
    }

    func testFoldersAndMovesPersistAcrossRelaunch() throws {
        let library = makeLibrary()
        let a = try importTrack("A", into: library)
        let folder = try XCTUnwrap(library.createFolder(named: "Vosges"))
        library.move(trackID: a.id, toFolder: folder.id)
        XCTAssertTrue(library.renameFolder(folder.id, to: "Hautes-Vosges"))

        let relaunched = makeLibrary()
        XCTAssertEqual(relaunched.folders.map(\.name), ["Hautes-Vosges"])
        XCTAssertEqual(relaunched.folderID(of: a.id), folder.id)

        relaunched.move(trackID: a.id, toFolder: nil)
        XCTAssertNil(makeLibrary().folderID(of: a.id))
    }

    /// Purement organisationnel : ranger la trace active ne change ni la trace active ni
    /// "affichée", ni l'export.
    func testFoldersNeverTouchTheActiveTrackOrExport() throws {
        let library = makeLibrary()
        let active = try importTrack("Active", into: library)
        library.setActive(active.id)
        let exportBefore = try Data(contentsOf: try XCTUnwrap(library.exportURL(for: active)))
        let folder = try XCTUnwrap(library.createFolder(named: "Rangé"))

        library.move(trackID: active.id, toFolder: folder.id)
        XCTAssertEqual(library.activeTrackID, active.id)
        XCTAssertTrue(library.isDisplayed(active.id))
        library.deleteFolder(folder.id)
        XCTAssertEqual(library.activeTrackID, active.id)

        XCTAssertEqual(try Data(contentsOf: try XCTUnwrap(library.exportURL(for: active))), exportBefore)
    }

    func testFolderNamesMustBeNonEmptyAndUnique() throws {
        let library = makeLibrary()
        XCTAssertNil(library.createFolder(named: "   "))
        let alsace = try XCTUnwrap(library.createFolder(named: " Alsace "))
        XCTAssertEqual(alsace.name, "Alsace")
        XCTAssertNil(library.createFolder(named: "alsace"), "doublon, casse ignorée")
        let jura = try XCTUnwrap(library.createFolder(named: "Jura"))
        XCTAssertFalse(library.renameFolder(jura.id, to: "ALSACE"))
        XCTAssertTrue(library.renameFolder(jura.id, to: "Jura "), "renommer en son propre nom reste permis")
        XCTAssertEqual(library.sortedFolders.map(\.name), ["Alsace", "Jura"])
    }

    /// Supprimer une trace oublie son affectation ; une affectation vers un dossier ou une trace
    /// disparus est nettoyée au lancement.
    func testDeletedTracksAndStaleAssignmentsAreForgotten() throws {
        let library = makeLibrary()
        let a = try importTrack("A", into: library)
        let folder = try XCTUnwrap(library.createFolder(named: "X"))
        library.move(trackID: a.id, toFolder: folder.id)
        library.delete(a)

        XCTAssertTrue(library.folderAssignments.isEmpty)
        XCTAssertTrue(makeLibrary().folderAssignments.isEmpty)
        library.move(trackID: UUID(), toFolder: folder.id)
        XCTAssertTrue(library.folderAssignments.isEmpty, "trace inconnue : ignorée")
    }
}
