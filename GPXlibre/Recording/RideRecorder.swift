import Foundation
import CoreLocation

/// Enregistrement de la sortie (it30, fix "recording-survives-tabs-and-background") — service
/// APPLICATIF unique, créé une fois par `GPXlibreApp`, totalement découplé du cycle de vie des vues.
///
/// Diagnostic à l'origine de ce service : la capture vivait dans `RideSessionManager`, dont le
/// `stop()` (appelé à chaque sortie de l'onglet Ride : `onDisappear`, changement d'onglet) coupait
/// le GPS (`stopUpdatingLocation`) — plus aucun point hors de Ride. En arrière-plan, rien ne
/// pouvait tourner : pas de `UIBackgroundModes: location`, pas de `allowsBackgroundLocationUpdates`.
/// Les points ne vivaient qu'en mémoire (secours GPX tous les 10 points).
///
/// Règles :
/// - démarré, mis en pause, repris, terminé UNIQUEMENT par une action de l'utilisateur ; jamais au
///   lancement de l'app ni à l'ouverture d'un écran ;
/// - son propre GPS (`RecordingLocationSource`), actif en arrière-plan SEULEMENT pendant
///   l'enregistrement (indicateur bleu d'iOS), coupé en pause et à la fin ;
/// - chaque point enregistré est écrit IMMÉDIATEMENT dans un journal sur disque
///   (`RideRecordingJournal`) : après un arrêt forcé de l'app, l'enregistrement est restauré, en
///   PAUSE (reprise explicite) ;
/// - le secours "Sorties non enregistrées" (GPX tous les N points, it19) est conservé tel quel.
@MainActor
final class RideRecorder: ObservableObject {
    enum State: String, Codable {
        case idle, recording, paused
    }

    enum StartOutcome: Equatable {
        case started
        /// Autorisation demandée : l'enregistrement démarre dès qu'elle est accordée.
        case awaitingAuthorization
        /// Localisation refusée ou restreinte : rien ne démarre, l'UI l'explique.
        case denied
    }

    @Published private(set) var state: State = .idle
    @Published private(set) var pointCount = 0
    @Published private(set) var authorizationStatus: CLAuthorizationStatus
    /// Proposition "Enregistrer cette sortie ?" déjà faite, par trace (it31) — ici plutôt que dans
    /// `RideView` : elle survit à la reconstruction des vues (changement de langue).
    var promptPolicy = RecordingPromptPolicy()
    /// Enregistrement retrouvé au lancement après un arrêt de l'app (kill système/utilisateur).
    @Published private(set) var wasRestoredAfterInterruption = false

    private(set) var points: [GPXPoint] = []
    private(set) var sessionID: UUID?
    private(set) var sessionStartedAt: Date?
    private var lastRecordedLocation: CLLocation?
    private var startWhenAuthorized = false

    private let source: RecordingLocationSource
    private let journal: RideRecordingJournal
    private let settings: RideSettingsStore
    /// Secours "Sorties non enregistrées" — `internal` pour les tests (dossier dédié).
    var unsavedRideStore: UnsavedRideStore

    /// Une sortie est EN COURS (enregistrement actif, en pause, ou points non terminés).
    var isInProgress: Bool { state != .idle || pointCount > 0 }

    /// Enregistrement possible en arrière-plan : autorisation "Lors de l'utilisation" (suffisante
    /// pour une session démarrée au premier plan, avec le mode arrière-plan) ou "Toujours".
    var canRecordInBackground: Bool {
        authorizationStatus == .authorizedWhenInUse || authorizationStatus == .authorizedAlways
    }

    init(
        settings: RideSettingsStore,
        source: RecordingLocationSource? = nil,
        journal: RideRecordingJournal? = nil,
        unsavedRideStore: UnsavedRideStore? = nil
    ) {
        self.settings = settings
        self.source = source ?? CoreLocationRecordingSource()
        self.journal = journal ?? RideRecordingJournal()
        self.unsavedRideStore = unsavedRideStore ?? UnsavedRideStore()
        authorizationStatus = self.source.authorizationStatus
        self.source.onLocation = { [weak self] location in self?.ingest(location) }
        self.source.onAuthorizationChange = { [weak self] status in self?.authorizationDidChange(status) }
        restoreFromJournal()
    }

    // MARK: - Actions utilisateur

    @discardableResult
    func start() -> StartOutcome {
        switch authorizationStatus {
        case .denied, .restricted:
            return .denied
        case .notDetermined:
            startWhenAuthorized = true
            source.requestAuthorization()
            return .awaitingAuthorization
        default:
            break
        }
        if state == .idle, pointCount == 0 {
            sessionID = UUID()
            sessionStartedAt = Date()
            journal.begin(sessionID: sessionID ?? UUID(), startedAt: sessionStartedAt ?? Date())
        }
        state = .recording
        wasRestoredAfterInterruption = false
        source.startBackgroundUpdates()
        return .started
    }

