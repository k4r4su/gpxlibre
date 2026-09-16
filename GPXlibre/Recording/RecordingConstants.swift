import Foundation

/// Spec "recording-density-setting" (it19, retour terrain : "possibilité d'augmenter
/// l'intervalle pour alléger le fichier GPX final, forcément moins précis") — un point est
/// enregistré dès que l'un des deux seuils du preset actif est atteint (le plus fréquent des
/// deux déclenche l'enregistrement, inchangé). `précis` reste le défaut exact d'avant ce
/// réglage (aucune régression de comportement tant que l'utilisateur n'y touche pas) ;
/// `léger`/`très léger` espacent les points pour réduire la taille du fichier exporté, au prix
/// d'une trace moins fidèle au tracé réel.
enum RecordingConstants {
    static let minIntervalSecondsDefault: Double = 5
    static let minDistanceMetersDefault: Double = 15

    static let minIntervalSecondsLeger: Double = 10
    static let minDistanceMetersLeger: Double = 30

    static let minIntervalSecondsTresLeger: Double = 20
    static let minDistanceMetersTresLeger: Double = 60
}

/// Réglage Réglages > Enregistrement de la sortie — voir `RideSettingsStore.recordingDensityPreset`.
enum RecordingDensityPreset: String, CaseIterable, Identifiable, Codable {
    case precis, leger, tresLeger

    var id: String { rawValue }

    var label: String {
        switch self {
        case .precis: return "Précis (défaut)"
        case .leger: return "Léger"
        case .tresLeger: return "Très léger"
        }
    }

    var detail: String {
        switch self {
        case .precis: return "Un point toutes les \(Int(RecordingConstants.minIntervalSecondsDefault)) s ou \(Int(RecordingConstants.minDistanceMetersDefault)) m"
        case .leger: return "Un point toutes les \(Int(RecordingConstants.minIntervalSecondsLeger)) s ou \(Int(RecordingConstants.minDistanceMetersLeger)) m"
        case .tresLeger: return "Un point toutes les \(Int(RecordingConstants.minIntervalSecondsTresLeger)) s ou \(Int(RecordingConstants.minDistanceMetersTresLeger)) m"
        }
    }

    var minIntervalSeconds: Double {
        switch self {
        case .precis: return RecordingConstants.minIntervalSecondsDefault
        case .leger: return RecordingConstants.minIntervalSecondsLeger
        case .tresLeger: return RecordingConstants.minIntervalSecondsTresLeger
        }
    }

    var minDistanceMeters: Double {
        switch self {
        case .precis: return RecordingConstants.minDistanceMetersDefault
        case .leger: return RecordingConstants.minDistanceMetersLeger
        case .tresLeger: return RecordingConstants.minDistanceMetersTresLeger
        }
    }
}
