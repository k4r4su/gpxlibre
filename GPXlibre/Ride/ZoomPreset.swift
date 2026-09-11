import Foundation

enum ZoomPreset: String, CaseIterable, Identifiable {
    case prudent
    case normal
    case rapide

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .prudent: return "Prudent"
        case .normal: return "Normal"
        case .rapide: return "Rapide"
        }
    }

    var buckets: [RideConstants.ZoomBucket] {
        switch self {
        case .prudent: return RideConstants.zoomBucketsPrudent
        case .normal: return RideConstants.zoomBucketsNormal
        case .rapide: return RideConstants.zoomBucketsRapide
        }
    }
}
