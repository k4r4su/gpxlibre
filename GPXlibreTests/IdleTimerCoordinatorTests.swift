import XCTest
import UIKit
@testable import GPXlibre

/// Spec "roadbook-keep-screen-awake" (it25) — `IdleTimerCoordinator` est un état STATIQUE
/// partagé (pas d'instance injectable, reflète directement `UIApplication.shared`) : chaque test
/// remet les DEUX raisons à `false` en `tearDown` pour ne jamais polluer le test suivant.
@MainActor
final class IdleTimerCoordinatorTests: XCTestCase {
    override func tearDown() {
        IdleTimerCoordinator.setActive(false, for: .ride)
        IdleTimerCoordinator.setActive(false, for: .roadBook)
        super.tearDown()
    }

    func testActivatingOneReasonDisablesTheIdleTimer() {
        IdleTimerCoordinator.setActive(true, for: .roadBook)
        XCTAssertTrue(UIApplication.shared.isIdleTimerDisabled)
    }

    func testDeactivatingTheOnlyActiveReasonReEnablesTheIdleTimer() {
        IdleTimerCoordinator.setActive(true, for: .roadBook)
        IdleTimerCoordinator.setActive(false, for: .roadBook)
        XCTAssertFalse(UIApplication.shared.isIdleTimerDisabled)
    }

    /// Cœur du fix : quitter le Road Book ne doit JAMAIS couper le maintien réveillé demandé par
    /// un Ride toujours actif en arrière-plan (les deux peuvent coexister — le Ride continue
    /// d'enregistrer indépendamment de l'onglet affiché).
    func testDeactivatingOneReasonNeverClobbersAnotherStillActiveReason() {
        IdleTimerCoordinator.setActive(true, for: .ride)
        IdleTimerCoordinator.setActive(true, for: .roadBook)

        IdleTimerCoordinator.setActive(false, for: .roadBook)

        XCTAssertTrue(UIApplication.shared.isIdleTimerDisabled, "le Ride est toujours actif, l'écran doit rester allumé")
    }

    func testTheIdleTimerOnlyReEnablesOnceEveryReasonIsInactive() {
        IdleTimerCoordinator.setActive(true, for: .ride)
        IdleTimerCoordinator.setActive(true, for: .roadBook)

        IdleTimerCoordinator.setActive(false, for: .roadBook)
        IdleTimerCoordinator.setActive(false, for: .ride)

        XCTAssertFalse(UIApplication.shared.isIdleTimerDisabled)
    }

    /// Idempotence : réactiver une raison déjà active, ou désactiver une raison déjà inactive,
    /// ne doit jamais désynchroniser l'état.
    func testActivatingTheSameReasonTwiceStaysConsistent() {
        IdleTimerCoordinator.setActive(true, for: .roadBook)
        IdleTimerCoordinator.setActive(true, for: .roadBook)
        XCTAssertTrue(UIApplication.shared.isIdleTimerDisabled)

        IdleTimerCoordinator.setActive(false, for: .roadBook)
        XCTAssertFalse(UIApplication.shared.isIdleTimerDisabled)
    }
}
