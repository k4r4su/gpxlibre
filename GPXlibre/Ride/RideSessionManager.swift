import Foundation
import CoreLocation
import UIKit

enum RideContext {
    case track, normal, fastRoad
}

/// Pilote la session Ride : localisation haute précision, lissage vitesse, zoom auto,
/// et progression du roadbook. Ne tourne QUE pendant que l'onglet Ride est actif
/// (start()/stop() appelés par RideView.onAppear/onDisappear).
@MainActor
final class RideSessionManager: NSObject, ObservableObject, CLLocationManagerDelegate {
    @Published private(set) var currentLocation: CLLocation?
    @Published private(set) var headingDegrees: CLLocationDirection = 0
    @Published private(set) var smoothedSpeedKmh: Double = 0
    @Published private(set) var cameraDistanceMeters: Double
    @Published private(set) var rideContext: RideContext = .normal
    @Published private(set) var checkpoints: [Checkpoint] = []
    @Published private(set) var currentCheckpointIndex: Int = 0
    @Published private(set) var distanceToCurrentCheckpointMeters: Double?
    @Published private(set) var isCloseToCheckpoint: Bool = false
    /// Change de valeur à chaque déclenchement d'alerte : FlashOverlayView observe ce token.
    @Published var flashSequenceToken: UUID?

    // MARK: - Chemin bloqué / détour (la trace originale reste affichée et n'est jamais modifiée)
    @Published private(set) var distanceOffTrackMeters: Double = 0
    @Published private(set) var isBlockedBannerVisible = false
    @Published private(set) var detourRoute: DetourRoute?
    @Published private(set) var isRequestingDetour = false
    @Published private(set) var detourRequestFailed = false

    // MARK: - Mesures en cours
    @Published private(set) var averageSpeedKmh: Double = 0
    @Published private(set) var maxSpeedKmh: Double = 0
    @Published private(set) var distanceRemainingMeters: Double?
    @Published private(set) var percentComplete: Double?
    @Published private(set) var estimatedArrivalDate: Date?

    // MARK: - Enregistrement automatique de la sortie (persiste across tab switches, voir start())
    @Published private(set) var recordedPointsCount = 0
    private(set) var recordedPoints: [GPXPoint] = []
    private var recordingTrackID: UUID?
    private var lastRecordedLocation: CLLocation?
    private var lastRecordedDate: Date?
    @Published private(set) var isRecordingPaused = false

    // MARK: - Aller à universel (Bloc 4) — guidage PARALLÈLE, jamais un remplacement de la
    // trace sacrée ni de la route Nav principale. Fonctionne en Mode Trace ET Mode Nav.
    @Published private(set) var goToGuidance: GoToGuidance?
    @Published private(set) var goToDistanceRemainingMeters: Double?
    @Published private(set) var isRequestingGoTo = false
    @Published var goToRequestFailed: String?
    private var goToTask: Task<Void, Never>?

    // MARK: - Mode Nav (guidage A→B, recalcul automatique — jamais en Mode Trace)
    @Published private(set) var navRoute: NavRoute?
    @Published private(set) var isRoutingInProgress = false
    @Published private(set) var navRoutingError: String?
    @Published private(set) var currentManeuverIndex = 0
    @Published private(set) var distanceToCurrentManeuverMeters: Double?
    @Published private(set) var isRecalculatingRoute = false

    private var navDestinationCoordinate: CLLocationCoordinate2D?
    private var navDestinationLabel = ""
    private var navRoutePoints: [GPXPoint] = []
    private var navRouteCumulativeDistances: [Double] = []
    private var announcedManeuverThresholds: [Int: Set<Double>] = [:]
    private var navOffRouteSinceDate: Date?
    private var navRoutingTask: Task<Void, Never>?
    private let voiceAnnouncer = NavVoiceAnnouncer()

    // MARK: - Limite de vitesse (Mode Nav, OSM maxspeed, silencieux si absent)
    @Published private(set) var currentSpeedLimitKmh: Int?
    @Published private(set) var isOverSpeedLimit = false
    private var lastSpeedLimitLookupDate: Date?

    var currentManeuver: NavManeuver? {
        guard let navRoute, navRoute.maneuvers.indices.contains(currentManeuverIndex) else { return nil }
        return navRoute.maneuvers[currentManeuverIndex]
    }

    private let manager = CLLocationManager()
    private let settings: RideSettingsStore
    private let networkMonitor: NetworkMonitor
    private let modeStore: RideModeStore
    private let blockageLog = BlockageLogStore()
    private let sharedBlockages: SharedBlockageSyncCoordinator
    private var track: GPXTrack?
    private var trackCumulativeDistances: [Double] = []

