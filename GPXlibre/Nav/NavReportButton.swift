import SwiftUI
import UIKit

/// Signalement 1-tap Mode Nav : danger/bouchon/attention → waypoint LOCAL uniquement,
/// aucun serveur de partage en v1 (viendra plus tard, communautaire).
struct NavReportButton: View {
    @EnvironmentObject private var waypointStore: RollingWaypointStore
    @EnvironmentObject private var session: RideSessionManager
    @State private var isExpanded = false
    private let hapticGenerator = UINotificationFeedbackGenerator()

    var body: some View {
        VStack(alignment: .trailing, spacing: 10) {
            if isExpanded {
                HStack(spacing: 10) {
                    ForEach(WaypointCategory.navReportCategories) { category in
                        Button {
                            report(category: category)
                        } label: {
                            Image(systemName: category.systemImageName)
                                .font(.system(size: 18, weight: .bold))
                                .foregroundStyle(.white)
                                .frame(width: 44, height: 44)
                                .background(Color.red.opacity(0.85))
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
                Image(systemName: isExpanded ? "xmark" : "exclamationmark.bubble.fill")
                    .font(.system(size: 22, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(width: 52, height: 52)
                    .background(Color.red.opacity(0.9))
                    .clipShape(Circle())
            }
            .accessibilityLabel("Signaler")
        }
    }

    private func report(category: WaypointCategory) {
        guard let location = session.currentLocation else { return }
        waypointStore.add(category: category, coordinate: location.coordinate, recordedTrackID: nil)
        hapticGenerator.notificationOccurred(.success)
        withAnimation { isExpanded = false }
    }
}
