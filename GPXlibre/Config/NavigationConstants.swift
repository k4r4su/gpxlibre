import Foundation

/// Constantes du roadbook rebuilt from scratch (spec "roadbook-angle-buckets-replay", it14,
/// Bloc 4) — regroupées ici plutôt que dans RideConstants.swift comme demandé explicitement
/// par le prompt d'itération ("Constantes exposées dans Config/NavigationConstants.swift").
/// Tout le reste des constantes Ride (hors roadbook) reste dans RideConstants.swift, inchangé.
enum NavigationConstants {

    // MARK: - Fenêtre de mesure de la tangente (ROADBOOK_WINDOW_BEFORE_M / AFTER_M)

    /// Distance (m) AVANT/APRÈS un point de la trace sur laquelle le cap entrant/sortant est
    /// mesuré (spec : "±40-80 m autour de la position") — ASYMÉTRIQUE par construction (avant
    /// ≠ après possibles), réglable indépendamment dans Réglages > Roadbook > Fenêtre de mesure
    /// (spec "roadbook-settings-wired", Bloc 5).
    /// Fix "roadbook-turn-angle-from-heading-chords" : ce sont désormais les longueurs des
    /// cordes AVANT/APRÈS (cap moyen) comparées en chaque point, positions interpolées — 40 m
    /// (fiche : "~30-50 m"), au lieu de 60 m sommés segment par segment.
    static let roadbookWindowBeforeMetersDefault: Double = 40
    static let roadbookWindowAfterMetersDefault: Double = 40
    static let roadbookWindowRange: ClosedRange<Double> = 30...80

    // MARK: - Paliers d'angle (segmentation type Waze/MUTCD)

    /// < ce seuil : rien (tout droit, pas affiché) — SEUIL MINIMAL d'un checkpoint, pour la
    /// géométrie ET pour les manœuvres Valhalla (règle produit : pas de vrai changement de cap =
    /// pas de checkpoint). 25° (fiche : "~20-25°", 30° avant) : en dessous, une route qui ondule.
    static let roadbookLightThresholdDegreesDefault: Double = 25
    /// [light, marked[ = virage léger ; [marked, hard[ = virage prononcé ; [hard, veryHard[ =
    /// virage fort ; ≥ veryHard = virage très serré (avec son sens). Le demi-tour n'est PLUS un
    /// palier d'angle (it26 point 2, voir `roadbookUTurn*` ci-dessous). Clé de réglage persistée
    /// inchangée (`settings.roadbookUTurnThresholdDegrees`) : la valeur choisie avant it26 borne
    /// désormais le palier "très serré".
    static let roadbookMarkedThresholdDegreesDefault: Double = 45
    static let roadbookHardThresholdDegreesDefault: Double = 90
    static let roadbookVeryHardThresholdDegreesDefault: Double = 135

    /// Deux candidats de virage à moins de cette distance (le long de la trace) forment une seule
    /// grappe : un seul checkpoint dans le sens du virage net, ou aucun si le virage net reste
    /// sous le seuil minimal (zigzag parasite). Fiche : "~30-50 m" — 50 : à 40, les deux coins
    /// d'une épingle tracée à 40 m d'écart (40,07 m sur l'ellipsoïde) ressortaient en deux
    /// "Virage fort" au lieu d'une épingle "très serré".
    static let roadbookTurnClusterMeters: Double = 50

    /// Changement de ROUTE (noms Valhalla avant/après disjoints) : checkpoint "Changement de
    /// direction" même sous le seuil minimal, si la trace tourne d'au moins ça (fiche : "le nom de
    /// la route change ET le cap change sensiblement"). La classe de route n'est pas disponible
    /// dans `/trace_route` (seulement dans `/trace_attributes`, non utilisé).
    static let roadbookRoadChangeMinTurnDegrees: Double = 10

    // MARK: - Demi-tour (it26 point 2, fix "roadbook-no-false-uturn")

