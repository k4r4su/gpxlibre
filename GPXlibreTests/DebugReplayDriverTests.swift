import XCTest
@testable import GPXlibre

/// Spec "Vérifications automatiques" (it17, Bloc 4) : "Replay x2, x4, x8 : distance simulée =
/// vitesse × temps, sans dérive cumulative". `stepWaitSeconds` est une fonction STATIQUE PURE
/// (aucun état partagé entre appels) — la propriété "pas de dérive" est donc structurelle,
/// vérifiée ici en appelant la fonction plusieurs fois de suite avec les MÊMES arguments et en
/// confirmant un résultat rigoureusement identique (un compteur qui dériverait ne le serait pas).
final class DebugReplayDriverTests: XCTestCase {
    /// Distance choisie pour rester dans la plage NON bornée (ni min ni max), là où "distance =
    /// vitesse × temps" doit être exact — vitesse simulée 45 km/h = 12.5 m/s. Le bornage
    /// s'applique AVANT la division par le multiplicateur (voir stepWaitSeconds), donc c'est le
    /// temps de trajet BRUT (distance / 12.5) qui doit rester dans [0.05 s, 3 s] — 20 m donne
    /// 1.6 s, confortablement dans la plage pour ×2/×4/×8.
    private let midRangeDistanceMeters: Double = 20

    func testDistanceEqualsSpeedTimesTimeForEachMultiplier() {
        let speedMetersPerSecond = 45.0 / 3.6
        for multiplier: Double in [2, 4, 8] {
            let wait = DebugReplayDriver.stepWaitSeconds(distanceToNextMeters: midRangeDistanceMeters, speedMultiplier: multiplier)
            // Le temps RÉEL écoulé (wait) correspond à distance / (vitesse × multiplicateur) —
            // reformulé : distance == vitesse × multiplicateur × wait (v*t, "temps" incluant
            // l'accélération du multiplicateur, c'est tout l'intérêt du ×2/×4/×8).
            let impliedDistance = speedMetersPerSecond * multiplier * wait
            XCTAssertEqual(impliedDistance, midRangeDistanceMeters, accuracy: 0.01, "distance = vitesse × temps doit être exact hors bornage")
        }
    }

    /// Un multiplicateur plus élevé doit STRICTEMENT réduire le délai (×8 avance plus vite que
    /// ×2) — sinon "x2 ajouté en plus de x4/x8" n'aurait aucun effet observable.
    func testHigherMultiplierProducesShorterWait() {
        let wait2 = DebugReplayDriver.stepWaitSeconds(distanceToNextMeters: midRangeDistanceMeters, speedMultiplier: 2)
        let wait4 = DebugReplayDriver.stepWaitSeconds(distanceToNextMeters: midRangeDistanceMeters, speedMultiplier: 4)
        let wait8 = DebugReplayDriver.stepWaitSeconds(distanceToNextMeters: midRangeDistanceMeters, speedMultiplier: 8)

        XCTAssertGreaterThan(wait2, wait4)
        XCTAssertGreaterThan(wait4, wait8)
    }

    /// Aucune dérive cumulative possible : la fonction est pure, un appel N'INFLUENCE JAMAIS le
    /// suivant — deux appels identiques doivent produire une sortie BIT-À-BIT identique, à
    /// n'importe quel point d'une longue séquence simulée.
    func testRepeatedCallsWithSameInputsNeverDrift() {
        let first = DebugReplayDriver.stepWaitSeconds(distanceToNextMeters: midRangeDistanceMeters, speedMultiplier: 4)
        for _ in 0..<200 {
            let repeated = DebugReplayDriver.stepWaitSeconds(distanceToNextMeters: midRangeDistanceMeters, speedMultiplier: 4)
            XCTAssertEqual(repeated, first)
        }
    }

    /// Bornage (fix "debug-replay-erratic-speed", it16, réutilisé tel quel) : au-delà des
    /// bornes, "distance = vitesse × temps" n'est plus exact PAR CONSTRUCTION (comportement
    /// voulu, pas une dérive) — vérifié explicitement pour ne pas confondre les deux.
    func testWaitIsClampedForExtremeDistances() {
        let tinyDistanceWait = DebugReplayDriver.stepWaitSeconds(distanceToNextMeters: 0.001, speedMultiplier: 8)
        XCTAssertEqual(tinyDistanceWait, NavigationConstants.debugReplayMinStepSeconds / 8, accuracy: 0.0001)

        let hugeDistanceWait = DebugReplayDriver.stepWaitSeconds(distanceToNextMeters: 1_000_000, speedMultiplier: 2)
        XCTAssertEqual(hugeDistanceWait, NavigationConstants.debugReplayMaxStepSeconds / 2, accuracy: 0.0001)
    }
}