    func pause() {
        guard state == .recording else { return }
        state = .paused
        startWhenAuthorized = false
        source.stopUpdates()
    }

    @discardableResult
    func resume() -> StartOutcome {
        guard state == .paused else { return state == .recording ? .started : start() }
        return start()
    }

    /// Fin de sortie (après enregistrement dans la Bibliothèque, ou abandon explicite) : GPS
    /// coupé, journal et secours supprimés, prêt pour une nouvelle sortie.
    func finish() {
        source.stopUpdates()
        startWhenAuthorized = false
        if let sessionID { unsavedRideStore.discard(sessionID: sessionID) }
        journal.clear()
        state = .idle
        points = []
        pointCount = 0
        sessionID = nil
        sessionStartedAt = nil
        lastRecordedLocation = nil
        wasRestoredAfterInterruption = false
    }

    // MARK: - Points

    /// `internal` pour les tests ; en production, appelé par la source GPS.
    func ingest(_ location: CLLocation) {
        guard state == .recording else { return }
        let preset = settings.recordingDensityPreset
        if let last = lastRecordedLocation {
            let elapsed = location.timestamp.timeIntervalSince(last.timestamp)
            let distance = location.distance(from: last)
            guard elapsed >= preset.minIntervalSeconds || distance >= preset.minDistanceMeters else { return }
        }
        lastRecordedLocation = location
        let point = GPXPoint(
            latitude: location.coordinate.latitude,
            longitude: location.coordinate.longitude,
            elevation: location.verticalAccuracy >= 0 ? location.altitude : nil,
            time: location.timestamp
        )
        points.append(point)
        pointCount = points.count
        journal.append(point)
        checkpointUnsavedRideIfNeeded()
    }

    /// Distance parcourue enregistrée.
    var recordedDistanceMeters: Double {
        zip(points, points.dropFirst()).reduce(0) { $0 + RoadbookAnalyzer.distanceMeters($1.0.coordinate, $1.1.coordinate) }
    }

    // MARK: - Autorisation

    private func authorizationDidChange(_ status: CLAuthorizationStatus) {
        authorizationStatus = status
        switch status {
        case .authorizedWhenInUse, .authorizedAlways:
            if startWhenAuthorized {
                startWhenAuthorized = false
                start()
            }
        case .denied, .restricted:
            startWhenAuthorized = false
            if state == .recording { pause() }
        default:
            break
        }
    }

    // MARK: - Persistance

    private func restoreFromJournal() {
        guard let restored = journal.load(), !restored.points.isEmpty else {
            journal.clear()
            return
        }
        sessionID = restored.sessionID
        sessionStartedAt = restored.startedAt
        points = restored.points
        pointCount = points.count
        if let last = points.last {
            lastRecordedLocation = CLLocation(coordinate: last.coordinate, altitude: last.elevation ?? 0, horizontalAccuracy: 5, verticalAccuracy: last.elevation == nil ? -1 : 5, timestamp: last.time ?? Date())
        }
        // Jamais de reprise automatique : l'utilisateur relance ou termine.
        state = .paused
        wasRestoredAfterInterruption = true
    }

    private func checkpointUnsavedRideIfNeeded() {
        guard let sessionID, let startedAt = sessionStartedAt,
              points.count % RideConstants.unsavedRideCheckpointEveryNPoints == 0
        else { return }
        let data = GPXExporter.export(
            trackName: String(localized: "Sortie non enregistrée – \(Self.unsavedRideNameDateFormatter.string(from: startedAt))", bundle: .appLanguage),
            points: points,
            waypoints: [],
            comment: nil
        )
        unsavedRideStore.checkpoint(sessionID: sessionID, startedAt: startedAt, gpxData: data, pointCount: points.count, maxRetained: settings.unsavedRideRetentionLimit)
    }

    private static var unsavedRideNameDateFormatter: DateFormatter {
        let formatter = DateFormatter()
        formatter.locale = AppLanguageBundle.locale
        formatter.setLocalizedDateFormatFromTemplate("d MMM yyyy HH:mm")
        return formatter
    }
}

// MARK: - Source GPS

/// GPS de l'enregistrement — abstrait pour les tests (aucun vrai GPS, vérification de l'état
/// arrière-plan).
@MainActor
protocol RecordingLocationSource: AnyObject {
    var onLocation: ((CLLocation) -> Void)? { get set }
    var onAuthorizationChange: ((CLAuthorizationStatus) -> Void)? { get set }
    var authorizationStatus: CLAuthorizationStatus { get }
    /// GPS actif ET autorisé en arrière-plan (indicateur bleu) — vrai seulement pendant un
    /// enregistrement.
    var isUpdatingInBackground: Bool { get }
    func requestAuthorization()
    func startBackgroundUpdates()
    func stopUpdates()
}

