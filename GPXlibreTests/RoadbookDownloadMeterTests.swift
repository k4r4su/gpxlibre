import XCTest
@testable import GPXlibre

/// It29 — mesures de la progression enrichie (quantité, débit, temps restant), horloge simulée :
/// déterministe, aucune attente réelle.
final class RoadbookDownloadMeterTests: XCTestCase {
    private let t0 = Date(timeIntervalSince1970: 1_000_000)

    private func at(_ seconds: Double) -> Date { t0.addingTimeInterval(seconds) }

    /// Téléchargement lent simulé : 3 tronçons de 8 km, ~10 s chacun, octets par paquets.
    func testSlowDownloadGivesConsistentQuantitySpeedAndRemainingTime() throws {
        var meter = RoadbookDownloadMeter(totalMeters: 24_000, startedAt: t0)
        XCTAssertNil(meter.bytesPerSecond(at: at(0.5)), "trop tôt pour un débit honnête")
        XCTAssertNil(meter.secondsRemaining(at: at(5)), "aucun tronçon terminé : pas d'estimation")

        // 1er tronçon : le serveur calcule 7 s, puis envoie 30 Ko en 3 s.
        XCTAssertEqual(meter.bytesPerSecond(at: at(7)), 0, "rien reçu : le serveur calcule")
        for second in [8.0, 9.0, 10.0] { meter.record(bytes: 10_240, at: at(second)) }
        meter.completeChunk(meters: 8000, elements: 120, at: at(10))

        let speed = try XCTUnwrap(meter.bytesPerSecond(at: at(10)))
        XCTAssertEqual(speed, 30_720.0 / 3, accuracy: 1, "30 Ko reçus sur la fenêtre de 3 s")
        XCTAssertEqual(meter.bytesReceived, 30_720)
        XCTAssertEqual(meter.elementsReceived, 120)

        // 8 km en 10 s → 16 km restants ≈ 20 s, décomptés en continu entre deux tronçons.
        XCTAssertEqual(try XCTUnwrap(meter.secondsRemaining(at: at(10))), 20, accuracy: 0.001)
        XCTAssertEqual(try XCTUnwrap(meter.secondsRemaining(at: at(15))), 15, accuracy: 0.001)
        XCTAssertNil(meter.secondsRemaining(at: at(40)), "estimation dépassée : masquée, jamais \"presque fini\" à tort")

        // Débit qui retombe quand plus rien n'arrive (le serveur recalcule pour le tronçon suivant).
        XCTAssertEqual(try XCTUnwrap(meter.bytesPerSecond(at: at(14))), 0, accuracy: 0.001)

        // 2e tronçon plus lent : l'estimation se recale sur la moyenne CUMULÉE (pas de saut brutal).
        meter.record(bytes: 20_000, at: at(24))
        meter.completeChunk(meters: 8000, elements: 80, at: at(25))
        XCTAssertEqual(try XCTUnwrap(meter.secondsRemaining(at: at(25))), 8000 / (16_000 / 25), accuracy: 0.001)
        XCTAssertEqual(meter.stats(at: at(25)).elementsReceived, 200)
    }

    /// Les paquets d'octets ne font pas bouger l'estimation (seuls les tronçons terminés comptent) :
    /// un temps restant qui ne saute pas à chaque paquet.
    func testRemainingTimeIgnoresPacketJitter() throws {
        var meter = RoadbookDownloadMeter(totalMeters: 16_000, startedAt: t0)
        meter.completeChunk(meters: 8000, elements: 1, at: at(10))
        let before = try XCTUnwrap(meter.secondsRemaining(at: at(12)))
        for step in stride(from: 12.0, to: 13, by: 0.1) { meter.record(bytes: Int.random(in: 1...50_000), at: at(step)) }
        XCTAssertEqual(try XCTUnwrap(meter.secondsRemaining(at: at(12))), before, accuracy: 0.001)
    }

    /// Réponse refusée (504/429) : le bandeau le dit, avec le décompte jusqu'au nouvel essai — et
    /// plus jamais "attente du serveur" pendant ce temps.
    func testARetryIsAnnouncedUntilDataArrives() throws {
        var meter = RoadbookDownloadMeter(totalMeters: 16_000, startedAt: t0)
        meter.recordRetry(after: 15, at: at(8))
        let during = meter.stats(at: at(10))
        XCTAssertEqual(try XCTUnwrap(during.retryInSeconds), 13, accuracy: 0.001)
        XCTAssertEqual(RoadbookLandmarkProgressView.detail(for: during), "serveur saturé, nouvel essai dans 13 s")

        // Un tronçon déjà terminé : l'estimation reste suspendue pendant l'attente.
        meter.completeChunk(meters: 8000, elements: 1, at: at(20))
        meter.recordRetry(after: 5, at: at(21))
        XCTAssertNil(meter.stats(at: at(22)).secondsRemaining, "pas de temps restant pendant un nouvel essai")
        meter.record(bytes: 4096, at: at(25))
        XCTAssertNil(meter.stats(at: at(25)).retryInSeconds, "des données arrivent : l'essai a abouti")
    }

    func testFinishedTrackHasNoRemainingTime() {
        var meter = RoadbookDownloadMeter(totalMeters: 8000, startedAt: t0)
        meter.completeChunk(meters: 8000, elements: 1, at: at(10))
        XCTAssertNil(meter.secondsRemaining(at: at(10)))
    }

    // MARK: - Affichage

    func testDetailLineShowsQuantitySpeedAndRemainingTime() {
        let stats = RoadbookLandmarkDownloadStats(bytesReceived: 88_064, elementsReceived: 412, bytesPerSecond: 24_576, secondsRemaining: 17)
        XCTAssertEqual(RoadbookLandmarkProgressView.detail(for: stats), "412 éléments · 86 Ko · 24 Ko/s · ~20 s restantes")
    }

    /// Cible inconnue (un seul tronçon : pas de découpage) : pas de barre, pas de pourcentage — la
    /// quantité et le débit sont affichés quand même.
    func testUnknownTargetShowsQuantityAndSpeedButNoPercentage() {
        XCTAssertNil(RoadbookLandmarkProgressView.determinateProgress(for: .downloading(completedChunks: 0, totalChunks: 1)))
        XCTAssertEqual(RoadbookLandmarkProgressView.determinateProgress(for: .downloading(completedChunks: 1, totalChunks: 4)), 0.25)
        let stats = RoadbookLandmarkDownloadStats(bytesReceived: 1_572_864, elementsReceived: 0, bytesPerSecond: 0, secondsRemaining: nil)
        XCTAssertEqual(RoadbookLandmarkProgressView.detail(for: stats), "1,5 Mo · attente du serveur")
    }

    func testFormatting() {
        XCTAssertEqual(RoadbookLandmarkProgressView.byteString(512), "512 o")
        XCTAssertEqual(RoadbookLandmarkProgressView.remainingString(3), "presque fini")
        XCTAssertEqual(RoadbookLandmarkProgressView.remainingString(61), "~2 min restantes")
        XCTAssertNil(RoadbookLandmarkProgressView.detail(for: RoadbookLandmarkDownloadStats(bytesReceived: 0, elementsReceived: 0, bytesPerSecond: nil, secondsRemaining: nil)))
    }
}
