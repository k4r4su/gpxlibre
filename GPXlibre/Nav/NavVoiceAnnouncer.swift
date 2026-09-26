import Foundation
import AVFoundation

/// Synthèse vocale française native (AVSpeechSynthesizer, gratuit) — annonce chaque manœuvre
/// à 500 m puis 100 m. Utilisé uniquement en Mode Nav.
@MainActor
final class NavVoiceAnnouncer {
    private let synthesizer = AVSpeechSynthesizer()

    func announce(_ text: String, volume: Float = 1.0) {
        guard !text.isEmpty else { return }
        let utterance = AVSpeechUtterance(string: text)
        utterance.voice = AVSpeechSynthesisVoice(language: AppLanguageBundle.bcp47)
        utterance.rate = AVSpeechUtteranceDefaultSpeechRate
        utterance.volume = volume
        synthesizer.speak(utterance)
    }

    func stop() {
        synthesizer.stopSpeaking(at: .immediate)
    }
}
