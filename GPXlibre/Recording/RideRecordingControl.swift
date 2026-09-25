import SwiftUI
import CoreLocation

/// Bouton d'enregistrement de la sortie (it30) — posé au-dessus du badge vitesse, dans le MÊME
/// calque (`RideView.speedoBadgeLayer`) : aucune nouvelle zone d'overlay. Trois états :
/// "Enregistrer" (rien en cours), "REC · n pts" (tap = pause), "Pause · n pts" (tap = reprendre).
/// Terminer la sortie : panneau Mesures (`RideStatsPanel`), comme avant.
struct RideRecordingControl: View {
    @EnvironmentObject private var recorder: RideRecorder
    @State private var showDeniedAlert = false

    var body: some View {
        Button(action: toggle) {
            HStack(spacing: 6) {
                Circle()
                    .fill(dotColor)
                    .frame(width: 10, height: 10)
                Text(RideRecordingControl.label(state: recorder.state, pointCount: recorder.pointCount))
                    .font(.caption.bold().monospacedDigit())
                    .lineLimit(1)
            }
            .foregroundStyle(.white)
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .background(Color.black.opacity(0.35))
            .background(.ultraThinMaterial)
            .environment(\.colorScheme, .dark)
            .clipShape(Capsule())
            .shadow(color: .black.opacity(0.28), radius: 8, x: 0, y: 3)
        }
        .accessibilityLabel(RideRecordingControl.accessibilityLabel(state: recorder.state, pointCount: recorder.pointCount))
        .recordingDeniedAlert(isPresented: $showDeniedAlert)
    }

    private var dotColor: Color {
        switch recorder.state {
        case .idle: return .red.opacity(0.85)
        case .recording: return .red
        case .paused: return .orange
        }
    }

    private func toggle() {
        switch recorder.state {
        case .idle, .paused:
            if recorder.start() == .denied { showDeniedAlert = true }
        case .recording:
            recorder.pause()
        }
    }

    static func label(state: RideRecorder.State, pointCount: Int) -> String {
        switch state {
        case .idle: return "Enregistrer"
        case .recording: return "REC · \(pointCount) pts"
        case .paused: return "Pause · \(pointCount) pts"
        }
    }

    static func accessibilityLabel(state: RideRecorder.State, pointCount: Int) -> String {
        switch state {
        case .idle: return "Démarrer l'enregistrement de la sortie"
        case .recording: return "Enregistrement en cours, \(pointCount) points. Toucher pour mettre en pause"
        case .paused: return "Enregistrement en pause, \(pointCount) points. Toucher pour reprendre"
        }
    }
}

/// Message d'état de l'enregistrement pour le panneau Mesures — explique aussi les cas dégradés.
enum RideRecordingStatusText {
    static func text(state: RideRecorder.State, authorization: CLAuthorizationStatus, wasRestored: Bool) -> String? {
        switch authorization {
        case .denied, .restricted:
            return "Localisation refusée : aucun enregistrement possible. Autorise GPXlibre dans Réglages > Confidentialité > Service de localisation."
        default:
            break
        }
        if wasRestored, state == .paused {
            return "Sortie retrouvée après l'arrêt de l'app : en pause. Reprends ou termine-la."
        }
        switch state {
        case .recording: return "L'enregistrement continue dans les autres onglets, écran verrouillé ou dans une autre app (flèche bleue d'iOS en haut de l'écran)."
        case .paused: return "Enregistrement en pause : aucun point n'est capté."
        case .idle: return nil
        }
    }
}

private struct RecordingDeniedAlert: ViewModifier {
    @Binding var isPresented: Bool

    func body(content: Content) -> some View {
        content.alert("Localisation refusée", isPresented: $isPresented) {
            Button("Ouvrir Réglages") {
                if let url = URL(string: UIApplication.openSettingsURLString) { UIApplication.shared.open(url) }
            }
            Button("Annuler", role: .cancel) {}
        } message: {
            Text("GPXlibre ne peut pas enregistrer ta sortie sans accès à la localisation. Choisis « Lorsque l'app est active » (suffisant, l'enregistrement continue écran verrouillé) dans les Réglages.")
        }
    }
}

extension View {
    func recordingDeniedAlert(isPresented: Binding<Bool>) -> some View {
        modifier(RecordingDeniedAlert(isPresented: isPresented))
    }
}
