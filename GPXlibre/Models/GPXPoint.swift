import Foundation
import CoreLocation

struct GPXPoint: Identifiable, Codable, Hashable {
    let id: UUID
    let latitude: Double
    let longitude: Double
    let elevation: Double?
    let time: Date?

    init(id: UUID = UUID(), latitude: Double, longitude: Double, elevation: Double? = nil, time: Date? = nil) {
        self.id = id
        self.latitude = latitude
        self.longitude = longitude
        self.elevation = elevation
        self.time = time
    }

    var coordinate: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    }
}
