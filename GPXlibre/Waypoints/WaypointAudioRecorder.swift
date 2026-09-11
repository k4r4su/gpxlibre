import Foundation
import AVFoundation

@MainActor
final class WaypointAudioRecorder: NSObject, ObservableObject, AVAudioRecorderDelegate {
    @Published private(set) var isRecording = false

    private var recorder: AVAudioRecorder?
    private var stopTimer: Timer?
    private var completion: ((URL?) -> Void)?

    func start(completion: @escaping (URL?) -> Void) {
        self.completion = completion
        AVAudioSession.sharedInstance().requestRecordPermission { [weak self] granted in
            Task { @MainActor in
                guard let self, granted else {
                    completion(nil)
                    return
                }
                self.beginRecording()
            }
        }
    }

    private func beginRecording() {
        let session = AVAudioSession.sharedInstance()
        try? session.setCategory(.playAndRecord, options: [.defaultToSpeaker])
        try? session.setActive(true)

        let url = FileManager.default.temporaryDirectory.appendingPathComponent("\(UUID().uuidString).m4a")
        let settings: [String: Any] = [
            AVFormatIDKey: kAudioFormatMPEG4AAC,
            AVSampleRateKey: 12_000,
            AVNumberOfChannelsKey: 1,
            AVEncoderAudioQualityKey: AVAudioQuality.medium.rawValue,
        ]

        guard let recorder = try? AVAudioRecorder(url: url, settings: settings) else {
            completion?(nil)
            return
        }
        self.recorder = recorder
        recorder.delegate = self
        recorder.record(forDuration: WaypointConstants.maxAudioNoteDurationSeconds)
        isRecording = true
    }

    func stop() {
        guard isRecording else { return }
        recorder?.stop()
    }

    nonisolated func audioRecorderDidFinishRecording(_ recorder: AVAudioRecorder, successfully flag: Bool) {
        Task { @MainActor in
            self.isRecording = false
            self.completion?(flag ? recorder.url : nil)
            self.completion = nil
        }
    }
}
