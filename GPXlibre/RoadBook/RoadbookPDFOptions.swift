import CoreGraphics
import Foundation

enum PDFOrientation: String, CaseIterable, Identifiable, Codable {
    case portrait, landscape
    var id: String { rawValue }
    var label: String { self == .portrait ? String(localized: "Portrait", bundle: .appLanguage) : String(localized: "Paysage", bundle: .appLanguage) }
}

enum PDFDensity: String, CaseIterable, Identifiable, Codable {
    case compact, comfortable
    var id: String { rawValue }
    var label: String { self == .compact ? String(localized: "Compact", bundle: .appLanguage) : String(localized: "Confortable", bundle: .appLanguage) }
    var rowHeightPoints: CGFloat { self == .compact ? RoadBookConstants.pdfRowHeightCompact : RoadBookConstants.pdfRowHeightComfortable }
}

enum PDFHeadingStyle: String, CaseIterable, Identifiable, Codable {
    case pictogram, degrees
    var id: String { rawValue }
    var label: String { self == .pictogram ? String(localized: "Pictogramme", bundle: .appLanguage) : String(localized: "Degrés", bundle: .appLanguage) }
}

enum PDFFontSize: String, CaseIterable, Identifiable, Codable {
    case small, medium, large
    var id: String { rawValue }
    var label: String {
        switch self {
        case .small: return String(localized: "Petite", bundle: .appLanguage)
        case .medium: return String(localized: "Moyenne", bundle: .appLanguage)
        case .large: return String(localized: "Grande", bundle: .appLanguage)
        }
    }
    var points: CGFloat {
        switch self {
        case .small: return RoadBookConstants.pdfFontSizeSmall
        case .medium: return RoadBookConstants.pdfFontSizeMedium
        case .large: return RoadBookConstants.pdfFontSizeLarge
        }
    }
}

/// Toutes les options de mise en forme du panneau d'export PDF (spec "roadbook-mode", it23,
/// point 2 : "panneau avant export, pas juste un bouton Exporter") — persistées
/// (`RideSettingsStore`) pour ne pas tout re-régler à chaque export, modifiables juste avant
/// chaque génération dans `RoadbookExportOptionsView`. `Codable` pour un stockage direct en
/// UserDefaults (encodé en JSON, même patron que d'autres structures de réglages du projet).
struct RoadbookPDFOptions: Codable, Equatable {
    var orientation: PDFOrientation = .portrait
    var density: PDFDensity = .comfortable
    var showCumulativeDistance = true
    var showNoteColumn = true
    var headingStyle: PDFHeadingStyle = .pictogram
    var distanceUnit: DistanceUnit = .km
    var fontSize: PDFFontSize = .medium
}
