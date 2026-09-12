import Foundation

/// Constantes ajustables du Bloc 5 (base partagée des points bloqués).
enum SharedBlockageConstants {
    /// Aucune instance publique n'est déployée par ce projet — vide par défaut. Tant que
    /// l'utilisateur n'a pas renseigné l'URL de sa propre instance (Réglages → Avancé),
    /// aucune tentative réseau n'est faite : l'app reste 100% locale sur ce point,
    /// jamais d'appel vers une adresse inventée.
    static let defaultServerURLString = ""

    /// Synchro "une fois par jour + à chaque lancement" (spec) — pas de tâche temps réel.
    static let syncIntervalSeconds: TimeInterval = 24 * 3600
    /// Distance sous laquelle un point bloqué connu déclenche l'alerte pill sur la trace.
    static let alertRadiusMeters: Double = 300
    static let fadeAfterDays: Double = 90
    static let expireAfterDays: Double = 180
    /// Marge ajoutée autour du cadre (bbox) de la trace ou de la position courante lors de
    /// la requête GET, pour ne pas manquer un point juste en dehors du cadre strict.
    static let bboxPaddingDegrees: Double = 0.05
    static let bboxPaddingDegreesAroundLocation: Double = 0.2
    static let requestTimeoutSeconds: TimeInterval = 8
}
