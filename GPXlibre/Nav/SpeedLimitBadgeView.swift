import SwiftUI

/// Panneau de limite de vitesse façon signalisation routière — silencieux si absent (tag
/// OSM maxspeed rare hors zones urbaines denses). Alerte visuelle si dépassement.
struct SpeedLimitBadgeView: View {
    let speedLimitKmh: Int
    let isOverLimit: Bool

    var body: some View {
        Text("\(speedLimitKmh)")
            .font(.system(size: 22, weight: .heavy, design: .rounded))
            .foregroundStyle(.black)
            .frame(width: 54, height: 54)
            .background(Circle().fill(.white))
            .overlay(Circle().stroke(isOverLimit ? .red : .red.opacity(0.8), lineWidth: isOverLimit ? 6 : 5))
            .shadow(color: isOverLimit ? .red.opacity(0.8) : .clear, radius: 8)
            .animation(.easeInOut(duration: 0.2), value: isOverLimit)
            .accessibilityLabel("Limite de vitesse \(speedLimitKmh) km/h\(isOverLimit ? ", dépassée" : "")")
    }
}
