import XCTest
@testable import GPXlibre

/// It31, point 2 — proposition d'enregistrement au démarrage du suivi d'une trace.
final class RecordingPromptPolicyTests: XCTestCase {
    func testPromptsOnceWhenATrackStartsAndNothingIsRecording() {
        var policy = RecordingPromptPolicy()
        let trackID = UUID()

        XCTAssertTrue(policy.shouldPrompt(onStartOf: trackID, recorderState: .idle, recordedPointCount: 0))
        XCTAssertFalse(policy.shouldPrompt(onStartOf: trackID, recorderState: .idle, recordedPointCount: 0), "une seule fois par trace (retour sur Ride, relance du suivi)")
    }

    func testANewActiveTrackIsProposedAgain() {
        var policy = RecordingPromptPolicy()
        XCTAssertTrue(policy.shouldPrompt(onStartOf: UUID(), recorderState: .idle, recordedPointCount: 0))
        XCTAssertTrue(policy.shouldPrompt(onStartOf: UUID(), recorderState: .idle, recordedPointCount: 0))
    }

    func testNeverPromptsWithoutATrackOrWhileARecordingExists() {
        var policy = RecordingPromptPolicy()
        XCTAssertFalse(policy.shouldPrompt(onStartOf: nil, recorderState: .idle, recordedPointCount: 0), "pas de trace suivie")
        XCTAssertFalse(policy.shouldPrompt(onStartOf: UUID(), recorderState: .recording, recordedPointCount: 12))
        XCTAssertFalse(policy.shouldPrompt(onStartOf: UUID(), recorderState: .paused, recordedPointCount: 12), "sortie restaurée en pause : pas de proposition")
        XCTAssertFalse(policy.shouldPrompt(onStartOf: UUID(), recorderState: .idle, recordedPointCount: 3))
    }

    /// Un refus ne "consomme" rien d'autre : une trace refusée n'est pas reproposée, une autre oui.
    func testRefusingForOneTrackDoesNotSilenceTheNextOne() {
        var policy = RecordingPromptPolicy()
        let refused = UUID()
        _ = policy.shouldPrompt(onStartOf: refused, recorderState: .idle, recordedPointCount: 0)
        XCTAssertFalse(policy.shouldPrompt(onStartOf: refused, recorderState: .idle, recordedPointCount: 0))
        XCTAssertTrue(policy.shouldPrompt(onStartOf: UUID(), recorderState: .idle, recordedPointCount: 0))
    }
}
