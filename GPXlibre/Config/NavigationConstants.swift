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
    static let roadbookWindowBeforeMetersDefault: Double = 60
    static let roadbookWindowAfterMetersDefault: Double = 60
    static let roadbookWindowRange: ClosedRange<Double> = 40...80

    // MARK: - Paliers d'angle (segmentation type Waze/MUTCD)

    /// < ce seuil : rien (tout droit, pas affiché).
    static let roadbookLightThresholdDegreesDefault: Double = 30
    /// [light, marked[ = virage léger ; [marked, hard[ = virage prononcé ; [hard, uTurn[ =
    /// virage fort ; ≥ uTurn = demi-tour.
    static let roadbookMarkedThresholdDegreesDefault: Double = 45
    static let roadbookHardThresholdDegreesDefault: Double = 90
    static let roadbookUTurnThresholdDegreesDefault: Double = 135

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
