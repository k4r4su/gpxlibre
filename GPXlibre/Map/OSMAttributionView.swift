import SwiftUI

/// Attribution OSM/ODbL visible en permanence — exigence de licence, non désactivable.
struct OSMAttributionView: View {
    var body: some View {
        Text(MapEngineConstants.osmAttributionPlainText)
            .font(.system(size: 10))
            .foregroundStyle(.white.opacity(0.9))
            .padding(.horizontal, 6)
            .padding(.vertical, 3)
            .background(.black.opacity(0.5))
            .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
    }
}
