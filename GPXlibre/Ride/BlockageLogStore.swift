import Foundation
import CoreLocation

struct BlockageEvent: Codable, Identifiable {
    let id: UUID
    let date: Date
    let coordinate: CLLocationCoordinate2DCodable
    let resolvedOnline: Bool

    init(coordinate: CLLocationCoordinate2D, resolvedOnline: Bool) {
        self.id = UUID()
        self.date = Date()
        self.coordinate = CLLocationCoordinate2DCodable(coordinate)
        self.resolvedOnline = resolvedOnline
    }
}

/// Encodable/Decodable wrapper — CLLocationCoordinate2D lui-même ne conforme pas à Codable.
struct CLLocationCoordinate2DCodable: Codable, Equatable {
    let latitude: Double
    let longitude: Double

    init(_ coordinate: CLLocationCoordinate2D) {
        latitude = coordinate.latitude
        longitude = coordinate.longitude
    }

    var coordinate: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    }
}

/// Journal local des "blocages rencontrés" par trace — première brique pour une future
/// mémoire communautaire (hors périmètre de cette itération : uniquement local pour l'instant).
@MainActor
final class BlockageLogStore {
    private let fileManager = FileManager.default

    private var directory: URL {
        let docs = fileManager.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let dir = docs.appendingPathComponent("Tracks/Blockages", isDirectory: true)
        if !fileManager.fileExists(atPath: dir.path) {
            try? fileManager.createDirectory(at: dir, withIntermediateDirectories: true)
        }
        return dir
    }

    private func fileURL(for trackID: UUID) -> URL {
        directory.appendingPathComponent("\(trackID.uuidString).json")
    }

    func events(for trackID: UUID) -> [BlockageEvent] {
        guard let data = try? Data(contentsOf: fileURL(for: trackID)),
              let decoded = try? JSONDecoder().decode([BlockageEvent].self, from: data) else { return [] }
        return decoded
    }

    func append(_ event: BlockageEvent, for trackID: UUID) {
        var events = events(for: trackID)
        events.append(event)
        guard let data = try? JSONEncoder().encode(events) else { return }
        try? data.write(to: fileURL(for: trackID))
    }
}
