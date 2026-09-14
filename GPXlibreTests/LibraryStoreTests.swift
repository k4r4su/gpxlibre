import XCTest
@testable import GPXlibre

/// Invariants de la source de vérité unique active/affichée (fix "single-source-active-track",
/// itération 10) — plus fiable qu'une capture simulateur pour vérifier l'absence d'état
/// fantôme après suppression/import, difficile à observer visuellement de façon fiable.
///
/// Chaque test utilise un `tracksDirectoryOverride` et un `UserDefaults` de suite dédiés
/// (voir `LibraryStore.init`) : jamais le vrai `Documents/Tracks` ni le vrai
/// `UserDefaults.standard` de l'app, pour ne jamais polluer ni dépendre de données réelles.
@MainActor
final class LibraryStoreTests: XCTestCase {
    private var tempDirectory: URL!
    private var defaultsSuiteName: String!
    private var testDefaults: UserDefaults!

    override func setUp() {
        super.setUp()
        tempDirectory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        defaultsSuiteName = "LibraryStoreTests.\(UUID().uuidString)"
        testDefaults = UserDefaults(suiteName: defaultsSuiteName)
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: tempDirectory)
        testDefaults.removePersistentDomain(forName: defaultsSuiteName)
        super.tearDown()
    }

    private func makeStore() -> LibraryStore {
        LibraryStore(tracksDirectoryOverride: tempDirectory, defaults: testDefaults)
    }

    /// Écrit un GPX minimal valide et l'importe via la VRAIE API publique (`importTrack`) —
    /// exerce le même chemin de code que l'import réel (partage système / sélecteur), pas un
    /// raccourci de test.
    @discardableResult
    private func importSampleTrack(into store: LibraryStore, name: String) -> GPXTrack {
        let gpx = """
        <?xml version="1.0"?>
        <gpx><trk><name>\(name)</name><trkseg>
        <trkpt lat="45.0" lon="5.0"></trkpt>
        <trkpt lat="45.01" lon="5.01"></trkpt>
        </trkseg></trk></gpx>
        """
        let fileURL = tempDirectory.appendingPathComponent("\(UUID().uuidString).gpx")
        try? FileManager.default.createDirectory(at: tempDirectory, withIntermediateDirectories: true)
        try? gpx.write(to: fileURL, atomically: true, encoding: .utf8)
        store.importTrack(from: fileURL)
        guard let imported = store.tracks.first(where: { $0.name == name }) else {
            XCTFail("Import du GPX de test a échoué : \(store.lastError ?? "erreur inconnue")")
            return GPXTrack(id: UUID(), name: name, fileName: "", importDate: Date(), points: [], waypoints: [])
        }
        return imported
    }

    func testImportBecomesActiveAndDisplayedWhenNoneActive() {
        let store = makeStore()
        let a = importSampleTrack(into: store, name: "A")

        XCTAssertEqual(store.activeTrackID, a.id)
        XCTAssertTrue(store.isDisplayed(a.id))
    }

    /// "conflit double trace" (spec Bloc 1) : importer B pendant que A est active le rend
    /// affichée SANS jamais voler l'état actif de A.
    func testSecondImportWhileAnotherIsActiveStaysDisplayedOnly() {
        let store = makeStore()
        let a = importSampleTrack(into: store, name: "A")
        let b = importSampleTrack(into: store, name: "B")

        XCTAssertEqual(store.activeTrackID, a.id, "la première trace importée reste active")
        XCTAssertTrue(store.isDisplayed(b.id), "la seconde trace importée est affichée")
        XCTAssertNotEqual(store.activeTrackID, b.id, "B ne doit jamais voler l'état actif de A")
    }

    func testSetActiveAndSetDisplayedAreNoOpForUnknownTrackID() {
        let store = makeStore()
        let unknownID = UUID()

        store.setActive(unknownID)
        XCTAssertNil(store.activeTrackID, "setActive sur un id absent de tracks doit être un no-op")

        store.setDisplayed(unknownID, true)
        XCTAssertFalse(store.isDisplayed(unknownID), "setDisplayed sur un id absent de tracks doit être un no-op")
    }

    func testDeletingActiveTrackClearsActiveState() {
        let store = makeStore()
        let track = importSampleTrack(into: store, name: "Active")
        XCTAssertEqual(store.activeTrackID, track.id)

        store.delete(track)

        XCTAssertNil(store.activeTrackID, "supprimer la trace ACTIVE doit faire tomber l'état actif")
        XCTAssertFalse(store.isDisplayed(track.id))
        XCTAssertTrue(store.tracks.isEmpty)
    }

    func testDeletingNonActiveTrackDoesNotAffectActiveState() {
        let store = makeStore()
        let active = importSampleTrack(into: store, name: "Active")
        let other = importSampleTrack(into: store, name: "Other")
        XCTAssertEqual(store.activeTrackID, active.id)

        store.delete(other)

        XCTAssertEqual(store.activeTrackID, active.id, "supprimer une trace non active ne doit rien changer à l'état actif")
    }

    /// Invariant "active ⟹ affichée" dans le sens inverse : masquer la trace active la
    /// désactive aussi (une trace non affichée ne peut jamais rester active).
    func testHidingActiveTrackClearsActiveState() {
        let store = makeStore()
        let track = importSampleTrack(into: store, name: "T")

        store.setDisplayed(track.id, false)

        XCTAssertNil(store.activeTrackID)
        XCTAssertFalse(store.isDisplayed(track.id))
    }

    /// Spec "biblio-date-display" (it15, Bloc 1) : tri par date décroissante — importe D'ABORD
    /// la trace la plus ANCIENNE (metadata GPX 2020) puis la plus RÉCENTE (2024), et vérifie
    /// que l'ordre d'affichage se réordonne bien par date malgré un ordre d'import inverse
    /// (sinon le tri par défaut it10 "dernière importée en tête" masquerait un tri par
    /// insertion qui semblerait correct par coïncidence).
    func testSortsByGPXMetadataDateMostRecentFirstRegardlessOfImportOrder() {
        let suite = "LibraryStoreTests.\(UUID().uuidString)"
        defer { UserDefaults(suiteName: suite)?.removePersistentDomain(forName: suite) }
        let store = makeStore()

        func importDated(name: String, isoTime: String) {
            let gpx = """
            <?xml version="1.0"?>
            <gpx><metadata><time>\(isoTime)</time></metadata><trk><name>\(name)</name><trkseg>
            <trkpt lat="45.0" lon="5.0"></trkpt>
            <trkpt lat="45.01" lon="5.01"></trkpt>
            </trkseg></trk></gpx>
            """
            let fileURL = tempDirectory.appendingPathComponent("\(UUID().uuidString).gpx")
            try? FileManager.default.createDirectory(at: tempDirectory, withIntermediateDirectories: true)
            try? gpx.write(to: fileURL, atomically: true, encoding: .utf8)
            store.importTrack(from: fileURL)
        }

        importDated(name: "Ancienne", isoTime: "2020-01-01T10:00:00Z")
        importDated(name: "Récente", isoTime: "2024-06-15T10:00:00Z")

        XCTAssertEqual(store.tracks.map(\.name), ["Récente", "Ancienne"], "la trace la plus récente (metadata GPX) doit apparaître en tête, indépendamment de l'ordre d'import")
    }

    func testReimportAfterFullDeletionBehavesLikeAFreshImport() {
        let store = makeStore()
        let track = importSampleTrack(into: store, name: "T")
        store.delete(track)
        XCTAssertNil(store.activeTrackID)
        XCTAssertTrue(store.displayedTrackIDs.isEmpty)

        let reimported = importSampleTrack(into: store, name: "T")

        XCTAssertEqual(store.activeTrackID, reimported.id, "plus aucune trace active : le nouvel import doit le redevenir, comme un import initial")
        XCTAssertTrue(store.isDisplayed(reimported.id))
    }
}