    private var speedSamples: [(date: Date, speedMps: Double)] = []
    private var currentBucketIndex: Int = 0
    private var fastSpeedSustainedSince: Date?
    private var flashedCheckpointIDs: Set<UUID> = []
    private var hapticCheckpointIDs: Set<UUID> = []
    private let hapticGenerator = UIImpactFeedbackGenerator(style: .heavy)
    private let detourClearedHapticGenerator = UINotificationFeedbackGenerator()

    private var offTrackSinceDate: Date?
    private var offTrackAccumulatedDistance: Double = 0
    private var lastOffTrackLocation: CLLocation?
    private var detourTask: Task<Void, Never>?

    private var rideStartDate: Date?
    private var totalDistanceTraveledMeters: Double = 0
    private var lastLocationForDistance: CLLocation?

    var lastManualGestureDate: Date?

    // MARK: - Contrôles "gants" (zoom +/- discret, recentrer)
    @Published private(set) var manualZoomDistanceMeters: Double?
    /// Change à chaque tap +/- ou recentrage : force la carte à appliquer la caméra tout de
    /// suite, même pendant la fenêtre d'override manuel (sinon un tap immédiatement après un
    /// pinch resterait sans effet visible).
    @Published private(set) var cameraCommandToken: UUID?

    var isManualOverrideActive: Bool {
        guard let date = lastManualGestureDate else { return false }
        return Date().timeIntervalSince(date) < RideConstants.manualZoomOverrideTimeoutSeconds
    }

    /// Distance caméra effective : le palier manuel prime tant qu'il est actif, sinon l'auto.
    var effectiveCameraDistanceMeters: Double {
        manualZoomDistanceMeters ?? cameraDistanceMeters
    }

    func zoomIn() { adjustManualZoom(factor: RideConstants.manualZoomStepFactor) }
    func zoomOut() { adjustManualZoom(factor: 1 / RideConstants.manualZoomStepFactor) }

    private func adjustManualZoom(factor: Double) {
        let base = manualZoomDistanceMeters ?? cameraDistanceMeters
        let newValue = min(max(base * factor, RideConstants.manualZoomMinMeters), RideConstants.manualZoomMaxMeters)
        manualZoomDistanceMeters = newValue
        lastManualGestureDate = Date()
        cameraCommandToken = UUID()
    }

    /// Re-snappe la caméra sur la position et repasse en mode suivre-cap immédiatement
    /// (n'attend pas l'expiration des 5 s d'override).
    func recenterCamera() {
        manualZoomDistanceMeters = nil
        lastManualGestureDate = nil
        cameraCommandToken = UUID()
    }

    var currentCheckpoint: Checkpoint? {
        checkpoints.indices.contains(currentCheckpointIndex) ? checkpoints[currentCheckpointIndex] : nil
    }

    /// Mini preview roadbook (spec "roadbook-declutter") : le motard voit qu'il y a un
    /// deuxième virage à venir sans avoir à lire le détail.
    var nextCheckpoint: Checkpoint? {
        let nextIndex = currentCheckpointIndex + 1
        return checkpoints.indices.contains(nextIndex) ? checkpoints[nextIndex] : nil
    }

    var remainingCheckpointsCount: Int {
        max(checkpoints.count - currentCheckpointIndex, 0)
    }

    init(settings: RideSettingsStore, networkMonitor: NetworkMonitor, modeStore: RideModeStore, sharedBlockages: SharedBlockageSyncCoordinator) {
        self.settings = settings
        self.networkMonitor = networkMonitor
        self.modeStore = modeStore
        self.sharedBlockages = sharedBlockages
        self.cameraDistanceMeters = ZoomPreset.normal.buckets.first?.cameraDistanceMeters ?? 300
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyBestForNavigation
        manager.distanceFilter = RideConstants.rideDistanceFilterMeters
        manager.activityType = .automotiveNavigation
    }

    private(set) var isActive = false

    /// `track` est optionnel : en Mode Nav, aucune trace GPX n'est nécessaire pour naviguer
    /// A→B. En Mode Trace, une trace est requise (voir RideView, qui gère l'état vide).
    func start(track: GPXTrack?) {
        self.track = track
        isActive = true
        speedSamples.removeAll()
        fastSpeedSustainedSince = nil
        currentBucketIndex = 0
        rideContext = .normal
        hapticGenerator.prepare()
        detourClearedHapticGenerator.prepare()

        if let track {
            trackCumulativeDistances = TrackProjector.cumulativeDistances(for: track.points)
            rebuildCheckpoints()
            resetBlockedPathState()

            rideStartDate = Date()
            totalDistanceTraveledMeters = 0
            lastLocationForDistance = nil
            averageSpeedKmh = 0
            maxSpeedKmh = 0
            distanceRemainingMeters = track.totalDistanceMeters
            percentComplete = 0
            estimatedArrivalDate = nil

            // L'enregistrement de la sortie persiste tant que c'est la même trace (ne
            // redémarre pas à chaque va-et-vient vers un autre onglet) ; seule une trace
            // différente ou resetRecording() (après export) le réinitialise.
            if recordingTrackID != track.id {
                recordedPoints = []
                recordedPointsCount = 0
                recordingTrackID = track.id
                lastRecordedLocation = nil
                lastRecordedDate = nil
            }
        } else {
            trackCumulativeDistances = []
            checkpoints = []
        }

        manager.requestWhenInUseAuthorization()
        manager.startUpdatingLocation()
        applyIdleTimerSetting()
        syncSharedBlockagesIfNeeded()
    }

