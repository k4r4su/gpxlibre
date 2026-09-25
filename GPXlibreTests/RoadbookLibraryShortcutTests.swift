import XCTest
@testable import GPXlibre

/// It29 — une seule trace active dans l'app (`LibraryStore.activeTrackID`), partagée par
/// Bibliothèque, Ride et Road Book. Le Road Book ne sélectionne plus rien : il affiche la trace
/// active, et son raccourci mène à la Bibliothèque. Changer de trace pendant une sortie en cours
/// demande confirmation. Stores isolés (dossier et `UserDefaults` dédiés), jamais les vraies données.
@MainActor
final class RoadbookLibraryShortcutTests: XCTestCase {
    private var tempDirectory: URL!
    private var suiteName: String!
    private var defaults: UserDefaults!

    override func setUp() {
        super.setUp()
        tempDirectory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        suiteName = "RoadbookLibraryShortcutTests.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: tempDirectory)
        defaults.removePersistentDomain(forName: suiteName)
        super.tearDown()
    }

    private func makeLibrary() -> LibraryStore {
        LibraryStore(tracksDirectoryOverride: tempDirectory, defaults: defaults)
    }

    @discardableResult
    private func importTrack(_ name: String, into library: LibraryStore) throws -> GPXTrack {
        let gpx = """
        <?xml version="1.0"?>
        <gpx><trk><name>\(name)</name><trkseg>
        <trkpt lat="45.0" lon="5.0"></trkpt><trkpt lat="45.01" lon="5.01"></trkpt><trkpt lat="45.02" lon="5.0"></trkpt>
        </trkseg></trk></gpx>
        """
        try FileManager.default.createDirectory(at: tempDirectory, withIntermediateDirectories: true)
        let url = tempDirectory.appendingPathComponent("\(UUID().uuidString).gpx")
        try gpx.write(to: url, atomically: true, encoding: .utf8)
        library.importTrack(from: url)
        return try XCTUnwrap(library.tracks.first { $0.name == name })
    }

    // MARK: - Source unique

    /// Sélection dans la Bibliothèque → le Road Book affiche cette trace immédiatement (et le
    /// raccourci son nom : même valeur).
    func testSelectingATrackInTheLibraryIsWhatTheRoadBookShows() throws {
        let library = makeLibrary()
        let settings = TrackRideSettingsStore()
        let first = try importTrack("Trace A", into: library)
        let second = try importTrack("Trace B", into: library)
        XCTAssertEqual(RoadbookTrackSource.displayedTrack(library: library, trackRideSettings: settings)?.id, first.id, "import : la première trace devient active")

        library.setActive(second.id)
        XCTAssertEqual(RoadbookTrackSource.displayedTrack(library: library, trackRideSettings: settings)?.id, second.id)
        XCTAssertEqual(RoadbookTrackSource.displayedTrack(library: library, trackRideSettings: settings)?.name, "Trace B")
    }

    /// Plus aucun repli sur "la première trace" : sans trace active, le Road Book n'en invente pas
    /// une autre que la Bibliothèque (impossible de désynchroniser les deux écrans).
    func testWithoutAnActiveTrackTheRoadBookShowsNone() throws {
        let library = makeLibrary()
        let track = try importTrack("Trace A", into: library)
        library.setDisplayed(track.id, false)

        XCTAssertNil(library.activeTrack)
        XCTAssertNil(RoadbookTrackSource.displayedTrack(library: library, trackRideSettings: TrackRideSettingsStore()))
    }

    func testTheShortcutNavigatesToTheLibrary() {
        let navigation = AppNavigationState()
        navigation.selectedTab = .roadBook
        var tapped = false
        let shortcut = RoadbookLibraryShortcut(trackName: "Trace A") {
            tapped = true
            navigation.showLibrary()
        }

        shortcut.action()

        XCTAssertTrue(tapped)
        XCTAssertEqual(navigation.selectedTab, .library)
        XCTAssertEqual(shortcut.trackName, "Trace A", "libellé en lecture seule : le nom de la trace active")
    }

    // MARK: - Sortie en cours

    func testChangingTheActiveTrackDuringARideRequiresConfirmation() throws {
        let library = makeLibrary()
        let first = try importTrack("Trace A", into: library)
        let second = try importTrack("Trace B", into: library)

        let pending = library.request(.activate(second), recordedPointsCount: 42)

        XCTAssertEqual(pending, .activate(second), "demande renvoyée pour confirmation")
        XCTAssertEqual(library.activeTrackID, first.id, "aucun changement silencieux")

        let deactivation = library.request(.deactivate(first), recordedPointsCount: 42)
        XCTAssertEqual(deactivation, .deactivate(first))
        XCTAssertEqual(library.activeTrackID, first.id)

        // Confirmation explicite : appliquée.
        TrackActivationPolicy.apply(.activate(second), to: library)
        XCTAssertEqual(library.activeTrackID, second.id)
    }

    func testWithoutARideInProgressTheChangeIsImmediate() throws {
        let library = makeLibrary()
        _ = try importTrack("Trace A", into: library)
        let second = try importTrack("Trace B", into: library)

        XCTAssertNil(library.request(.activate(second), recordedPointsCount: 0))
        XCTAssertEqual(library.activeTrackID, second.id)
    }

    func testReselectingTheActiveTrackDuringARideNeedsNoConfirmation() throws {
        let library = makeLibrary()
        let first = try importTrack("Trace A", into: library)
        XCTAssertFalse(TrackActivationPolicy.requiresConfirmation(.activate(first), activeTrackID: first.id, recordedPointsCount: 42))
        XCTAssertFalse(TrackActivationPolicy.requiresConfirmation(.activate(first), activeTrackID: nil, recordedPointsCount: 42), "aucune trace suivie : rien à interrompre")
    }

    /// Depuis it30, l'enregistrement est indépendant de la trace suivie : le message le dit (plus
    /// de renvoi vers "Sorties non enregistrées", rien n'est perdu).
    func testTheConfirmationMessageNamesBothTracksAndSaysRecordingContinues() throws {
        let library = makeLibrary()
        let second = try importTrack("Trace B", into: library)
        let message = TrackActivationPolicy.confirmationMessage(for: .activate(second), activeTrackName: "Trace A", recordedPointsCount: 42)

        XCTAssertTrue(message.contains("42 points"))
        XCTAssertTrue(message.contains("« Trace B »"))
        XCTAssertTrue(message.contains("« Trace A »"))
        XCTAssertTrue(message.contains("L'enregistrement de la sortie, lui, continue"))
    }

    // MARK: - Import / partage : inchangé

    /// Ouverture directe depuis un partage/import : jamais de vol de l'état actif (même pendant une
    /// sortie), la première trace importée devient active s'il n'y en avait aucune.
    func testImportNeverStealsTheActiveTrack() throws {
        let library = makeLibrary()
        let first = try importTrack("Trace A", into: library)
        XCTAssertEqual(library.activeTrackID, first.id)

        let shared = try importTrack("Trace partagée", into: library)
        XCTAssertEqual(library.activeTrackID, first.id)
        XCTAssertTrue(library.isDisplayed(shared.id))
    }
}
