import XCTest
import CoreLocation
@testable import GPXlibre

/// Bloc 5 — "livrer les tests unitaires du encode/decode" est un engagement explicite de
/// la spec, y compris si la connectivité à une vraie instance ne peut pas être prouvée en
/// session (voir server/README.md pour la démonstration curl du serveur lui-même).
final class SharedBlockageCodingTests: XCTestCase {
    func testDecodesServerStyleFractionalISO8601Dates() throws {
        // Format exact émis par server/app.py (`datetime.now(timezone.utc).isoformat()`) :
        // microsecondes + offset "+00:00", qu'ISO8601DateFormatter par défaut ne comprend pas.
        let json = """
        {
            "id": "5ef689e8-65b9-4d0e-a8e1-d61dd50d78e0",
            "lat": 45.188529,
            "lon": 5.724524,
            "note": "arbre au sol",
            "created_at": "2026-09-12T08:56:56.651092+00:00",
            "last_confirmed_at": "2026-09-12T08:56:56.679075+00:00"
        }
        """
        let blockage = try SharedBlockageCoding.decoder.decode(SharedBlockage.self, from: Data(json.utf8))

        XCTAssertEqual(blockage.id, "5ef689e8-65b9-4d0e-a8e1-d61dd50d78e0")
        XCTAssertEqual(blockage.coordinate.latitude, 45.188529, accuracy: 0.000001)
        XCTAssertEqual(blockage.coordinate.longitude, 5.724524, accuracy: 0.000001)
        XCTAssertEqual(blockage.note, "arbre au sol")
        XCTAssertNotNil(blockage.createdAt)
    }

    func testDecodesPlainISO8601DatesWithoutFractionalSeconds() throws {
        let json = """
        {
            "id": "abc",
            "lat": 45.0,
            "lon": 5.0,
            "note": null,
            "created_at": "2026-09-12T08:56:56+00:00",
            "last_confirmed_at": "2026-09-12T08:56:56+00:00"
        }
        """
        let blockage = try SharedBlockageCoding.decoder.decode(SharedBlockage.self, from: Data(json.utf8))
        XCTAssertNil(blockage.note)
        XCTAssertEqual(blockage.coordinate.latitude, 45.0, accuracy: 0.000001)
    }

    func testDecodingArrayOfBlockagesMatchesGETResponseShape() throws {
        let json = """
        [
            {"id": "a", "lat": 45.0, "lon": 5.0, "note": null, "created_at": "2026-09-12T08:56:56.0+00:00", "last_confirmed_at": "2026-09-12T08:56:56.0+00:00"},
            {"id": "b", "lat": 46.0, "lon": 6.0, "note": "barriere fermee", "created_at": "2026-09-12T08:56:56.0+00:00", "last_confirmed_at": "2026-09-12T08:56:56.0+00:00"}
        ]
        """
        let blockages = try SharedBlockageCoding.decoder.decode([SharedBlockage].self, from: Data(json.utf8))
        XCTAssertEqual(blockages.count, 2)
        XCTAssertEqual(blockages.map(\.id), ["a", "b"])
    }

    func testEncodeThenDecodeRoundTripsExactly() throws {
        let original = SharedBlockage(
            id: UUID().uuidString,
            coordinate: CLLocationCoordinate2D(latitude: 45.5, longitude: 5.5),
            note: "test aller-retour",
            createdAt: Date(timeIntervalSince1970: 1_757_000_000),
            lastConfirmedAt: Date(timeIntervalSince1970: 1_757_000_100)
        )

        let data = try SharedBlockageCoding.encoder.encode(original)
        let decoded = try SharedBlockageCoding.decoder.decode(SharedBlockage.self, from: data)

        XCTAssertEqual(decoded.id, original.id)
        XCTAssertEqual(decoded.note, original.note)
        XCTAssertEqual(decoded.coordinate.latitude, original.coordinate.latitude, accuracy: 0.000001)
        XCTAssertEqual(decoded.coordinate.longitude, original.coordinate.longitude, accuracy: 0.000001)
        XCTAssertEqual(decoded.createdAt.timeIntervalSince1970, original.createdAt.timeIntervalSince1970, accuracy: 0.001)
        XCTAssertEqual(decoded.lastConfirmedAt.timeIntervalSince1970, original.lastConfirmedAt.timeIntervalSince1970, accuracy: 0.001)
    }

    func testOutgoingReportEncodesReporterIDAsSnakeCase() throws {
        let report = SharedBlockageOutgoingReport(
            coordinate: CLLocationCoordinate2D(latitude: 45.1, longitude: 5.2),
            note: "chute d'arbre",
            reporterID: "abc123"
        )
        let data = try SharedBlockageCoding.encoder.encode(report)
        let object = try JSONSerialization.jsonObject(with: data) as? [String: Any]

        XCTAssertEqual(object?["reporter_id"] as? String, "abc123")
        XCTAssertEqual(object?["lat"] as? Double, 45.1)
        XCTAssertEqual(object?["lon"] as? Double, 5.2)
        XCTAssertEqual(object?["note"] as? String, "chute d'arbre")
    }

    func testFadeAndExpiryThresholds() {
        let fresh = SharedBlockage(id: "a", coordinate: CLLocationCoordinate2D(latitude: 0, longitude: 0), note: nil, createdAt: Date(), lastConfirmedAt: Date())
        XCTAssertFalse(fresh.isFaded)
        XCTAssertFalse(fresh.isExpired)

        let faded = SharedBlockage(id: "b", coordinate: CLLocationCoordinate2D(latitude: 0, longitude: 0), note: nil, createdAt: Date(), lastConfirmedAt: Date().addingTimeInterval(-95 * 86400))
        XCTAssertTrue(faded.isFaded)
        XCTAssertFalse(faded.isExpired)

        let expired = SharedBlockage(id: "c", coordinate: CLLocationCoordinate2D(latitude: 0, longitude: 0), note: nil, createdAt: Date(), lastConfirmedAt: Date().addingTimeInterval(-190 * 86400))
        XCTAssertTrue(expired.isExpired)
    }

    func testBBoxAroundTrackPointsIncludesPadding() {
        let points = [
            CLLocationCoordinate2D(latitude: 45.0, longitude: 5.0),
            CLLocationCoordinate2D(latitude: 45.2, longitude: 5.3),
        ]
        let bbox = SharedBlockageBBox.around(trackPoints: points, paddingDegrees: 0.01)
        XCTAssertNotNil(bbox)
        XCTAssertEqual(bbox?.minLat ?? 0, 44.99, accuracy: 0.0001)
        XCTAssertEqual(bbox?.maxLat ?? 0, 45.21, accuracy: 0.0001)
    }

    func testBBoxAroundEmptyTrackPointsIsNil() {
        XCTAssertNil(SharedBlockageBBox.around(trackPoints: []))
    }
}
