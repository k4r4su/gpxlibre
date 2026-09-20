import XCTest
@testable import GPXlibre

/// Spec "roadbook-mode" (it23) — "bascule countdown live / distances fixes ne partage pas
/// d'état parasite entre les deux modes" : `RoadbookLiveProgress.nextManeuver` est une fonction
/// PURE, ne mute jamais `[RoadbookManeuver]` — ces tests vérifient son comportement isolément,
/// sans jamais construire de `RoadbookManeuver` "classique" modifié en retour (la preuve que le
/// mode classique et le mode assisté GPS n'ont RIEN en commun à synchroniser).
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

    func testAdvancesToSecondManeuverOnceFirstIsReached() {
        let maneuvers = [maneuver(cumulativeDistanceMeters: 500), maneuver(cumulativeDistanceMeters: 1200)]
        // Bien au-delà du rayon "manœuvre atteinte" — la première ne doit plus être ciblée.
        let result = RoadbookLiveProgress.nextManeuver(maneuvers: maneuvers, currentCumulativeDistanceMeters: 600)
        XCTAssertEqual(result?.index, 1)
        XCTAssertEqual(result?.distanceRemainingMeters ?? -1, 600, accuracy: 0.01)
    }

    func testReturnsNilOnceLastManeuverIsPassed() {
        let maneuvers = [maneuver(cumulativeDistanceMeters: 500), maneuver(cumulativeDistanceMeters: 1200)]
        let result = RoadbookLiveProgress.nextManeuver(maneuvers: maneuvers, currentCumulativeDistanceMeters: 1300)
        XCTAssertNil(result)
    }

    func testReturnsNilForEmptyManeuverList() {
        XCTAssertNil(RoadbookLiveProgress.nextManeuver(maneuvers: [], currentCumulativeDistanceMeters: 100))
    }

    /// Une manœuvre "juste franchie" (à l'intérieur du rayon de tolérance) ne doit pas rester
    /// ciblée — évite un countdown bloqué à "0 m" à cause du bruit GPS.
    func testManeuverWithinReachedRadiusIsNoLongerTargeted() {
        let maneuvers = [maneuver(cumulativeDistanceMeters: 500), maneuver(cumulativeDistanceMeters: 1200)]
        let justPast = 500 + RoadBookConstants.liveManeuverReachedRadiusMeters - 1
        let result = RoadbookLiveProgress.nextManeuver(maneuvers: maneuvers, currentCumulativeDistanceMeters: justPast)
        XCTAssertEqual(result?.index, 1, "toujours dans le rayon de tolérance de la 1ère manœuvre, elle ne doit plus être ciblée")
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
