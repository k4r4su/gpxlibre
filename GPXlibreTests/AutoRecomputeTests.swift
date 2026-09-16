import XCTest
import CoreLocation
@testable import GPXlibre

/// Spec "link-recompute-on-divergence" (it18, Bloc 3) : divergence > RECOMPUTE_DIVERGENCE_M
/// (100 m) soutenue pendant > RECOMPUTE_DURATION_S (2 s) déclenche automatiquement le même
/// guidage que "Reprendre la trace ici" (isAutomatic = true, auto-confirmé) — même patron de
/// harnais que ResumeGuidanceTests/OffTrackHysteresisTests (session réelle, timestamps
/// explicites pour contrôler la durée simulée, jamais Date() implicite).
@MainActor
final class AutoRecomputeTests: XCTestCase {
    private func makeSession(defaultsSuiteName: String) -> RideSessionManager {
        let defaults = UserDefaults(suiteName: defaultsSuiteName)!
        return RideSessionManager(
            settings: RideSettingsStore(defaults: defaults),
            networkMonitor: NetworkMonitor(),
            modeStore: RideModeStore(),
            sharedBlockages: SharedBlockageSyncCoordinator(defaults: defaults)
        )
    }

    private func makeTrack() -> GPXTrack {
        GPXTrack(
            id: UUID(),
            name: "T",
            fileName: "t.gpx",
            importDate: Date(),
            points: (0...40).map { GPXPoint(latitude: 45.0 + Double($0) * 0.001, longitude: 5.0) },
            waypoints: []
        )
    }

    private func location(_ coordinate: CLLocationCoordinate2D, at date: Date) -> CLLocation {
        CLLocation(coordinate: coordinate, altitude: 0, horizontalAccuracy: 5, verticalAccuracy: 5, timestamp: date)
    }

    private func offsetEast(_ coordinate: CLLocationCoordinate2D, meters: Double) -> CLLocationCoordinate2D {
        let metersPerDegreeLongitude = 111_320 * cos(coordinate.latitude * .pi / 180)
        return CLLocationCoordinate2D(latitude: coordinate.latitude, longitude: coordinate.longitude + meters / metersPerDegreeLongitude)
    }

    func testDoesNotTriggerBeforeDurationElapsed() {
        let suite = "AutoRecomputeTests.\(UUID().uuidString)"
        defer { UserDefaults(suiteName: suite)?.removePersistentDomain(forName: suite) }
        let session = makeSession(defaultsSuiteName: suite)
        let track = makeTrack()
        session.start(track: track)
        let t0 = Date()

        session.handle(location: location(offsetEast(track.points[10].coordinate, meters: 150), at: t0))
        session.handle(location: location(offsetEast(track.points[10].coordinate, meters: 150), at: t0.addingTimeInterval(1)))

        XCTAssertNil(session.resumeGuidance, "1 s < RECOMPUTE_DURATION_S (2 s) : ne doit pas encore déclencher")
    }

    func testTriggersAutomaticResumeAfterSustainedDivergence() {
        let suite = "AutoRecomputeTests.\(UUID().uuidString)"
        defer { UserDefaults(suiteName: suite)?.removePersistentDomain(forName: suite) }
        let session = makeSession(defaultsSuiteName: suite)
        let track = makeTrack()
        session.start(track: track)
        let t0 = Date()

        session.handle(location: location(offsetEast(track.points[10].coordinate, meters: 150), at: t0))
        session.handle(location: location(offsetEast(track.points[10].coordinate, meters: 150), at: t0.addingTimeInterval(2.5)))

        XCTAssertNotNil(session.resumeGuidance, "150 m > 100 m soutenu 2.5 s > RECOMPUTE_DURATION_S : doit déclencher")
        XCTAssertEqual(session.resumeGuidance?.isAutomatic, true)
        XCTAssertEqual(session.resumeGuidance?.phase, .active, "automatique : auto-confirmé, jamais de preview à valider")
    }

    func testDivergenceBelowThresholdNeverTriggers() {
        let suite = "AutoRecomputeTests.\(UUID().uuidString)"
        defer { UserDefaults(suiteName: suite)?.removePersistentDomain(forName: suite) }
        let session = makeSession(defaultsSuiteName: suite)
        let track = makeTrack()
        session.start(track: track)
        let t0 = Date()

        session.handle(location: location(offsetEast(track.points[10].coordinate, meters: 60), at: t0))
        session.handle(location: location(offsetEast(track.points[10].coordinate, meters: 60), at: t0.addingTimeInterval(5)))

        XCTAssertNil(session.resumeGuidance, "60 m < RECOMPUTE_DIVERGENCE_M (100) : ne doit jamais déclencher, même longtemps soutenu")
    }

    func testReturningBelowThresholdResetsTheTimer() {
        let suite = "AutoRecomputeTests.\(UUID().uuidString)"
        defer { UserDefaults(suiteName: suite)?.removePersistentDomain(forName: suite) }
        let session = makeSession(defaultsSuiteName: suite)
        let track = makeTrack()
        session.start(track: track)
        let t0 = Date()

        session.handle(location: location(offsetEast(track.points[10].coordinate, meters: 150), at: t0))
        session.handle(location: location(offsetEast(track.points[11].coordinate, meters: 10), at: t0.addingTimeInterval(1.5)))
        session.handle(location: location(offsetEast(track.points[12].coordinate, meters: 150), at: t0.addingTimeInterval(3)))

        XCTAssertNil(session.resumeGuidance, "le retour sous le seuil entre-temps doit repartir de zéro sur la durée soutenue")
    }

