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
                            VStack(spacing: 2) {
                                Image(systemName: category.systemImageName)
                                    .font(.system(size: 16, weight: .bold))
                                Text(category.label)
                                    .font(.system(size: 8, weight: .semibold))
                                    .lineLimit(1)
                                    .minimumScaleFactor(0.7)
                            }
                            .foregroundStyle(.white)
                            .frame(width: 48, height: 48)
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

            // "blocage"/signalement est une action critique (spec Bloc 2) : label texte
            // permanent, pas seulement un explicateur au long-press.
            Button {
                withAnimation { isExpanded.toggle() }
            } label: {
                VStack(spacing: 2) {
                    Image(systemName: isExpanded ? "xmark" : "exclamationmark.bubble.fill")
                        .font(.system(size: 20, weight: .bold))
                    Text(isExpanded ? "Fermer" : "Signaler")
                        .font(.system(size: 9, weight: .semibold))
                }
                .foregroundStyle(.white)
                .frame(width: 56, height: 56)
                .background(Color.red.opacity(0.9))
                .clipShape(Circle())
            }
            .accessibilityLabel(isExpanded ? "Fermer le menu de signalement" : "Signaler un danger, un bouchon ou un point d'attention")
        }
    }

    private func report(category: WaypointCategory) {
        guard let location = session.currentLocation else { return }
        waypointStore.add(category: category, coordinate: location.coordinate, recordedTrackID: nil)
        hapticGenerator.notificationOccurred(.success)
        withAnimation { isExpanded = false }
    }
}
