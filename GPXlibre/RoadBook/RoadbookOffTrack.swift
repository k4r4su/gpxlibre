import Foundation
import CoreLocation

/// Statut "Hors trace" du Road Book (it30) — MÊME règle que le Ride (`OffTrackDetector` :
/// hystérésis 30 m / 25 m, aucune constante dupliquée), même terminologie. Calcul pur à partir
/// de la position et de la trace dans son sens de parcours.
struct RoadbookOffTrackState: Equatable {
    private(set) var isOffTrack = false
    /// Depuis quand, pour afficher la distance de reprise après le même délai que la puce Ride.
    private(set) var sinceDate: Date?
    private(set) var distanceToTrackMeters: Double?
    /// Distance à vol d'oiseau du point de trace le plus proche (même "point de reprise" que le
    /// Ride, `TrackProjector.nearestPointByAirDistance`).
    private(set) var rejoinDistanceMeters: Double?

    mutating func update(location: CLLocation, points: [GPXPoint], cumulativeDistances: [Double]) {
        guard let projection = TrackProjector.project(location.coordinate, onto: points, cumulativeDistances: cumulativeDistances) else { return }
        let offTrack = OffTrackDetector.isOffTrack(wasOffTrack: isOffTrack, distanceToTrackMeters: projection.distanceToTrackMeters)
        if offTrack, !isOffTrack { sinceDate = location.timestamp }
        isOffTrack = offTrack
        distanceToTrackMeters = projection.distanceToTrackMeters
        guard offTrack else {
            sinceDate = nil
            rejoinDistanceMeters = nil
            return
        }
        rejoinDistanceMeters = TrackProjector.nearestPointByAirDistance(to: location.coordinate, in: points, cumulativeDistances: cumulativeDistances)
            .map { RoadbookAnalyzer.distanceMeters(location.coordinate, $0.coordinate) }
    }

    mutating func reset() {
        self = RoadbookOffTrackState()
    }

    /// Distance de reprise affichée seulement après le même délai que la puce du Ride
    /// (`RideConstants.offTrackChipDistanceDelaySeconds`) : discret tant que ça peut se résorber.
    func showsRejoinDistance(now: Date) -> Bool {
        guard isOffTrack, let sinceDate else { return false }
        return now.timeIntervalSince(sinceDate) >= RideConstants.offTrackChipDistanceDelaySeconds
    }
}
