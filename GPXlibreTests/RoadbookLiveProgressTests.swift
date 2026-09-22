import XCTest
@testable import GPXlibre

/// Spec "roadbook-mode" (it23) — "bascule countdown live / distances fixes ne partage pas
/// d'état parasite entre les deux modes" : `RoadbookLiveProgress.nextManeuver` est une fonction
/// PURE, ne mute jamais `[RoadbookManeuver]` — ces tests vérifient son comportement isolément,
/// sans jamais construire de `RoadbookManeuver` "classique" modifié en retour (la preuve que le
/// mode classique et le mode assisté GPS n'ont RIEN en commun à synchroniser).
///
/// Comportement de maintien après franchissement (fix "roadbook-live-progress-hold") — voir
/// `RoadbookLiveProgress.swift` pour le détail du root cause corrigé.
final class RoadbookLiveProgressTests: XCTestCase {
    private func maneuver(cumulativeDistanceMeters: Double) -> RoadbookManeuver {
        let checkpoint = Checkpoint(
            coordinate: .init(latitude: 45, longitude: 5),
            turnAngleDegrees: 40,
            direction: .right,
            tier: .marked,
            sequenceIndex: 1,
            sourcePointIndex: 0
        )
        return RoadbookManeuver(checkpoint: checkpoint, partialDistanceMeters: cumulativeDistanceMeters, cumulativeDistanceMeters: cumulativeDistanceMeters, headingDegrees: 0)
    }

    func testReturnsFirstManeuverBeforeAnyProgress() {
        let maneuvers = [maneuver(cumulativeDistanceMeters: 500), maneuver(cumulativeDistanceMeters: 1200)]
        let result = RoadbookLiveProgress.nextManeuver(maneuvers: maneuvers, currentCumulativeDistanceMeters: 0)
        XCTAssertEqual(result?.index, 0)
        XCTAssertEqual(result?.distanceRemainingMeters ?? -1, 500, accuracy: 0.01)
    }

    /// Cœur du fix : approcher la première manœuvre ne doit JAMAIS basculer l'affichage sur la
    /// suivante avant d'avoir réellement atteint la première (countdown continu jusqu'à 0).
    func testStaysTargetingTheUpcomingManeuverRightUntilItIsReached() {
        let maneuvers = [maneuver(cumulativeDistanceMeters: 500), maneuver(cumulativeDistanceMeters: 1200)]
        let justBefore = 500.0 - 1
        let result = RoadbookLiveProgress.nextManeuver(maneuvers: maneuvers, currentCumulativeDistanceMeters: justBefore)
        XCTAssertEqual(result?.index, 0)
        XCTAssertEqual(result?.distanceRemainingMeters ?? -1, 1, accuracy: 0.01)
    }

    /// Une fois ATTEINTE exactement (distance restante 0), la manœuvre reste ciblée (affichage
    /// figé à 0 m) — pas de bascule instantanée sur la suivante.
    func testManeuverStaysTargetedAtTheExactMomentItIsReached() {
        let maneuvers = [maneuver(cumulativeDistanceMeters: 500), maneuver(cumulativeDistanceMeters: 1200)]
        let result = RoadbookLiveProgress.nextManeuver(maneuvers: maneuvers, currentCumulativeDistanceMeters: 500)
        XCTAssertEqual(result?.index, 0)
        XCTAssertEqual(result?.distanceRemainingMeters ?? -1, 0, accuracy: 0.01)
    }

    /// Toujours dans la zone de maintien après franchissement — reste sur la manœuvre atteinte.
    func testManeuverStaysTargetedWithinTheHoldWindowAfterBeingReached() {
        let maneuvers = [maneuver(cumulativeDistanceMeters: 500), maneuver(cumulativeDistanceMeters: 1200)]
        let stillHeld = 500 + RoadBookConstants.liveManeuverHoldAfterMeters - 1
        let result = RoadbookLiveProgress.nextManeuver(maneuvers: maneuvers, currentCumulativeDistanceMeters: stillHeld)
        XCTAssertEqual(result?.index, 0)
        XCTAssertEqual(result?.distanceRemainingMeters ?? -1, 0, accuracy: 0.01)
    }

