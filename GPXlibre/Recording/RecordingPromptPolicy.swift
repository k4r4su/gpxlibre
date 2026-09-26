import Foundation

/// Proposition "Enregistrer cette sortie ?" au démarrage d'un Ride (it31, point 2) — règle PURE.
///
/// Comportement réel vérifié avant d'écrire ceci : depuis it30, l'enregistrement est MANUEL
/// (`RideRecorder`, bouton "Enregistrer" au-dessus du badge vitesse), jamais automatique. Le filet
/// de secours ("Sorties non enregistrées" + journal sur disque) ne protège qu'un enregistrement en
/// cours. La proposition s'insère AVANT : elle ne remplace rien, et un refus laisse le bouton
/// disponible.
///
/// "Démarrage d'un Ride" = premier démarrage du SUIVI d'une trace : première apparition de Ride
/// avec une trace active, ou nouvelle trace active. Jamais au lancement de l'app, jamais à un
/// simple retour sur l'onglet Ride, une seule fois par trace et par session de l'app, et jamais si
/// un enregistrement est déjà en cours ou en pause.
struct RecordingPromptPolicy {
    private(set) var promptedTrackIDs: Set<UUID> = []

    mutating func shouldPrompt(onStartOf trackID: UUID?, recorderState: RideRecorder.State, recordedPointCount: Int) -> Bool {
        guard let trackID,
              recorderState == .idle, recordedPointCount == 0,
              !promptedTrackIDs.contains(trackID)
        else { return false }
        promptedTrackIDs.insert(trackID)
        return true
    }
}
