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

    /// Fusionne les checkpoints trop rapprochés (piste qui zigzague, sinon "196 virages"
    /// pour une trace qui n'en a réellement qu'une poignée) — DISTINCT de
    /// checkpointPassedRadiusMeters ci-dessus (rayon "checkpoint atteint" en Ride, un tout
    /// autre usage) : les deux étaient auparavant confondus dans le même chiffre (25 m),
    /// bien trop court pour déclencher une vraie fusion. Réglable en Réglages (item #15).
    static let turnMergeMinDistanceMetersDefault: Double = 150
    static let turnMergeMinDistanceMetersOptions: [Double] = [100, 150, 250]

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

    // MARK: - Caméra Ride (2D, cap-en-haut ou nord-en-haut — plus de pitch, spec "2d-only")

    /// POSITION_ANCHOR_RATIO (fix "position-anchor", Bug 2) — ratio, depuis le HAUT de la
    /// zone visible libre, auquel la position s'ancre en cap-en-haut. Constante fixe
    /// (itération "stabilisation UI" : aucun nouveau réglage), dans la fourchette 60-65%
    /// demandée. En vue nord-en-haut, la position reste au centre géométrique (0.5) — pas de
    /// biais "regarder devant soi" pertinent en cap-en-haut non plus depuis l'abandon du
    /// pitch (spec "2d-only", it11), mais gardé distinct par cohérence avec l'existant.
    static let positionAnchorRatio: Double = 0.625
    static let positionAnchorRatio2D: Double = 0.5

    /// RIDE_ANCHOR_Y_FRACTION (spec "ride-anchor-lowered-setting", it14, terrain : "le point
    /// bleu est trop peu bas, pas assez de visibilité avant"). Remplace `positionAnchorRatio`
    /// ci-dessus UNIQUEMENT en mode suivi cap-en-haut actif (`!is2DNorthUp` — la "conduite"
    /// réelle) : nord-en-haut garde `positionAnchorRatio2D` (0.5) inchangé, et le pan manuel
    /// n'utilise de toute façon aucune ancre tant qu'il est actif (caméra non reprogrammée,
    /// voir `isManualOverrideActive`). Réglable (slider Réglages > Navigation > Position point
    /// bleu, `RideSettingsStore.rideAnchorYFraction`), valeur par défaut ci-dessous.
    static let rideAnchorYFractionDefault: Double = 0.75
    /// Fourchette du slider — `computeMapInsets` clampe de toute façon à [0.5, 0.9], cette
    /// plage UI reste légèrement à l'intérieur pour un slider dont chaque extrémité a un effet
    /// visible réel.
    static let rideAnchorYFractionRange: ClosedRange<Double> = 0.55...0.85

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

    /// Distance perpendiculaire à la trace (m) au-delà de laquelle on est considéré "hors
    /// trace" pour "Portion bloquée ?" (30 s/200 m avant proposition de détour) — DISTINCT du
    /// panneau/bannière "Hors trace" du roadbook, voir HORS_TRACE_ENTER_M/EXIT_M ci-dessous
    /// (spec "offtrace-threshold-hysteresis", it14, Bloc 8), non touché par ce fix.
    static let offTrackDistanceThresholdMeters: Double = 50

    /// HORS_TRACE_ENTER_M / HORS_TRACE_EXIT_M (spec "offtrace-threshold-hysteresis", it14,
    /// Bloc 8, bug terrain confirmé par capture du 14/09 : bandeau "Hors trace" persistant
    /// alors que la position était proche de la trace). Hystérésis à DEUX seuils distincts —
    /// remplace l'ancienne hystérésis à seuil unique (50 m) + temporelle (20 s ou 2 fixs
    /// stables) : la bande ENTER-EXIT (30 m > distance > 25 m) EST l'anti-rebond, aucun état
    /// ne change tant que la distance y reste, donc plus besoin de bookkeeping temporel séparé.
    static let horsTraceEnterMeters: Double = 30
    static let horsTraceExitMeters: Double = 25

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

    // MARK: - Resync hors-trace (spec "resync-hysteresis")

    // MARK: - Chevrons de direction par trace (spec "per-track-settings")

    /// DIRECTION_ARROW_SPACING_M — espacement par défaut des chevrons de direction le long de
    /// la trace, réglable par trace (100 / 200 / 500 / 1000 m). Défaut réduit 500 → 100 m
    /// (it12, retour terrain) : chevrons plus fréquents, plus utile pour lire le sens sans
    /// avoir à zoomer. Le slider garde toutes les valeurs précédentes.
    static let directionArrowSpacingMetersDefault: Double = 100
    static let directionArrowSpacingMetersOptions: [Double] = [100, 200, 500, 1000]

    static let detourRoutingTimeoutSeconds: Double = 12

    // MARK: - "Reprendre la trace ici" (feat "resume-at-point", Bloc 3, it10)

    /// Tolérance de tap sur la trace (points écran, ~30-40 pt demandés) — convertie en mètres
    /// au moment du tap via `MLNMapView.metersPerPointAtLatitude(_:)`, donc valable à tout
    /// niveau de zoom.
    static let resumeTapToleranceScreenPoints: Double = 36
    /// Jonction considérée atteinte (spec explicite "< 30 m") — reprise normale du fil.
    static let resumeJunctionDistanceMeters: Double = 30

    /// API publique gratuite de démonstration OSRM — pas de clé, usage raisonnable uniquement.
    /// À remplacer par une instance auto-hébergée si le volume d'usage grandit (cf. doc OSRM).
    static let osrmPublicBaseURL = "https://router.project-osrm.org"

    // MARK: - Mesures en cours (panneau data)

    /// Fenêtre de moyenne glissante utilisée pour l'heure d'arrivée estimée.
    static let etaSpeedWindowSeconds: Double = 300
    /// En dessous de cette vitesse (km/h), l'ETA est masquée (silencieuse à l'arrêt).
    static let etaSilenceSpeedThresholdKmh: Double = 2

    // MARK: - Contrôles "gants" (zoom manuel +/-, recentrer)

    /// Facteur multiplicatif appliqué à la distance caméra à chaque tap +/-.
    static let manualZoomStepFactor: Double = 0.7
    static let manualZoomMinMeters: Double = 120
    /// Fix "zoom-out-unclamped" (it13, Bloc 4) : le zoom − était bridé artificiellement à
    /// 3000 m (à peine plus loin qu'un palier auto "rapide" normal, 1500 m) — le motard ne
    /// pouvait jamais consulter la carte à l'échelle région/pays. Relevé à l'échelle pays
    /// entier (~2000 km de portée caméra, correspond à peu près au zoom 3-4 demandé). Aucune
    /// protection par contexte (route/piste) ajoutée : cette portée n'est utilisée QUE pendant
    /// la consultation manuelle (tant que `manualZoomDistanceMeters` est non-nil) — le zoom
    /// auto qui suit le cap (paliers vitesse, voir zoomBuckets*) reste plafonné à 1500 m comme
    /// avant, totalement indépendant de cette constante.
    static let manualZoomMaxMeters: Double = 2_000_000
    /// Animation courte pour un tap +/- ou un recentrage — distincte du lissage auto (1.2 s).
    static let manualZoomAnimationDurationSeconds: Double = 0.25
    /// Cible tactile minimale recommandée pour une utilisation gantée.
    static let glovedTapTargetSize: Double = 56

    // MARK: - Bannière latérale cap + countdown (spec "lateral-cap-banner-countdown", it12)

    /// Seuil (°) d'angle CUMULÉ (signé, sur `bannerInflectionWindowMeters`) au-delà duquel un
    /// point de la trace devient une "inflexion" pour la bannière latérale — DISTINCT du seuil
    /// ponctuel du roadbook (`turnThresholdDegreesDefault`, ±20 m de lissage) : une fenêtre
    /// glissante de 100-150 m couvre à la fois les vraies "splits" (tout l'angle dans un petit
    /// sous-segment de la fenêtre) et les virages progressifs qu'aucun point isolé ne dépasse.
    /// Voir RoadbookAnalyzer.buildInflectionPoints.
    static let bannerInflectionThresholdDegrees: Double = 40
    static let bannerInflectionWindowMeters: Double = 150

    /// BANNER_ALERT_START_M : distance (m) à laquelle la bannière latérale apparaît.
    static let bannerAlertStartMeters: Double = 600
    /// BANNER_COARSE_STEP_M : pas d'affichage (m) au-dessus de bannerFineThresholdMeters.
    static let bannerCoarseStepMeters: Double = 100
    /// BANNER_FINE_THRESHOLD_M : distance (m) sous laquelle l'affichage passe au pas fin.
    static let bannerFineThresholdMeters: Double = 150
    /// BANNER_FINE_STEP_M : pas d'affichage (m) sous bannerFineThresholdMeters, jusqu'à 0.
    static let bannerFineStepMeters: Double = 10
}
