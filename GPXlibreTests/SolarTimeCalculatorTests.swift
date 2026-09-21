import XCTest
import CoreLocation
@testable import GPXlibre

/// Spec "roadbook-ui-redesign" (it25, point 0) — calcul PUR, aucun réseau/permission ici.
/// Précision volontairement approximative (±10-15 min, équation du temps ignorée) : les tests
/// vérifient des propriétés STRUCTURELLES (ordre, longueur du jour, cas polaires) plutôt que des
/// horaires exacts codés en dur, pour rester robustes à un futur raffinement de la formule.
final class SolarTimeCalculatorTests: XCTestCase {
    /// 21 mars ~midi UTC — équinoxe, jour ≈ nuit partout sauf aux pôles.
    private let equinox = ISO8601DateFormatter().date(from: "2026-03-20T12:00:00Z")!
    /// Solstice d'été (hémisphère nord).
    private let juneSolstice = ISO8601DateFormatter().date(from: "2026-06-21T12:00:00Z")!
    /// Solstice d'hiver (hémisphère nord).
    private let decemberSolstice = ISO8601DateFormatter().date(from: "2026-12-21T12:00:00Z")!

    private let paris = CLLocationCoordinate2D(latitude: 48.85, longitude: 2.35)
    private let equator = CLLocationCoordinate2D(latitude: 0, longitude: 0)

    func testSunriseIsAlwaysBeforeSunset() {
        let result = SolarTimeCalculator.sunriseSunset(for: juneSolstice, coordinate: paris)
        XCTAssertNotNil(result)
        XCTAssertLessThan(result!.sunrise, result!.sunset)
    }

    /// À l'équateur, le jour dure environ 12h toute l'année (variation saisonnière minimale).
    func testEquatorHasRoughlyTwelveHourDaysYearRound() {
        for date in [equinox, juneSolstice, decemberSolstice] {
            let result = SolarTimeCalculator.sunriseSunset(for: date, coordinate: equator)
            XCTAssertNotNil(result)
            let dayLengthHours = result!.sunset.timeIntervalSince(result!.sunrise) / 3600
            XCTAssertEqual(dayLengthHours, 12, accuracy: 0.5, "\(date)")
        }
    }

    /// À l'équinoxe, le jour dure ~12h à N'IMPORTE QUELLE latitude non polaire.
    func testEquinoxHasRoughlyTwelveHourDaysAtMidLatitude() {
        let result = SolarTimeCalculator.sunriseSunset(for: equinox, coordinate: paris)
        XCTAssertNotNil(result)
        let dayLengthHours = result!.sunset.timeIntervalSince(result!.sunrise) / 3600
        XCTAssertEqual(dayLengthHours, 12, accuracy: 0.5)
    }

    /// Hémisphère nord : le jour du solstice d'été est nettement plus long que celui du solstice
    /// d'hiver, à une latitude qui n'est ni équatoriale ni polaire.
    func testSummerDayIsLongerThanWinterDayAtMidLatitude() {
        let summer = SolarTimeCalculator.sunriseSunset(for: juneSolstice, coordinate: paris)!
        let winter = SolarTimeCalculator.sunriseSunset(for: decemberSolstice, coordinate: paris)!
        let summerLength = summer.sunset.timeIntervalSince(summer.sunrise)
        let winterLength = winter.sunset.timeIntervalSince(winter.sunrise)
        XCTAssertGreaterThan(summerLength, winterLength)
    }

    /// Nuit polaire : au cercle arctique et au-delà, en plein hiver, le soleil ne se lève jamais.
    func testPolarNightReturnsNilInWinterAtExtremeLatitude() {
        let farNorth = CLLocationCoordinate2D(latitude: 78, longitude: 15)
        XCTAssertNil(SolarTimeCalculator.sunriseSunset(for: decemberSolstice, coordinate: farNorth))
    }

    /// Jour polaire : symétriquement, en plein été, le soleil ne se couche jamais.
    func testPolarDayReturnsNilInSummerAtExtremeLatitude() {
        let farNorth = CLLocationCoordinate2D(latitude: 78, longitude: 15)
        XCTAssertNil(SolarTimeCalculator.sunriseSunset(for: juneSolstice, coordinate: farNorth))
    }

    /// Deux points à la même latitude mais des longitudes différentes ont un midi solaire décalé
    /// d'environ 4 minutes par degré de longitude — vérifie que la longitude est bien prise en
    /// compte, pas seulement la latitude.
    func testLongitudeShiftsSolarNoonEastward() {
        let west = CLLocationCoordinate2D(latitude: 45, longitude: -75) // ~heure de l'Est US
        let east = CLLocationCoordinate2D(latitude: 45, longitude: 15) // ~Europe centrale
        let resultWest = SolarTimeCalculator.sunriseSunset(for: equinox, coordinate: west)!
        let resultEast = SolarTimeCalculator.sunriseSunset(for: equinox, coordinate: east)!
        // 90° d'écart ≈ 6h de décalage de midi solaire en UTC.
        let sunriseShiftHours = resultWest.sunrise.timeIntervalSince(resultEast.sunrise) / 3600
        XCTAssertEqual(sunriseShiftHours, 6, accuracy: 0.2)
    }
}
