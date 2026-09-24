import Foundation
import os

/// Dump de debug, une ligne par checkpoint du Road Book (itération corrective "fiabilité des
/// checkpoints", étape de diagnostic demandée par la fiche) : index, point GPX, distance cumulée,
/// source, type Valhalla, rues avant → après, angle Valhalla, angle recalculé depuis la trace
/// suivie, palier (libellé) et cap. Journalisé en build DEBUG uniquement (`Logger`, catégorie
/// "roadbook", niveau notice : visible dans Console.app ou `idevicesyslog` sur l'iPhone branché).
enum RoadbookDebugDump {
    static func lines(maneuvers: [RoadbookManeuver], mapMatched: [MapMatchedManeuver]) -> [String] {
        maneuvers.enumerated().map { index, maneuver in
            let checkpoint = maneuver.checkpoint
            // Une manœuvre Valhalla retenue garde la coordonnée EXACTE du carrefour recalé.
            let valhalla = mapMatched.first { RoadbookAnalyzer.distanceMeters($0.coordinate, checkpoint.coordinate) < 0.5 }
            let signedAngle = checkpoint.direction == .left ? -checkpoint.turnAngleDegrees : checkpoint.turnAngleDegrees
            var fields = [
                "#\(index + 1)",
                "point \(checkpoint.sourcePointIndex)",
                String(format: "cumul %.0f m", maneuver.cumulativeDistanceMeters),
            ]
            if let valhalla {
                fields += [
                    "source Valhalla",
                    "type \(valhalla.type)",
                    "rues \(names(valhalla.streetNamesBefore)) → \(names(valhalla.streetNamesAfter))",
                    // `/trace_route` ne renvoie qu'une CATÉGORIE (léger/normal/serré), aucun angle.
                    "angle Valhalla : catégorie seule",
                ]
            } else {
                fields.append("source géométrie")
            }
            fields += [
                String(format: "angle recalculé %+.0f°", signedAngle),
                "palier \(checkpoint.tier.label)",
                String(format: "cap %.0f°", maneuver.headingDegrees),
            ]
            return fields.joined(separator: " | ")
        }
    }

    private static func names(_ names: [String]) -> String {
        names.isEmpty ? "(sans nom)" : names.joined(separator: "/")
    }

    #if DEBUG
    private static let logger = Logger(subsystem: "com.olivier.gpxlibre", category: "roadbook")

    static func log(trackName: String, maneuvers: [RoadbookManeuver], mapMatched: [MapMatchedManeuver]) {
        logger.notice("Road Book « \(trackName, privacy: .public) » : \(maneuvers.count) checkpoints")
        for line in lines(maneuvers: maneuvers, mapMatched: mapMatched) {
            logger.notice("\(line, privacy: .public)")
        }
    }
    #endif
}