    func testDoesNotOverrideAnExistingManualResume() {
        let suite = "AutoRecomputeTests.\(UUID().uuidString)"
        defer { UserDefaults(suiteName: suite)?.removePersistentDomain(forName: suite) }
        let session = makeSession(defaultsSuiteName: suite)
        let track = makeTrack()
        session.start(track: track)
        session.requestResume(pinCoordinate: track.points[30].coordinate, pinCumulativeDistanceMeters: 3000)
        session.confirmResume()
        XCTAssertEqual(session.resumeGuidance?.isAutomatic, false)
        let t0 = Date()

        session.handle(location: location(offsetEast(track.points[10].coordinate, meters: 150), at: t0))
        session.handle(location: location(offsetEast(track.points[10].coordinate, meters: 150), at: t0.addingTimeInterval(3)))

        XCTAssertEqual(session.resumeGuidance?.isAutomatic, false, "un guidage manuel déjà actif ne doit jamais être remplacé par un recalcul automatique")
    }

    /// Spec "rejoin-trace-guidance-banner" (it18, Bloc 5) : "la distance vers retour à la trace
    /// compte en continu (pas de stale)".
    func testLiveDistanceUpdatesOnEachFixWhileAutomaticGuidanceIsActive() {
        let suite = "AutoRecomputeTests.\(UUID().uuidString)"
        defer { UserDefaults(suiteName: suite)?.removePersistentDomain(forName: suite) }
        let session = makeSession(defaultsSuiteName: suite)
        let track = makeTrack()
        session.start(track: track)
        let t0 = Date()

        session.handle(location: location(offsetEast(track.points[10].coordinate, meters: 150), at: t0))
        session.handle(location: location(offsetEast(track.points[10].coordinate, meters: 150), at: t0.addingTimeInterval(2.5)))
        XCTAssertNotNil(session.resumeGuidance)
        // La distance n'est publiée qu'à PARTIR du fix qui suit celui où le guidage automatique
        // vient d'être créé (updateResumeProgress prend le relais au fix suivant, voir
        // updateRoadbookProgress) — pas encore sur ce même fix déclencheur.
        session.handle(location: location(offsetEast(track.points[10].coordinate, meters: 150), at: t0.addingTimeInterval(3)))
        let firstDistance = session.resumeGuidanceLiveDistanceMeters
        XCTAssertNotNil(firstDistance)

        // Un pas vers le pin (plus loin sur la trace) doit faire changer la distance publiée.
        session.handle(location: location(offsetEast(track.points[10].coordinate, meters: 140), at: t0.addingTimeInterval(3.5)))

        XCTAssertNotEqual(session.resumeGuidanceLiveDistanceMeters, firstDistance)
    }

    /// Spec "rejoin-nearest-by-air" (it19, bug terrain) : trace en boucle où le retour repasse
    /// près du départ. Vérifie que le recalcul automatique délègue bien à
    /// `TrackProjector.nearestPointByAirDistance` (voir TrackProjectorNearestPointTests pour la
    /// couverture géométrique du bug exact — point suivant chronologique loin, autre point de
    /// la trace proche à vol d'oiseau) plutôt qu'à l'ancien calcul "point suivant + 500 m".
    func testAutoRecomputeTargetsNearestPointByAirAcrossTheWholeTrack() {
        let suite = "AutoRecomputeTests.\(UUID().uuidString)"
        defer { UserDefaults(suiteName: suite)?.removePersistentDomain(forName: suite) }
        let session = makeSession(defaultsSuiteName: suite)
        let track = makeTrack()
        session.start(track: track)
        let t0 = Date()

        let riderPosition = offsetEast(track.points[10].coordinate, meters: 150)
        session.handle(location: location(riderPosition, at: t0))
        session.handle(location: location(riderPosition, at: t0.addingTimeInterval(2.5)))

        XCTAssertNotNil(session.resumeGuidance)
        guard let pin = session.resumeGuidance?.pinCoordinate else {
            return XCTFail("le recalcul automatique doit avoir posé un pin")
        }

        let cumulativeDistances = TrackProjector.cumulativeDistances(for: track.points)
        guard let expected = TrackProjector.nearestPointByAirDistance(
            to: riderPosition, in: track.points, cumulativeDistances: cumulativeDistances
        ) else {
            return XCTFail("nearestPointByAirDistance doit trouver un candidat sur une trace non vide")
        }

        XCTAssertEqual(pin.latitude, expected.coordinate.latitude, accuracy: 0.00001)
        XCTAssertEqual(pin.longitude, expected.coordinate.longitude, accuracy: 0.00001)
        guard let pinCumulativeDistanceMeters = session.resumeGuidance?.pinCumulativeDistanceMeters else {
            return XCTFail("le pin doit porter sa distance cumulée sur la trace")
        }
        XCTAssertEqual(pinCumulativeDistanceMeters, expected.cumulativeDistanceMeters, accuracy: 0.01)
    }
}
