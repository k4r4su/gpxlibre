import Foundation

/// Unité de distance du Road Book et de son export PDF (spec "roadbook-mode", it23, point 2)
/// — DISTINCT de `SpeedUnit` (vitesses uniquement, voir `SpeedUnit.swift`) : aucune unité de
/// distance globale n'existait ailleurs dans l'app avant cette feature (RideStatsPanel etc.
/// restent en km, explicitement hors périmètre de `SpeedUnit`, voir son commentaire de tête).
/// Introduite ici, scopée au Road Book — ne change rien à l'affichage des distances existant
/// ailleurs dans l'app.
enum DistanceUnit: String, CaseIterable, Identifiable, Codable {
    case km, mi

    var id: String { rawValue }
    var label: String { self == .km ? "km" : "mi" }

    private static let kmToMiles = 0.621371

    func value(fromMeters meters: Double) -> Double {
        let km = meters / 1000
        return self == .km ? km : km * Self.kmToMiles
    }

    /// Formatage court adapté à une colonne étroite (écran ou PDF) : en mètres si la distance
    /// reste sous 1 km (reste précis sur des manœuvres rapprochées), sinon 1 décimale.
    func displayString(fromMeters meters: Double) -> String {
        if self == .km, meters < 1000 {
            return "\(Int(meters.rounded())) m"
        }
        return String(format: "%.1f %@", value(fromMeters: meters), label)
    }
}