    /// Synchro Bloc 5 : "une fois par jour + à chaque lancement" — déclenchée ici (ouverture
    /// de l'onglet Ride) et à chaque mise à jour de position tant qu'aucune trace n'est
    /// chargée (Mode Nav), le garde-fou anti-rafale étant porté par le coordinateur lui-même.
    private func syncSharedBlockagesIfNeeded() {
        let bbox: SharedBlockageBBox?
        if let track {
            bbox = SharedBlockageBBox.around(trackPoints: track.points.map(\.coordinate))
        } else if let currentLocation {
            bbox = SharedBlockageBBox.around(location: currentLocation.coordinate)
        } else {
            bbox = nil
        }
        sharedBlockages.syncIfNeeded(
            bbox: bbox,
            serverURLString: settings.sharedBlockageServerURLString,
            isReachable: networkMonitor.isReachable,
            isEnabled: settings.shareBlockagesAnonymously
        )
    }

    func stop() {
        isActive = false
        manager.stopUpdatingLocation()
        UIApplication.shared.isIdleTimerDisabled = false
        detourTask?.cancel()
    }

    private func resetBlockedPathState() {
        distanceOffTrackMeters = 0
        isBlockedBannerVisible = false
        detourRoute = nil
        isRequestingDetour = false
        detourRequestFailed = false
        offTrackSinceDate = nil
        offTrackAccumulatedDistance = 0
        lastOffTrackLocation = nil
        detourTask?.cancel()
    }

    /// N'agit que si le mode Ride est actif : évite qu'un changement de réglage fait
    /// depuis un autre onglet ne bloque la mise en veille du téléphone hors Ride.
    func applyIdleTimerSetting() {
        guard isActive else { return }
        UIApplication.shared.isIdleTimerDisabled = settings.keepScreenAwakeInRide
    }

    /// Recalcule les checkpoints (ex : l'utilisateur change le seuil d'angle dans Réglages).
    /// Prend effet immédiatement, pas besoin de relancer l'app.
    func rebuildCheckpoints() {
        guard let track else { return }
        checkpoints = RoadbookAnalyzer.buildCheckpoints(
            for: track,
            turnThresholdDegrees: settings.turnThresholdDegrees,
            turnMergeMinDistanceMeters: settings.turnMergeMinDistanceMeters
        )
        currentCheckpointIndex = 0
        distanceToCurrentCheckpointMeters = nil
        isCloseToCheckpoint = false
        flashedCheckpointIDs.removeAll()
        hapticCheckpointIDs.removeAll()
    }

