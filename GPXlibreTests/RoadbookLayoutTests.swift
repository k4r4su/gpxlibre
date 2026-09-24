import XCTest
import SwiftUI
import MapKit
@testable import GPXlibre

/// Jalon it28 — mini-carte RETIRÉE du Road Book (vue Assisté GPS, portrait et paysage) : la vue
/// focus hébergée pour de vrai (UIKit) ne contient plus aucune carte, et le hero + la liste des
/// étapes tiennent dans l'écran sans rien réserver pour elle.
@MainActor
final class RoadbookLayoutTests: XCTestCase {
    private func maneuver(_ cumulative: Double) -> RoadbookManeuver {
        let checkpoint = Checkpoint(
            coordinate: .init(latitude: 45, longitude: 5 + cumulative / 100_000),
            turnAngleDegrees: 60,
            direction: .right,
            tier: .marked,
            sequenceIndex: 1,
            sourcePointIndex: 0
        )
        return RoadbookManeuver(checkpoint: checkpoint, partialDistanceMeters: 500, cumulativeDistanceMeters: cumulative, headingDegrees: 90)
    }

    private func hostedFocusedView(size: CGSize, sizeClass: UserInterfaceSizeClass) -> UIView {
        let view = RoadbookFocusedView(
            maneuvers: [maneuver(500), maneuver(1000), maneuver(1500)],
            landmarkCheckpoints: [RoadbookLandmarkCheckpoint(info: RoadbookLandmarkInfo(category: .church, label: "Église"), latitude: 45, longitude: 5, cumulativeDistanceMeters: 800)],
            currentIndex: 0,
            distanceRemainingMeters: 320,
            currentCumulativeDistanceMeters: 180,
            unit: .km,
            hasLocationFix: true,
            landmarks: [:]
        )
        .environment(\.verticalSizeClass, sizeClass)
        .environmentObject(AppNavigationState())

        let controller = UIHostingController(rootView: view)
        let window = UIWindow(frame: CGRect(origin: .zero, size: size))
        window.rootViewController = controller
        window.makeKeyAndVisible()
        controller.view.frame = window.bounds
        controller.view.layoutIfNeeded()
        RunLoop.main.run(until: Date().addingTimeInterval(0.2))
        return controller.view
    }

    private func allSubviews(of view: UIView) -> [UIView] {
        view.subviews + view.subviews.flatMap(allSubviews)
    }

    func testFocusedViewHasNoMapInPortrait() {
        let root = hostedFocusedView(size: CGSize(width: 390, height: 700), sizeClass: .regular)
        XCTAssertFalse(allSubviews(of: root).contains { $0 is MKMapView }, "Aucune mini-carte dans la vue Assisté GPS (portrait)")
        XCTAssertFalse(allSubviews(of: root).isEmpty, "La vue focus doit être réellement rendue")
    }

    func testFocusedViewHasNoMapInLandscape() {
        let root = hostedFocusedView(size: CGSize(width: 750, height: 300), sizeClass: .compact)
        XCTAssertFalse(allSubviews(of: root).contains { $0 is MKMapView }, "Aucune mini-carte dans la vue Assisté GPS (paysage)")
        XCTAssertFalse(allSubviews(of: root).isEmpty, "La vue focus doit être réellement rendue")
    }
}
