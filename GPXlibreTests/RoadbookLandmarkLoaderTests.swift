import XCTest
import CoreLocation
@testable import GPXlibre

/// Jalon it28 — chargement des repères : complément par catégorie, filtrage sans réseau,
/// progression (en cours / terminé / échec / hors-ligne), Road Book utilisable pendant le
/// chargement. Aucun réseau : le téléchargement d'un tronçon est simulé.
@MainActor
final class RoadbookLandmarkLoaderTests: XCTestCase {
    /// Enregistre chaque requête (catégories demandées) ; peut bloquer un tronçon jusqu'à
    /// `release()` pour observer l'état intermédiaire.
    private actor FakeOverpass {
        private(set) var requests: [Set<RoadbookLandmarkCategory>] = []
        private var failing = false
        private var failOnRequest: Int?
        private var holdFromRequest: Int?
        private var waiters: [CheckedContinuation<Void, Never>] = []
        private let candidates: [RoadbookLandmarkCandidate]

        init(candidates: [RoadbookLandmarkCandidate]) {
            self.candidates = candidates
        }

        func setFailing(_ value: Bool) { failing = value }
        /// La requête n° `index` (1 = la première) échoue une fois.
        func failOnce(onRequest index: Int) { failOnRequest = index }
        func hold(fromRequest index: Int) { holdFromRequest = index }

        func release() {
            holdFromRequest = nil
            waiters.forEach { $0.resume() }
            waiters = []
        }

        func fetch(_ points: [GPXPoint], _ categories: Set<RoadbookLandmarkCategory>) async -> RoadbookLandmarkData? {
            requests.append(categories)
            if let holdFromRequest, requests.count > holdFromRequest {
                await withCheckedContinuation { waiters.append($0) }
            }
            if failing { return nil }
            if failOnRequest == requests.count {
                failOnRequest = nil
                return nil
            }
            // Tronçon : seulement les candidats proches de ses points (à 300 m près).
            let inChunk = candidates.filter { candidate in
                categories.contains(candidate.category) && points.contains { RoadbookAnalyzer.distanceMeters($0.coordinate, candidate.coordinate) < 300 }
            }
            return RoadbookLandmarkData(candidates: inChunk, fetchedCategories: [])
        }
    }

    private let start = CLLocationCoordinate2D(latitude: 45.0, longitude: 5.0)
    private var cacheDirectory: URL!

