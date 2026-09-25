import Foundation

/// Règle "Hors trace" UNIQUE de l'app (it30) — hystérésis à deux seuils de distance
/// (`RideConstants.horsTraceEnterMeters`/`horsTraceExitMeters`, spec
/// "offtrace-threshold-hysteresis", it14) : on SORT de la trace au-delà de 30 m, on n'y REVIENT
/// qu'en deçà de 25 m ; entre les deux, rien ne change (anti-rebond). Utilisée par le Ride
/// (`RideSessionManager`, puce "Hors trace") ET le Road Book (carte "Hors trace") : même seuil,
/// même terminologie, jamais deux comportements.
enum OffTrackDetector {
    static func isOffTrack(wasOffTrack: Bool, distanceToTrackMeters: Double) -> Bool {
        wasOffTrack
            ? distanceToTrackMeters > RideConstants.horsTraceExitMeters
            : distanceToTrackMeters > RideConstants.horsTraceEnterMeters
    }
}
