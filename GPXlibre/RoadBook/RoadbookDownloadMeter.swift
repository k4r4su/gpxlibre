import Foundation

/// Ce que la barre de progression des repères affiche en plus des tronçons (it29).
struct RoadbookLandmarkDownloadStats: Equatable {
    /// Octets reçus (tous tronçons de ce téléchargement) — Overpass n'annonce aucune taille : pas
    /// de total en octets, jamais de pourcentage inventé.
    var bytesReceived: Int
    /// Éléments OSM retenus (repères candidats, zones bâties, localités).
    var elementsReceived: Int
    /// Débit lissé, calculé localement. `0` = rien reçu récemment (le serveur calcule).
    var bytesPerSecond: Double?
    /// Temps restant estimé, seulement quand l'estimation est stable.
    var secondsRemaining: Double?
    /// Le serveur a refusé la requête (504/429) : nouvel essai dans ce délai.
    var retryInSeconds: Double? = nil
}

/// Mesures PURES du téléchargement des repères (horloge injectée : testable sans attendre).
///
/// - Débit : octets reçus sur une fenêtre glissante de `landmarkProgressSpeedWindowSeconds`.
/// - Temps restant : Overpass passe l'essentiel du temps à CALCULER avant d'envoyer (mesuré :
///   4 à 15 s d'attente pour quelques dizaines de Ko), le débit en Ko/s ne dit donc rien de la
///   durée restante. L'estimation vient du rythme réel de traitement de la TRACE : mètres de
///   tronçons terminés par seconde (moyenne cumulée, stable par construction) × mètres restants.
///   Affichée seulement après `landmarkProgressMinChunksForEstimate` tronçon(s) terminé(s), puis
///   décomptée en continu entre deux tronçons (jamais de saut à chaque paquet reçu) ; masquée
///   pendant un nouvel essai et une fois dépassée (plus fiable).
struct RoadbookDownloadMeter {
    let totalMeters: Double
    let startedAt: Date

    private(set) var bytesReceived = 0
    private(set) var elementsReceived = 0
    private(set) var completedMeters: Double = 0
    private(set) var completedChunks = 0
    private var lastCompletionAt: Date?
    private var retryAt: Date?
    /// (instant, octets cumulés) des paquets reçus — élagué à la fenêtre du débit, en gardant le
    /// dernier paquet AVANT la fenêtre comme référence.
    private var samples: [(date: Date, bytes: Int)] = []

    init(totalMeters: Double, startedAt: Date) {
        self.totalMeters = totalMeters
        self.startedAt = startedAt
    }

    /// Nouvel essai annoncé : affiché jusqu'à ce que des octets arrivent ou que le tronçon aboutisse.
    mutating func recordRetry(after seconds: Double, at date: Date) {
        retryAt = date.addingTimeInterval(seconds)
    }

    mutating func record(bytes: Int, at date: Date) {
        retryAt = nil
        bytesReceived += bytes
        samples.append((date, bytesReceived))
        let window = RoadBookConstants.landmarkProgressSpeedWindowSeconds
        if let lastOutside = samples.lastIndex(where: { date.timeIntervalSince($0.date) > window }), lastOutside > 0 {
            samples.removeFirst(lastOutside)
        }
    }

    mutating func completeChunk(meters: Double, elements: Int, at date: Date) {
        completedMeters += meters
        completedChunks += 1
        elementsReceived += elements
        retryAt = nil
        lastCompletionAt = date
    }

    /// Octets reçus sur la fenêtre glissante / durée de la fenêtre. `nil` au tout début (pas assez
    /// de recul pour une valeur honnête), `0` si rien n'arrive (le serveur calcule).
    func bytesPerSecond(at date: Date) -> Double? {
        let elapsed = date.timeIntervalSince(startedAt)
        guard elapsed >= RoadBookConstants.landmarkProgressSpeedMinSeconds else { return nil }
        let window = RoadBookConstants.landmarkProgressSpeedWindowSeconds
        let baseline = samples.last { date.timeIntervalSince($0.date) > window }?.bytes ?? 0
        return Double(bytesReceived - baseline) / min(window, elapsed)
    }

    func secondsRemaining(at date: Date) -> Double? {
        guard completedChunks >= RoadBookConstants.landmarkProgressMinChunksForEstimate,
              let lastCompletionAt, completedMeters > 0, totalMeters > completedMeters
        else { return nil }
        let elapsedAtCompletion = lastCompletionAt.timeIntervalSince(startedAt)
        guard elapsedAtCompletion > 0 else { return nil }
        let metersPerSecond = completedMeters / elapsedAtCompletion
        let estimateAtCompletion = (totalMeters - completedMeters) / metersPerSecond
        let remaining = estimateAtCompletion - date.timeIntervalSince(lastCompletionAt)
        // Estimation dépassée (tronçon plus lent que prévu) : elle ne vaut plus rien, on se tait
        // plutôt que d'afficher "presque fini" alors que rien n'avance.
        return remaining > 0 ? remaining : nil
    }

    func stats(at date: Date) -> RoadbookLandmarkDownloadStats {
        RoadbookLandmarkDownloadStats(
            bytesReceived: bytesReceived,
            elementsReceived: elementsReceived,
            bytesPerSecond: bytesPerSecond(at: date),
            // Nouvel essai en attente : estimation suspendue.
            secondsRemaining: retryAt == nil ? secondsRemaining(at: date) : nil,
            retryInSeconds: retryAt.map { max($0.timeIntervalSince(date), 0) }
        )
    }
}
