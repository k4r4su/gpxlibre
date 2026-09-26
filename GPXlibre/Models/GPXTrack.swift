import Foundation
import CoreLocation

struct GPXTrack: Identifiable, Codable, Hashable {
    let id: UUID
    var name: String
    let fileName: String
    let importDate: Date
    /// Date du CONTENU de la trace (spec "biblio-date-display", it15, Bloc 1) — distincte
    /// d'`importDate` : `<metadata><time>` du GPX en priorité, sinon la date de création du
    /// fichier au moment de l'import (voir `LibraryStore.addTrack`), `nil` si ni l'un ni
    /// l'autre n'a pu être déterminé. `Optional` pour rester décodable depuis un `index.json`
    /// pré-it15 (clé absente → `nil` via `decodeIfPresent` synthétisé, aucune migration requise).
    let contentDate: Date?
    let points: [GPXPoint]
    let waypoints: [GPXPoint]

    init(
        id: UUID,
        name: String,
        fileName: String,
        importDate: Date,
        contentDate: Date? = nil,
        points: [GPXPoint],
        waypoints: [GPXPoint]
    ) {
        self.id = id
        self.name = name
        self.fileName = fileName
        self.importDate = importDate
        self.contentDate = contentDate
        self.points = points
        self.waypoints = waypoints
    }

    var pointCount: Int { points.count }

    /// Date affichée en Biblio (spec Bloc 1) : `contentDate` si connue, repli sur `importDate`.
    var displayDate: Date { contentDate ?? importDate }

    /// Libellé convivial en Biblio, ex. « Tracée le 7 sept. » ou « Importée le 12 sept. 2026 »
    /// — préfixe "Tracée le" si une date de contenu réelle est connue (métadonnée GPX ou date
    /// de création fichier), "Importée le" en repli pur sur `importDate`. Année omise si
    /// l'année en cours, pour rester sobre au quotidien.
    var displayDateLabel: String {
        let prefix = contentDate != nil ? String(localized: "Tracée le", bundle: .appLanguage) : String(localized: "Importée le", bundle: .appLanguage)
        let sameYear = Calendar.current.isDate(displayDate, equalTo: Date(), toGranularity: .year)
        let formatter = DateFormatter()
        formatter.locale = AppLanguageBundle.locale
        formatter.setLocalizedDateFormatFromTemplate(sameYear ? "d MMM" : "d MMM yyyy")
        return "\(prefix) \(formatter.string(from: displayDate))"
    }

    var totalDistanceMeters: Double {
        guard points.count > 1 else { return 0 }
        var total: CLLocationDistance = 0
        for i in 1..<points.count {
            let a = CLLocation(latitude: points[i - 1].latitude, longitude: points[i - 1].longitude)
            let b = CLLocation(latitude: points[i].latitude, longitude: points[i].longitude)
            total += a.distance(from: b)
        }
        return total
    }

    var totalDistanceKm: Double { totalDistanceMeters / 1000 }

    var elevationGainMeters: Double {
        guard points.count > 1 else { return 0 }
        var gain: Double = 0
        for i in 1..<points.count {
            guard let e0 = points[i - 1].elevation, let e1 = points[i].elevation else { continue }
            let delta = e1 - e0
            if delta > 0 { gain += delta }
        }
        return gain
    }

    var boundingRegion: (center: CLLocationCoordinate2D, span: (latDelta: Double, lonDelta: Double))? {
        guard !points.isEmpty else { return nil }
        let lats = points.map(\.latitude)
        let lons = points.map(\.longitude)
        guard let minLat = lats.min(), let maxLat = lats.max(),
              let minLon = lons.min(), let maxLon = lons.max() else { return nil }
        let center = CLLocationCoordinate2D(latitude: (minLat + maxLat) / 2, longitude: (minLon + maxLon) / 2)
        let latDelta = max((maxLat - minLat) * 1.3, 0.01)
        let lonDelta = max((maxLon - minLon) * 1.3, 0.01)
        return (center, (latDelta, lonDelta))
    }

    /// Boucle détectée (spec "per-track-settings") : premier et dernier point à moins de
    /// 200 m — dans ce cas, le sens par défaut reste l'ordre du fichier (indiqué dans l'UI),
    /// jamais deviné autrement.
    var isLoop: Bool {
        guard let first = points.first, let last = points.last, points.count > 2 else { return false }
        return RoadbookAnalyzer.distanceMeters(first.coordinate, last.coordinate) < 200
    }

    /// Trace effective (spec "per-track-settings") : sens A→B/B→A + départ personnalisé,
    /// appliqués UNE fois ici — n'écrit JAMAIS le fichier GPX source, tout le reste du code
    /// (roadbook, projection, stats, rendu) continue de lire `points` normalement sans savoir
    /// qu'un réordonnancement a eu lieu.
    func reordered(using settings: TrackRideSettings) -> GPXTrack {
        guard settings.isReversed || settings.customStartPointIndex != nil else { return self }
        var reordered = settings.isReversed ? points.reversed().map { $0 } : points
        if let startIndex = settings.customStartPointIndex, reordered.indices.contains(startIndex), startIndex > 0 {
            reordered = Array(reordered[startIndex...] + reordered[..<startIndex])
        }
        return GPXTrack(id: id, name: name, fileName: fileName, importDate: importDate, contentDate: contentDate, points: reordered, waypoints: waypoints)
    }

    /// Identifie la trace ET le sens/le départ dans lequel elle est parcourue — `reordered(using:)`
    /// préserve `id`, donc `id` seul ne distingue pas A→B de B→A. Toute donnée dérivée qui dépend
    /// de l'ORDRE des points (types de manœuvre Valhalla gauche/droite, rang de sortie de
    /// rond-point, entrées de commune) doit être mise en cache sous cette clé, jamais sous `id`.
    /// Les DEUX premiers points (pas un seul) : sur une boucle, le premier point est au même
    /// endroit dans les deux sens, le second ne l'est pas.
    var traversalKey: String {
        let head = points.prefix(2)
            .map { String(format: "%.6f,%.6f", $0.latitude, $0.longitude) }
            .joined(separator: ";")
        return "\(id.uuidString)|\(head)"
    }
}
