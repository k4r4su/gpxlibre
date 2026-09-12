import XCTest
import CoreLocation
@testable import GPXlibre

/// Test d'intégration optionnel contre une vraie instance du serveur Bloc 5
/// (`server/`, voir docker-compose.yml) tournant en local sur la machine de dev — pas le
/// simulateur iOS, qui partage le réseau de l'hôte et peut donc atteindre `127.0.0.1`.
///
/// `XCTSkip` si le serveur n'est pas démarré : ce test ne doit jamais faire échouer une
/// exécution normale de la suite (le serveur n'est pas censé tourner en permanence). Pour
/// le lancer réellement : `cd server && docker compose up -d --build`, puis exécuter la
/// suite de tests.
final class SharedBlockageLiveServerTests: XCTestCase {
    private let localServerURL = "http://127.0.0.1:8000"

    private func skipIfServerUnreachable() async throws {
        guard let url = URL(string: "\(localServerURL)/health") else { return }
        do {
            var request = URLRequest(url: url, timeoutInterval: 2)
            request.httpMethod = "GET"
            _ = try await URLSession.shared.data(for: request)
        } catch {
            throw XCTSkip("Serveur local non joignable sur \(localServerURL) — lancer `docker compose up` dans server/ pour exécuter ce test.")
        }
    }

    func testSubmitAndFetchAgainstRealLocalServer() async throws {
        try await skipIfServerUnreachable()

        // Coordonnée unique par run pour ne jamais entrer en collision de dédoublonnage
        // (rayon 100 m côté serveur) avec un run précédent.
        let coordinate = CLLocationCoordinate2D(latitude: 48.0 + Double.random(in: 0...0.5), longitude: 2.0 + Double.random(in: 0...0.5))
        let report = SharedBlockageOutgoingReport(coordinate: coordinate, note: "test live", reporterID: "test-runner")

        let created = try await SharedBlockageSyncService.submit(report, serverURLString: localServerURL)
        XCTAssertEqual(created.coordinate.latitude, coordinate.latitude, accuracy: 0.000001)
        XCTAssertEqual(created.note, "test live")

        let bbox = SharedBlockageBBox.around(trackPoints: [coordinate], paddingDegrees: 0.01)!
        let fetched = try await SharedBlockageSyncService.fetch(bbox: bbox, serverURLString: localServerURL)
        XCTAssertTrue(fetched.contains { $0.id == created.id })
    }
}
