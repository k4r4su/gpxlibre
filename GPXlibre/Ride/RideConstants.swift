import Foundation

/// Toutes les constantes réglables du mode Ride sont centralisées ici.
/// Valeurs de départ raisonnables — à ajuster après tests terrain (route + piste).
enum RideConstants {

    // MARK: - Roadbook / checkpoints
    //
    // Fix "roadbook-angle-buckets-replay" (it14, Bloc 4) : l'ancien seuil ponctuel unique
    // (turnThresholdDegreesDefault/Options, bearingLookaroundMeters ±20 m,
    // uTurnThresholdDegrees=120, alerte/haptique par index de checkpoint) a été retiré —
    // remplacé par la détection à paliers + fenêtre avant/après configurable de
    // Config/NavigationConstants.swift (voir RoadbookAnalyzer.buildRoadbookEvents), pilotée
    // par les réglages Réglages > Roadbook (spec "roadbook-settings-wired", Bloc 5).

    /// Fusionne les événements trop rapprochés (piste qui zigzague, sinon "196 virages" pour
    /// une trace qui n'en a réellement qu'une poignée). Réglable en Réglages (item #15).
    static let turnMergeMinDistanceMetersDefault: Double = 150
    static let turnMergeMinDistanceMetersOptions: [Double] = [100, 150, 250]

    // MARK: - Alerte flash

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

    // MARK: - Zoom par défaut au démarrage (spec "default-zoom-preview", it14, Bloc 6)

    /// DEFAULT_RIDE_ZOOM : mesuré comme "5 taps zoom-arrière" (manualZoomStepFactor appliqué 5
    /// fois, DEHORS) depuis l'ancien point de départ fixe (zoomBucketsNormal, palier le plus
    /// serré, 280 m — voir RideSessionManager.init, avant it14) — valeur RÉELLE persistée telle
    /// quelle plutôt que recalculée à chaque lancement, réglable ensuite (slider + aperçu,
    /// Réglages > Navigation > Zoom par défaut). Relevé de 4 à 5 taps (spec "default-zoom-
    /// persist-rework", it18, Bloc 4, terrain : "ouvre trop zoomé, ne voit pas le prochain
    /// virage") — un cran de dézoom supplémentaire (~750 m → ~1075 m de portée caméra à
    /// l'ouverture) ; le réglage Réglages > Navigation > Zoom par défaut reste le point
    /// d'ajustement fin ensuite, cette constante ne pilote que la valeur de départ des
    /// nouvelles installs (un utilisateur ayant déjà sa propre valeur persistée n'est pas
    /// affecté, voir RideSettingsStore.init).
    static let manualZoomBackTapsForDefaultRideZoom = 5
    static let defaultRideZoomCameraMetersDefault: Double = {
        let startMeters = zoomBucketsNormal.first?.cameraDistanceMeters ?? 280
        return startMeters / pow(manualZoomStepFactor, Double(manualZoomBackTapsForDefaultRideZoom))
    }()
    static let defaultRideZoomRange: ClosedRange<Double> = 300...6000

    // MARK: - Zoom automatique vitesse (spec "auto-zoom-speed-curve", it14, Bloc 7)

    /// Bornes réglables (ON/OFF géré par `RideSettingsStore.autoZoomEnabled`) — appliquées en
    /// clamp final sur `cameraDistanceMeters` calculé par `updateZoomBucket()`, quel que soit
    /// le preset actif.
    static let autoZoomMinMetersDefault: Double = 150
    static let autoZoomMaxMetersDefault: Double = 2000
    static let autoZoomBoundsRange: ClosedRange<Double> = 100...3000

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

    /// Multiplicateur du seuil hors-trace en contexte "piste" (resserré) — pour itération future.
    static let trackOffTrackToleranceMultiplier: Double = 0.6

    // MARK: - Avertissement de pente (spec "slope-warning-native", it19)
    //
    // Détection native (élévation déjà disponible par point, `GPXPoint.elevation`) — décision
    // tranchée avec le propriétaire plutôt que d'ajouter GPXKit (package tiers réel, existe et
    // conviendrait techniquement, mais violerait la règle du projet "MapLibre est la SEULE
    // dépendance tierce autorisée", voir project.yml). Symboles PONCTUELS aux endroits de forte
    // pente (jamais un dégradé continu sur toute la trace, demande explicite).

    /// SLOPE_WARNING_THRESHOLD_PERCENT : pente (%) au-delà de laquelle un symbole est posé.
    /// 10 % choisi comme défaut raisonnable pour un usage moto (proche des seuils réels des
    /// panneaux routiers français de signalisation de pente, 8/10/12 %) — réglable.
    static let slopeWarningThresholdPercentDefault: Double = 10
    static let slopeWarningThresholdPercentOptions: [Double] = [8, 10, 12, 15]

