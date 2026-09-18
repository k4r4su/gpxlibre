import XCTest
import CoreLocation
@testable import GPXlibre

/// Spec "track-geek-metrics" (it21, retour terrain : "rajouter des metrics si possible avec la
/// vitesse, le dénivelé... mode petit côté geek").
final class TrackMetricsCalculatorTests: XCTestCase {
    /// Déplace un point d'un cap/distance donné (formule de destination great-circle) — même
    /// helper que RoadbookInflectionTests/RoadbookMapMatchingTests.
    private func destination(from coordinate: CLLocationCoordinate2D, bearingDegrees: Double, distanceMeters: Double) -> CLLocationCoordinate2D {
        let earthRadius = 6_371_000.0
        let bearing = bearingDegrees * .pi / 180
        let lat1 = coordinate.latitude * .pi / 180
        let lon1 = coordinate.longitude * .pi / 180
        let angularDistance = distanceMeters / earthRadius

        let lat2 = asin(sin(lat1) * cos(angularDistance) + cos(lat1) * sin(angularDistance) * cos(bearing))
        let lon2 = lon1 + atan2(sin(bearing) * sin(angularDistance) * cos(lat1), cos(angularDistance) - sin(lat1) * sin(lat2))
        return CLLocationCoordinate2D(latitude: lat2 * 180 / .pi, longitude: lon2 * 180 / .pi)
    }

    func testReturnsNilForFewerThanTwoPoints() {
        XCTAssertNil(TrackMetricsCalculator.compute(for: []))
        XCTAssertNil(TrackMetricsCalculator.compute(for: [GPXPoint(latitude: 45, longitude: 5)]))
    }

    func testReturnsNilWhenPointsHaveNoTimestamps() {
        let points = [
            GPXPoint(latitude: 45.0, longitude: 5.0),
            GPXPoint(latitude: 45.001, longitude: 5.0),
        ]
        XCTAssertNil(TrackMetricsCalculator.compute(for: points), "pas d'horodatage réel : aucune métrique de vitesse ne doit être calculée")
    }

    /// 1000 m parcourus en exactement 100 s (deux points, un seul segment) → 36 km/h de moyenne
    /// EXACTE, calcul simple à vérifier à la main.
    func testAverageSpeedMatchesDistanceOverDuration() {
        let t0 = Date()
        let start = CLLocationCoordinate2D(latitude: 45.0, longitude: 5.0)
        let end = destination(from: start, bearingDegrees: 0, distanceMeters: 1000)
        let points = [
            GPXPoint(latitude: start.latitude, longitude: start.longitude, time: t0),
            GPXPoint(latitude: end.latitude, longitude: end.longitude, time: t0.addingTimeInterval(100)),
        ]

        let metrics = TrackMetricsCalculator.compute(for: points)

        XCTAssertEqual(metrics?.durationSeconds ?? -1, 100, accuracy: 0.01)
        XCTAssertEqual(metrics?.averageSpeedKmh ?? 0, 36, accuracy: 0.5)
    }

    func testElevationGainAndLossAccumulateSeparately() {
        let t0 = Date()
        var coordinate = CLLocationCoordinate2D(latitude: 45.0, longitude: 5.0)
        var points = [GPXPoint(latitude: coordinate.latitude, longitude: coordinate.longitude, elevation: 100, time: t0)]
        let elevations: [Double] = [150, 120, 200]
        for (index, elevation) in elevations.enumerated() {
            coordinate = destination(from: coordinate, bearingDegrees: 0, distanceMeters: 200)
            points.append(GPXPoint(latitude: coordinate.latitude, longitude: coordinate.longitude, elevation: elevation, time: t0.addingTimeInterval(Double(index + 1) * 60)))
        }
        // 100→150 (+50), 150→120 (-30), 120→200 (+80) : gain total 130, perte totale 30.
        let metrics = TrackMetricsCalculator.compute(for: points)

        XCTAssertEqual(metrics?.elevationGainMeters ?? 0, 130, accuracy: 0.01)
        XCTAssertEqual(metrics?.elevationLossMeters ?? 0, 30, accuracy: 0.01)
        XCTAssertEqual(metrics?.minElevationMeters, 100)
        XCTAssertEqual(metrics?.maxElevationMeters, 200)
    }

