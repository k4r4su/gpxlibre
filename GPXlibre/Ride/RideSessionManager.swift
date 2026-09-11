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

    private let manager = CLLocationManager()
    private let settings: RideSettingsStore
    private var track: GPXTrack?

    private var speedSamples: [(date: Date, speedMps: Double)] = []
    private var currentBucketIndex: Int = 0
    private var fastSpeedSustainedSince: Date?
    private var flashedCheckpointIDs: Set<UUID> = []
    private var hapticCheckpointIDs: Set<UUID> = []
    private let hapticGenerator = UIImpactFeedbackGenerator(style: .heavy)

    var lastManualGestureDate: Date?

    var isManualOverrideActive: Bool {
        guard let date = lastManualGestureDate else { return false }
        return Date().timeIntervalSince(date) < RideConstants.manualZoomOverrideTimeoutSeconds
    }

    var currentCheckpoint: Checkpoint? {
        checkpoints.indices.contains(currentCheckpointIndex) ? checkpoints[currentCheckpointIndex] : nil
    }

    var remainingCheckpointsCount: Int {
        max(checkpoints.count - currentCheckpointIndex, 0)
    }

    init(settings: RideSettingsStore) {
        self.settings = settings
        self.cameraDistanceMeters = ZoomPreset.normal.buckets.first?.cameraDistanceMeters ?? 300
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyBestForNavigation
        manager.distanceFilter = RideConstants.rideDistanceFilterMeters
        manager.activityType = .automotiveNavigation
    }

    private(set) var isActive = false

    func start(track: GPXTrack) {
        self.track = track
        isActive = true
        rebuildCheckpoints()
        speedSamples.removeAll()
        fastSpeedSustainedSince = nil
        currentBucketIndex = 0
        rideContext = .normal
        hapticGenerator.prepare()

        manager.requestWhenInUseAuthorization()
        manager.startUpdatingLocation()
        applyIdleTimerSetting()
    }

    func stop() {
        isActive = false
        manager.stopUpdatingLocation()
        UIApplication.shared.isIdleTimerDisabled = false
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
        checkpoints = RoadbookAnalyzer.buildCheckpoints(for: track, turnThresholdDegrees: settings.turnThresholdDegrees)
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
        let cutoff = location.timestamp.addingTimeInterval(-RideConstants.speedSmoothingWindowSeconds)
        speedSamples.removeAll { $0.date < cutoff }
        let avgMps = speedSamples.map(\.speedMps).reduce(0, +) / Double(max(speedSamples.count, 1))
        smoothedSpeedKmh = avgMps * 3.6

        if location.course >= 0, speedMps > 0.5 {
            headingDegrees = location.course
        }

        updateRideContext()
        updateZoomBucket()
        updateRoadbookProgress(from: location)
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
}
