import SwiftUI
import CoreLocation

/// Palette RÉSOLUE (spec "roadbook-ui-redesign", it25, point 0) — DISTINCTE du réglage utilisateur
/// `RoadbookPaletteSetting` ci-dessous : celui-ci porte l'INTENTION ("automatique"/forcé), celle-là
/// le résultat final après résolution (jamais "automatique" une fois résolu).
enum RoadbookPalette: String, Codable, Equatable {
    case paper, night
}

/// Réglage UTILISATEUR (Réglages > Apparence > "Palette Road Book") — `.automatic` (défaut)
/// laisse `RoadbookPaletteResolver` décider selon l'heure/la position, `.paper`/`.night` forcent
/// une valeur en permanence (retour terrain : "tunnel long, préférence personnelle").
enum RoadbookPaletteSetting: String, CaseIterable, Identifiable, Codable, Equatable {
    case automatic, paper, night

    var id: String { rawValue }

    var label: String {
        switch self {
        case .automatic: return "Automatique"
        case .paper: return "Papier (clair)"
        case .night: return "Sombre"
        }
    }

    /// `nil` = laisser `RoadbookPaletteResolver` décider — jamais une 3e valeur côté résolveur,
    /// qui ne connaît que `RoadbookPalette` (déjà tranché).
    var overrideValue: RoadbookPalette? {
        switch self {
        case .automatic: return nil
        case .paper: return .paper
        case .night: return .night
        }
    }
}

/// Résolution PURE (aucun effet de bord) de la palette effective — même patron que
/// `MapSourceResolver`/`RoutingProviderResolver` : un réglage explicite gagne toujours, sinon
/// bascule automatique selon le lever/coucher du soleil réel à la position actuelle
/// (`SolarTimeCalculator`), avec un repli honnête si aucune position n'est disponible (Mode
/// Classique sans permission de localisation, ou pas encore de fix).
enum RoadbookPaletteResolver {
    static func resolve(
        override: RoadbookPalette?,
        now: Date = Date(),
        coordinate: CLLocationCoordinate2D?,
        calendar: Calendar = .current
    ) -> RoadbookPalette {
        if let override { return override }

        if let coordinate, let (sunrise, sunset) = SolarTimeCalculator.sunriseSunset(for: now, coordinate: coordinate) {
            return (now >= sunrise && now < sunset) ? .paper : .night
        }

        // Repli honnête SANS position (permission refusée/pas encore de fix, spec "roadbook-mode"
        // Mode Classique n'a pas toujours de GPS actif) — heuristique horaire simple, pas une
        // fausse précision astronomique qu'on ne peut pas calculer sans coordonnées.
        let hour = calendar.component(.hour, from: now)
        return (hour >= RoadBookConstants.paletteFallbackDayStartHour && hour < RoadBookConstants.paletteFallbackDayEndHour) ? .paper : .night
    }
}

/// Jeu de couleurs esprit "roadbook papier de rallye" (fond clair/crème, texte sombre, accents
/// colorés ponctuels) — DISTINCT des couleurs sémantiques standard (`Color(.systemBackground)`
/// en mode clair est blanc pur, pas crème) : appliqué en PLUS de `colorScheme` (qui, lui, pilote
/// `.primary`/`.secondary` et le rendu natif des contrôles), jamais à la place.
struct RoadbookPaletteColors: Equatable {
    let colorScheme: ColorScheme
    /// Fond de page — appliqué à la racine de l'écran Road Book uniquement (périmètre explicite
    /// de la fiche : ni la carte Ride, ni le reste de l'app).
    let background: Color
    /// Fond des surfaces "au-dessus" du fond de page (carte hero, lignes mises en avant).
    let surface: Color
    /// Filets/séparateurs de tableau — volontairement PLUS visibles qu'un simple `.opacity(0.15)`
    /// sur fond crème (moins de contraste naturel qu'un fond blanc pur).
    let rule: Color

    static func resolved(for palette: RoadbookPalette) -> RoadbookPaletteColors {
        switch palette {
        case .paper:
            return RoadbookPaletteColors(
                colorScheme: .light,
                background: Color(red: 0.97, green: 0.945, blue: 0.88),
                surface: Color(red: 1.0, green: 0.99, blue: 0.955),
                rule: Color.black.opacity(0.18)
            )
        case .night:
            return RoadbookPaletteColors(
                colorScheme: .dark,
                background: Color.black,
                surface: Color(white: 0.11),
                rule: Color.white.opacity(0.18)
            )
        }
    }
}

private struct RoadbookPaletteColorsKey: EnvironmentKey {
    static let defaultValue = RoadbookPaletteColors.resolved(for: .paper)
}

extension EnvironmentValues {
    var roadbookPaletteColors: RoadbookPaletteColors {
        get { self[RoadbookPaletteColorsKey.self] }
        set { self[RoadbookPaletteColorsKey.self] = newValue }
    }
}

/// Calcul APPROXIMATIF du lever/coucher du soleil (formule d'équation du lever de soleil,
/// précision de l'ordre de ±10-15 min — ignore volontairement l'équation du temps, largement
/// suffisant pour une bascule de palette visuelle, PAS un usage scientifique/religieux).
enum SolarTimeCalculator {
    /// `nil` en cas de jour ou nuit polaire (le point ne se lève/couche pas ce jour-là à cette
    /// latitude) — l'appelant (`RoadbookPaletteResolver`) retombe alors sur l'heuristique horaire.
    static func sunriseSunset(for date: Date, coordinate: CLLocationCoordinate2D) -> (sunrise: Date, sunset: Date)? {
        var utcCalendar = Calendar(identifier: .gregorian)
        utcCalendar.timeZone = TimeZone(identifier: "UTC") ?? .gmt
        guard let dayOfYear = utcCalendar.ordinality(of: .day, in: .year, for: date) else { return nil }

        let latitudeRadians = coordinate.latitude * .pi / 180
        // Déclinaison solaire approximative (Cooper's equation).
        let declinationRadians = -23.44 * .pi / 180 * cos(2 * .pi / 365.0 * (Double(dayOfYear) + 10))

        let cosHourAngle = -tan(latitudeRadians) * tan(declinationRadians)
        guard cosHourAngle >= -1, cosHourAngle <= 1 else { return nil }
        let hourAngleDegrees = acos(cosHourAngle) * 180 / .pi
        let halfDayHours = hourAngleDegrees / 15

        // Midi solaire approximatif en UTC — ignore l'équation du temps (±15 min max dans
        // l'année), négligeable pour cet usage (bascule de palette, pas un cadran solaire).
        let solarNoonUTCHours = 12 - coordinate.longitude / 15
        let sunriseUTCHours = solarNoonUTCHours - halfDayHours
        let sunsetUTCHours = solarNoonUTCHours + halfDayHours

        guard let startOfDayUTC = utcCalendar.date(from: utcCalendar.dateComponents([.year, .month, .day], from: date)) else { return nil }
        let sunrise = startOfDayUTC.addingTimeInterval(sunriseUTCHours * 3600)
        let sunset = startOfDayUTC.addingTimeInterval(sunsetUTCHours * 3600)
        return (sunrise, sunset)
    }
}