    override func setUp() {
        super.setUp()
        cacheDirectory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: cacheDirectory)
        super.tearDown()
    }

    private func north(_ meters: Double, lateral: Double = 0) -> CLLocationCoordinate2D {
        let metersPerDegreeLat = 111_320.0
        let metersPerDegreeLon = metersPerDegreeLat * cos(start.latitude * .pi / 180)
        return CLLocationCoordinate2D(latitude: start.latitude + meters / metersPerDegreeLat, longitude: start.longitude + lateral / metersPerDegreeLon)
    }

    private func points(lengthMeters: Double) -> [GPXPoint] {
        stride(from: 0.0, through: lengthMeters, by: 20).map { GPXPoint(latitude: north($0).latitude, longitude: north($0).longitude) }
    }

    private func candidate(_ category: RoadbookLandmarkCategory, _ label: String, at meters: Double, lateral: Double, id: Int) -> RoadbookLandmarkCandidate {
        RoadbookLandmarkCandidate(category: category, label: label, coordinate: north(meters, lateral: lateral), osmID: "node/\(id)")
    }

    private func makeLoader(_ fake: FakeOverpass, online: @escaping () -> Bool = { true }) -> RoadbookLandmarkLoader {
        RoadbookLandmarkLoader(
            cache: RoadbookLandmarkDataCache(directoryOverride: cacheDirectory),
            fetchChunk: { points, categories in await fake.fetch(points, categories) },
            isOnline: online
        )
    }

    private func waitUntil(_ condition: @autoclosure () -> Bool, timeout: TimeInterval = 5, file: StaticString = #filePath, line: UInt = #line) async {
        let deadline = Date().addingTimeInterval(timeout)
        while !condition() && Date() < deadline {
            try? await Task.sleep(nanoseconds: 10_000_000)
        }
        XCTAssertTrue(condition(), "condition jamais atteinte", file: file, line: line)
    }

    private func turn(at meters: Double) -> RoadbookManeuver {
        let checkpoint = Checkpoint(coordinate: north(meters), turnAngleDegrees: 90, direction: .right, tier: .hard, sequenceIndex: 1, sourcePointIndex: Int(meters / 20), trackCumulativeDistanceMeters: meters)
        return RoadbookManeuver(checkpoint: checkpoint, partialDistanceMeters: meters, cumulativeDistanceMeters: meters, headingDegrees: 90)
    }

    private var sample: [RoadbookLandmarkCandidate] {
        [
            candidate(.church, "Église Saint-Blaise", at: 600, lateral: 15, id: 1),
            candidate(.fuel, "Total", at: 1400, lateral: 60, id: 2),
            candidate(.bakery, "Au bon pain", at: 1700, lateral: 10, id: 3),
        ]
    }

    private func labels(_ loader: RoadbookLandmarkLoader) -> [String] {
        loader.selection.standalone.map(\.info.label)
    }

    // MARK: - Complément par catégorie, filtrage sans réseau

    func testDisablingACategoryRemovesItWithoutAnyDownload() async {
        let fake = FakeOverpass(candidates: sample)
        let loader = makeLoader(fake)
        let trackID = UUID()
        let track = points(lengthMeters: 2000)
        let defaults = RoadBookConstants.landmarkDefaultEnabledCategories

        loader.update(trackID: trackID, traversalKey: "a", points: track, maneuvers: [], enabled: defaults)
        await loader.settle()
        XCTAssertEqual(labels(loader), ["Église Saint-Blaise", "Total"])
        let requestsAfterFirstLoad = await fake.requests.count

        loader.update(trackID: trackID, traversalKey: "a", points: track, maneuvers: [], enabled: defaults.subtracting([.church]))
        await loader.settle()

        XCTAssertEqual(labels(loader), ["Total"], "l'église disparaît")
        let requestsAfterToggle = await fake.requests.count
        XCTAssertEqual(requestsAfterToggle, requestsAfterFirstLoad, "aucun re-téléchargement")
    }

    func testEnablingANeverDownloadedCategoryDownloadsOnlyThatCategory() async throws {
        let fake = FakeOverpass(candidates: sample)
        let loader = makeLoader(fake)
        let trackID = UUID()
        let track = points(lengthMeters: 2000)
        let defaults = RoadBookConstants.landmarkDefaultEnabledCategories

        loader.update(trackID: trackID, traversalKey: "a", points: track, maneuvers: [], enabled: defaults)
        await loader.settle()
        let firstRequests = await fake.requests
        let first = try XCTUnwrap(firstRequests.first)
        XCTAssertEqual(first, defaults, "premier chargement : uniquement les catégories actives")
        XCTAssertFalse(first.contains(.bakery))

        // Un virage à 1500 m : la boulangerie (1700 m) a son propre tronçon (densité : 1 par tronçon).
        loader.update(trackID: trackID, traversalKey: "a", points: track, maneuvers: [turn(at: 1500)], enabled: defaults.union([.bakery]))
        await loader.settle()

        let requests = await fake.requests
        XCTAssertEqual(requests.count, 2)
        XCTAssertEqual(try XCTUnwrap(requests.last), [.bakery], "complément : la seule catégorie manquante")
        XCTAssertEqual(labels(loader), ["Église Saint-Blaise", "Total", "Au bon pain"])
    }

    func testCachedCategoriesAreNeverDownloadedAgainAfterARelaunch() async {
        let fake = FakeOverpass(candidates: sample)
        let trackID = UUID()
        let track = points(lengthMeters: 2000)
        let defaults = RoadBookConstants.landmarkDefaultEnabledCategories
        let first = makeLoader(fake)
        first.update(trackID: trackID, traversalKey: "a", points: track, maneuvers: [], enabled: defaults)
        await first.settle()

        let relaunched = makeLoader(fake)
        relaunched.update(trackID: trackID, traversalKey: "b", points: Array(track.reversed()), maneuvers: [], enabled: defaults)
        await relaunched.settle()

        let requests = await fake.requests
        XCTAssertEqual(requests.count, 1, "cache par trace, valable dans les deux sens")
        XCTAssertEqual(Set(labels(relaunched)), ["Église Saint-Blaise", "Total"])
        XCTAssertEqual(relaunched.phase, .idle, "rien à télécharger : aucun indicateur")
    }

    // MARK: - Progression

    /// Téléchargement par tronçons : progression déterministe, repères affichés au fur et à mesure,
    /// `update` rend la main immédiatement (le Road Book reste utilisable), puis "Terminé".
    func testProgressAdvancesChunkByChunkAndLandmarksAppearAsTheyArrive() async {
        // 17 km : 3 tronçons de ~8 km. L'église est dans le premier, la station dans le dernier.
        let landmarks = [
            candidate(.church, "Église", at: 600, lateral: 15, id: 1),
            candidate(.fuel, "Station", at: 16_500, lateral: 40, id: 2),
        ]
        let fake = FakeOverpass(candidates: landmarks)
        await fake.hold(fromRequest: 1)
        let loader = makeLoader(fake)

        loader.update(trackID: UUID(), traversalKey: "a", points: points(lengthMeters: 17_000), maneuvers: [], enabled: RoadBookConstants.landmarkDefaultEnabledCategories)
        XCTAssertEqual(loader.phase, .downloading(completedChunks: 0, totalChunks: 3), "update ne bloque pas : l'état est déjà affichable")

        await waitUntil(loader.phase == .downloading(completedChunks: 1, totalChunks: 3))
        XCTAssertEqual(loader.phase.progress ?? 0, 1.0 / 3, accuracy: 0.001)
        await waitUntil(self.labels(loader) == ["Église"])

        await fake.release()
        await loader.settle()

        XCTAssertEqual(loader.phase, .finished)
        XCTAssertEqual(labels(loader), ["Église", "Station"])
        await waitUntil(loader.phase == .idle, timeout: RoadBookConstants.landmarkProgressDoneDisplaySeconds + 3)
    }

    /// Overpass indisponible : pas de crash, état d'échec, rien en cache ; "Réessayer" relance.
    func testAFailureShowsTheFailedStateAndRetryRecovers() async {
        let fake = FakeOverpass(candidates: sample)
        await fake.setFailing(true)
        let loader = makeLoader(fake)
        let trackID = UUID()
        let track = points(lengthMeters: 2000)

        loader.update(trackID: trackID, traversalKey: "a", points: track, maneuvers: [], enabled: RoadBookConstants.landmarkDefaultEnabledCategories)
        await loader.settle()
        XCTAssertEqual(loader.phase, .failed)
        XCTAssertTrue(loader.selection.standalone.isEmpty)
        XCTAssertNil(RoadbookLandmarkDataCache(directoryOverride: cacheDirectory).data(for: trackID), "un échec n'est jamais mis en cache")

        // Nouvelles manœuvres (map matching) : pas de nouvel essai automatique en boucle.
        loader.update(trackID: trackID, traversalKey: "a", points: track, maneuvers: [], enabled: RoadBookConstants.landmarkDefaultEnabledCategories)
        await loader.settle()
        let requestsBeforeRetry = await fake.requests.count
        XCTAssertEqual(requestsBeforeRetry, 1)

        await fake.setFailing(false)
        loader.retry()
        await loader.settle()
        XCTAssertEqual(loader.phase, .finished)
        XCTAssertEqual(labels(loader), ["Église Saint-Blaise", "Total"])
    }

    /// Échec au 2e tronçon sur 3 : le 1er reste affiché, "Réessayer" reprend AU 2e (jamais tout
    /// recommencer : l'instance Overpass publique limite le débit).
    func testRetryResumesAtTheFailedChunkKeepingWhatWasReceived() async {
        let landmarks = [
            candidate(.church, "Église", at: 600, lateral: 15, id: 1),
            candidate(.fuel, "Station", at: 16_500, lateral: 40, id: 2),
        ]
        let fake = FakeOverpass(candidates: landmarks)
        await fake.failOnce(onRequest: 2)
        let loader = makeLoader(fake)

        loader.update(trackID: UUID(), traversalKey: "a", points: points(lengthMeters: 17_000), maneuvers: [], enabled: RoadBookConstants.landmarkDefaultEnabledCategories)
        await loader.settle()
        XCTAssertEqual(loader.phase, .failed)
        XCTAssertEqual(labels(loader), ["Église"], "le tronçon reçu reste affiché")

        loader.retry()
        XCTAssertEqual(loader.phase, .downloading(completedChunks: 1, totalChunks: 3), "reprise au tronçon en échec")
        await loader.settle()

        let requests = await fake.requests.count
        XCTAssertEqual(requests, 4, "1 réussi + 1 échec + les 2 restants, jamais le 1er une 2e fois")
        XCTAssertEqual(loader.phase, .finished)
        XCTAssertEqual(labels(loader), ["Église", "Station"])
    }

    /// Hors ligne : aucun essai réseau, état hors-ligne, repères du cache s'il y en a.
    func testOfflineUsesTheCacheAndShowsTheOfflineState() async {
        let fake = FakeOverpass(candidates: sample)
        let trackID = UUID()
        let track = points(lengthMeters: 2000)
        let defaults = RoadBookConstants.landmarkDefaultEnabledCategories
        let online = makeLoader(fake)
        online.update(trackID: trackID, traversalKey: "a", points: track, maneuvers: [], enabled: defaults)
        await online.settle()

        let offline = makeLoader(fake, online: { false })
        offline.update(trackID: trackID, traversalKey: "a", points: track, maneuvers: [], enabled: defaults.union([.bakery]))
        await offline.settle()

        XCTAssertEqual(offline.phase, .offline(hasCachedData: true))
        XCTAssertEqual(labels(offline), ["Église Saint-Blaise", "Total"], "cache affiché, la boulangerie n'a jamais été téléchargée")
        let requests = await fake.requests.count
        XCTAssertEqual(requests, 1, "aucune requête hors ligne")

        let neverLoaded = makeLoader(fake, online: { false })
        neverLoaded.update(trackID: UUID(), traversalKey: "c", points: track, maneuvers: [], enabled: defaults)
        await neverLoaded.settle()
        XCTAssertEqual(neverLoaded.phase, .offline(hasCachedData: false))
        XCTAssertTrue(neverLoaded.selection.standalone.isEmpty)
    }

    func testChunksCoverTheWholeTrackContiguously() throws {
        let track = points(lengthMeters: 17_000)
        let chunks = RoadbookLandmarkLoader.chunks(of: track)

        XCTAssertEqual(chunks.count, 3)
        XCTAssertEqual(try XCTUnwrap(chunks.first?.first), try XCTUnwrap(track.first))
        XCTAssertEqual(try XCTUnwrap(chunks.last?.last), try XCTUnwrap(track.last))
        for (previous, next) in zip(chunks, chunks.dropFirst()) {
            XCTAssertEqual(try XCTUnwrap(previous.last), try XCTUnwrap(next.first), "tronçons jointifs")
        }
        XCTAssertTrue(RoadbookLandmarkLoader.chunks(of: []).isEmpty)
    }

    func testProgressMessagesForEveryState() {
        XCTAssertEqual(RoadbookLandmarkProgressView.message(for: .downloading(completedChunks: 1, totalChunks: 3)), "Téléchargement des repères… 1/3")
        XCTAssertEqual(RoadbookLandmarkProgressView.message(for: .analyzing), "Analyse des repères…")
        XCTAssertEqual(RoadbookLandmarkProgressView.message(for: .finished), "Repères à jour")
        XCTAssertEqual(RoadbookLandmarkProgressView.message(for: .failed), "Repères indisponibles (serveur OSM)")
        XCTAssertEqual(RoadbookLandmarkProgressView.message(for: .offline(hasCachedData: true)), "Hors ligne — repères en cache")
        XCTAssertEqual(RoadbookLandmarkProgressView.message(for: .offline(hasCachedData: false)), "Hors ligne — repères indisponibles")
        XCTAssertNil(RoadbookLandmarkLoadPhase.finished.progress)
    }

    // MARK: - Réglages persistés

    func testCategorySelectionPersistsAndDefaultsMatchTheCatalog() throws {
        let suite = "roadbook-landmarks-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }

        let store = RideSettingsStore(defaults: defaults)
        XCTAssertEqual(store.roadbookLandmarkCategories, RoadBookConstants.landmarkDefaultEnabledCategories)

        store.roadbookLandmarkCategories = [.bakery, .fuel]
        XCTAssertEqual(RideSettingsStore(defaults: defaults).roadbookLandmarkCategories, [.bakery, .fuel])

        store.roadbookLandmarkCategories = []
        XCTAssertEqual(RideSettingsStore(defaults: defaults).roadbookLandmarkCategories, [], "tout désactivé reste tout désactivé")

        store.resetRoadbookLandmarkCategoriesToDefaults()
        XCTAssertEqual(RideSettingsStore(defaults: defaults).roadbookLandmarkCategories, RoadBookConstants.landmarkDefaultEnabledCategories)
    }
}
