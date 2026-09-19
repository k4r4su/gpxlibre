import XCTest
import CoreLocation
@testable import GPXlibre

/// Spec "rejoin-icon-dynamic-bearing" (it22) — "calculer la direction réelle via le point le
/// plus proche sur la trace + le bearing... l'icône pivote/change de forme (gauche/droite/tout
/// droit)". Teste directement `RoadbookAnalyzer.bearing`/`signedAngleDifference`, les DEUX
/// fonctions pures qui alimentent `RideView.resumeRelativeBearingDegrees` (privée, non
/// testable directement — même calcul exact, exercé ici sans dépendance SwiftUI).
final class RejoinBearingTests: XCTestCase {
    private func relativeBearing(currentLocation: CLLocationCoordinate2D, headingDegrees: Double, target: CLLocationCoordinate2D) -> Double {
        let targetBearing = RoadbookAnalyzer.bearing(from: currentLocation, to: target)
        return RoadbookAnalyzer.signedAngleDifference(from: headingDegrees, to: targetBearing)
    }

    private let origin = CLLocationCoordinate2D(latitude: 45.0, longitude: 5.0)

    /// Cap plein nord, cible plein nord — tout droit, angle relatif ~0°.
    func testTargetStraightAheadProducesNearZeroRelativeBearing() {
        let target = CLLocationCoordinate2D(latitude: 45.01, longitude: 5.0)
        let relative = relativeBearing(currentLocation: origin, headingDegrees: 0, target: target)
        XCTAssertEqual(relative, 0, accuracy: 1)
    }

    /// Cap plein nord, cible plein est — à droite, angle relatif positif (~90°).
    func testTargetToTheRightProducesPositiveRelativeBearing() {
        let target = CLLocationCoordinate2D(latitude: 45.0, longitude: 5.01)
        let relative = relativeBearing(currentLocation: origin, headingDegrees: 0, target: target)
        XCTAssertEqual(relative, 90, accuracy: 2)
    }

    /// Cap plein nord, cible plein ouest — à gauche, angle relatif négatif (~-90°).
    func testTargetToTheLeftProducesNegativeRelativeBearing() {
        let target = CLLocationCoordinate2D(latitude: 45.0, longitude: 4.99)
        let relative = relativeBearing(currentLocation: origin, headingDegrees: 0, target: target)
        XCTAssertEqual(relative, -90, accuracy: 2)
    }

    /// Le cap du rider influence bien le résultat RELATIF : une cible plein est devient "tout
    /// droit" si le rider roule déjà plein est.
    func testRelativeBearingAccountsForCurrentHeadingNotJustAbsoluteTargetDirection() {
        let target = CLLocationCoordinate2D(latitude: 45.0, longitude: 5.01)
        let relative = relativeBearing(currentLocation: origin, headingDegrees: 90, target: target)
        XCTAssertEqual(relative, 0, accuracy: 2)
    }

    /// Cible plein sud avec un cap plein nord — demi-tour, ±180° (le signe précis dépend de la
    /// normalisation, seule la magnitude proche de 180° compte ici).
    func testTargetBehindProducesRelativeBearingNearOneEighty() {
        let target = CLLocationCoordinate2D(latitude: 44.99, longitude: 5.0)
        let relative = relativeBearing(currentLocation: origin, headingDegrees: 0, target: target)
        XCTAssertEqual(abs(relative), 180, accuracy: 2)
    }
}
