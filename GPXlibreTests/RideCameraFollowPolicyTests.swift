import XCTest
@testable import GPXlibre

/// Fix "roadbook-jump-to-map-sticky" (it26 point 4) — retour terrain : "le tap sur une étape saute
/// vers la bonne position une fois sur deux ; quand il fonctionne, la carte revient d'elle-même
/// sur la position GPS après quelques secondes". Rejoue la séquence de mises à jour de la carte
/// Ride (`RideMapLibreView.updateUIView`) à travers la décision pure qu'elle applique.
final class RideCameraFollowPolicyTests: XCTestCase {
    private func decide(forced: Bool = false, manual: Bool = false, focus: Bool = false, jumped: Bool = false) -> RideCameraFollowPolicy.Decision {
        RideCameraFollowPolicy.decide(isForcedCommand: forced, isManualOverrideActive: manual, isRoadBookFocusActive: focus, didJumpToRoadBookFocus: jumped)
    }

    /// "Une fois sur deux" : la mise à jour qui lance le saut ne doit JAMAIS enchaîner sur un
    /// recentrage GPS, même sans aucun geste manuel récent (cas qui échouait avant).
    func testTheUpdateThatJumpsToTheStepNeverRecentersOnGPSInTheSamePass() {
        XCTAssertEqual(decide(focus: true, jumped: true), .keepCamera)
        XCTAssertEqual(decide(forced: true, focus: true, jumped: true), .keepCamera, "même une commande forcée arrivée dans la même passe ne l'écrase pas")
    }

    /// Test demandé par la fiche it26 : après un saut vers une étape, une nouvelle position GPS ne
    /// recentre pas la carte tant que le suivi n'est pas réactivé — y compris bien après les 5 s
    /// de l'ancienne fenêtre de geste manuel (`manual: false`).
    func testNewGPSFixesNeverRecenterWhileAStepIsDisplayed() {
        for _ in 0..<20 {
            XCTAssertEqual(decide(manual: false, focus: true), .keepCamera)
        }
    }

    /// Zoom +/- pendant qu'une étape est affichée : zoome AUTOUR de l'étape, jamais un retour
    /// sur le GPS.
    func testZoomingWhileAStepIsDisplayedStaysOnTheStep() {
        XCTAssertEqual(decide(forced: true, manual: true, focus: true), .applyCommandAroundScreenCenter)
    }

    /// "Me recentrer" : sort du mode étape (`endRoadBookFocus`) ET force une commande
    /// (`recenterCamera`, qui désarme aussi le geste manuel) — retour au suivi GPS, qui continue
    /// ensuite normalement.
    @MainActor
    func testRecenterEndsTheStepModeAndResumesGPSFollowing() {
        let navigation = AppNavigationState()
        navigation.focusRideMap(on: .init(latitude: 45, longitude: 5))
        XCTAssertEqual(decide(focus: navigation.roadBookFocusRequest != nil), .keepCamera)

        navigation.endRoadBookFocus()

        XCTAssertEqual(decide(forced: true, manual: false, focus: navigation.roadBookFocusRequest != nil), .followCurrentLocation)
        XCTAssertEqual(decide(focus: navigation.roadBookFocusRequest != nil), .followCurrentLocation)
    }

    /// Non-régression : comportements existants hors étape Road Book inchangés.
    func testBehaviourOutsideAStepIsUnchanged() {
        XCTAssertEqual(decide(), .followCurrentLocation, "suivi normal")
        XCTAssertEqual(decide(manual: true), .keepCamera, "carte déplacée à la main (fenêtre de 5 s)")
        XCTAssertEqual(decide(forced: true, manual: true), .applyCommandAroundScreenCenter, "fix explore-zoom-anchoring (it14)")
        XCTAssertEqual(decide(forced: true), .followCurrentLocation, "recentrage explicite")
    }
}
