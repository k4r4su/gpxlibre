import XCTest
import CoreLocation
@testable import GPXlibre

/// Spec "roadbook-ui-redesign" (it25, point 0) — résolution PURE, aucun réseau/permission ici.
final class RoadbookPaletteResolverTests: XCTestCase {
    private let paris = CLLocationCoordinate2D(latitude: 48.85, longitude: 2.35)
    /// 21 juin, 12h UTC ≈ 14h heure locale Paris — en plein jour, sans ambiguïté.
    private let noonInJune = ISO8601DateFormatter().date(from: "2026-06-21T12:00:00Z")!
    /// 21 juin, minuit UTC ≈ 2h heure locale Paris — en pleine nuit, sans ambiguïté.
    private let midnightInJune = ISO8601DateFormatter().date(from: "2026-06-21T00:00:00Z")!

    func testExplicitOverrideAlwaysWinsRegardlessOfTimeOrPosition() {
        XCTAssertEqual(
            RoadbookPaletteResolver.resolve(override: .night, now: noonInJune, coordinate: paris),
            .night
        )
        XCTAssertEqual(
            RoadbookPaletteResolver.resolve(override: .paper, now: midnightInJune, coordinate: paris),
            .paper
        )
    }

    func testAutomaticResolvesToPaperDuringDaylightWithAKnownPosition() {
        XCTAssertEqual(
            RoadbookPaletteResolver.resolve(override: nil, now: noonInJune, coordinate: paris),
            .paper
        )
    }

    func testAutomaticResolvesToNightAfterDarkWithAKnownPosition() {
        XCTAssertEqual(
            RoadbookPaletteResolver.resolve(override: nil, now: midnightInJune, coordinate: paris),
            .night
        )
    }

    /// Repli honnête sans position — heuristique horaire (`RoadBookConstants.
    /// paletteFallbackDayStartHour/EndHour`), jamais un crash ni une valeur figée.
    func testAutomaticFallsBackToHourHeuristicWithoutAPosition() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!

        let midday = calendar.date(bySettingHour: 14, minute: 0, second: 0, of: noonInJune)!
        let midnight = calendar.date(bySettingHour: 2, minute: 0, second: 0, of: noonInJune)!

        XCTAssertEqual(RoadbookPaletteResolver.resolve(override: nil, now: midday, coordinate: nil, calendar: calendar), .paper)
        XCTAssertEqual(RoadbookPaletteResolver.resolve(override: nil, now: midnight, coordinate: nil, calendar: calendar), .night)
    }

    /// Cas polaire (`SolarTimeCalculator` retourne `nil`) — même repli honnête que "sans
    /// position", jamais une valeur absurde ou un crash.
    func testAutomaticFallsBackToHourHeuristicOnPolarDayOrNight() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        let farNorth = CLLocationCoordinate2D(latitude: 78, longitude: 15)
        let decemberMidday = calendar.date(bySettingHour: 14, minute: 0, second: 0, of: ISO8601DateFormatter().date(from: "2026-12-21T00:00:00Z")!)!

        XCTAssertEqual(RoadbookPaletteResolver.resolve(override: nil, now: decemberMidday, coordinate: farNorth, calendar: calendar), .paper)
    }
}
