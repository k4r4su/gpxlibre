import Foundation

/// Génère un GPX 1.1 valide à partir d'une trace enregistrée pendant le Ride + les waypoints
/// roulants associés. Note audio non embarquable dans le GPX (format texte standard) — reste
/// locale à l'app, seul le point (nom/catégorie/heure) est exporté.
enum GPXExporter {
    static func export(trackName: String, points: [GPXPoint], waypoints: [RollingWaypoint], comment: String?) -> Data {
        var xml = "<?xml version=\"1.0\" encoding=\"UTF-8\"?>\n"
        xml += "<gpx version=\"1.1\" creator=\"GPXlibre\" xmlns=\"http://www.topografix.com/GPX/1/1\">\n"
        xml += "  <metadata>\n    <name>\(escape(trackName))</name>\n"
        if let comment, !comment.trimmingCharacters(in: .whitespaces).isEmpty {
            xml += "    <desc>\(escape(comment))</desc>\n"
        }
        xml += "  </metadata>\n"

        for waypoint in waypoints {
            let coordinate = waypoint.coordinate.coordinate
            xml += "  <wpt lat=\"\(coordinate.latitude)\" lon=\"\(coordinate.longitude)\">\n"
            xml += "    <name>\(escape(waypoint.category.label))</name>\n"
            xml += "    <time>\(isoString(waypoint.createdAt))</time>\n"
            xml += "  </wpt>\n"
        }

        xml += "  <trk>\n    <name>\(escape(trackName))</name>\n    <trkseg>\n"
        for point in points {
            xml += "      <trkpt lat=\"\(point.latitude)\" lon=\"\(point.longitude)\">"
            if let elevation = point.elevation {
                xml += "<ele>\(elevation)</ele>"
            }
            if let time = point.time {
                xml += "<time>\(isoString(time))</time>"
            }
            xml += "</trkpt>\n"
        }
        xml += "    </trkseg>\n  </trk>\n</gpx>\n"

        return Data(xml.utf8)
    }

    private static func isoString(_ date: Date) -> String {
        ISO8601DateFormatter().string(from: date)
    }

    private static func escape(_ string: String) -> String {
        string
            .replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
            .replacingOccurrences(of: "\"", with: "&quot;")
    }
}
