import XCTest
import CoreLocation
@testable import GPXlibre

/// Fix "speed-freeze-low-speed" (it19, bug terrain P0) : `manager.distanceFilter` posé à 5 m
/// (it1) affamait les fixs GPS sous ~21 km/h (temps pour parcourir 5 m > 1 s) et les arrêtait
/// purement à l'arrêt complet — `rawSpeedKmh`/`smoothedSpeedKmh` restaient figés à leur
/// dernière valeur. Voir RideConstants.swift (MARK: Localisation Ride) pour le détail complet.
///
/// La starvation elle-même se produit AVANT `handle(location:)` (au niveau de la livraison
/// CoreLocation, jamais reproductible dans un test qui appelle `handle(location:)` directement
/// — même limite que documentée dans CLAUDE.md, pas de device physique dans cet environnement).
/// Ce fichier vérifie donc deux choses distinctes et complémentaires :
/// 1. la CONFIGURATION corrigée (`configuredDistanceFilterMeters`) — la seule garantie contre
///    une régression qui réintroduirait un distanceFilter > 0 ;
/// 2. que le PIPELINE de calcul (throttle 1 Hz, décroissance) n'a lui-même aucun palier caché
///    qui figerait l'affichage une fois les fixs à nouveau continus.
@MainActor
final class SpeedFreezeTests: XCTestCase {
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
            points: (0...20).map { GPXPoint(latitude: 45.0 + Double($0) * 0.0002, longitude: 5.0) },
            waypoints: []
        )
    }

    private func location(_ coordinate: CLLocationCoordinate2D, speedKmh: Double, timestamp: Date) -> CLLocation {
        CLLocation(
            coordinate: coordinate,
            altitude: 0,
            horizontalAccuracy: 5,
            verticalAccuracy: 5,
            course: 0,
            speed: max(speedKmh, 0) / 3.6,
            timestamp: timestamp
        )
    }

    func testDistanceFilterNeverStarvesFixesRegardlessOfSpeed() {
        let suite = "SpeedFreezeTests.\(UUID().uuidString)"
        defer { UserDefaults(suiteName: suite)?.removePersistentDomain(forName: suite) }
        let session = makeSession(defaultsSuiteName: suite)

        XCTAssertEqual(session.configuredDistanceFilterMeters, kCLDistanceFilterNone,
                        "un distanceFilter > 0 recommencerait à affamer les fixs sous ~21 km/h et à l'arrêt")
    }

    /// Décélération 30 → 0 km/h (scénario exact demandé pour la validation terrain, "sans
    /// palier") — un fix par seconde (throttle 1 Hz respecté), position quasi fixe pour isoler
    /// la variable testée (la vitesse), pas la distance parcourue.
    func testRawSpeedDecreasesContinuouslyToZeroWithoutPlateau() {
        let suite = "SpeedFreezeTests.\(UUID().uuidString)"
        defer { UserDefaults(suiteName: suite)?.removePersistentDomain(forName: suite) }
        let session = makeSession(defaultsSuiteName: suite)
        let track = makeTrack()
        session.start(track: track)

        let start = Date()
        let coordinate = track.points[10].coordinate
        let speedsKmh: [Double] = [30, 25, 20, 15, 10, 5, 0]

        for (index, speedKmh) in speedsKmh.enumerated() {
            let timestamp = start.addingTimeInterval(Double(index) * 1.1)
            session.handle(location: location(coordinate, speedKmh: speedKmh, timestamp: timestamp))
            XCTAssertEqual(session.rawSpeedKmh, speedKmh, accuracy: 0.01,
                            "rawSpeedKmh doit suivre chaque palier de décélération sans rester bloqué au précédent")
        }

        XCTAssertEqual(session.rawSpeedKmh, 0, "l'arrêt complet doit se refléter jusqu'à 0, jamais rester figé au-dessus")
    }

    /// Garde-fou ajouté en contrepartie du distanceFilter continu : la gigue GPS à l'arrêt
    /// strict (quelques mètres, vitesse quasi nulle) ne doit PAS dériver la distance totale —
    /// seul un déplacement réel (vitesse au-dessus du seuil) doit compter.
    func testDistanceAccumulationIgnoresStandstillJitterButCountsRealMovement() {
        let suite = "SpeedFreezeTests.\(UUID().uuidString)"
        defer { UserDefaults(suiteName: suite)?.removePersistentDomain(forName: suite) }
        let session = makeSession(defaultsSuiteName: suite)
        let track = makeTrack()
        session.start(track: track)

        let start = Date()
        let base = track.points[10].coordinate
        // ~3 m de gigue est-ouest, vitesse rapportée quasi nulle (0.4 km/h < seuil 1 km/h).
        let jitterCoordinate = CLLocationCoordinate2D(latitude: base.latitude, longitude: base.longitude + 0.00003)

        session.handle(location: location(base, speedKmh: 0, timestamp: start))
        session.handle(location: location(jitterCoordinate, speedKmh: 0.4, timestamp: start.addingTimeInterval(1)))
        session.handle(location: location(base, speedKmh: 0.4, timestamp: start.addingTimeInterval(2)))
        XCTAssertEqual(session.totalDistanceTraveledMeters, 0, accuracy: 0.001,
                        "la gigue GPS sous le seuil ne doit jamais incrémenter la distance totale")

        // Déplacement réel suivant (vitesse au-dessus du seuil) : doit maintenant compter.
        let movedCoordinate = CLLocationCoordinate2D(latitude: base.latitude + 0.0001, longitude: base.longitude)
        session.handle(location: location(movedCoordinate, speedKmh: 10, timestamp: start.addingTimeInterval(3)))
        XCTAssertGreaterThan(session.totalDistanceTraveledMeters, 0,
                              "un déplacement réel au-dessus du seuil doit être compté normalement")
    }
}
