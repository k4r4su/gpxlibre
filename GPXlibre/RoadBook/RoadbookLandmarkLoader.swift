import Foundation

/// État du chargement des repères, affiché par `RoadbookLandmarkProgressView` — jamais bloquant :
/// les directions du Road Book restent utilisables quel que soit l'état.
enum RoadbookLandmarkLoadPhase: Equatable {
    /// Rien à signaler (tout est en cache, ou l'indicateur "Terminé" a disparu).
    case idle
    /// Téléchargement tronçon par tronçon — progression déterministe.
    case downloading(completedChunks: Int, totalChunks: Int)
    /// Tous les tronçons reçus : sélection des repères pour le parcours affiché.
    case analyzing
    /// Terminé — affiché `landmarkProgressDoneDisplaySeconds` puis `.idle`.
    case finished
    /// Échec Overpass (réseau disponible) : message + "Réessayer".
    case failed
    /// Pas de réseau : les repères en cache s'il y en a, sinon aucun.
    case offline(hasCachedData: Bool)

    /// 0...1 pendant le téléchargement, `nil` sinon.
    var progress: Double? {
        guard case .downloading(let completed, let total) = self, total > 0 else { return nil }
        return Double(completed) / Double(total)
    }
}

/// Chargement + sélection des repères du Road Book pour la trace affichée (jalon it28). Seul
/// endroit qui décide QUAND télécharger :
/// - catégories activées déjà en cache → aucune requête, sélection locale seulement ;
/// - catégorie activée jamais téléchargée → téléchargement COMPLÉMENTAIRE de celle-ci seulement ;
/// - catégorie désactivée → simple filtre, aucune requête ;
/// - hors ligne → cache existant, état `.offline` ; échec → `.failed`, rien n'est mis en cache,
///   pas de nouvel essai automatique tant que rien ne change (bouton "Réessayer").
/// Le téléchargement est découpé en tronçons (`landmarkQueryChunkMeters`) : progression réelle,
/// et les repères apparaissent au fur et à mesure. Un échec garde (et affiche) les tronçons déjà
/// reçus ; "Réessayer" reprend AU tronçon en échec — l'instance Overpass publique limite le débit,
/// constaté sur trace réelle : recommencer tout le téléchargement aggraverait la limitation. La
/// sélection (projection de centaines de candidats) tourne hors du fil principal.
@MainActor
final class RoadbookLandmarkLoader: ObservableObject {
    typealias ChunkFetcher = @Sendable (_ points: [GPXPoint], _ categories: Set<RoadbookLandmarkCategory>) async -> RoadbookLandmarkData?

    @Published private(set) var phase: RoadbookLandmarkLoadPhase = .idle
    @Published private(set) var selection: RoadbookLandmarkSelection = .empty
    /// Candidats connus pour la trace courante (cache + tronçons déjà reçus).
    @Published private(set) var data: RoadbookLandmarkData?

    private let cache: RoadbookLandmarkDataCache
    private let fetchChunk: ChunkFetcher
    /// Réseau disponible ? Branché sur `NetworkMonitor` par `RoadBookTabView` à l'apparition.
    var isOnline: () -> Bool

    private var trackID: UUID?
    private var traversalKey: String?
    private var points: [GPXPoint] = []
    private var maneuvers: [RoadbookManeuver] = []
    private var enabled: Set<RoadbookLandmarkCategory> = []

    private var downloadTask: Task<Void, Never>?
    private var selectionTask: Task<Void, Never>?
    private var hideTask: Task<Void, Never>?
    private var selectionGeneration = 0
    /// Catégories dont le dernier téléchargement a échoué pour cette trace : pas de nouvel essai
    /// automatique à chaque changement de manœuvres (seulement "Réessayer" ou un autre besoin).
    private var failedCategories: Set<RoadbookLandmarkCategory>?

    /// Téléchargement interrompu par un échec : reprise au premier tronçon non reçu.
    private struct PartialDownload {
        let trackID: UUID
        let categories: Set<RoadbookLandmarkCategory>
        let totalChunks: Int
        let base: RoadbookLandmarkData
        let completedChunks: Int
        let received: RoadbookLandmarkData
    }
    private var partial: PartialDownload?

    init(
        cache: RoadbookLandmarkDataCache? = nil,
        fetchChunk: @escaping ChunkFetcher = { points, categories in
            await RoadbookLandmarkOverpassService.shared.fetch(for: points, categories: categories)
        },
        isOnline: @escaping () -> Bool = { true }
    ) {
        self.cache = cache ?? RoadbookLandmarkDataCache()
        self.fetchChunk = fetchChunk
        self.isOnline = isOnline
    }

    /// À appeler à chaque changement de trace/sens, de manœuvres ou de catégories activées.
    func update(trackID: UUID, traversalKey: String, points: [GPXPoint], maneuvers: [RoadbookManeuver], enabled: Set<RoadbookLandmarkCategory>) {
        if trackID != self.trackID {
            downloadTask?.cancel()
            downloadTask = nil
            hideTask?.cancel()
            failedCategories = nil
            partial = nil
            data = cache.data(for: trackID)
            phase = .idle
        }
        if traversalKey != self.traversalKey {
            // Ids des repères dérivés de la position le long de CE parcours : jamais réutilisés.
            selection = .empty
        }
        let enabledChanged = enabled != self.enabled
        self.trackID = trackID
        self.traversalKey = traversalKey
        self.points = points
        self.maneuvers = maneuvers
        self.enabled = enabled
        if enabledChanged { failedCategories = nil }

        reselect()
        ensureDownloaded()
    }

