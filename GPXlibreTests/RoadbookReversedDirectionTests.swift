import XCTest
import CoreLocation
@testable import GPXlibre

/// Fix "roadbook-reversed-direction-broken" (retour terrain : "Road Book Assisté GPS fonctionne
/// normalement en sens A→B, mais affiche immédiatement 'Toutes les manœuvres de cette trace ont
/// été passées' en sens inversé, alors que le trajet vient de commencer").
///
/// Root cause : `RoadBookTabView.selectedTrack` n'appliquait JAMAIS `GPXTrack.reordered(using:)`
/// — contrairement à `RideView.rideContent` — donc les manœuvres ET la projection GPS restaient
/// TOUJOURS calculées sur l'ordre CANONIQUE stocké, quel que soit `TrackRideSettings.isReversed`.
/// En sens inversé, la position physique de départ (proche du point B canonique) se projette sur
/// une distance cumulée déjà proche du TOTAL de la trace — supérieure à celle de TOUTES les
/// manœuvres (elles aussi mesurées en ordre canonique) — d'où "tout est déjà passé" dès le départ.
///
/// Reproduit ici le pipeline exact de `RoadBookTabView` (`reordered(using:)` →
/// `RoadbookExtractor.maneuvers` → `TrackProjector.project` → `RoadbookLiveProgress.nextManeuver`)
/// plutôt que d'instancier la vue SwiftUI elle-même (environment objects, `LocationManager`, non
/// testables directement — même contrainte que le reste du module, voir RoadBook/CLAUDE.md).
final class RoadbookReversedDirectionTests: XCTestCase {
    private let latPerMeter = 1.0 / 111_320
    private let lonPerMeter = 1.0 / (111_320 * cos(45 * .pi / 180))

    /// Même trace "escalier" que `RoadbookExtractorTests` — `legs - 1` virages francs à 90°,
    /// largement au-dessus du seuil "light" par défaut.
    private func staircaseTrack(legs: Int, pointsPerLeg: Int = 6, legLengthMeters: Double = 220) -> GPXTrack {
        var points: [GPXPoint] = []
        var lat = 45.000
        var lon = 5.000
        points.append(GPXPoint(latitude: lat, longitude: lon))
        let step = legLengthMeters / Double(pointsPerLeg)
        for leg in 0..<legs {
            let headingEast = leg % 2 == 0
            for _ in 0..<pointsPerLeg {
                if headingEast {
                    lon += step * lonPerMeter
                } else {
                    lat += step * latPerMeter
                }
                points.append(GPXPoint(latitude: lat, longitude: lon))
            }
        }
        return GPXTrack(id: UUID(), name: "Test", fileName: "test.gpx", importDate: Date(), points: points, waypoints: [])
    }

    private func extract(_ track: GPXTrack) -> [RoadbookManeuver] {
        RoadbookExtractor.maneuvers(
            for: track,
            windowBeforeMeters: NavigationConstants.roadbookWindowBeforeMetersDefault,
            windowAfterMeters: NavigationConstants.roadbookWindowAfterMetersDefault,
            lightThresholdDegrees: NavigationConstants.roadbookLightThresholdDegreesDefault,
            markedThresholdDegrees: NavigationConstants.roadbookMarkedThresholdDegreesDefault,
            hardThresholdDegrees: NavigationConstants.roadbookHardThresholdDegreesDefault,
            uTurnThresholdDegrees: NavigationConstants.roadbookUTurnThresholdDegreesDefault,
            mergeMinDistanceMeters: RideConstants.turnMergeMinDistanceMetersDefault
        )
    }

