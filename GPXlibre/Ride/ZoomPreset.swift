import Foundation

enum ZoomPreset: String, CaseIterable, Identifiable {
    case prudent
    case normal
    case rapide

    var id: String { rawValue }

    // Renommés (spec "auto-zoom-speed-curve", it14, Bloc 7) : rawValue Codable/UserDefaults
    // INCHANGÉ ("prudent"/"normal"/"rapide", persistance existante non cassée), seul le LABEL
    // affiché change — même patron que "Gants-épais" → "Épais" (it13).
    var displayName: String {
        switch self {
        case .prudent: return "Conservateur"
        case .normal: return "Équilibré"
        case .rapide: return "Agressif"
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