    /// Distance minimale (m) d'une fenêtre de mesure avant de calculer une pente — évite les
    /// pentes aberrantes sur un segment de quelques mètres (bruit GPS/altimétrique).
    static let slopeWarningMinSegmentMeters: Double = 100

    /// Espacement minimal (m) entre deux symboles consécutifs — évite un mur de triangles sur
    /// une longue montée/descente régulière, un seul avertissement suffit par section.
    static let slopeWarningMinMarkerSpacingMeters: Double = 300

    // MARK: - Traces enregistrées (spec "ride-record-tracks-visible", it18, Bloc 2)

    /// RECORDED_TRACK_DISPLAY_COLOR : couleur distinctive appliquée par défaut (override
    /// par-trace, `TrackRideSettings.colorOverride`) à toute trace fraîchement enregistrée
    /// depuis le Ride — pour la reconnaître au premier coup d'œil face à une trace importée/
    /// curée (couleur globale par défaut : orange). Ambre = jaune, le plus proche du "ambre"
    /// demandé parmi les presets existants (voir TraceColorPreset) ; reste un override
    /// éditable comme tout autre, jamais figé.
    static let recordedTrackColorPreset: TraceColorPreset = .jaune

    // MARK: - Localisation Ride

    /// Fix "speed-freeze-low-speed" (it19, bug terrain P0) : `manager.distanceFilter` posé à
    /// 5 m (it1) empêchait CoreLocation de délivrer TOUT nouveau fix tant que la position
    /// n'avait pas bougé de 5 m depuis le dernier fix rapporté — en dessous d'~21 km/h (temps
    /// pour parcourir 5 m > 1 s) les fixs s'espacent, et à l'arrêt complet (déplacement < 5 m
    /// indéfiniment) ils s'arrêtent purement et simplement : `rawSpeedKmh`/`smoothedSpeedKmh`
    /// restent figés à leur dernière valeur, contradictoire avec le spec "vraie vitesse à 1 Hz
    /// sans lissage" (it12) qui suppose des fixs continus. Remplacé par
    /// `kCLLocationDistanceFilterNone` dans `init()` — fixs continus à la cadence GPS native
    /// quelle que soit la vitesse, y compris à l'arrêt (la vitesse décroît alors normalement
    /// jusqu'à 0 au lieu de rester bloquée).
    ///
    /// Contrepartie assumée : à l'arrêt strict, le bruit GPS (quelques mètres de gigue autour
    /// d'une position fixe) peut désormais générer des fixs consécutifs légèrement décalés —
    /// sans garde, `totalDistanceTraveledMeters` (et donc `averageSpeedKmh`) dériverait
    /// lentement à l'arrêt. Voir `distanceAccumulationMinSpeedKmh` ci-dessous, garde-fou dédié
    /// à CETTE seule accumulation (n'affecte jamais `rawSpeedKmh`/`smoothedSpeedKmh`, qui
    /// doivent rester la vitesse réelle sans filtrage, spec it12 inchangée).
    static let distanceAccumulationMinSpeedKmh: Double = 1

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

    /// Chip hors-trace compact (spec "offtrack-compact-chip", it18, Bloc 1) : titre seul tant
    /// que ce délai n'est pas dépassé, distance de reprise affichée en plus au-delà — voir
    /// OffTrackChipView.
    static let offTrackChipDistanceDelaySeconds: Double = 30

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

    // MARK: - Recalcul automatique de liaison (spec "link-recompute-on-divergence" /
    // "rejoin-trace-guidance-banner", it18, Blocs 3/5)

    /// RECOMPUTE_DIVERGENCE_M : distance perpendiculaire (m) à la trace au-delà de laquelle,
    /// soutenue pendant RECOMPUTE_DURATION_S, un guidage de reprise (même mécanisme que
    /// "Reprendre la trace ici", Bloc 3 it10) se déclenche AUTOMATIQUEMENT — plus strict que
    /// horsTraceEnterMeters (30 m, pause immédiate du roadbook) : celui-ci réagit tout de suite
    /// à un simple écart, celui-là attend une vraie divergence soutenue avant de calculer un
    /// itinéraire de liaison. Constantes strictes demandées par le prompt, non réglables.
    static let recomputeDivergenceThresholdMeters: Double = 100
    static let recomputeDivergenceDurationSeconds: Double = 2