/// `CLLocationManager` dédié à l'enregistrement, DISTINCT de celui du guidage Ride (qui, lui,
/// s'arrête hors de l'onglet Ride).
///
/// Autorisation : "Lors de l'utilisation" suffit. Une session démarrée au premier plan continue en
/// arrière-plan et écran verrouillé grâce à `UIBackgroundModes: location` +
/// `allowsBackgroundLocationUpdates` (et `CLBackgroundActivitySession` sur iOS 17+), avec
/// l'indicateur bleu d'iOS. "Toujours" n'apporterait rien ici : même avec lui, iOS ne relance pas
/// une app tuée pour des mises à jour GPS standard. D'où la persistance point par point.
@MainActor
final class CoreLocationRecordingSource: NSObject, RecordingLocationSource, CLLocationManagerDelegate {
    var onLocation: ((CLLocation) -> Void)?
    var onAuthorizationChange: ((CLAuthorizationStatus) -> Void)?
    private(set) var isUpdatingInBackground = false

    private let manager = CLLocationManager()
    /// `CLBackgroundActivitySession` (iOS 17+), gardé en `Any` : cible de déploiement iOS 16.
    private var backgroundSession: Any?

    override init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyBest
        manager.distanceFilter = kCLDistanceFilterNone
        manager.activityType = .automotiveNavigation
        // Jamais de pause automatique d'iOS (arrêt au feu, pause café) : trou dans la trace.
        manager.pausesLocationUpdatesAutomatically = false
    }

    var authorizationStatus: CLAuthorizationStatus { manager.authorizationStatus }

    func requestAuthorization() {
        manager.requestWhenInUseAuthorization()
    }

    func startBackgroundUpdates() {
        manager.allowsBackgroundLocationUpdates = true
        manager.showsBackgroundLocationIndicator = true
        if #available(iOS 17.0, *), backgroundSession == nil {
            backgroundSession = CLBackgroundActivitySession()
        }
        manager.startUpdatingLocation()
        isUpdatingInBackground = true
    }

    func stopUpdates() {
        manager.stopUpdatingLocation()
        manager.allowsBackgroundLocationUpdates = false
        if #available(iOS 17.0, *) {
            (backgroundSession as? CLBackgroundActivitySession)?.invalidate()
        }
        backgroundSession = nil
        isUpdatingInBackground = false
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        Task { @MainActor in
            for location in locations { self.onLocation?(location) }
        }
    }

    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        let status = manager.authorizationStatus
        Task { @MainActor in self.onAuthorizationChange?(status) }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {}
}

// MARK: - Journal sur disque

/// Journal de l'enregistrement en cours : une ligne JSON par point, AJOUTÉE à chaque point
/// (jamais de réécriture complète). `Documents/RideRecording/journal.jsonl`. Première ligne :
/// identifiant et début de session.
final class RideRecordingJournal {
    struct Restored {
        let sessionID: UUID
        let startedAt: Date
        let points: [GPXPoint]
    }

    private struct Header: Codable {
        let sessionID: UUID
        let startedAt: Date
    }

    private struct Line: Codable {
        let lat: Double
        let lon: Double
        let ele: Double?
        let time: Date?
    }

    private let fileManager = FileManager.default
    let fileURL: URL
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    init(directoryOverride: URL? = nil) {
        let directory = directoryOverride
            ?? FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0].appendingPathComponent("RideRecording", isDirectory: true)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        fileURL = directory.appendingPathComponent("journal.jsonl")
        encoder.dateEncodingStrategy = .iso8601
        decoder.dateDecodingStrategy = .iso8601
    }

    func begin(sessionID: UUID, startedAt: Date) {
        guard let header = try? encoder.encode(Header(sessionID: sessionID, startedAt: startedAt)) else { return }
        try? (header + Data("\n".utf8)).write(to: fileURL, options: .atomic)
    }

    func append(_ point: GPXPoint) {
        guard let line = try? encoder.encode(Line(lat: point.latitude, lon: point.longitude, ele: point.elevation, time: point.time)),
              let handle = try? FileHandle(forWritingTo: fileURL)
        else { return }
        defer { try? handle.close() }
        _ = try? handle.seekToEnd()
        try? handle.write(contentsOf: line + Data("\n".utf8))
    }

    /// Une ligne tronquée (arrêt pendant l'écriture) est ignorée, les autres restent valides.
    func load() -> Restored? {
        guard let data = try? Data(contentsOf: fileURL) else { return nil }
        let lines = data.split(separator: UInt8(ascii: "\n"))
        guard let first = lines.first, let header = try? decoder.decode(Header.self, from: Data(first)) else { return nil }
        let points = lines.dropFirst().compactMap { try? decoder.decode(Line.self, from: Data($0)) }
            .map { GPXPoint(latitude: $0.lat, longitude: $0.lon, elevation: $0.ele, time: $0.time) }
        return Restored(sessionID: header.sessionID, startedAt: header.startedAt, points: points)
    }

    func clear() {
        try? fileManager.removeItem(at: fileURL)
    }
}
