#if DEBUG
import Foundation
import CoreLocation

/// Mode debug replay (spec "roadbook-angle-buckets-replay", it14, Bloc 4 : "obligatoire pour
/// valider les paliers sans sortir en voiture") — rejoue les points d'une trace déjà chargée
/// comme des fixs GPS synthétiques, à x4/x8, à travers le MÊME `RideSessionManager.handle
/// (location:)` que le vrai chemin GPS (`locationManager(_:didUpdateLocations:)`) : aucune
/// logique dupliquée, ce qui est validé ici est exactement ce qui tourne en conduite réelle.
///
/// `#if DEBUG` entier (build flag demandé explicitement) : absent des builds Release, aucun
/// risque qu'un utilisateur final tombe dessus. Accessible depuis Réglages > Avancé (section
/// déjà repliée par défaut, "menu caché" — voir SettingsView).
@MainActor
final class DebugReplayDriver: ObservableObject {
    @Published private(set) var isPlaying = false
    @Published private(set) var currentPointIndex = 0
    @Published private(set) var totalPointCount = 0

    private var task: Task<Void, Never>?
    /// Retenue UNIQUEMENT pour que `stop()` (et la fin naturelle du replay) puisse lever le
    /// flag sandbox posé au démarrage — spec "replay-marker-heading-x2", it17, Bloc 4 : "état
    /// replay totalement séparé de l'état ride". `weak` : jamais responsable du cycle de vie
    /// de la session, purement pour retrouver le point de sortie propre.
    private weak var activeSession: RideSessionManager?

    /// Vitesse simulée constante (km/h) injectée dans chaque fix — juste assez réaliste pour
    /// alimenter `smoothedSpeedKmh`/`rideContext` sans prétendre reproduire un vrai profil de
    /// vitesse (hors sujet ici, seul le roadbook est à valider).
    private static let simulatedSpeedKmh: Double = 45

    /// Délai réel (s) avant d'injecter le POINT SUIVANT — extrait en fonction pure et statique
    /// (spec "Vérifications automatiques", it17 : "distance parcourue = vitesse × temps, sans
    /// dérive cumulative") pour être testable directement : AUCUN état accumulé d'un appel à
    /// l'autre (chaque distance est recalculée depuis les coordonnées réelles, jamais depuis un
    /// compteur qui avancerait tout seul), donc structurellement sans dérive possible. Bornée
    /// (voir NavigationConstants) pour éviter une rafale quasi instantanée sur des points très
    /// rapprochés ou un blocage visible sur un grand trou de la trace (fix "debug-replay-
    /// erratic-speed", it16).
    nonisolated static func stepWaitSeconds(distanceToNextMeters: Double, speedMultiplier: Double) -> Double {
        let metersPerSecond = simulatedSpeedKmh / 3.6
        let travelSeconds = distanceToNextMeters / metersPerSecond
        let boundedSeconds = min(max(travelSeconds, NavigationConstants.debugReplayMinStepSeconds), NavigationConstants.debugReplayMaxStepSeconds)
        return boundedSeconds / max(speedMultiplier, 0.01)
    }

    /// - Parameter forceHeadingUp: spec "replay-marker-heading-x2", it17, Bloc 4 — toggle menu
    ///   debug, indépendant du réglage nord-en-haut/cap-en-haut réel de l'utilisateur (jamais
    ///   touché, voir `RideSessionManager.debugSetReplayActive`).
    func start(track: GPXTrack, speedMultiplier: Double, session: RideSessionManager, forceHeadingUp: Bool) {
        stop()
        guard track.points.count > 1 else { return }
        isPlaying = true
        currentPointIndex = 0
        totalPointCount = track.points.count
        activeSession = session
        session.debugSetReplayActive(true, forcesHeadingUp: forceHeadingUp)

        // Vrai (re)démarrage de session pour CETTE trace, comme RideView.onAppear le ferait —
        // pas un simple switchMode (spec "camera-mode-stability") : le replay doit repartir
        // d'un état propre, y compris si une autre trace était en cours.
        session.start(track: track)

        let points = track.points

        task = Task { [weak self] in
            for index in points.indices {
                guard !Task.isCancelled else { break }
                guard let self else { return }
                let point = points[index]
                let heading = index < points.count - 1
                    ? RoadbookAnalyzer.bearing(from: point.coordinate, to: points[index + 1].coordinate)
                    : (index > 0 ? RoadbookAnalyzer.bearing(from: points[index - 1].coordinate, to: point.coordinate) : 0)
                let location = CLLocation(
                    coordinate: point.coordinate,
                    altitude: point.elevation ?? 0,
                    horizontalAccuracy: 5,
                    verticalAccuracy: 5,
                    course: heading,
                    speed: Self.simulatedSpeedKmh / 3.6,
                    timestamp: Date()
                )
                self.currentPointIndex = index
                session.handle(location: location)

                // Fix "debug-replay-erratic-speed" (bug terrain, it16) : délai proportionnel à
                // la distance RÉELLE jusqu'au point suivant (à vitesse simulée constante) au
                // lieu d'un intervalle fixe par point — sinon les points GPX bruts, espacés très
                // irrégulièrement, donnaient un point bleu erratique ("un oiseau qui vole").
                if index < points.count - 1 {
                    let distanceToNext = RoadbookAnalyzer.distanceMeters(point.coordinate, points[index + 1].coordinate)
                    let waitSeconds = Self.stepWaitSeconds(distanceToNextMeters: distanceToNext, speedMultiplier: speedMultiplier)
                    try? await Task.sleep(nanoseconds: UInt64(waitSeconds * 1_000_000_000))
                }
            }
            self?.stop()
        }
    }

    func stop() {
        task?.cancel()
        task = nil
        isPlaying = false
        activeSession?.debugSetReplayActive(false, forcesHeadingUp: false)
        activeSession = nil
    }
}
#endif
