import SwiftUI

/// Bascule Trace / Nav — visible et évidente en haut de l'écran Ride. On ne mélange jamais
/// les deux : changer de mode arrête proprement l'autre (voir RideView).
struct RideModeSegmentedControl: View {
    @Binding var mode: RideMode

    var body: some View {
        Picker("Mode", selection: $mode) {
            ForEach(RideMode.allCases) { mode in
                Text(mode.label).tag(mode)
            }
        }
        .pickerStyle(.segmented)
        .background(.black.opacity(0.35))
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .padding(.horizontal, 60)
    }
}
