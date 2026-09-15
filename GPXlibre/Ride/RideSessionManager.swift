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
    /// Vitesse brute affichée au speedo (spec "raw-speed-1hz", it12) — DISTINCT de
    /// `smoothedSpeedKmh` ci-dessus (moyenne glissante 10 s, inchangée, continue d'alimenter
    /// zoom auto/contexte route rapide/limite de vitesse) : ici `location.speed` brut, sans
    /// lissage ni moyenne, juste throttlé à 1 Hz (voir handle(location:)) — demande terrain
    /// explicite ("m'enfou que ça oscille"), lecture brute de la loi GPS.
    @Published private(set) var rawSpeedKmh: Double = 0
    private var lastRawSpeedDisplayDate: Date?
    @Published private(set) var cameraDistanceMeters: Double
    @Published private(set) var rideContext: RideContext = .normal
    /// Épingles carte (spec "roadbook-angle-buckets-replay", it14) — MÊME liste que
    /// `inflectionPoints` ci-dessous (une seule détection désormais, voir rebuildCheckpoints) ;
    /// gardée comme propriété séparée pour ne pas renommer le paramètre `checkpoints:` déjà
    /// consommé par RideMapLibreView/RideMapView (épingles) sans nécessité.
    @Published private(set) var checkpoints: [Checkpoint] = []
    /// Bannière latérale roadbook (spec "lateral-cap-banner-countdown", it12 ; détection
    /// remplacée "roadbook-angle-buckets-replay", it14, Bloc 4) — SANS index à avancer/
    /// resynchroniser : `currentInflection` est recalculé sans état propre à chaque fix (voir
    /// updateRoadbookBanner), donc toujours correct même après un hors-trace/reprise.
    @Published private(set) var inflectionPoints: [Checkpoint] = []
    @Published private(set) var currentInflection: Checkpoint?
    @Published private(set) var distanceToCurrentInflectionMeters: Double?
    /// Bloc 2 "resync-hysteresis" : roadbook en pause (hors trace) — direction/distance vers
    /// le checkpoint courant gelées, remplacées par un indicateur "hors trace" + point de
    /// reprise, tant que la position n'est pas stable ON trace pendant resyncHysteresisSeconds
    /// (ou resyncMinConsecutiveStableFixes points consécutifs).
    @Published private(set) var isOffTrackPaused = false
    @Published private(set) var offTrackResumeCoordinate: CLLocationCoordinate2D?
    @Published private(set) var offTrackResumeDistanceMeters: Double?
    /// Depuis quand `isOffTrackPaused` est vrai EN CONTINU (spec "offtrack-compact-chip", it18,
    /// Bloc 1) — pilote uniquement l'affichage de la distance dans le chip compact (voir
    /// OffTrackChipView), jamais la logique hors-trace elle-même (hystérésis inchangée).
    @Published private(set) var offTrackPausedSinceDate: Date?
    /// Change de valeur à chaque déclenchement d'alerte : FlashOverlayView observe ce token.
    @Published var flashSequenceToken: UUID?

    // MARK: - Chemin bloqué / détour (la trace originale reste affichée et n'est jamais modifiée)
    @Published private(set) var distanceOffTrackMeters: Double = 0
    @Published private(set) var isBlockedBannerVisible = false
    @Published private(set) var detourRoute: DetourRoute?
    @Published private(set) var isRequestingDetour = false
    @Published private(set) var detourRequestFailed = false

    // MARK: - "Reprendre la trace ici" (feat "resume-at-point", Bloc 3, it10) — guidage
    // parallèle vers un point tapé plus loin sur la trace, jamais une altération de celle-ci.
    @Published private(set) var resumeGuidance: ResumeGuidance?
    @Published private(set) var isRequestingResume = false
    @Published private(set) var resumeRoutingError: String?
    /// Distance EN CONTINU jusqu'au pin/jonction (spec "rejoin-trace-guidance-banner", it18,
    /// Bloc 5, "compte en continu, pas de stale") — recalculée à chaque fix GPS tant qu'un
    /// guidage de reprise est actif, `nil` sinon. Alimente RejoinGuidanceBannerView.
    @Published private(set) var resumeGuidanceLiveDistanceMeters: Double?
    private var resumeTask: Task<Void, Never>?
    /// Depuis quand la divergence dépasse RECOMPUTE_DIVERGENCE_M en continu (spec "link-
    /// recompute-on-divergence", it18, Bloc 3) — `nil` tant que sous le seuil ou déjà déclenché.
    private var autoRecomputeSinceDate: Date?
    /// Change à chaque recalcul automatique déclenché : RideView observe ce token pour afficher
    /// un toast bref "Recalcul" (spec explicite "notification silencieuse, pas de bannière
    /// permanente").
    @Published var autoRecomputeToastToken: UUID?

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

    /// Guidage arrêté (spec "stop-guidance-semantics", it14, Bloc 3) — DISTINCT de
    /// `isRecordingPaused` ci-dessus (jamais touché par Stop désormais, l'enregistrement
    /// continue toujours en arrière-plan). Masque roadbook/bannières de guidage (voir RideView)
    /// sans rien arrêter d'autre : trace, vitesse, carte restent affichées, on reste en vue
    /// Ride. Levé automatiquement par une nouvelle sélection de trace (start/switchMode) ou un
    /// recentrage manuel explicite (recenterCamera()), ou via l'icône "reprendre" discrète.
    @Published private(set) var isGuidanceStopped = false
    private let stopGuidanceHapticGenerator = UINotificationFeedbackGenerator()
    /// Haptique LÉGÈRE de `pauseGuidance()` (spec "guidance-toggle-stop-pause-play", it15,
    /// Bloc 3) — distincte de `stopGuidanceHapticGenerator` (forte, réservée au Stop défini via
    /// menu contextuel) : "Haptique différente pour Pause (légère) vs Stop défini (forte)".
    private let pauseGuidanceHapticGenerator = UIImpactFeedbackGenerator(style: .light)

    // MARK: - Replay debug v2 (spec "replay-marker-heading-x2", it17, Bloc 4) — sandbox : ces
    // deux propriétés ne sont JAMAIS écrites ailleurs que par `debugSetReplayActive`, lui-même
    // appelé UNIQUEMENT depuis DebugReplayDriver (fichier entier #if DEBUG, absent des builds
    // Release). Volontairement SANS #if DEBUG ici, pour ne pas propager la compilation
    // conditionnelle jusque dans RideView/RideMapLibreView (déjà partagés par tout le monde) —
    // restent simplement inertes (false) en Release, aucun coût fonctionnel ni visuel.
    @Published private(set) var isDebugReplayActive = false
    @Published private(set) var debugReplayForcesHeadingUp = false

    func debugSetReplayActive(_ active: Bool, forcesHeadingUp: Bool) {
        isDebugReplayActive = active
        debugReplayForcesHeadingUp = active && forcesHeadingUp
    }

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
    /// Dédup du flash roadbook (spec "roadbook-angle-buckets-replay", it14) — une seule fois
    /// par événement, remis à zéro à chaque `rebuildCheckpoints()`.
    private var flashedRoadbookEventIDs: Set<UUID> = []
    private let detourClearedHapticGenerator = UINotificationFeedbackGenerator()

    private var offTrackSinceDate: Date?
    private var offTrackAccumulatedDistance: Double = 0
    private var lastOffTrackLocation: CLLocation?

    // MARK: - Resync hors-trace (spec "resync-hysteresis" it10, seuils remplacés
    // "offtrace-threshold-hysteresis" it14) — pause roadbook DISTINCTE du minuteur "Portion
    // bloquée ?" ci-dessus (celui-ci propose un détour après 30s/200m ; la pause roadbook
    // ci-dessous s'active IMMÉDIATEMENT dès la sortie de trace, pour ne plus rappeler un
    // checkpoint largué) — plus de bookkeeping temporel séparé depuis it14 (voir
    // updateRoadbookProgress, hystérésis à deux seuils de distance uniquement).
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
        // Spec "stop-guidance-semantics" (it14, Bloc 3) : "Reprendre = ... le bouton cible/
        // recenter si un guidage était actif" — un recentrage explicite relance le guidage
        // arrêté, pas seulement la caméra.
        isGuidanceStopped = false
    }

    init(settings: RideSettingsStore, networkMonitor: NetworkMonitor, modeStore: RideModeStore, sharedBlockages: SharedBlockageSyncCoordinator) {
        self.settings = settings
        self.networkMonitor = networkMonitor
        self.modeStore = modeStore
        self.sharedBlockages = sharedBlockages
        // Spec "default-zoom-preview" (it14, Bloc 6) : point de départ réglable
        // (RideSettingsStore.defaultRideZoomCameraMeters, défaut "4 taps zoom-arrière" depuis
        // l'ancien point fixe) plutôt que le premier palier "Normal" codé en dur — écrasé dès
        // le premier fix GPS par updateZoomBucket() de toute façon (vitesse), ce réglage ne
        // pilote que le tout premier instant avant mouvement.
        self.cameraDistanceMeters = settings.defaultRideZoomCameraMeters
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
        // Spec "stop-guidance-semantics" (it14, Bloc 3) : "Reprendre = tap de nouvelle trace" —
        // un vrai (re)démarrage relance toujours un guidage précédemment arrêté.
        isGuidanceStopped = false
        speedSamples.removeAll()
        fastSpeedSustainedSince = nil
        currentBucketIndex = 0
        rideContext = .normal
        detourClearedHapticGenerator.prepare()
        stopGuidanceHapticGenerator.prepare()

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
            inflectionPoints = []
            currentInflection = nil
            distanceToCurrentInflectionMeters = nil
            // "Reprendre ici" est spécifique au Mode Trace (Bloc 3) — quitter vers le Mode Nav
            // purge tout guidage en cours, jamais laissé orphelin.
            resumeTask?.cancel()
            resumeGuidance = nil
        }

        manager.requestWhenInUseAuthorization()
        manager.startUpdatingLocation()
        applyIdleTimerSetting()
        syncSharedBlockagesIfNeeded()
    }

    /// Bascule Trace ↔ Nav OU retour d'onglet SANS repartir de zéro (spec "camera-mode-stability") —
    /// `start(track:)` remettait `currentBucketIndex` à 0 (palier de zoom le plus rapproché) et
    /// vidait l'historique de vitesse à CHAQUE appel, y compris pour un simple aller-retour
    /// Biblio→Ride ou Trace→Nav : c'était la cause du "le zoom change drastiquement" remonté du
    /// terrain. Ici, seul ce qui dépend réellement de la trace active est recalculé (checkpoints,
    /// distance cumulée, état hors-trace) ; le zoom (manuel ou auto), l'historique de vitesse, les
    /// statistiques de sortie et l'enregistrement en cours restent intacts. La caméra elle-même
    /// n'a rien de spécial à faire : elle continue de suivre `currentLocation` avec la même
    /// `cameraDistanceMeters` qu'avant, donc "conservée à l'identique" tombe naturellement de ne
    /// plus réinitialiser le palier de zoom.
    func switchMode(track: GPXTrack?) {
        self.track = track

        if let track {
            trackCumulativeDistances = TrackProjector.cumulativeDistances(for: track.points)
            rebuildCheckpoints()
            resetBlockedPathState()
            distanceRemainingMeters = track.totalDistanceMeters
            percentComplete = 0

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
            inflectionPoints = []
            currentInflection = nil
            distanceToCurrentInflectionMeters = nil
            // "Reprendre ici" est spécifique au Mode Trace (Bloc 3) — quitter vers le Mode Nav
            // purge tout guidage en cours, jamais laissé orphelin.
            resumeTask?.cancel()
            resumeGuidance = nil
        }

        if !isActive {
            // Session pas encore active (jamais démarrée) — même démarrage que start(track:).
            isActive = true
            manager.requestWhenInUseAuthorization()
            manager.startUpdatingLocation()
            applyIdleTimerSetting()
        }
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

    /// Purge explicite (fix "single-source-active-track", it10) : plutôt que de compter sur
    /// le PROCHAIN `start()`/`switchMode()` pour écraser silencieusement l'état d'une trace
    /// disparue, on nettoie ici, au moment même où la vue Ride se démonte (trace supprimée,
    /// onglet quitté). Aucun état fantôme ne doit survivre à un `stop()`.
    func stop() {
        isActive = false
        manager.stopUpdatingLocation()
        UIApplication.shared.isIdleTimerDisabled = false
        detourTask?.cancel()
        isGuidanceStopped = false
        track = nil
        checkpoints = []
        inflectionPoints = []
        currentInflection = nil
        distanceToCurrentInflectionMeters = nil
        trackCumulativeDistances = []
        goToGuidance = nil
        resetBlockedPathState()
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
        isOffTrackPaused = false
        offTrackResumeCoordinate = nil
        offTrackResumeDistanceMeters = nil
        offTrackPausedSinceDate = nil
        resumeTask?.cancel()
        resumeGuidance = nil
        isRequestingResume = false
        resumeRoutingError = nil
        resumeGuidanceLiveDistanceMeters = nil
        autoRecomputeSinceDate = nil
    }

    /// N'agit que si le mode Ride est actif : évite qu'un changement de réglage fait
    /// depuis un autre onglet ne bloque la mise en veille du téléphone hors Ride.
    func applyIdleTimerSetting() {
        guard isActive else { return }
        UIApplication.shared.isIdleTimerDisabled = settings.keepScreenAwakeInRide
    }

    /// Recalcule les événements roadbook (ex : l'utilisateur change un réglage sensibilité/
    /// fenêtre dans Réglages > Roadbook, spec "roadbook-settings-wired", it14, Bloc 5). Prend
    /// effet immédiatement, pas besoin de relancer l'app. `roadbookEnabled = false` vide tout
    /// (activation/désactivation globale, Bloc 5) sans jamais toucher `track`/la trace.
    func rebuildCheckpoints() {
        guard let track else { return }
        guard settings.roadbookEnabled else {
            checkpoints = []
            inflectionPoints = []
            currentInflection = nil
            distanceToCurrentInflectionMeters = nil
            flashedRoadbookEventIDs.removeAll()
            return
        }

        let events = RoadbookAnalyzer.buildRoadbookEvents(
            for: track,
            windowBeforeMeters: settings.roadbookWindowBeforeMeters,
            windowAfterMeters: settings.roadbookWindowAfterMeters,
            lightThresholdDegrees: settings.roadbookLightThresholdDegrees,
            markedThresholdDegrees: settings.roadbookMarkedThresholdDegrees,
            hardThresholdDegrees: settings.roadbookHardThresholdDegrees,
            uTurnThresholdDegrees: settings.roadbookUTurnThresholdDegrees,
            mergeMinDistanceMeters: settings.turnMergeMinDistanceMeters
        )
        checkpoints = events
        inflectionPoints = events
        currentInflection = nil
        distanceToCurrentInflectionMeters = nil
        flashedRoadbookEventIDs.removeAll()
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

    /// `internal` plutôt que `private` uniquement pour la testabilité (appelé directement
    /// par les tests de la state machine "resume-at-point" — le vrai chemin de production
    /// passe toujours par `locationManager(_:didUpdateLocations:)`, inchangé).
    func handle(location: CLLocation) {
        currentLocation = location

        let speedMps = max(location.speed, 0)

        // Speedo en 1 Hz brut (spec "raw-speed-1hz") : le GPS continue d'être consommé à sa
        // cadence normale (manager.distanceFilter inchangé) — seul le DISPLAY est throttlé,
        // jamais le calcul (smoothedSpeedKmh ci-dessous tourne à chaque fix, comme avant).
        if location.timestamp.timeIntervalSince(lastRawSpeedDisplayDate ?? .distantPast) >= 1.0 {
            lastRawSpeedDisplayDate = location.timestamp
            rawSpeedKmh = speedMps * 3.6
        }

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
            // La projection (distance perpendiculaire + position curviligne) sert à la fois au
            // hors-trace/détour ET au resync roadbook — calculée une seule fois par fix.
            let projection = updateBlockedPathTracking(from: location)
            updateRoadbookProgress(from: location, projection: projection)
            updateAutoRecompute(from: location, projection: projection)
            updateRoadbookBanner(projection: projection)
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
    /// Suspendu UNIQUEMENT par `isRecordingPaused` (bouton pause dédié) ; depuis it14, le Stop
    /// de guidage (`stopGuidance()`) ne touche plus à l'enregistrement, voir sa doc.
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

    /// Spec "auto-zoom-speed-curve" (it14, Bloc 7) : `autoZoomEnabled = false` fige la caméra
    /// à sa dernière valeur (le motard garde le contrôle manuel exclusif via +/-, voir
    /// zoomIn/zoomOut) — jamais recalculée depuis la vitesse tant que désactivé. Quand activé,
    /// le résultat des paliers/contexte est clampé à [autoZoomMinMeters, autoZoomMaxMeters]
    /// (bornes réglables), APRÈS le calcul habituel — la courbe vitesse→zoom (paliers +
    /// hystérésis, INCHANGÉE) définit la forme, les bornes en limitent juste l'amplitude.
    private func updateZoomBucket() {
        guard settings.autoZoomEnabled else { return }
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
        cameraDistanceMeters = min(max(distance, settings.autoZoomMinMeters), settings.autoZoomMaxMeters)
    }

    /// Bloc 2 "resync-hysteresis" (it10), seuils remplacés spec "offtrace-threshold-
    /// hysteresis" (it14, Bloc 8, bug terrain confirmé par capture du 14/09 : bandeau "Hors
    /// trace" persistant alors que la position était proche de la trace) — tant que hors
    /// trace (au-delà de `horsTraceEnterMeters`), le roadbook s'arrête (plus de rappel d'un
    /// checkpoint déjà largué) : affiche à la place un indicateur "hors trace" + le point de
    /// reprise le plus proche plus loin sur la trace (même mécanique que le détour direct sans
    /// réseau). Hystérésis à DEUX seuils distincts (30 m entrée / 25 m sortie) plutôt qu'un
    /// seuil unique + hystérésis temporelle (20 s/2 fixs) : la bande 25-30 m EST l'anti-rebond,
    /// aucun état ne change tant que la distance y reste — plus besoin de bookkeeping temporel
    /// séparé. Le retour au guidage complet reprend TOUJOURS à l'index courant ou plus loin —
    /// jamais de rattrapage des checkpoints déjà passés.
    private func updateRoadbookProgress(from location: CLLocation, projection: TrackProjector.Projection?) {
        // "Reprendre la trace ici" confirmé (Bloc 3) : la progression normale est gelée tant
        // que le guidage vers le pin n'a pas atteint sa jonction — en phase "previewing"
        // (pas encore confirmé), le hors-trace normal continue de tourner sans interférence,
        // réversible sans conséquence.
        guard resumeGuidance?.phase != .active else {
            updateResumeProgress(from: location)
            return
        }

        guard let projection else { return }

        if isOffTrackPaused {
            guard projection.distanceToTrackMeters <= RideConstants.horsTraceExitMeters else {
                updateOffTrackResumeTarget(from: location, projection: projection)
                return
            }
            isOffTrackPaused = false
            offTrackResumeCoordinate = nil
            offTrackResumeDistanceMeters = nil
            offTrackPausedSinceDate = nil
        } else if projection.distanceToTrackMeters > RideConstants.horsTraceEnterMeters {
            isOffTrackPaused = true
            offTrackPausedSinceDate = location.timestamp
            updateOffTrackResumeTarget(from: location, projection: projection)
        }
        // Plus de progression par INDEX ici depuis it14 (spec "roadbook-angle-buckets-replay") :
        // `updateRoadbookBanner`, appelée juste après dans `handle(location:)`, est SANS état
        // (reprend juste le prochain événement dont la distance cumulée dépasse la position
        // actuelle) — s'auto-corrige seule à chaque fix, hors-trace ou reprise inclus, sans
        // synchronisation d'index à maintenir ici.
    }

    /// Point de reprise (spec Bloc 2) : le premier point de trace atteignable plus loin —
    /// même mécanique que `requestDirectDetour()` (detourAheadMinMeters), pas un nouvel algo.
    private func updateOffTrackResumeTarget(from location: CLLocation, projection: TrackProjector.Projection) {
        guard let track else { return }
        guard let target = TrackProjector.coordinate(
            in: track.points,
            cumulativeDistances: trackCumulativeDistances,
            atCumulativeDistance: projection.cumulativeDistanceMeters + RideConstants.detourAheadMinMeters
        ) else { return }
        offTrackResumeCoordinate = target
        offTrackResumeDistanceMeters = RoadbookAnalyzer.distanceMeters(location.coordinate, target)
    }

    private func roadbookEventCumulativeDistanceMeters(_ event: Checkpoint) -> Double {
        trackCumulativeDistances.indices.contains(event.sourcePointIndex)
            ? trackCumulativeDistances[event.sourcePointIndex]
            : .infinity
    }

    /// Bannière latérale roadbook (spec "lateral-cap-banner-countdown" it12, détection
    /// remplacée "roadbook-angle-buckets-replay" it14, Bloc 4) : SANS état propre (pas d'index
    /// à avancer) — reprend juste le premier événement dont la distance cumulée dépasse la
    /// position curviligne actuelle. S'auto-corrige seule à chaque fix (hors-trace, reprise,
    /// retour en arrière GPS). Flash bref dans les `NavigationConstants.roadbookFlashMeters`
    /// (100 m) derniers mètres — une seule fois par événement (dédup par id, remis à zéro à
    /// chaque `rebuildCheckpoints()`), voir `flashedRoadbookEventIDs`.
    private func updateRoadbookBanner(projection: TrackProjector.Projection?) {
        guard let projection,
              let next = inflectionPoints.first(where: { roadbookEventCumulativeDistanceMeters($0) > projection.cumulativeDistanceMeters })
        else {
            currentInflection = nil
            distanceToCurrentInflectionMeters = nil
            return
        }
        currentInflection = next
        let distance = max(roadbookEventCumulativeDistanceMeters(next) - projection.cumulativeDistanceMeters, 0)
        distanceToCurrentInflectionMeters = distance

        guard settings.roadbookFlashEnabled, distance <= NavigationConstants.roadbookFlashMeters,
              !flashedRoadbookEventIDs.contains(next.id)
        else { return }
        flashedRoadbookEventIDs.insert(next.id)
        flashSequenceToken = UUID()
    }

    /// Phase "active" du guidage "Reprendre ici" (Bloc 3) — deux façons de rejoindre le fil :
    /// jonction avec le pin atteinte (< 30 m), OU retour naturel sur la trace avant même
    /// d'y arriver ("hystérésis silencieuse" demandée — pas de confirmation, juste la reprise).
    /// Ne resynchronise plus d'index depuis it14 (voir updateRoadbookProgress) : le roadbook
    /// se recale seul, sans état, dès le prochain fix.
    private func updateResumeProgress(from location: CLLocation) {
        guard let guidance = resumeGuidance, let track, !trackCumulativeDistances.isEmpty else {
            resumeGuidanceLiveDistanceMeters = nil
            return
        }

        let distanceToPin = RoadbookAnalyzer.distanceMeters(location.coordinate, guidance.pinCoordinate)
        resumeGuidanceLiveDistanceMeters = distanceToPin
        if distanceToPin <= RideConstants.resumeJunctionDistanceMeters {
            resumeTask?.cancel()
            resumeGuidance = nil
            resumeRoutingError = nil
            resumeGuidanceLiveDistanceMeters = nil
            return
        }

        guard let projection = TrackProjector.project(location.coordinate, onto: track.points, cumulativeDistances: trackCumulativeDistances) else { return }
        if projection.distanceToTrackMeters <= RideConstants.horsTraceEnterMeters {
            resumeTask?.cancel()
            resumeGuidance = nil
            resumeRoutingError = nil
            resumeGuidanceLiveDistanceMeters = nil
        }
    }

    /// Recalcul automatique de liaison (spec "link-recompute-on-divergence", it18, Bloc 3) :
    /// divergence soutenue > RECOMPUTE_DIVERGENCE_M pendant > RECOMPUTE_DURATION_S déclenche le
    /// MÊME guidage que "Reprendre la trace ici" (Bloc 3, it10), auto-confirmé — voir
    /// `ResumeGuidance.isAutomatic`. Jamais déclenché si un guidage de reprise (manuel ou
    /// automatique) existe déjà, ni pendant un guidage arrêté. Cible : la prochaine jonction
    /// atteignable plus loin sur la trace, même mécanique que `updateOffTrackResumeTarget`/
    /// `requestDirectDetour` (detourAheadMinMeters), pas un nouvel algorithme de recherche.
    private func updateAutoRecompute(from location: CLLocation, projection: TrackProjector.Projection?) {
        guard resumeGuidance == nil, !isGuidanceStopped, let track, !trackCumulativeDistances.isEmpty, let projection else {
            autoRecomputeSinceDate = nil
            return
        }
        guard projection.distanceToTrackMeters > RideConstants.recomputeDivergenceThresholdMeters else {
            autoRecomputeSinceDate = nil
            return
        }
        guard let since = autoRecomputeSinceDate else {
            autoRecomputeSinceDate = location.timestamp
            return
        }
        guard location.timestamp.timeIntervalSince(since) >= RideConstants.recomputeDivergenceDurationSeconds else { return }
        autoRecomputeSinceDate = nil

        let targetCumulative = projection.cumulativeDistanceMeters + RideConstants.detourAheadMinMeters
        guard let target = TrackProjector.coordinate(in: track.points, cumulativeDistances: trackCumulativeDistances, atCumulativeDistance: targetCumulative) else { return }
        requestResume(pinCoordinate: target, pinCumulativeDistanceMeters: targetCumulative, isAutomatic: true)
        autoRecomputeToastToken = UUID()
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

    // MARK: - "Reprendre la trace ici" (feat "resume-at-point", Bloc 3, it10)

    /// Pose le pin en phase "previewing" immédiatement (distance à vol d'oiseau visible sans
    /// réseau), puis lance le calcul d'itinéraire route (miroir exact de `requestDetour`,
    /// même `DetourRoutingService`) — la réponse met à jour l'objet EN PLACE sans changer de
    /// phase : rien n'est figé tant que `confirmResume()` n'a pas été appelé.
    func requestResume(pinCoordinate: CLLocationCoordinate2D, pinCumulativeDistanceMeters: Double, isAutomatic: Bool = false) {
        resumeTask?.cancel()
        resumeRoutingError = nil
        resumeGuidance = ResumeGuidance(
            pinCoordinate: pinCoordinate,
            pinCumulativeDistanceMeters: pinCumulativeDistanceMeters,
            // Automatique (spec "link-recompute-on-divergence") : auto-confirmé, jamais de
            // preview à valider — "recalcule routage" est présenté comme un fait accompli
            // (toast bref), pas une proposition.
            phase: isAutomatic ? .active : .previewing,
            isAutomatic: isAutomatic
        )

        guard let origin = currentLocation?.coordinate else { return }
        guard networkMonitor.isReachable else {
            resumeRoutingError = "Réseau requis pour l'itinéraire — vol d'oiseau affiché"
            return
        }

        isRequestingResume = true
        resumeTask = Task { [weak self] in
            guard let self else { return }
            do {
                let result = try await DetourRoutingService.requestRoute(from: origin, candidates: [pinCoordinate], profile: .route)
                guard !Task.isCancelled else { return }
                await MainActor.run {
                    guard var guidance = self.resumeGuidance, guidance.pinCoordinate.latitude == pinCoordinate.latitude, guidance.pinCoordinate.longitude == pinCoordinate.longitude else { return }
                    guidance.routeCoordinates = result.coordinates
                    guidance.isRouted = true
                    guidance.routeDistanceMeters = self.routeLengthMeters(result.coordinates)
                    self.resumeGuidance = guidance
                    self.isRequestingResume = false
                }
            } catch {
                guard !Task.isCancelled else { return }
                await MainActor.run {
                    self.isRequestingResume = false
                    self.resumeRoutingError = "Réseau requis pour l'itinéraire — vol d'oiseau affiché"
                }
            }
        }
    }

    /// Confirme le guidage prévisualisé — seul moment où la progression normale du roadbook
    /// se fige (voir `updateRoadbookProgress`). Ne touche jamais `track`/checkpoints.
    func confirmResume() {
        guard var guidance = resumeGuidance else { return }
        guidance.phase = .active
        resumeGuidance = guidance
    }

    /// Annulation 1 tap, à tout instant (preview ou active) — état propre, trace jamais
    /// altérée (spec Bloc 3 explicite).
    func cancelResume() {
        resumeTask?.cancel()
        resumeGuidance = nil
        isRequestingResume = false
        resumeRoutingError = nil
        resumeGuidanceLiveDistanceMeters = nil
    }

    private func routeLengthMeters(_ coordinates: [CLLocationCoordinate2D]) -> Double {
        guard coordinates.count > 1 else { return 0 }
        var total: Double = 0
        for i in 1..<coordinates.count {
            total += RoadbookAnalyzer.distanceMeters(coordinates[i - 1], coordinates[i])
        }
        return total
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
    /// principale). `.route` réutilise OSRM (profil voiture), `.offroad` réutilise le MÊME
    /// moteur avec le profil hors-route déjà documenté dans DetourRoutingService (spec
    /// "offroad-routing-preference", it13 — remplace l'ancienne ligne droite "vol d'oiseau"),
    /// `.mixed` route jusqu'au point routable le plus proche (OSRM snappe naturellement
    /// dessus) puis termine en hors-route plutôt qu'à vol d'oiseau ("route rapide d'approche →
    /// pistes dès que possible"). Si le réseau/OSRM échoue pour N'IMPORTE quel profil, repli
    /// honnête en ligne directe (jamais de faux semblant d'itinéraire).
    func startGoTo(to destination: CLLocationCoordinate2D, label: String, profile: GoToProfile) {
        goToTask?.cancel()
        goToRequestFailed = nil

        guard let origin = currentLocation?.coordinate else {
            goToRequestFailed = "Position GPS indisponible pour l'instant."
            return
        }

        isRequestingGoTo = true
        goToTask = Task { [weak self] in
            guard let self else { return }
            do {
                let coordinates = try await Self.resolvedGoToCoordinates(
                    from: origin, to: destination, label: label, profile: profile, networkMonitor: self.networkMonitor
                )
                guard !Task.isCancelled else { return }
                await MainActor.run {
                    self.goToGuidance = GoToGuidance(coordinates: coordinates, profile: profile, destinationCoordinate: destination, destinationLabel: label)
                    self.isRequestingGoTo = false
                }
            } catch {
                guard !Task.isCancelled else { return }
                await MainActor.run {
                    self.isRequestingGoTo = false
                    // Honnête : si le réseau/OSRM échoue, on ne prétend pas avoir un
                    // itinéraire — fallback automatique en ligne directe.
                    self.goToRequestFailed = (error as? LocalizedError)?.errorDescription ?? "Itinéraire impossible — guidage direct."
                    self.goToGuidance = GoToGuidance(coordinates: [origin, destination], profile: .offroad, destinationCoordinate: destination, destinationLabel: label)
                }
            }
        }
    }

    /// Extrait de startGoTo (fonction pure côté réseau, testable indépendamment de l'état de
    /// session) — un throw remonte tel quel au catch de l'appelant, qui gère le repli commun.
    private static func resolvedGoToCoordinates(
        from origin: CLLocationCoordinate2D,
        to destination: CLLocationCoordinate2D,
        label: String,
        profile: GoToProfile,
        networkMonitor: NetworkMonitor
    ) async throws -> [CLLocationCoordinate2D] {
        switch profile {
        case .offroad:
            return try await DetourRoutingService.route(from: origin, to: destination, profile: .offroad)
        case .route:
            let route = try await NavRoutingService.route(from: origin, to: destination, destinationLabel: label, networkMonitor: networkMonitor)
            return route.coordinates
        case .mixed:
            let route = try await NavRoutingService.route(from: origin, to: destination, destinationLabel: label, networkMonitor: networkMonitor)
            var coordinates = route.coordinates
            if let snappedEnd = coordinates.last {
                // OSRM a déjà "snappé" `destination` sur le point routable le plus proche côté
                // route : `snappedEnd` EST ce point. Le tronçon final se termine désormais en
                // HORS-ROUTE (routé, pas une ligne droite) si la destination réelle est encore
                // loin de ce point — "route rapide d'approche → pistes dès que possible".
                let residual = RoadbookAnalyzer.distanceMeters(snappedEnd, destination)
                if residual > RideConstants.detourRejoinClearRadiusMeters {
                    let offroadTail = try await DetourRoutingService.route(from: snappedEnd, to: destination, profile: .offroad)
                    coordinates.append(contentsOf: offroadTail.dropFirst())
                }
            }
            return coordinates
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

    /// Stop DÉFINI, visible en Mode Trace ET Mode Nav (spec "stop-guidance-semantics", it14,
    /// Bloc 3 ; accessible depuis it15 via le menu contextuel du bouton toggle plutôt qu'un
    /// bouton dédié, voir RideGuidanceToggleButton/RideView) : arrête IMMÉDIATEMENT le guidage
    /// actif (Nav, Aller à, détour, roadbook/bannières via `isGuidanceStopped`) — la trace reste
    /// affichée, la vitesse reste affichée, on reste en vue Ride. Ne touche JAMAIS
    /// l'enregistrement GPS en cours : le tracking continue silencieusement, seul le GUIDAGE
    /// s'interrompt (avant it14, Stop mettait `isRecordingPaused` à true — contraire à la
    /// consigne explicite "NE PAS fermer la session de tracking record"). Confirmation haptique
    /// FORTE portée ici ; le toast "Guidage arrêté" est déclenché côté RideView (composant
    /// visuel, pas d'état session). Voir `pauseGuidance()` pour l'équivalent léger (tap court).
    func stopGuidance() {
        haltActiveGuidance()
        stopGuidanceHapticGenerator.notificationOccurred(.success)
    }

    /// Pause légère (spec "guidance-toggle-stop-pause-play", it15, Bloc 3, tap court sur le
    /// bouton toggle unique) — MÊME état résultant que `stopGuidance()` (`isGuidanceStopped`,
    /// réversible sans reset via `resumeGuidanceAfterStop()`), mais haptique légère au lieu de
    /// forte. Toast dédié "Guidage en pause" côté RideView (`commitPause()`, distinct du "Guidage
    /// arrêté" du Stop défini) depuis le fix "pause-stop-indistinguishable" (bug terrain, it16) —
    /// les deux états étaient auparavant indiscernables à l'écran.
    func pauseGuidance() {
        haltActiveGuidance()
        pauseGuidanceHapticGenerator.impactOccurred()
    }

    private func haltActiveGuidance() {
        stopNav()
        stopGoTo()
        cancelDetour()
        isGuidanceStopped = true
    }

    /// Relance un guidage arrêté (spec Bloc 3) — icône "reprendre" discrète dans la colonne de
    /// contrôles, visible uniquement si une trace reste sélectionnée et que le guidage est à
    /// l'arrêt (voir RideView).
    func resumeGuidanceAfterStop() {
        isGuidanceStopped = false
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
