import SwiftUI
import UIKit

/// Marquage POI en un tap (Essence/Eau/Bivouac/Point de vue/Attention) — le bouton principal
/// reste seul visible par défaut ; un tap révèle les 5 catégories, un second tap crée le
/// waypoint et referme. Note audio courte proposée juste après, entièrement optionnelle.
struct WaypointQuickAddButton: View {
    @EnvironmentObject private var waypointStore: RollingWaypointStore
    @EnvironmentObject private var session: RideSessionManager
    @StateObject private var audioRecorder = WaypointAudioRecorder()

    @State private var isExpanded = false
    @State private var lastCreatedWaypoint: RollingWaypoint?
    @State private var showAudioPrompt = false

    private let hapticGenerator = UINotificationFeedbackGenerator()

    var body: some View {
        VStack(alignment: .trailing, spacing: 10) {
            if showAudioPrompt, let waypoint = lastCreatedWaypoint {
                AudioNotePromptView(
                    isRecording: audioRecorder.isRecording,
                    onStart: { startAudio(for: waypoint) },
                    onStop: { audioRecorder.stop() }
                )
            }

            if isExpanded {
                HStack(spacing: 10) {
                    ForEach(WaypointCategory.allCases) { category in
                        Button {
                            createWaypoint(category: category)
                        } label: {
                            Image(systemName: category.systemImageName)
                                .font(.system(size: 18, weight: .bold))
                                .foregroundStyle(.white)
                                .frame(width: 44, height: 44)
                                .background(.blue.opacity(0.85))
                                .clipShape(Circle())
                        }
                        .accessibilityLabel(category.label)
                    }
                }
                .padding(8)
                .background(.black.opacity(0.55))
                .clipShape(Capsule())
            }

            Button {
                withAnimation { isExpanded.toggle() }
            } label: {
                Image(systemName: isExpanded ? "xmark" : "mappin.and.ellipse")
                    .font(.system(size: 22, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(width: 52, height: 52)
                    .background(.blue.opacity(0.9))
                    .clipShape(Circle())
            }
            .accessibilityLabel("Ajouter un point d'intérêt")
        }
    }

    private func createWaypoint(category: WaypointCategory) {
        guard let location = session.currentLocation else { return }
        let waypoint = waypointStore.add(category: category, coordinate: location.coordinate, recordedTrackID: nil)
        hapticGenerator.notificationOccurred(.success)
        withAnimation {
            isExpanded = false
            lastCreatedWaypoint = waypoint
            showAudioPrompt = true
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + WaypointConstants.audioPromptWindowSeconds) {
            if !audioRecorder.isRecording {
                withAnimation { showAudioPrompt = false }
            }
        }
    }

    private func startAudio(for waypoint: RollingWaypoint) {
        audioRecorder.start { url in
            defer { withAnimation { showAudioPrompt = false } }
            guard let url else { return }
            let fileName = "\(waypoint.id.uuidString).m4a"
            let destination = waypointStore.audioDirectory.appendingPathComponent(fileName)
            try? FileManager.default.removeItem(at: destination)
            try? FileManager.default.moveItem(at: url, to: destination)
            waypointStore.attachAudio(fileName: fileName, to: waypoint)
        }
    }
}

private struct AudioNotePromptView: View {
    let isRecording: Bool
    let onStart: () -> Void
    let onStop: () -> Void

    var body: some View {
        Button(action: isRecording ? onStop : onStart) {
            HStack(spacing: 6) {
                Image(systemName: isRecording ? "stop.circle.fill" : "mic.circle.fill")
                Text(isRecording ? "Arrêter" : "Note audio")
            }
            .font(.caption.bold())
            .foregroundStyle(.white)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(isRecording ? Color.red.opacity(0.85) : Color.black.opacity(0.6))
            .clipShape(Capsule())
        }
    }
}
