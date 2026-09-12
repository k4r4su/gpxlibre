import Foundation
import CoreLocation

struct RollingWaypoint: Codable, Identifiable {
    let id: UUID
    let category: WaypointCategory
    let coordinate: CLLocationCoordinate2DCodable
    let createdAt: Date
    /// Trace en cours d'enregistrement au moment de la création (pour la fusion à l'export, axe recording).
    let recordedTrackID: UUID?

    init(category: WaypointCategory, coordinate: CLLocationCoordinate2D, recordedTrackID: UUID?) {
        self.id = UUID()
        self.category = category
        self.coordinate = CLLocationCoordinate2DCodable(coordinate)
        self.createdAt = Date()
        self.recordedTrackID = recordedTrackID
    }
}

/// Persiste les waypoints "roulants" créés en un tap pendant le Ride. Servent aussi de
/// mémoire locale : affichés sur toute trace future si on en approche (< 50 m).
@MainActor
final class RollingWaypointStore: ObservableObject {
    @Published private(set) var waypoints: [RollingWaypoint] = []

    private let fileManager = FileManager.default

    private var directory: URL {
        let docs = fileManager.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let dir = docs.appendingPathComponent("Waypoints", isDirectory: true)
        if !fileManager.fileExists(atPath: dir.path) {
            try? fileManager.createDirectory(at: dir, withIntermediateDirectories: true)
        }
        return dir
    }

    private var indexFileURL: URL { directory.appendingPathComponent("waypoints.json") }

    init() {
        load()
    }

    @discardableResult
    func add(category: WaypointCategory, coordinate: CLLocationCoordinate2D, recordedTrackID: UUID?) -> RollingWaypoint {
        let waypoint = RollingWaypoint(category: category, coordinate: coordinate, recordedTrackID: recordedTrackID)
        waypoints.insert(waypoint, at: 0)
        save()
        return waypoint
    }

    func nearby(_ coordinate: CLLocationCoordinate2D, radiusMeters: Double = WaypointConstants.proximityDisplayRadiusMeters) -> [RollingWaypoint] {
        waypoints.filter { RoadbookAnalyzer.distanceMeters($0.coordinate.coordinate, coordinate) <= radiusMeters }
    }

    /// Tous les waypoints situés à moins de `radiusMeters` d'au moins un point de la trace —
    /// utilisé pour afficher les points pertinents sur la carte pendant tout le Ride.
    func waypoints(near track: GPXTrack, radiusMeters: Double = WaypointConstants.proximityDisplayRadiusMeters) -> [RollingWaypoint] {
        guard !waypoints.isEmpty else { return [] }
        let sampleStep = max(1, track.points.count / 500)
        let sampled = stride(from: 0, to: track.points.count, by: sampleStep).map { track.points[$0] }
        return waypoints.filter { waypoint in
            sampled.contains { RoadbookAnalyzer.distanceMeters($0.coordinate, waypoint.coordinate.coordinate) <= radiusMeters }
        }
    }

    private func load() {
        guard let data = try? Data(contentsOf: indexFileURL),
              let decoded = try? JSONDecoder().decode([RollingWaypoint].self, from: data) else { return }
        waypoints = decoded
    }

    private func save() {
        guard let data = try? JSONEncoder().encode(waypoints) else { return }
        try? data.write(to: indexFileURL)
    }
}
