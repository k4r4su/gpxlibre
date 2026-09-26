import Foundation

enum GPXParserError: Error, LocalizedError {
    case invalidXML
    case noTrackData

    var errorDescription: String? {
        switch self {
        case .invalidXML: return String(localized: "Le fichier n'est pas un GPX valide.", bundle: .appLanguage)
        case .noTrackData: return String(localized: "Aucune trace ou point trouvé dans ce fichier GPX.", bundle: .appLanguage)
        }
    }
}

/// Parser GPX maison basé sur XMLParser (aucune dépendance externe).
/// Supporte les tracks (<trk>/<trkseg>/<trkpt>), les routes (<rte>/<rtept>) en repli,
/// et les waypoints (<wpt>).
final class GPXParser: NSObject, XMLParserDelegate {
    private var trackPoints: [GPXPoint] = []
    private var waypoints: [GPXPoint] = []
    private var routePoints: [GPXPoint] = []

    private var currentLat: Double?
    private var currentLon: Double?
    private var currentEle = ""
    private var currentTime = ""
    private var currentTextBuffer = ""
    private var currentContext: PointContext = .none

    private var parsedName: String?
    /// `<metadata><time>` (spec "biblio-date-display", it15, Bloc 1) — DISTINCT du `<time>` par
    /// point (`currentTime`/`endPoint()`) : capturé uniquement quand on est dans `<metadata>`
    /// ET hors de tout point (`currentContext == .none`), sinon un `<trkpt><time>` écraserait
    /// la même variable partagée `currentTextBuffer`/`time` element name.
    private var isInMetadata = false
    private var parsedMetadataTime: Date?

    private enum PointContext {
        case none, trkpt, wpt, rtept
    }

    static func parse(data: Data) throws -> (name: String?, points: [GPXPoint], waypoints: [GPXPoint], metadataDate: Date?) {
        let parser = GPXParser()
        let xmlParser = XMLParser(data: data)
        xmlParser.delegate = parser
        guard xmlParser.parse() else {
            throw GPXParserError.invalidXML
        }
        let points = parser.trackPoints.isEmpty ? parser.routePoints : parser.trackPoints
        guard !points.isEmpty || !parser.waypoints.isEmpty else {
            throw GPXParserError.noTrackData
        }
        return (parser.parsedName, points, parser.waypoints, parser.parsedMetadataTime)
    }

    func parser(
        _ parser: XMLParser,
        didStartElement elementName: String,
        namespaceURI: String?,
        qualifiedName qName: String?,
        attributes attributeDict: [String: String]
    ) {
        currentTextBuffer = ""
        switch elementName {
        case "trkpt":
            beginPoint(.trkpt, attributes: attributeDict)
        case "wpt":
            beginPoint(.wpt, attributes: attributeDict)
        case "rtept":
            beginPoint(.rtept, attributes: attributeDict)
        case "metadata":
            isInMetadata = true
        default:
            break
        }
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) {
        currentTextBuffer += string
    }

    func parser(
        _ parser: XMLParser,
        didEndElement elementName: String,
        namespaceURI: String?,
        qualifiedName qName: String?
    ) {
        let trimmed = currentTextBuffer.trimmingCharacters(in: .whitespacesAndNewlines)
        switch elementName {
        case "ele":
            currentEle = trimmed
        case "time":
            currentTime = trimmed
            if isInMetadata, currentContext == .none, parsedMetadataTime == nil {
                parsedMetadataTime = ISO8601DateFormatter().date(from: trimmed)
            }
        case "name":
            if currentContext == .none, parsedName == nil, !trimmed.isEmpty {
                parsedName = trimmed
            }
        case "metadata":
            isInMetadata = false
        case "trkpt", "wpt", "rtept":
            endPoint()
        default:
            break
        }
        currentTextBuffer = ""
    }

    private func beginPoint(_ context: PointContext, attributes: [String: String]) {
        currentContext = context
        currentLat = Double(attributes["lat"] ?? "")
        currentLon = Double(attributes["lon"] ?? "")
        currentEle = ""
        currentTime = ""
    }

    private func endPoint() {
        defer { currentContext = .none }
        guard let lat = currentLat, let lon = currentLon else { return }
        let elevation = Double(currentEle)
        let time = ISO8601DateFormatter().date(from: currentTime)
        let point = GPXPoint(latitude: lat, longitude: lon, elevation: elevation, time: time)
        switch currentContext {
        case .trkpt: trackPoints.append(point)
        case .wpt: waypoints.append(point)
        case .rtept: routePoints.append(point)
        case .none: break
        }
    }
}