    /// Spec "auto-recompute-periodic-reevaluation" (it19, retour terrain : "la logique
    /// actuelle est trop random... toutes les minutes, si on est hors trace, ajuster vers le
    /// point le plus proche à vol d'oiseau") — une fois un guidage automatique déclenché, sa
    /// cible n'était plus jamais réévaluée tant qu'il restait actif (figée à la position du
    /// rider au moment du déclenchement), même si le rider continuait à s'éloigner ou se
    /// rapprochait d'un point de la trace différent, plus pertinent. Réévalué toutes les 60 s
    /// tant que le guidage automatique reste actif ET hors-trace.
    static let autoRecomputeReevaluationIntervalSeconds: Double = 60
    /// Écart minimal (m) entre la cible actuelle et le point le plus proche recalculé pour
    /// déclencher un nouveau routage — évite un aller-retour réseau (OSRM/Valhalla) inutile
    /// quand le point le plus proche n'a, dans les faits, pas changé (gigue GPS).
    static let autoRecomputeRetargetMinDistanceMeters: Double = 10

    /// REJOINDRE_GUIDANCE_BANNER : feature flag (même patron que `guidanceButtonMode`) — permet
    /// de revenir instantanément au comportement précédent (pas de bannière latérale dédiée
    /// pendant un recalcul automatique, seul le tracé pointillé bleu sur la carte) sans toucher
    /// à la logique de déclenchement, si la bannière s'avère mal comprise sur le terrain.
    static let rejoindreGuidanceBannerEnabled = true

    // MARK: - Resync hors-trace (spec "resync-hysteresis")

    // MARK: - Chevrons de direction par trace (spec "per-track-settings")

    /// DIRECTION_ARROW_SPACING_M — espacement par défaut des chevrons de direction le long de
    /// la trace, réglable par trace (100 / 200 / 500 / 1000 m). Défaut réduit 500 → 100 m
    /// (it12, retour terrain) : chevrons plus fréquents, plus utile pour lire le sens sans
    /// avoir à zoomer. Le slider garde toutes les valeurs précédentes.
    static let directionArrowSpacingMetersDefault: Double = 100
    static let directionArrowSpacingMetersOptions: [Double] = [100, 200, 500, 1000]

    static let detourRoutingTimeoutSeconds: Double = 12

    /// Retour terrain (it19) : timeout DÉDIÉ, distinct de `detourRoutingTimeoutSeconds`
    /// (OSRM, inchangé) — un aller-retour vers une instance auto-hébergée derrière un
    /// reverse-proxy (Traefik, Basic Auth) en 4G peut légitimement dépasser les 12 s prévus
    /// pour l'API de démo OSRM, surtout sur la toute première requête (négociation TLS +
    /// HTTP/2 + vérification d'auth, sans connexion déjà "chaude").
    static let valhallaRequestTimeoutSeconds: Double = 20

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

    // MARK: - Bouton guidage (spec "guidance-toggle-stop-pause-play", it15, Bloc 3)

    /// GUIDANCE_BUTTON_MODE : `.toggle` (défaut) = un seul bouton Pause↔Play, Stop défini
    /// accessible via menu contextuel (appui long) — voir `RideGuidanceToggleButton`.
    /// `.twoButtons` = comportement it14 conservé tel quel (Stop + icône Play séparée
    /// empilés), gardé derrière ce flag comme filet de secours si le toggle unique s'avère
    /// mal compris sur le terrain — voir `RideView.bottomControlsColumn`.
    enum GuidanceButtonMode {
        case toggle
        case twoButtons
    }
    static let guidanceButtonMode: GuidanceButtonMode = .toggle

    // MARK: - Bannière latérale cap + countdown (spec "lateral-cap-banner-countdown", it12)
    //
    // Le SEUIL/la FENÊTRE de détection de "quand un point devient un événement" a déménagé
    // dans Config/NavigationConstants.swift + Réglages > Roadbook (spec "roadbook-angle-
    // buckets-replay", it14) — les constantes BANNER_* ci-dessous, qui ne pilotent QUE
    // l'affichage du countdown (déjà existant, INCHANGÉ par it14), restent ici.

    /// BANNER_ALERT_START_M : distance (m) à laquelle la bannière latérale apparaît.
    static let bannerAlertStartMeters: Double = 600
    /// BANNER_COARSE_STEP_M : pas d'affichage (m) au-dessus de bannerFineThresholdMeters.
    static let bannerCoarseStepMeters: Double = 100
    /// BANNER_FINE_THRESHOLD_M : distance (m) sous laquelle l'affichage passe au pas fin.
    static let bannerFineThresholdMeters: Double = 150
    /// BANNER_FINE_STEP_M : pas d'affichage (m) sous bannerFineThresholdMeters, jusqu'à 0.
    static let bannerFineStepMeters: Double = 10
}
