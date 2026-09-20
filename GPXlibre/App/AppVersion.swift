import Foundation

/// Point d'accès UNIQUE à la version affichée dans l'app (spec "splash-version-robustness",
/// it23, point 3 : "confirmer que le splash et tout autre endroit affichant la version lisent
/// dynamiquement CFBundleShortVersionString plutôt qu'une chaîne codée en dur"). Audit fait à
/// l'écriture de ce fichier : SEUL `SplashScreenView` affiche une version dans l'app — aucun
/// écran "À propos" n'existe encore dans Réglages — et il la lisait déjà dynamiquement depuis
/// `Bundle.main.infoDictionary`, jamais en dur. Ce fichier factorise cette lecture en un point
/// unique, testable, pour qu'un futur second endroit (écran "À propos", etc.) ne puisse pas
/// diverger en recopiant la clé à la main.
///
/// `infoDictionary` injectable (jamais un vrai `Bundle` dans les tests, même patron que
/// `fileExists`/`defaults: UserDefaults` ailleurs dans le projet) — un dictionnaire de test
/// n'a pas besoin d'un vrai bundle Info.plist chargé.
enum AppVersion {
    /// Convention explicite du propriétaire tant que l'app reste en phase de test :
    /// `MARKETING_VERSION` (project.yml) suit le numéro d'itération, "0.0.<n>".
    static func shortVersion(infoDictionary: [String: Any]? = Bundle.main.infoDictionary) -> String {
        infoDictionary?["CFBundleShortVersionString"] as? String ?? "0.0.0"
    }

    static func displayText(infoDictionary: [String: Any]? = Bundle.main.infoDictionary) -> String {
        "Version \(shortVersion(infoDictionary: infoDictionary))"
    }
}
