import Foundation
import CoreLocation

/// Statistiques "geek" calculées depuis les points bruts d'une trace (spec "track-geek-metrics",
/// it21, retour terrain : "ça peut rester dans l'app en mode petit côté geek pour ceux qui
/// veulent savoir comment s'est passé le trajet") — logique pure, même patron que
/// `SlopeAnalyzer`/`RoadbookAnalyzer`, aucune dépendance à MapLibre/UIKit.
struct TrackMetrics: Equatable {
    let durationSeconds: Double
    /// Durée où la vitesse instantanée dépasse `TrackMetricsCalculator.movingSpeedThresholdKmh`
    /// — exclut les arrêts (feu rouge, pause) de la moyenne "en mouvement" ci-dessous.
    let movingDurationSeconds: Double
    /// Distance / durée TOTALE (arrêts inclus) — la moyenne "brute" qu'on voit habituellement.
    let averageSpeedKmh: Double
    /// Distance / durée EN MOUVEMENT uniquement — souvent plus parlante pour juger l'allure
    /// réelle d'une sortie moto, indépendamment des pauses.
    let averageMovingSpeedKmh: Double
    let maxSpeedKmh: Double
    let elevationGainMeters: Double
    let elevationLossMeters: Double
    let minElevationMeters: Double
    let maxElevationMeters: Double
    /// Pente la plus marquée rencontrée (valeur absolue, montée OU descente) sur un segment d'au
    /// moins `TrackMetricsCalculator.minSegmentMetersForGrade` — jamais mesurée sur un segment
    /// trop court (bruit GPS/altimétrique), même précaution que `SlopeAnalyzer`.
    let maxGradePercent: Double
}

enum TrackMetricsCalculator {
    /// Vitesse en dessous de laquelle un intervalle est considéré "à l'arrêt" (feu, pause) —
    /// exclu de `averageMovingSpeedKmh`/`movingDurationSeconds`.
    static let movingSpeedThresholdKmh: Double = 3
    /// Plafond de plausibilité — un intervalle plus rapide (saut GPS, deux points quasi
    /// simultanés) est ignoré pour `maxSpeedKmh`, jamais retenu comme un vrai pic de vitesse.
    static let maxPlausibleSpeedKmh: Double = 260
    /// Distance minimale d'un segment pour être considéré dans `maxGradePercent` — un segment de
    /// quelques mètres produit une pente instantanée aberrante (bruit GPS/altimétrique).
    static let minSegmentMetersForGrade: Double = 20

    /// `nil` si la trace n'a pas d'horodatage RÉEL exploitable (import externe sans `time`, ou
    /// une trace planifiée dont les temps seraient arbitraires) — jamais un calcul de vitesse
    /// silencieusement faux affiché comme si c'était une mesure réelle.
    static func compute(for points: [GPXPoint]) -> TrackMetrics? {
        guard points.count > 1,
              let firstTime = points.first?.time,
              let lastTime = points.last?.time
        else { return nil }
        let durationSeconds = lastTime.timeIntervalSince(firstTime)
        guard durationSeconds > 0 else { return nil }

        var totalDistanceMeters: Double = 0
        var movingSeconds: Double = 0
        var maxSpeedKmh: Double = 0
        var elevationGainMeters: Double = 0
        var elevationLossMeters: Double = 0
        var minElevationMeters = points.first?.elevation
        var maxElevationMeters = points.first?.elevation
        var maxGradePercent: Double = 0

        for i in 1..<points.count {
            let a = points[i - 1]
            let b = points[i]
            let segmentDistanceMeters = RoadbookAnalyzer.distanceMeters(a.coordinate, b.coordinate)
            totalDistanceMeters += segmentDistanceMeters

            if let elevationA = a.elevation, let elevationB = b.elevation {
                let delta = elevationB - elevationA
                if delta > 0 { elevationGainMeters += delta } else { elevationLossMeters += -delta }
                minElevationMeters = min(minElevationMeters ?? elevationB, elevationB)
                maxElevationMeters = max(maxElevationMeters ?? elevationB, elevationB)

                if segmentDistanceMeters >= minSegmentMetersForGrade {
                    let gradePercent = abs(delta) / segmentDistanceMeters * 100
                    maxGradePercent = max(maxGradePercent, gradePercent)
                }
            }

            guard let timeA = a.time, let timeB = b.time else { continue }
            let deltaSeconds = timeB.timeIntervalSince(timeA)
            guard deltaSeconds > 0 else { continue }
            let speedKmh = (segmentDistanceMeters / deltaSeconds) * 3.6

            if speedKmh <= maxPlausibleSpeedKmh {
                maxSpeedKmh = max(maxSpeedKmh, speedKmh)
            }
            if speedKmh >= movingSpeedThresholdKmh {
                movingSeconds += deltaSeconds
            }
        }

        let averageSpeedKmh = (totalDistanceMeters / 1000) / (durationSeconds / 3600)
        let averageMovingSpeedKmh = movingSeconds > 0 ? (totalDistanceMeters / 1000) / (movingSeconds / 3600) : 0

        return TrackMetrics(
            durationSeconds: durationSeconds,
            movingDurationSeconds: movingSeconds,
            averageSpeedKmh: averageSpeedKmh,
            averageMovingSpeedKmh: averageMovingSpeedKmh,
            maxSpeedKmh: maxSpeedKmh,
            elevationGainMeters: elevationGainMeters,
            elevationLossMeters: elevationLossMeters,
            minElevationMeters: minElevationMeters ?? 0,
            maxElevationMeters: maxElevationMeters ?? 0,
            maxGradePercent: maxGradePercent
        )
    }
}
