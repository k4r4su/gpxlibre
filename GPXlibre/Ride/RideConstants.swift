import Foundation

/// Toutes les constantes réglables du mode Ride sont centralisées ici.
/// Valeurs de départ raisonnables — à ajuster après tests terrain (route + piste).
enum RideConstants {

    // MARK: - Roadbook / checkpoints

    /// Angle de virage (°) au-delà duquel un point de la trace devient un checkpoint.
    /// Réglable dans Réglages (30 / 35 / 40) ; ceci est la valeur par défaut.
    static let turnThresholdDegreesDefault: Double = 35
    static let turnThresholdDegreesOptions: [Double] = [30, 35, 40]

    /// Au-delà de cet angle, la flèche devient "demi-tour" plutôt que gauche/droite.
    static let uTurnThresholdDegrees: Double = 120

    /// Distance minimale (m) utilisée pour lisser le calcul de cap avant/après un point,
    /// afin d'éviter le bruit dû à des points GPX très rapprochés.
    static let bearingLookaroundMeters: Double = 20

    /// Distance (m) sous laquelle un checkpoint est considéré "atteint" et on passe au suivant.
    static let checkpointPassedRadiusMeters: Double = 25

    /// Distance (m) sous laquelle la flèche grossit + haptique se déclenche.
    static let checkpointCloseRadiusMeters: Double = 30

    // MARK: - Alerte flash

    /// Distance d'alerte checkpoint (m). Réglable dans Réglages (100 / 200 / 300), défaut 200.
    static let alertDistanceDefaultMeters: Double = 200
    static let alertDistanceOptions: [Double] = [100, 200, 300]

    /// Nombre de flashs. Réglable (3 / 5), défaut 3.
    static let flashCountDefault: Int = 3
    static let flashCountOptions: [Int] = [3, 5]

    static let flashOnDurationSeconds: Double = 0.12
    static let flashOffDurationSeconds: Double = 0.12

    // MARK: - Lissage vitesse & caméra

    /// Fenêtre de moyenne glissante de la vitesse GPS.
    static let speedSmoothingWindowSeconds: Double = 10

    /// Marge d'hystérésis (km/h) autour des seuils de zoom pour ne jamais osciller.
    static let zoomHysteresisMarginKmh: Double = 4

    /// Durée d'animation de la caméra lors d'un changement de palier de zoom.
    static let cameraAnimationDurationSeconds: Double = 1.2

    // MARK: - Override zoom manuel (pinch)

    /// Durée pendant laquelle le zoom manuel (pinch) prend le pas sur le zoom auto.
    static let manualZoomOverrideTimeoutSeconds: Double = 5

    // MARK: - Caméra Ride (perspective)

    static let cameraPitchDegrees: Double = 55
    /// Position verticale de la position actuelle à l'écran (0 = haut, 1 = bas).
    /// ~0.33 place la position dans le tiers inférieur, regard vers l'avant.
    static let cameraCenterOffsetRatio: Double = 0.33

    // MARK: - Paliers de zoom (distance caméra en mètres) par preset, selon la vitesse (km/h)

    struct ZoomBucket { let speedUpToKmh: Double; let cameraDistanceMeters: Double }

    /// Prudent : reste plus zoomé même à haute vitesse (plus de détails visibles).
    static let zoomBucketsPrudent: [ZoomBucket] = [
        ZoomBucket(speedUpToKmh: 20, cameraDistanceMeters: 220),
        ZoomBucket(speedUpToKmh: 50, cameraDistanceMeters: 350),
        ZoomBucket(speedUpToKmh: 90, cameraDistanceMeters: 550),
        ZoomBucket(speedUpToKmh: .infinity, cameraDistanceMeters: 750),
    ]

    /// Normal : équilibre par défaut.
    static let zoomBucketsNormal: [ZoomBucket] = [
        ZoomBucket(speedUpToKmh: 20, cameraDistanceMeters: 280),
        ZoomBucket(speedUpToKmh: 50, cameraDistanceMeters: 450),
        ZoomBucket(speedUpToKmh: 90, cameraDistanceMeters: 750),
        ZoomBucket(speedUpToKmh: .infinity, cameraDistanceMeters: 1100),
    ]

    /// Rapide : dézoome plus vite pour anticiper à haute vitesse.
    static let zoomBucketsRapide: [ZoomBucket] = [
        ZoomBucket(speedUpToKmh: 20, cameraDistanceMeters: 320),
        ZoomBucket(speedUpToKmh: 50, cameraDistanceMeters: 600),
        ZoomBucket(speedUpToKmh: 90, cameraDistanceMeters: 1000),
        ZoomBucket(speedUpToKmh: .infinity, cameraDistanceMeters: 1500),
    ]

    // MARK: - Contexte route rapide / piste (adaptation caméra + alertes, JAMAIS de recalcul d'itinéraire)

    static let fastRoadSpeedThresholdKmh: Double = 60
    static let fastRoadSustainedDurationSeconds: Double = 60
    static let trackSpeedThresholdKmh: Double = 40

    /// Multiplicateur appliqué à la distance caméra du palier de zoom courant.
    static let fastRoadCameraDistanceMultiplier: Double = 1.4
    static let trackCameraDistanceMultiplier: Double = 0.7

    /// Distance d'alerte checkpoint forcée en contexte "route rapide" (remplace le réglage utilisateur).
    static let fastRoadAlertDistanceMeters: Double = 300
    /// Multiplicateur du seuil hors-trace en contexte "piste" (resserré) — pour itération future.
    static let trackOffTrackToleranceMultiplier: Double = 0.6

    // MARK: - Localisation Ride

    static let rideDistanceFilterMeters: Double = 5

    // MARK: - Chemin bloqué / détour temporaire (la trace originale n'est JAMAIS modifiée)

    /// Distance perpendiculaire à la trace (m) au-delà de laquelle on est considéré "hors trace".
    static let offTrackDistanceThresholdMeters: Double = 50

    /// Temps continu hors trace avant proposition de contournement.
    static let offTrackStagnantDurationSeconds: Double = 30
    /// OU distance cumulée parcourue hors trace avant proposition de contournement.
    static let offTrackStagnantDistanceMeters: Double = 200

    /// Fenêtre de recherche du point de ralliement sur la trace, après la zone bloquée.
    static let detourAheadMinMeters: Double = 500
    static let detourAheadMaxMeters: Double = 2000
    /// Pas d'essai entre candidats de ralliement dans la fenêtre ci-dessus.
    static let detourAheadStepMeters: Double = 500

    /// Distance de retour sur la trace (m) qui efface automatiquement le détour (+ haptique).
    static let detourRejoinClearRadiusMeters: Double = 20

    static let detourRoutingTimeoutSeconds: Double = 12

    /// API publique gratuite de démonstration OSRM — pas de clé, usage raisonnable uniquement.
    /// À remplacer par une instance auto-hébergée si le volume d'usage grandit (cf. doc OSRM).
    static let osrmPublicBaseURL = "https://router.project-osrm.org"
}