    /// Bouton "Réessayer", ou retour du réseau.
    func retry() {
        failedCategories = nil
        ensureDownloaded()
    }

    /// Attend la fin du travail en cours (tests).
    func settle() async {
        while let task = downloadTask {
            await task.value
            if downloadTask == task { break }
        }
        await selectionTask?.value
    }

    // MARK: - Téléchargement

    private var missingCategories: Set<RoadbookLandmarkCategory> {
        enabled.subtracting(data?.fetchedCategories ?? [])
    }

    private func ensureDownloaded() {
        guard downloadTask == nil, let trackID else { return }
        let missing = missingCategories
        guard !missing.isEmpty else {
            if case .offline = phase { phase = .idle }
            if phase == .failed { phase = .idle }
            return
        }
        guard isOnline() else {
            phase = .offline(hasCachedData: !(data?.candidates.isEmpty ?? true))
            return
        }
        if let failedCategories, missing.isSubset(of: failedCategories) { return }

        let chunks = Self.chunks(of: points)
        guard !chunks.isEmpty else { return }
        hideTask?.cancel()
        let resumed = partial.flatMap { $0.trackID == trackID && $0.categories == missing && $0.totalChunks == chunks.count ? $0 : nil }
        let start = PartialDownload(
            trackID: trackID,
            categories: missing,
            totalChunks: chunks.count,
            base: resumed?.base ?? data ?? .empty,
            completedChunks: resumed?.completedChunks ?? 0,
            received: resumed?.received ?? .empty
        )
        phase = .downloading(completedChunks: start.completedChunks, totalChunks: chunks.count)
        downloadTask = Task { [weak self] in
            await self?.download(chunks: chunks, from: start)
        }
    }

    private func download(chunks: [[GPXPoint]], from start: PartialDownload) async {
        let trackID = start.trackID
        let categories = start.categories
        let base = start.base
        var received = start.received
        for index in start.completedChunks..<chunks.count {
            let result = await fetchChunk(chunks[index], categories)
            guard !Task.isCancelled, self.trackID == trackID else { return }
            guard let result else {
                failedCategories = categories
                partial = PartialDownload(trackID: trackID, categories: categories, totalChunks: chunks.count, base: base, completedChunks: index, received: received)
                phase = isOnline() ? .failed : .offline(hasCachedData: !(data?.candidates.isEmpty ?? true))
                downloadTask = nil
                reselect()
                return
            }
            received = received.adding(result, markingFetched: [])
            // Au fur et à mesure : affichés, mais pas encore marqués "téléchargés".
            data = base.adding(received, markingFetched: [])
            phase = .downloading(completedChunks: index + 1, totalChunks: chunks.count)
            reselect()
        }

        partial = nil
        let complete = base.adding(received, markingFetched: categories)
        cache.store(complete, for: trackID)
        data = complete
        phase = .analyzing
        reselect()
        await selectionTask?.value
        guard self.trackID == trackID else { return }
        downloadTask = nil
        phase = .finished
        scheduleHide()
        // Une catégorie activée PENDANT le téléchargement : son complément maintenant.
        ensureDownloaded()
    }

    private func scheduleHide() {
        hideTask?.cancel()
        hideTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(RoadBookConstants.landmarkProgressDoneDisplaySeconds * 1_000_000_000))
            guard !Task.isCancelled, let self, self.phase == .finished else { return }
            self.phase = .idle
        }
    }

    /// Tronçons consécutifs d'environ `landmarkQueryChunkMeters` (le point de jonction appartient
    /// aux deux) — unité de la barre de progression.
    static func chunks(of points: [GPXPoint], chunkMeters: Double = RoadBookConstants.landmarkQueryChunkMeters) -> [[GPXPoint]] {
        let cumulative = TrackProjector.cumulativeDistances(for: points)
        guard points.count > 1, let total = cumulative.last, total > 0 else { return [] }
        var chunks: [[GPXPoint]] = []
        var start = 0
        for index in 1..<points.count where cumulative[index] - cumulative[start] >= chunkMeters || index == points.count - 1 {
            chunks.append(Array(points[start...index]))
            start = index
        }
        return chunks
    }

    // MARK: - Sélection

    private func reselect() {
        guard let data, points.count > 1 else {
            selection = .empty
            return
        }
        selectionGeneration += 1
        let generation = selectionGeneration
        let points = points
        let maneuvers = maneuvers
        let enabled = enabled
        let previous = selectionTask
        selectionTask = Task { [weak self] in
            await previous?.value
            let result = await Task.detached(priority: .utility) {
                RoadbookLandmarkSelector.select(data, points: points, maneuvers: maneuvers, enabledCategories: enabled)
            }.value
            guard let self, self.selectionGeneration == generation else { return }
            self.selection = result
        }
    }
}