    /// Règle métier non négociable : un demi-tour = repartir en sens inverse sur la MÊME route
    /// — en suivant une trace, ça ne doit quasiment jamais arriver. Repli géométrique : angle
    /// cumulé au moins égal à ce seuil (degrés)...
    static let roadbookUTurnMinDegrees: Double = 175
    /// ...ET la trace repart sur son propre tracé : le point situé une fenêtre APRÈS le virage
    /// passe à moins de cette distance (m) du tracé des mètres PRÉCÉDENTS. Vérifié sur les traces
    /// réelles du propriétaire : les épingles/lacets repartent à 35-225 m de leur autre branche,
    /// même avec un angle cumulé ≥ 175° — l'angle seul en laissait 5 sur un seul trajet de 110 km.
    static let roadbookUTurnSamePathMaxMeters: Double = 12
    /// Un demi-tour (géométrique OU Valhalla) dans les premiers/derniers mètres de la trace est
    /// une manœuvre de stationnement (sortie de place, cour), pas une instruction de parcours :
    /// ignoré. Seul demi-tour Valhalla du cache réel du propriétaire : à 20 m du départ.
    static let roadbookUTurnEndpointGuardMeters: Double = 200

    // MARK: - Manœuvres route-aware (map matching Valhalla)

    /// Distance max (m) entre un carrefour Valhalla et la trace GPX pour qu'il soit retenu (fix
    /// "roadbook-maneuver-position-from-route", it26 point 1) — la position affichée du virage
    /// est désormais celle du VRAI carrefour, plus le point GPX voisin : un carrefour plus loin
    /// que ça signifie que Valhalla a recalé une route qui n'est pas celle de la trace (route
    /// parallèle), jamais un virage à annoncer. Assez large pour une trace planifiée simplifiée
    /// qui coupe légèrement les courbes entre deux points.
    static let roadbookMapMatchMaxOffTrackMeters: Double = 60
    /// Aller-retour par la même route : un carrefour repassé au retour est aussi proche de
    /// l'aller que du retour. Si sa meilleure projection retombe sur la manœuvre précédente
    /// (doublon), un passage PLUS LOIN de la trace est retenu à la place — seulement s'il n'est
    /// pas plus éloigné du carrefour que de cette marge (m), pour ne jamais repousser à tort un
    /// vrai second carrefour rapproché sur une route parcourue une seule fois.
    static let roadbookMapMatchRepassToleranceMeters: Double = 15

    // MARK: - Flash / mise en avant

    /// ROADBOOK_FLASH_M : distance (m) sous laquelle le prochain virage déclenche une brève
    /// mise en avant visuelle (voir RideSessionManager.updateRoadbookBanner) — distincte du
    /// countdown BANNER_* (RideConstants), qui continue de piloter l'affichage 600→0 m.
    static let roadbookFlashMeters: Double = 100

    // MARK: - Mode debug replay (spec Bloc 4 : "obligatoire pour valider les paliers sans
    // sortir en voiture")

    /// Multiplicateurs de vitesse de rejeu disponibles — ×2 ajouté (spec "replay-marker-
    /// heading-x2", it17, Bloc 4) en plus de ×4/×8 déjà en place.
    static let debugReplaySpeedMultipliers: [Double] = [2, 4, 8]

    /// Fix "debug-replay-erratic-speed" (bug terrain, it16) : le rejeu utilisait un délai FIXE
    /// entre deux points bruts — or les points GPX sont espacés très irrégulièrement (parfois
    /// 3 m, parfois 300 m), ce qui donnait un point bleu erratique en replay ("un oiseau qui
    /// vole au-dessus de la trace"). Le délai entre deux points est désormais dérivé de leur
    /// distance réelle à vitesse simulée constante (`DebugReplayDriver.simulatedSpeedKmh`) —
    /// ces deux bornes évitent les deux excès opposés : une rafale d'appels quasi instantanés
    /// sur des points très rapprochés (min), ou un blocage visible plusieurs secondes sur un
    /// grand trou de la trace (max).
    static let debugReplayMinStepSeconds: Double = 0.05
    static let debugReplayMaxStepSeconds: Double = 3.0
}