    /// Au-delà de la zone de maintien, bascule sur la manœuvre suivante avec son propre countdown.
    func testAdvancesToSecondManeuverOnceHoldWindowIsPassed() {
        let maneuvers = [maneuver(cumulativeDistanceMeters: 500), maneuver(cumulativeDistanceMeters: 1200)]
        let pastHold = 500 + RoadBookConstants.liveManeuverHoldAfterMeters + 1
        let result = RoadbookLiveProgress.nextManeuver(maneuvers: maneuvers, currentCumulativeDistanceMeters: pastHold)
        XCTAssertEqual(result?.index, 1)
        XCTAssertEqual(result?.distanceRemainingMeters ?? -1, 1200 - pastHold, accuracy: 0.01)
    }

    /// Virages enchaînés (demande explicite : "sauf si les virages s'enchaînent") — la manœuvre
    /// suivante est plus proche que la zone de maintien elle-même : bascule IMMÉDIATE dès que la
    /// première est atteinte, pas d'attente artificielle qui retarderait une instruction déjà
    /// pertinente.
    func testChainedManeuversSwitchImmediatelyWithoutWaitingForTheHoldWindow() {
        let gapShorterThanHold = RoadBookConstants.liveManeuverHoldAfterMeters / 2
        let maneuvers = [maneuver(cumulativeDistanceMeters: 500), maneuver(cumulativeDistanceMeters: 500 + gapShorterThanHold)]
        let result = RoadbookLiveProgress.nextManeuver(maneuvers: maneuvers, currentCumulativeDistanceMeters: 500)
        XCTAssertEqual(result?.index, 1, "le virage suivant est déjà plus proche que la zone de maintien, il doit s'afficher tout de suite")
        XCTAssertEqual(result?.distanceRemainingMeters ?? -1, gapShorterThanHold, accuracy: 0.01)
    }

    /// La dernière manœuvre de la trace reste affichée (figée à 0 m) pendant la même zone de
    /// maintien avant de basculer sur `nil` (trace terminée) — cohérent avec le comportement
    /// intermédiaire ci-dessus, pas un cas à part.
    func testLastManeuverIsHeldBeforeReturningNil() {
        let maneuvers = [maneuver(cumulativeDistanceMeters: 500), maneuver(cumulativeDistanceMeters: 1200)]
        let stillHeld = 1200 + RoadBookConstants.liveManeuverHoldAfterMeters - 1
        let result = RoadbookLiveProgress.nextManeuver(maneuvers: maneuvers, currentCumulativeDistanceMeters: stillHeld)
        XCTAssertEqual(result?.index, 1)
        XCTAssertEqual(result?.distanceRemainingMeters ?? -1, 0, accuracy: 0.01)
    }

    func testReturnsNilOnceLastManeuverIsPassedBeyondTheHoldWindow() {
        let maneuvers = [maneuver(cumulativeDistanceMeters: 500), maneuver(cumulativeDistanceMeters: 1200)]
        let pastHold = 1200 + RoadBookConstants.liveManeuverHoldAfterMeters + 1
        let result = RoadbookLiveProgress.nextManeuver(maneuvers: maneuvers, currentCumulativeDistanceMeters: pastHold)
        XCTAssertNil(result)
    }

    func testReturnsNilForEmptyManeuverList() {
        XCTAssertNil(RoadbookLiveProgress.nextManeuver(maneuvers: [], currentCumulativeDistanceMeters: 100))
    }

    /// Coeur du test demandé par la fiche : appeler cette fonction en boucle (simulant le mode
    /// Assisté GPS qui avance) puis relire la liste `maneuvers` directement (simulant un bascule
    /// vers le mode Classique) — la liste elle-même ne doit JAMAIS avoir changé.
    func testRepeatedLiveQueriesNeverMutateTheUnderlyingManeuverList() {
        let maneuvers = [maneuver(cumulativeDistanceMeters: 500), maneuver(cumulativeDistanceMeters: 1200), maneuver(cumulativeDistanceMeters: 2000)]
        let snapshot = maneuvers

        for distance in stride(from: 0.0, through: 2500, by: 250) {
            _ = RoadbookLiveProgress.nextManeuver(maneuvers: maneuvers, currentCumulativeDistanceMeters: distance)
        }

        XCTAssertEqual(maneuvers, snapshot, "le mode Assisté GPS ne doit jamais muter la liste que le mode Classique affiche telle quelle")
    }
}
