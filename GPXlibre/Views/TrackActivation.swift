import SwiftUI

/// Demande de changement de la trace ACTIVE (it29) — la trace active est la source unique partagée
/// par Bibliothèque, Ride et Road Book (`LibraryStore.activeTrackID`), et elle ne se change QUE
/// depuis la Bibliothèque (ligne, fiche "Paramétrer la trace").
enum TrackActivationRequest: Identifiable, Equatable {
    case activate(GPXTrack)
    case deactivate(GPXTrack)

    var track: GPXTrack {
        switch self {
        case .activate(let track), .deactivate(let track): return track
        }
    }

    var id: String {
        switch self {
        case .activate(let track): return "activate-\(track.id)"
        case .deactivate(let track): return "deactivate-\(track.id)"
        }
    }

    static func == (lhs: Self, rhs: Self) -> Bool { lhs.id == rhs.id }
}

/// Règle PURE : quand faut-il demander confirmation ? Une sortie est EN COURS dès que des points
/// sont enregistrés (`RideRecorder.pointCount`). Changer la trace active, ou la désactiver,
/// pendant ce temps change le GUIDAGE en pleine sortie : jamais silencieusement. Depuis it30,
/// l'enregistrement, lui, continue sans interruption (service indépendant de la trace suivie).
enum TrackActivationPolicy {
    static func requiresConfirmation(_ request: TrackActivationRequest, activeTrackID: UUID?, recordedPointsCount: Int) -> Bool {
        guard recordedPointsCount > 0, let activeTrackID else { return false }
        switch request {
        case .activate(let track): return track.id != activeTrackID
        case .deactivate(let track): return track.id == activeTrackID
        }
    }

    /// Seuls points d'écriture : `LibraryStore.setActive`/`setDisplayed` (invariant it10).
    @MainActor
    static func apply(_ request: TrackActivationRequest, to library: LibraryStore) {
        switch request {
        case .activate(let track): library.setActive(track.id)
        case .deactivate(let track): library.setDisplayed(track.id, false)
        }
    }

    static func confirmationMessage(for request: TrackActivationRequest, activeTrackName: String?, recordedPointsCount: Int) -> String {
        let current = activeTrackName.map { "« \($0) »" } ?? String(localized: "la trace active", bundle: .appLanguage)
        let action: String
        switch request {
        case .activate(let track): action = String(localized: "Passer à « \(track.name) » arrête le guidage sur \(current)", bundle: .appLanguage)
        case .deactivate: action = String(localized: "Désactiver \(current) arrête le guidage", bundle: .appLanguage)
        }
        return "Une sortie est en cours (\(recordedPointsCount) points enregistrés). \(action). L'enregistrement de la sortie, lui, continue."
    }
}

/// Bouton/ligne qui change la trace active : applique directement, ou demande confirmation si une
/// sortie est en cours.
private struct TrackActivationConfirmation: ViewModifier {
    @Binding var pending: TrackActivationRequest?
    @EnvironmentObject private var library: LibraryStore
    @EnvironmentObject private var recorder: RideRecorder

    func body(content: Content) -> some View {
        content.confirmationDialog(
            "Changer de trace pendant la sortie ?",
            isPresented: Binding(get: { pending != nil }, set: { if !$0 { pending = nil } }),
            titleVisibility: .visible,
            presenting: pending
        ) { request in
            Button(request.isActivation ? "Passer à cette trace" : "Désactiver la trace", role: .destructive) {
                TrackActivationPolicy.apply(request, to: library)
                pending = nil
            }
            Button("Annuler", role: .cancel) { pending = nil }
        } message: { request in
            Text(TrackActivationPolicy.confirmationMessage(for: request, activeTrackName: library.activeTrack?.name, recordedPointsCount: recorder.pointCount))
        }
    }
}

extension TrackActivationRequest {
    var isActivation: Bool {
        if case .activate = self { return true }
        return false
    }
}

extension View {
    func trackActivationConfirmation(_ pending: Binding<TrackActivationRequest?>) -> some View {
        modifier(TrackActivationConfirmation(pending: pending))
    }
}

@MainActor
extension LibraryStore {
    /// Point d'entrée des vues : applique, ou renvoie la demande à confirmer.
    func request(_ request: TrackActivationRequest, recordedPointsCount: Int) -> TrackActivationRequest? {
        if TrackActivationPolicy.requiresConfirmation(request, activeTrackID: activeTrackID, recordedPointsCount: recordedPointsCount) {
            return request
        }
        TrackActivationPolicy.apply(request, to: self)
        return nil
    }
}