    func registerManualGesture() {
        lastManualGestureDate = Date()
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let location = locations.last else { return }
        Task { @MainActor in
            self.handle(location: location)
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {}

    private func handle(location: CLLocation) {
        currentLocation = location

        let speedMps = max(location.speed, 0)
        speedSamples.append((location.timestamp, speedMps))
        // Fenêtre la plus large des deux besoins (zoom auto 10 s, ETA 5 min) ; chacune
        // re-filtre ensuite ce même buffer sur sa propre durée.
        let retentionWindow = max(RideConstants.speedSmoothingWindowSeconds, RideConstants.etaSpeedWindowSeconds)
        let retentionCutoff = location.timestamp.addingTimeInterval(-retentionWindow)
        speedSamples.removeAll { $0.date < retentionCutoff }

        let shortWindowCutoff = location.timestamp.addingTimeInterval(-RideConstants.speedSmoothingWindowSeconds)
        let shortSamples = speedSamples.filter { $0.date >= shortWindowCutoff }
        let shortAvgMps = shortSamples.map(\.speedMps).reduce(0, +) / Double(max(shortSamples.count, 1))
        smoothedSpeedKmh = shortAvgMps * 3.6

        let etaWindowCutoff = location.timestamp.addingTimeInterval(-RideConstants.etaSpeedWindowSeconds)
        let etaSamples = speedSamples.filter { $0.date >= etaWindowCutoff }
        let etaAvgMps = etaSamples.map(\.speedMps).reduce(0, +) / Double(max(etaSamples.count, 1))
        let etaSpeedKmh = etaAvgMps * 3.6

        if location.course >= 0, speedMps > 0.5 {
            headingDegrees = location.course
        }

        maxSpeedKmh = max(maxSpeedKmh, speedMps * 3.6)
        if let last = lastLocationForDistance {
            totalDistanceTraveledMeters += location.distance(from: last)
        }
        lastLocationForDistance = location
        if let rideStartDate {
            let elapsedHours = Date().timeIntervalSince(rideStartDate) / 3600
            averageSpeedKmh = elapsedHours > 0 ? (totalDistanceTraveledMeters / 1000) / elapsedHours : 0
        }

        updateRideContext()
        updateZoomBucket()

        switch modeStore.mode {
        case .trace:
            updateRoadbookProgress(from: location)
            let projection = updateBlockedPathTracking(from: location)
            updateRideStats(from: location, projection: projection, etaSpeedKmh: etaSpeedKmh)
        case .nav:
            updateNavProgress(from: location, etaSpeedKmh: etaSpeedKmh)
        }

        updateGoToGuidance(from: location)
        recordRideTrack(location: location)

        if track == nil {
            syncSharedBlockagesIfNeeded()
        }
    }

    /// Enregistre un point dès que l'un des deux seuils est atteint (5 s OU 15 m, le plus
    /// fréquent des deux) — tourne automatiquement pendant tout le Ride, aucune action requise.
    /// Suspendu après un Stop (voir stopGuidance()) tant que l'enregistrement n'a pas repris.
    private func recordRideTrack(location: CLLocation) {
        guard !isRecordingPaused else { return }
        let shouldRecord: Bool
        if let lastDate = lastRecordedDate, let lastLocation = lastRecordedLocation {
            let elapsed = location.timestamp.timeIntervalSince(lastDate)
            let distance = location.distance(from: lastLocation)
            shouldRecord = elapsed >= RecordingConstants.minIntervalSeconds || distance >= RecordingConstants.minDistanceMeters
        } else {
            shouldRecord = true
        }
        guard shouldRecord else { return }

        lastRecordedDate = location.timestamp
        lastRecordedLocation = location
        recordedPoints.append(GPXPoint(
            latitude: location.coordinate.latitude,
            longitude: location.coordinate.longitude,
            elevation: location.verticalAccuracy >= 0 ? location.altitude : nil,
            time: location.timestamp
        ))
        recordedPointsCount = recordedPoints.count
    }

    /// À appeler après un export réussi (voir EndRideView) pour repartir d'un enregistrement vide.
    func resetRecording() {
        recordedPoints = []
        recordedPointsCount = 0
        recordingTrackID = nil
        lastRecordedLocation = nil
        lastRecordedDate = nil
        isRecordingPaused = false
    }

    /// Distance totale de la portion enregistrée — sert à décider si un export est proposé
    /// après un Stop (> 1 km, voir stopGuidance()).
    var recordedDistanceMeters: Double {
        guard recordedPoints.count > 1 else { return 0 }
        var total: Double = 0
        for i in 1..<recordedPoints.count {
            total += RoadbookAnalyzer.distanceMeters(recordedPoints[i - 1].coordinate, recordedPoints[i].coordinate)
        }
        return total
    }

    private func updateRideStats(from location: CLLocation, projection: TrackProjector.Projection?, etaSpeedKmh: Double) {
        guard let track, let projection else { return }
        let remaining = max(track.totalDistanceMeters - projection.cumulativeDistanceMeters, 0)
        distanceRemainingMeters = remaining
        percentComplete = track.totalDistanceMeters > 0
            ? min(100, max(0, projection.cumulativeDistanceMeters / track.totalDistanceMeters * 100))
            : 0

        guard etaSpeedKmh >= RideConstants.etaSilenceSpeedThresholdKmh else {
            estimatedArrivalDate = nil
            return
        }
        let remainingHours = (remaining / 1000) / etaSpeedKmh
        estimatedArrivalDate = Date().addingTimeInterval(remainingHours * 3600)
    }

    private func updateRideContext() {
        if smoothedSpeedKmh > RideConstants.fastRoadSpeedThresholdKmh {
            if fastSpeedSustainedSince == nil { fastSpeedSustainedSince = Date() }
            if let since = fastSpeedSustainedSince,
               Date().timeIntervalSince(since) >= RideConstants.fastRoadSustainedDurationSeconds {
                rideContext = .fastRoad
            }
        } else {
            fastSpeedSustainedSince = nil
            if smoothedSpeedKmh < RideConstants.trackSpeedThresholdKmh {
                rideContext = .track
            } else if rideContext == .fastRoad {
                rideContext = .normal
            }
        }
    }

    private func updateZoomBucket() {
        let buckets = settings.zoomPreset.buckets
        guard !buckets.isEmpty else { return }
        currentBucketIndex = min(currentBucketIndex, buckets.count - 1)

        let proposedIndex = buckets.firstIndex { smoothedSpeedKmh <= $0.speedUpToKmh } ?? buckets.count - 1

        if proposedIndex != currentBucketIndex {
            let movingUp = proposedIndex > currentBucketIndex
            let boundary = buckets[movingUp ? currentBucketIndex : proposedIndex].speedUpToKmh
            let margin = RideConstants.zoomHysteresisMarginKmh
            let crossedWithMargin = movingUp ? smoothedSpeedKmh > boundary + margin : smoothedSpeedKmh < boundary - margin
            if crossedWithMargin {
                currentBucketIndex = proposedIndex
            }
        }

        var distance = buckets[currentBucketIndex].cameraDistanceMeters
        switch rideContext {
        case .fastRoad: distance *= RideConstants.fastRoadCameraDistanceMultiplier
        case .track: distance *= RideConstants.trackCameraDistanceMultiplier
        case .normal: break
        }
        cameraDistanceMeters = distance
    }

    private var activeAlertDistanceMeters: Double {
        rideContext == .fastRoad ? RideConstants.fastRoadAlertDistanceMeters : settings.checkpointAlertDistanceMeters
    }

    private func updateRoadbookProgress(from location: CLLocation) {
        guard currentCheckpointIndex < checkpoints.count else {
            distanceToCurrentCheckpointMeters = nil
            isCloseToCheckpoint = false
            return
        }

        let checkpoint = checkpoints[currentCheckpointIndex]
        let distance = RoadbookAnalyzer.distanceMeters(location.coordinate, checkpoint.coordinate)
        distanceToCurrentCheckpointMeters = distance

        if distance <= RideConstants.checkpointPassedRadiusMeters {
            currentCheckpointIndex += 1
            isCloseToCheckpoint = false
            return
        }

        if distance <= activeAlertDistanceMeters, !flashedCheckpointIDs.contains(checkpoint.id) {
            flashedCheckpointIDs.insert(checkpoint.id)
            flashSequenceToken = UUID()
        }

        if distance <= RideConstants.checkpointCloseRadiusMeters {
            isCloseToCheckpoint = true
            if !hapticCheckpointIDs.contains(checkpoint.id) {
                hapticCheckpointIDs.insert(checkpoint.id)
                hapticGenerator.impactOccurred()
            }
        } else {
            isCloseToCheckpoint = false
        }
    }

    // MARK: - Chemin bloqué / détour

    @discardableResult
    private func updateBlockedPathTracking(from location: CLLocation) -> TrackProjector.Projection? {
        guard let track, !trackCumulativeDistances.isEmpty,
              let projection = TrackProjector.project(location.coordinate, onto: track.points, cumulativeDistances: trackCumulativeDistances)
        else { return nil }

        distanceOffTrackMeters = projection.distanceToTrackMeters

        if let detour = detourRoute {
            let distanceToTarget = RoadbookAnalyzer.distanceMeters(location.coordinate, detour.targetCoordinate)
            if projection.distanceToTrackMeters <= RideConstants.detourRejoinClearRadiusMeters
                || distanceToTarget <= RideConstants.detourRejoinClearRadiusMeters {
                clearDetour(haptic: true)
            }
        }

        guard detourRoute == nil else { return projection }

        if projection.distanceToTrackMeters > RideConstants.offTrackDistanceThresholdMeters {
            if offTrackSinceDate == nil {
                offTrackSinceDate = location.timestamp
                offTrackAccumulatedDistance = 0
            } else if let last = lastOffTrackLocation {
                offTrackAccumulatedDistance += location.distance(from: last)
            }
            lastOffTrackLocation = location

            let elapsed = location.timestamp.timeIntervalSince(offTrackSinceDate ?? location.timestamp)
            if !isBlockedBannerVisible,
               elapsed >= RideConstants.offTrackStagnantDurationSeconds
                || offTrackAccumulatedDistance >= RideConstants.offTrackStagnantDistanceMeters {
                isBlockedBannerVisible = true
            }
        } else {
            offTrackSinceDate = nil
            offTrackAccumulatedDistance = 0
            lastOffTrackLocation = nil
            isBlockedBannerVisible = false
        }

        return projection
    }

    /// Déclenché par le bouton manuel "Chemin bloqué", toujours visible en Ride — même flow
    /// que la détection automatique.
    func userReportedBlockedPath() {
        isBlockedBannerVisible = true
    }

    func dismissBlockedPathBanner() {
        isBlockedBannerVisible = false
    }

    /// Lance un contournement en ligne (OSRM public) vers un point de la trace situé
    /// 500 m–2 km plus loin. La trace originale reste affichée et intacte.
    func requestDetour(profile: DetourProfile) {
        guard let track, let location = currentLocation, !trackCumulativeDistances.isEmpty else { return }
        detourTask?.cancel()
        isBlockedBannerVisible = false
        detourRequestFailed = false

        guard networkMonitor.isReachable else {
            requestDirectDetour()
            return
        }

        let projection = TrackProjector.project(location.coordinate, onto: track.points, cumulativeDistances: trackCumulativeDistances)
        let baseCumulative = projection?.cumulativeDistanceMeters ?? 0
        let candidates = TrackProjector.rejoinCandidates(
            in: track.points,
            cumulativeDistances: trackCumulativeDistances,
            afterCumulativeDistance: baseCumulative,
            minAhead: RideConstants.detourAheadMinMeters,
            maxAhead: RideConstants.detourAheadMaxMeters,
            step: RideConstants.detourAheadStepMeters
        )
        guard !candidates.isEmpty else {
            requestDirectDetour()
            return
        }

        isRequestingDetour = true
        detourTask = Task { [weak self] in
            guard let self else { return }
            do {
                let result = try await DetourRoutingService.requestRoute(from: location.coordinate, candidates: candidates, profile: profile)
                guard !Task.isCancelled else { return }
                await MainActor.run {
                    self.detourRoute = result
                    self.isRequestingDetour = false
                    self.blockageLog.append(BlockageEvent(coordinate: location.coordinate, resolvedOnline: true), for: track.id)
                    self.reportBlockageIfSharingEnabled(at: location.coordinate)
                }
            } catch {
                guard !Task.isCancelled else { return }
                await MainActor.run {
                    self.isRequestingDetour = false
                    self.detourRequestFailed = true
                    self.requestDirectDetour()
                }
            }
        }
    }

    /// Guidage minimum sans réseau : flèche directe + distance jusqu'au point de la trace
    /// le plus proche au-delà de la zone bloquée. Aucune prétention de recalcul d'itinéraire.
    func requestDirectDetour() {
        guard let track, let location = currentLocation, !trackCumulativeDistances.isEmpty else { return }
        isBlockedBannerVisible = false

        let projection = TrackProjector.project(location.coordinate, onto: track.points, cumulativeDistances: trackCumulativeDistances)
        let baseCumulative = projection?.cumulativeDistanceMeters ?? 0
        guard let target = TrackProjector.coordinate(
            in: track.points,
            cumulativeDistances: trackCumulativeDistances,
            atCumulativeDistance: baseCumulative + RideConstants.detourAheadMinMeters
        ) else { return }

        detourRoute = DetourRoute(coordinates: [location.coordinate, target], mode: .direct, targetCoordinate: target, startedAt: Date())
        blockageLog.append(BlockageEvent(coordinate: location.coordinate, resolvedOnline: false), for: track.id)
        reportBlockageIfSharingEnabled(at: location.coordinate)
    }

    /// Signalement anonyme sortant (spec Bloc 5, toggle "partager anonymement" par défaut
    /// ON dans Réglages) — même point que le journal 100% local ci-dessus, best-effort,
    /// n'affecte jamais le flow de détour qui l'a déclenché.
    private func reportBlockageIfSharingEnabled(at coordinate: CLLocationCoordinate2D) {
        sharedBlockages.report(
            coordinate: coordinate,
            note: nil,
            serverURLString: settings.sharedBlockageServerURLString,
            isReachable: networkMonitor.isReachable,
            isEnabled: settings.shareBlockagesAnonymously
        )
    }

    func cancelDetour() {
        clearDetour(haptic: false)
    }

    private func clearDetour(haptic: Bool) {
        detourTask?.cancel()
        detourRoute = nil
        isRequestingDetour = false
        detourRequestFailed = false
        offTrackSinceDate = nil
        offTrackAccumulatedDistance = 0
        lastOffTrackLocation = nil
        if haptic {
            detourClearedHapticGenerator.notificationOccurred(.success)
        }
    }

    // MARK: - Mode Nav (guidage A→B)

    /// Démarre un guidage vers `destination`. Recalcule automatiquement en cas d'écart —
    /// c'est le principe même du Mode Nav, à l'opposé du Mode Trace.
    func startNav(to destination: CLLocationCoordinate2D, label: String) {
        navDestinationCoordinate = destination
        navDestinationLabel = label
        currentManeuverIndex = 0
        announcedManeuverThresholds = [:]
        navOffRouteSinceDate = nil
        navRoutingError = nil
        voiceAnnouncer.stop()
        requestNavRoute()
    }

    func stopNav() {
        navRoutingTask?.cancel()
        navRoute = nil
        navDestinationCoordinate = nil
        navRoutePoints = []
        navRouteCumulativeDistances = []
        distanceToCurrentManeuverMeters = nil
        distanceRemainingMeters = nil
        percentComplete = nil
        estimatedArrivalDate = nil
        currentSpeedLimitKmh = nil
        isOverSpeedLimit = false
        lastSpeedLimitLookupDate = nil
        voiceAnnouncer.stop()
    }

    // MARK: - Aller à universel (Bloc 4)

    /// Lance un guidage "Aller à" PARALLÈLE (pointillés cyan) — fonctionne en Mode Trace
    /// (la trace sacrée n'est jamais touchée) comme en Mode Nav (à côté de la route
    /// principale). `.route` réutilise OSRM, `.offroad` est une ligne directe honnête (cap +
    /// distance, aucune prétention de chemin réel), `.mixed` route jusqu'au point routable le
    /// plus proche (OSRM snappe naturellement dessus) puis termine à vol d'oiseau.
    func startGoTo(to destination: CLLocationCoordinate2D, label: String, profile: GoToProfile) {
        goToTask?.cancel()
        goToRequestFailed = nil

        guard let origin = currentLocation?.coordinate else {
            goToRequestFailed = "Position GPS indisponible pour l'instant."
            return
        }

        switch profile {
        case .offroad:
            goToGuidance = GoToGuidance(coordinates: [origin, destination], profile: .offroad, destinationCoordinate: destination, destinationLabel: label)
        case .route, .mixed:
            isRequestingGoTo = true
            goToTask = Task { [weak self] in
                guard let self else { return }
                do {
                    let route = try await NavRoutingService.route(from: origin, to: destination, destinationLabel: label, networkMonitor: self.networkMonitor)
                    guard !Task.isCancelled else { return }
                    var coordinates = route.coordinates
                    if profile == .mixed, let snappedEnd = coordinates.last {
                        // OSRM a déjà "snappé" `destination` sur le point routable le plus
                        // proche : `snappedEnd` EST ce point. On complète juste par une ligne
                        // droite honnête jusqu'à la vraie destination si elle est plus loin.
                        let residual = RoadbookAnalyzer.distanceMeters(snappedEnd, destination)
                        if residual > RideConstants.detourRejoinClearRadiusMeters {
                            coordinates.append(destination)
                        }
                    }
                    await MainActor.run {
                        self.goToGuidance = GoToGuidance(coordinates: coordinates, profile: profile, destinationCoordinate: destination, destinationLabel: label)
                        self.isRequestingGoTo = false
                    }
                } catch {
                    guard !Task.isCancelled else { return }
                    await MainActor.run {
                        self.isRequestingGoTo = false
                        // Honnête : si le réseau/OSRM échoue, on ne prétend pas avoir un
                        // itinéraire — fallback automatique en ligne directe (comme .offroad).
                        self.goToRequestFailed = (error as? LocalizedError)?.errorDescription ?? "Itinéraire impossible — guidage direct."
                        self.goToGuidance = GoToGuidance(coordinates: [origin, destination], profile: .offroad, destinationCoordinate: destination, destinationLabel: label)
                    }
                }
            }
        }
    }

    func stopGoTo() {
        goToTask?.cancel()
        goToGuidance = nil
        goToDistanceRemainingMeters = nil
        goToRequestFailed = nil
        isRequestingGoTo = false
    }

    private func updateGoToGuidance(from location: CLLocation) {
        guard let guidance = goToGuidance else { return }
        goToDistanceRemainingMeters = RoadbookAnalyzer.distanceMeters(location.coordinate, guidance.destinationCoordinate)
    }

    /// Stop universel, visible en Mode Trace ET Mode Nav : état propre en 1 geste
    /// (confirmation portée par l'appelant, voir RideView). N'efface JAMAIS la trace chargée
    /// — seulement les guidages actifs (Nav, Aller à, détour) et la caméra forcée (2D).
    /// L'enregistrement est mis en pause ; l'appelant propose l'export si > 1 km.
    func stopGuidance() {
        stopNav()
        stopGoTo()
        cancelDetour()
        isRecordingPaused = true
    }

    private func requestNavRoute() {
        guard let destination = navDestinationCoordinate, let origin = currentLocation?.coordinate else {
            navRoutingError = "Position GPS indisponible pour l'instant."
            return
        }
        navRoutingTask?.cancel()
        isRoutingInProgress = true
        navRoutingError = nil

        navRoutingTask = Task { [weak self] in
            guard let self else { return }
            do {
                let route = try await NavRoutingService.route(
                    from: origin, to: destination, destinationLabel: self.navDestinationLabel, networkMonitor: self.networkMonitor
                )
                guard !Task.isCancelled else { return }
                await MainActor.run {
                    self.navRoute = route
                    self.navRoutePoints = route.coordinates.map { GPXPoint(latitude: $0.latitude, longitude: $0.longitude) }
                    self.navRouteCumulativeDistances = TrackProjector.cumulativeDistances(for: self.navRoutePoints)
                    self.currentManeuverIndex = 0
                    self.announcedManeuverThresholds = [:]
                    self.navOffRouteSinceDate = nil
                    self.isRoutingInProgress = false
                    self.isRecalculatingRoute = false
                }
            } catch {
                guard !Task.isCancelled else { return }
                await MainActor.run {
                    self.isRoutingInProgress = false
                    self.isRecalculatingRoute = false
                    self.navRoutingError = (error as? LocalizedError)?.errorDescription ?? "Calcul d'itinéraire impossible."
                }
            }
        }
    }

    private func updateNavProgress(from location: CLLocation, etaSpeedKmh: Double) {
        guard let route = navRoute else { return }

        if currentManeuverIndex < route.maneuvers.count {
            let maneuver = route.maneuvers[currentManeuverIndex]
            let distance = RoadbookAnalyzer.distanceMeters(location.coordinate, maneuver.coordinate)
            distanceToCurrentManeuverMeters = distance

            if settings.voiceGuidanceEnabled {
                var thresholds = announcedManeuverThresholds[currentManeuverIndex] ?? []
                for threshold in NavConstants.voiceAnnounceDistancesMeters where distance <= threshold && !thresholds.contains(threshold) {
                    thresholds.insert(threshold)
                    voiceAnnouncer.announce(maneuver.instructionText, volume: Float(settings.voiceGuidanceVolume))
                }
                announcedManeuverThresholds[currentManeuverIndex] = thresholds
            }

            if distance <= NavConstants.maneuverPassedRadiusMeters {
                currentManeuverIndex += 1
            }
        } else {
            distanceToCurrentManeuverMeters = nil
        }

        guard !navRouteCumulativeDistances.isEmpty,
              let projection = TrackProjector.project(location.coordinate, onto: navRoutePoints, cumulativeDistances: navRouteCumulativeDistances)
        else { return }

        let remaining = max(route.totalDistanceMeters - projection.cumulativeDistanceMeters, 0)
        distanceRemainingMeters = remaining
        percentComplete = route.totalDistanceMeters > 0
            ? min(100, max(0, projection.cumulativeDistanceMeters / route.totalDistanceMeters * 100))
            : 0
        estimatedArrivalDate = etaSpeedKmh >= RideConstants.etaSilenceSpeedThresholdKmh
            ? Date().addingTimeInterval(((remaining / 1000) / etaSpeedKmh) * 3600)
            : nil

        // Recalcul automatique et silencieux si écart > 30 m pendant > 30 s — UNIQUEMENT en
        // Mode Nav. En Mode Trace ceci n'existe pas : la trace ne se recalcule jamais.
        if projection.distanceToTrackMeters > NavConstants.offRouteDistanceThresholdMeters {
            if navOffRouteSinceDate == nil { navOffRouteSinceDate = location.timestamp }
            let elapsed = location.timestamp.timeIntervalSince(navOffRouteSinceDate ?? location.timestamp)
            if elapsed >= NavConstants.offRouteToleranceSeconds, !isRecalculatingRoute, !isRoutingInProgress {
                isRecalculatingRoute = true
                requestNavRoute()
            }
        } else {
            navOffRouteSinceDate = nil
        }

        updateSpeedLimit(near: location.coordinate)
        updateOverSpeedFlag()
    }

    // MARK: - Limite de vitesse

    private func updateSpeedLimit(near coordinate: CLLocationCoordinate2D) {
        let now = Date()
        if let last = lastSpeedLimitLookupDate, now.timeIntervalSince(last) < NavConstants.speedLimitMinIntervalSeconds { return }
        lastSpeedLimitLookupDate = now
        Task { [weak self] in
            guard let self else { return }
            let speed = await SpeedLimitService.shared.lookup(near: coordinate)
            await MainActor.run {
                self.currentSpeedLimitKmh = speed
                self.updateOverSpeedFlag()
            }
        }
    }

    private func updateOverSpeedFlag() {
        guard let limit = currentSpeedLimitKmh else {
            isOverSpeedLimit = false
            return
        }
        isOverSpeedLimit = smoothedSpeedKmh > Double(limit + settings.speedLimitAlertThresholdKmh)
    }
}
