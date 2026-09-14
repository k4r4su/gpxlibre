import XCTest
import CoreLocation
@testable import GPXlibre

/// Fix "offtrace-threshold-hysteresis" (it14, Bloc 8) : vérifie directement les deux seuils
/// (HORS_TRACE_ENTER_M = 30, HORS_TRACE_EXIT_M = 25) sur RideSessionManager.isOffTrackPaused —
/// même patron de harnais que ResumeGuidanceTests (session réelle, pas de réseau/disque touché).
@MainActor
final class OffTrackHysteresisTests: XCTestCase {
    private func makeSession(defaultsSuiteName: String) -> RideSessionManager {
        let defaults = UserDefaults(suiteName: defaultsSuiteName)!
        return RideSessionManager(
            settings: RideSettingsStore(defaults: defaults),
            networkMonitor: NetworkMonitor(),
            modeStore: RideModeStore(),
            sharedBlockages: SharedBlockageSyncCoordinator(defaults: defaults)
        )
    }

    /// Trace rectiligne nord-sud (longitude fixe) — un décalage en LONGITUDE simule donc une
    /// distance perpendiculaire connue à la trace.
    private func makeTrack() -> GPXTrack {
        GPXTrack(
            id: UUID(),
            name: "T",
            fileName: "t.gpx",
            importDate: Date(),
            points: (0...20).map { GPXPoint(latitude: 45.0 + Double($0) * 0.001, longitude: 5.0) },
            waypoints: []
        )
    }

    private func location(_ coordinate: CLLocationCoordinate2D) -> CLLocation {
        CLLocation(coordinate: coordinate, altitude: 0, horizontalAccuracy: 5, verticalAccuracy: 5, timestamp: Date())
    }

    /// Décale une coordonnée vers l'est d'un nombre de mètres donné — la trace de test est
    /// nord-sud (longitude fixe), donc ce décalage EST la distance perpendiculaire à la trace.
    private func offsetEast(_ coordinate: CLLocationCoordinate2D, meters: Double) -> CLLocationCoordinate2D {
        let metersPerDegreeLongitude = 111_320 * cos(coordinate.latitude * .pi / 180)
        return CLLocationCoordinate2D(latitude: coordinate.latitude, longitude: coordinate.longitude + meters / metersPerDegreeLongitude)
    }

    func testStaysOnTrackBelowEnterThreshold() {
        let suite = "OffTrackHysteresisTests.\(UUID().uuidString)"
        defer { UserDefaults(suiteName: suite)?.removePersistentDomain(forName: suite) }
        let session = makeSession(defaultsSuiteName: suite)
        let track = makeTrack()
        session.start(track: track)

        session.handle(location: location(offsetEast(track.points[10].coordinate, meters: 20)))

        XCTAssertFalse(session.isOffTrackPaused, "20 m < HORS_TRACE_ENTER_M (30) : ne doit jamais déclencher hors-trace")
    }

    func testEntersOffTrackAboveEnterThreshold() {
        let suite = "OffTrackHysteresisTests.\(UUID().uuidString)"
        defer { UserDefaults(suiteName: suite)?.removePersistentDomain(forName: suite) }
        let session = makeSession(defaultsSuiteName: suite)
        let track = makeTrack()
        session.start(track: track)

        session.handle(location: location(offsetEast(track.points[10].coordinate, meters: 35)))

        XCTAssertTrue(session.isOffTrackPaused, "35 m > HORS_TRACE_ENTER_M (30) : doit déclencher hors-trace")
    }

    /// Cœur de l'hystérésis : dans la bande 25-30 m, une fois hors-trace, on le RESTE — c'est
    /// exactement le bug terrain (bandeau qui devrait déjà s'être retiré, resté affiché).
    func testStaysOffTrackWithinHysteresisBand() {
        let suite = "OffTrackHysteresisTests.\(UUID().uuidString)"
        defer { UserDefaults(suiteName: suite)?.removePersistentDomain(forName: suite) }
        let session = makeSession(defaultsSuiteName: suite)
        let track = makeTrack()
        session.start(track: track)

        session.handle(location: location(offsetEast(track.points[10].coordinate, meters: 35)))
        XCTAssertTrue(session.isOffTrackPaused)

        session.handle(location: location(offsetEast(track.points[11].coordinate, meters: 27)))
        XCTAssertTrue(session.isOffTrackPaused, "27 m est dans la bande 25-30 : doit rester hors-trace (anti-rebond)")
    }

    func testReengagesBelowExitThreshold() {
        let suite = "OffTrackHysteresisTests.\(UUID().uuidString)"
        defer { UserDefaults(suiteName: suite)?.removePersistentDomain(forName: suite) }
        let session = makeSession(defaultsSuiteName: suite)
        let track = makeTrack()
        session.start(track: track)

        session.handle(location: location(offsetEast(track.points[10].coordinate, meters: 35)))
        XCTAssertTrue(session.isOffTrackPaused)

        session.handle(location: location(offsetEast(track.points[11].coordinate, meters: 20)))
        XCTAssertFalse(session.isOffTrackPaused, "20 m < HORS_TRACE_EXIT_M (25) : doit ré-engager la guidance")
    }
}