    /// Une "vitesse" aberrante (deux points quasi simultanés, saut GPS classique) ne doit jamais
    /// être retenue comme le pic de vitesse affiché.
    func testImplausibleSpeedSpikeIsExcludedFromMaxSpeed() {
        let t0 = Date()
        let start = CLLocationCoordinate2D(latitude: 45.0, longitude: 5.0)
        let normal = destination(from: start, bearingDegrees: 0, distanceMeters: 100) // 100 m en 10 s = 36 km/h
        let spike = destination(from: normal, bearingDegrees: 0, distanceMeters: 500) // 500 m en 1 s = 1800 km/h (implausible)
        let points = [
            GPXPoint(latitude: start.latitude, longitude: start.longitude, time: t0),
            GPXPoint(latitude: normal.latitude, longitude: normal.longitude, time: t0.addingTimeInterval(10)),
            GPXPoint(latitude: spike.latitude, longitude: spike.longitude, time: t0.addingTimeInterval(11)),
            GPXPoint(latitude: spike.latitude, longitude: spike.longitude, time: t0.addingTimeInterval(21)),
        ]

        let metrics = TrackMetricsCalculator.compute(for: points)

        XCTAssertLessThan(metrics?.maxSpeedKmh ?? 0, TrackMetricsCalculator.maxPlausibleSpeedKmh)
        XCTAssertEqual(metrics?.maxSpeedKmh ?? 0, 36, accuracy: 1, "seul le segment plausible (36 km/h) doit être retenu")
    }

    /// Un arrêt prolongé (vitesse quasi nulle) ne doit pas compter dans la durée "en mouvement",
    /// donc la moyenne en mouvement doit être PLUS ÉLEVÉE que la moyenne globale.
    func testStoppedSegmentIsExcludedFromMovingAverage() {
        let t0 = Date()
        let start = CLLocationCoordinate2D(latitude: 45.0, longitude: 5.0)
        let afterMoving = destination(from: start, bearingDegrees: 0, distanceMeters: 1000) // 1000 m en 100 s = 36 km/h
        let points = [
            GPXPoint(latitude: start.latitude, longitude: start.longitude, time: t0),
            GPXPoint(latitude: afterMoving.latitude, longitude: afterMoving.longitude, time: t0.addingTimeInterval(100)),
            // Arrêt de 5 minutes au même endroit (vitesse ~0).
            GPXPoint(latitude: afterMoving.latitude, longitude: afterMoving.longitude, time: t0.addingTimeInterval(400)),
        ]

        let metrics = TrackMetricsCalculator.compute(for: points)

        XCTAssertEqual(metrics?.movingDurationSeconds ?? 0, 100, accuracy: 0.01, "seul le premier segment (en mouvement) doit compter")
        XCTAssertGreaterThan(metrics?.averageMovingSpeedKmh ?? 0, metrics?.averageSpeedKmh ?? .infinity, "l'arrêt tire la moyenne globale vers le bas, pas la moyenne en mouvement")
    }

    /// La pente n'est mesurée QUE sur des segments assez longs (bruit GPS/altimétrique sur de
    /// très courtes distances, même précaution que SlopeAnalyzer).
    func testGradeIgnoresSegmentsShorterThanMinimum() {
        let t0 = Date()
        var coordinate = CLLocationCoordinate2D(latitude: 45.0, longitude: 5.0)
        // Segment TRÈS court (5 m) mais avec un delta d'élévation énorme : pente instantanée
        // aberrante, ne doit PAS ressortir comme maxGradePercent.
        var points = [GPXPoint(latitude: coordinate.latitude, longitude: coordinate.longitude, elevation: 100, time: t0)]
        coordinate = destination(from: coordinate, bearingDegrees: 0, distanceMeters: 5)
        points.append(GPXPoint(latitude: coordinate.latitude, longitude: coordinate.longitude, elevation: 150, time: t0.addingTimeInterval(10)))
        // Segment assez long (100 m) avec une pente réelle de 10 %.
        coordinate = destination(from: coordinate, bearingDegrees: 0, distanceMeters: 100)
        points.append(GPXPoint(latitude: coordinate.latitude, longitude: coordinate.longitude, elevation: 160, time: t0.addingTimeInterval(30)))

        let metrics = TrackMetricsCalculator.compute(for: points)

        XCTAssertEqual(metrics?.maxGradePercent ?? 0, 10, accuracy: 0.1, "seul le segment de 100 m (10 %) doit compter, pas le segment de 5 m")
    }
}
