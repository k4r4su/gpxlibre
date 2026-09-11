import Foundation

/// Item Réglages #12. Ne convertit que les vitesses affichées (km/h ↔ mph) — les distances
/// restent en mètres/kilomètres, hors périmètre de ce réglage.
enum SpeedUnit: String, CaseIterable, Identifiable, Codable {
    case kmh, mph

    var id: String { rawValue }
    var label: String { self == .kmh ? "km/h" : "mph" }

    func value(fromKmh kmh: Double) -> Double {
        self == .kmh ? kmh : kmh * 0.621371
    }

    func displayString(fromKmh kmh: Double) -> String {
        "\(Int(value(fromKmh: kmh).rounded())) \(label)"
    }

    func roundedValue(fromKmh kmh: Double) -> Int {
        Int(value(fromKmh: kmh).rounded())
    }
}
