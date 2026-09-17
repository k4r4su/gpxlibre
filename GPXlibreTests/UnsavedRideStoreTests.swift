import XCTest
@testable import GPXlibre

/// Spec "unsaved-ride-recovery" (it19, retour terrain : "créer dans Biblio une catégorie
/// 'non-enregistré'... avec un cleanup au bout de 10 ou 20 traces, réglable") — chaque test
/// utilise un dossier temporaire dédié (jamais le vrai `Documents/UnsavedRides` de l'app).
@MainActor
final class UnsavedRideStoreTests: XCTestCase {
    private var tempDirectory: URL!

    override func setUp() {
        super.setUp()
        tempDirectory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: tempDirectory)
        super.tearDown()
    }

    private func makeStore() -> UnsavedRideStore {
        UnsavedRideStore(directoryOverride: tempDirectory)
    }

    func testCheckpointCreatesANewEntryAndWritesTheFile() {
        let store = makeStore()
        let sessionID = UUID()

        store.checkpoint(sessionID: sessionID, startedAt: Date(), gpxData: Data("<gpx></gpx>".utf8), pointCount: 10, maxRetained: 10)

        XCTAssertEqual(store.rides.count, 1)
        XCTAssertEqual(store.rides.first?.id, sessionID)
        XCTAssertEqual(store.rides.first?.pointCount, 10)
        XCTAssertTrue(FileManager.default.fileExists(atPath: store.fileURL(for: store.rides[0]).path))
    }

    func testCheckpointingTheSameSessionAgainUpdatesInPlaceRatherThanDuplicating() {
        let store = makeStore()
        let sessionID = UUID()
        let startedAt = Date()

        store.checkpoint(sessionID: sessionID, startedAt: startedAt, gpxData: Data("<gpx></gpx>".utf8), pointCount: 10, maxRetained: 10)
        store.checkpoint(sessionID: sessionID, startedAt: startedAt, gpxData: Data("<gpx>more</gpx>".utf8), pointCount: 20, maxRetained: 10)

        XCTAssertEqual(store.rides.count, 1, "la même session ne doit jamais produire deux entrées")
        XCTAssertEqual(store.rides.first?.pointCount, 20, "le compte de points doit refléter le dernier checkpoint")
    }

    /// Cœur du retour terrain : la limite de rétention doit purger les PLUS ANCIENNES d'abord.
    func testRetentionLimitPurgesTheOldestSessionsFirst() {
        let store = makeStore()
        let now = Date()

        for offset in 0..<5 {
            let sessionID = UUID()
            store.checkpoint(
                sessionID: sessionID,
                startedAt: now.addingTimeInterval(Double(offset) * 60),
                gpxData: Data("<gpx></gpx>".utf8),
                pointCount: 1,
                maxRetained: 3
            )
        }

        XCTAssertEqual(store.rides.count, 3, "au-delà de maxRetained, les sessions excédentaires doivent être purgées")
        let remainingStartDates = store.rides.map(\.startedAt).sorted()
        let expectedRemaining = (2..<5).map { now.addingTimeInterval(Double($0) * 60) }
        XCTAssertEqual(remainingStartDates, expectedRemaining, "seules les 3 sessions les PLUS RÉCENTES doivent survivre")
    }

    func testDiscardRemovesTheEntryAndItsFile() {
        let store = makeStore()
        let sessionID = UUID()
        store.checkpoint(sessionID: sessionID, startedAt: Date(), gpxData: Data("<gpx></gpx>".utf8), pointCount: 1, maxRetained: 10)
        let fileURL = store.fileURL(for: store.rides[0])

        store.discard(sessionID: sessionID)

        XCTAssertTrue(store.rides.isEmpty)
        XCTAssertFalse(FileManager.default.fileExists(atPath: fileURL.path), "le fichier GPX de secours doit être supprimé, pas seulement l'entrée d'index")
    }

    func testReloadPicksUpEntriesWrittenByAnotherInstance() {
        // Simule RideSessionManager (sa propre instance privée) et la Biblio (une autre
        // instance) partageant le même dossier — la Biblio, construite AVANT tout
        // enregistrement, ne voit les checkpoints écrits entre-temps qu'après un `reload()`.
        let store2 = makeStore()
        XCTAssertTrue(store2.rides.isEmpty, "précondition : rien n'a encore été enregistré")

        let store1 = makeStore()
        store1.checkpoint(sessionID: UUID(), startedAt: Date(), gpxData: Data("<gpx></gpx>".utf8), pointCount: 1, maxRetained: 10)

        XCTAssertTrue(store2.rides.isEmpty, "store2 ne doit pas se mettre à jour tout seul sans reload()")
        store2.reload()
        XCTAssertEqual(store2.rides.count, 1)
    }
}
