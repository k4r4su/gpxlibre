import Foundation
import CoreLocation

/// Orchestre la synchro Bloc 5 : "une fois par jour + à chaque lancement" (jamais en temps
/// réel), fusion avec le cache local, et signalement anonyme sortant. Offline-first de bout
/// en bout : toute erreur réseau ou absence de config serveur est avalée silencieusement —
/// l'app continue sur le dernier instantané local, jamais d'écran d'erreur pour ça.
@MainActor
final class SharedBlockageSyncCoordinator: ObservableObject {
    @Published private(set) var blockages: [SharedBlockage]

    private let store: SharedBlockageStore
    private let defaults: UserDefaults
    private var syncTask: Task<Void, Never>?
    private var isSyncInFlight = false
    /// Anti-rafale minimal (60 s) : `syncIfNeeded` est appelé à chaque mise à jour de
    /// position, pas seulement au lancement — sans ce garde-fou, une URL mal configurée
    /// relancerait une requête réseau à chaque tick de localisation.
    private var lastAttemptDate: Date?

    private enum Keys {
        static let lastSyncDate = "sync.sharedBlockages.lastSyncDate"
    }

    /// `store` par défaut construit ici (pas en valeur par défaut du paramètre) : une
    /// valeur par défaut est évaluée hors de l'isolation @MainActor du type, alors que
    /// SharedBlockageStore() l'exige.
    init(store: SharedBlockageStore? = nil, defaults: UserDefaults = .standard) {
        let resolvedStore = store ?? SharedBlockageStore()
        self.store = resolvedStore
        self.defaults = defaults
        blockages = resolvedStore.load()
    }

    private var lastSyncDate: Date? {
        get { defaults.object(forKey: Keys.lastSyncDate) as? Date }
        set { defaults.set(newValue, forKey: Keys.lastSyncDate) }
    }

    private var isSyncDue: Bool {
        if let lastAttemptDate, Date().timeIntervalSince(lastAttemptDate) < 60 { return false }
        guard let lastSyncDate else { return true }
        return Date().timeIntervalSince(lastSyncDate) >= SharedBlockageConstants.syncIntervalSeconds
    }

    /// À appeler au lancement et à l'ouverture de l'onglet Ride — n'effectue une requête
    /// réseau que si la synchro est due, le partage activé, le serveur configuré et le
    /// réseau joignable ; sinon ne fait rien (silencieux, cache local conservé tel quel).
    func syncIfNeeded(bbox: SharedBlockageBBox?, serverURLString: String, isReachable: Bool, isEnabled: Bool) {
        guard isEnabled, isReachable, !serverURLString.isEmpty, let bbox, isSyncDue, !isSyncInFlight else { return }
        lastAttemptDate = Date()
        isSyncInFlight = true
        syncTask = Task { [weak self] in
            guard let self else { return }
            defer { self.isSyncInFlight = false }
            do {
                let fetched = try await SharedBlockageSyncService.fetch(bbox: bbox, serverURLString: serverURLString)
                guard !Task.isCancelled else { return }
                self.merge(fetched)
                self.lastSyncDate = Date()
            } catch {
                // Offline-first : on garde le dernier instantané local, aucune UI d'erreur.
                print("[SharedBlockages] Synchro impossible, on garde le cache local : \(error.localizedDescription)")
            }
        }
    }

    private func merge(_ fetched: [SharedBlockage]) {
        var byID = Dictionary(uniqueKeysWithValues: blockages.map { ($0.id, $0) })
        for blockage in fetched {
            byID[blockage.id] = blockage
        }
        blockages = byID.values.filter { !$0.isExpired }
        store.save(blockages)
    }

    /// Signalement sortant — best-effort, ne doit jamais bloquer ni faire échouer le flow
    /// de détour local qui l'appelle (voir RideSessionManager.requestDetour/requestDirectDetour).
    func report(coordinate: CLLocationCoordinate2D, note: String?, serverURLString: String, isReachable: Bool, isEnabled: Bool) {
        guard isEnabled, isReachable, !serverURLString.isEmpty else { return }
        let payload = SharedBlockageOutgoingReport(coordinate: coordinate, note: note, reporterID: AnonymousReporterID.current())
        Task { [weak self] in
            do {
                let confirmed = try await SharedBlockageSyncService.submit(payload, serverURLString: serverURLString)
                guard let self else { return }
                self.merge([confirmed])
            } catch {
                print("[SharedBlockages] Signalement anonyme impossible (pas grave, reste local) : \(error.localizedDescription)")
            }
        }
    }

    /// Point bloqué connu le plus proche d'une trace, si sous le seuil d'alerte (spec :
    /// pill d'alerte si la trace passe à moins de 300 m). Approximation par distance au
    /// point de trace le plus proche — suffisant pour une alerte, pas pour un recalcul.
    func nearestKnownBlockage(alongTrackPoints points: [CLLocationCoordinate2D]) -> SharedBlockage? {
        guard !points.isEmpty, !blockages.isEmpty else { return nil }
        var best: (blockage: SharedBlockage, distance: Double)?
        for blockage in blockages {
            let coordinate = blockage.coordinate.coordinate
            var minDistance = Double.greatestFiniteMagnitude
            for point in points {
                let distance = RoadbookAnalyzer.distanceMeters(coordinate, point)
                if distance < minDistance { minDistance = distance }
                if minDistance <= SharedBlockageConstants.alertRadiusMeters { break }
            }
            guard minDistance <= SharedBlockageConstants.alertRadiusMeters else { continue }
            if best == nil || minDistance < best!.distance {
                best = (blockage, minDistance)
            }
        }
        return best?.blockage
    }
}