    /// Coeur du fix : au tout premier point du trajet en sens INVERSÉ (une fois `selectedTrack`
    /// correctement réordonné), la première manœuvre doit être annoncée comme À VENIR (index 0,
    /// distance restante > 0) — jamais "déjà passée".
    func testFirstManeuverIsUpcomingNotAlreadyPassedAtTheStartOfAReversedTrack() {
        let canonical = staircaseTrack(legs: 3)
        let reversed = canonical.reordered(using: TrackRideSettings(isReversed: true))

        XCTAssertEqual(reversed.id, canonical.id, "reordered(using:) doit préserver l'id — le cache map matching (clé = track.id) reste valide quel que soit le sens")

        let maneuvers = extract(reversed)
        XCTAssertFalse(maneuvers.isEmpty, "l'escalier inversé reste un escalier, les 2 virages doivent toujours être détectés")

        let cumulativeDistances = TrackProjector.cumulativeDistances(for: reversed.points)
        // Position GPS au tout début du trajet inversé — le premier point de `reversed.points`.
        let startCoordinate = reversed.points[0].coordinate
        guard let projection = TrackProjector.project(startCoordinate, onto: reversed.points, cumulativeDistances: cumulativeDistances) else {
            return XCTFail("projection attendue au tout premier point de la trace")
        }
        XCTAssertEqual(projection.cumulativeDistanceMeters, 0, accuracy: 1)

        let result = RoadbookLiveProgress.nextManeuver(maneuvers: maneuvers, currentCumulativeDistanceMeters: projection.cumulativeDistanceMeters)

        XCTAssertNotNil(result, "avant le fix : nil ici (\"toutes les manœuvres ont été passées\") dès le premier point")
        XCTAssertEqual(result?.index, 0, "la première manœuvre du trajet inversé doit être ciblée, pas une manœuvre déjà atteinte")
        XCTAssertGreaterThan(result?.distanceRemainingMeters ?? 0, 0)
    }

    /// Non-régression : le sens A→B (non inversé) continue de fonctionner à l'identique.
    func testFirstManeuverIsUpcomingAtTheStartOfANonReversedTrack() {
        let canonical = staircaseTrack(legs: 3)
        let maneuvers = extract(canonical)
        let cumulativeDistances = TrackProjector.cumulativeDistances(for: canonical.points)
        let startCoordinate = canonical.points[0].coordinate
        guard let projection = TrackProjector.project(startCoordinate, onto: canonical.points, cumulativeDistances: cumulativeDistances) else {
            return XCTFail("projection attendue au tout premier point de la trace")
        }
        let result = RoadbookLiveProgress.nextManeuver(maneuvers: maneuvers, currentCumulativeDistanceMeters: projection.cumulativeDistanceMeters)
        XCTAssertEqual(result?.index, 0)
    }

    /// Documente précisément le mécanisme du bug corrigé : calculer les manœuvres SUR L'ORDRE
    /// CANONIQUE (comme le faisait `RoadBookTabView` avant ce fix, `reordered(using:)` jamais
    /// appelé) et projeter la position physique de départ d'un trajet roulé en sens inversé (le
    /// DERNIER point canonique) reproduit exactement "toutes les manœuvres ont été passées" dès
    /// le premier point — garde-fou si `RoadBookTabView` revenait un jour à `rawSelectedTrack`
    /// par erreur pour l'un des trois usages (extraction/map matching/projection GPS).
    func testUsingCanonicalOrderManeuversAndProjectionReproducesTheOriginalBug() {
        let canonical = staircaseTrack(legs: 3)
        let maneuversComputedOnCanonicalOrder = extract(canonical)
        let cumulativeDistances = TrackProjector.cumulativeDistances(for: canonical.points)
        // Position physique de départ quand on roule en sens INVERSÉ = le dernier point canonique.
        let physicalStartOfReversedRide = canonical.points.last!.coordinate
        guard let projection = TrackProjector.project(physicalStartOfReversedRide, onto: canonical.points, cumulativeDistances: cumulativeDistances) else {
            return XCTFail("projection attendue au dernier point de la trace")
        }

        let result = RoadbookLiveProgress.nextManeuver(maneuvers: maneuversComputedOnCanonicalOrder, currentCumulativeDistanceMeters: projection.cumulativeDistanceMeters)

        XCTAssertNil(result, "reproduit le bug d'origine : sans reordered(using:) nulle part, la position de départ réelle en sens inversé retombe sur la fin de l'ordre canonique — tout semble déjà passé dès le premier point")
    }
}
