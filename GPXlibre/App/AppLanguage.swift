import Foundation
import ObjectiveC

/// Langue de l'app (it31, point 4) — français par défaut, anglais, allemand, espagnol, italien.
enum AppLanguage: String, CaseIterable, Identifiable, Codable {
    /// Langue PRINCIPALE de l'appareil si elle fait partie des cinq, sinon français.
    case automatic
    case fr, en, de, es, it

    var id: String { rawValue }

    static let supportedCodes = ["fr", "en", "de", "es", "it"]
    static let fallbackCode = "fr"

    /// Nom dans SA langue (jamais traduit : on reconnaît sa langue quelle que soit celle affichée).
    var nativeName: String {
        switch self {
        case .automatic: return String(localized: "Automatique (langue de l'appareil)", bundle: .appLanguage)
        case .fr: return "Français"
        case .en: return "English"
        case .de: return "Deutsch"
        case .es: return "Español"
        case .it: return "Italiano"
        }
    }

    /// Code effectif. `.automatic` : SEULE la première langue préférée de l'appareil compte — un
    /// appareil en suédois retombe sur le français, même si l'anglais est sa 2e langue.
    func resolvedCode(preferredLanguages: [String] = Locale.preferredLanguages) -> String {
        guard self == .automatic else { return rawValue }
        guard let first = preferredLanguages.first else { return Self.fallbackCode }
        let code = Locale(identifier: first).language.languageCode?.identifier ?? String(first.prefix(2))
        return Self.supportedCodes.contains(code) ? code : Self.fallbackCode
    }
}

/// Applique une langue à TOUTE l'app, en direct, sans relancer : les recherches de traduction de
/// `Bundle.main` (textes SwiftUI, `String(localized:)`) sont redirigées vers le `.lproj` choisi.
/// La vue racine est reconstruite au changement (`GPXlibreApp`, `.id(code)`).
enum AppLanguageBundle {
    private(set) static var currentCode = AppLanguage.fallbackCode

    /// Locale de la langue de l'app (dates, nombres).
    static var locale: Locale { Locale(identifier: currentCode) }

    /// Étiquette régionale pour les services externes (instructions Valhalla, voix de guidage).
    static var bcp47: String {
        ["fr": "fr-FR", "en": "en-US", "de": "de-DE", "es": "es-ES", "it": "it-IT"][currentCode] ?? "fr-FR"
    }
    fileprivate static var bundle: Bundle?

    static func apply(_ code: String) {
        if object_getClass(Bundle.main) != RedirectingBundle.self {
            object_setClass(Bundle.main, RedirectingBundle.self)
        }
        currentCode = code
        bundle = Bundle.main.path(forResource: code, ofType: "lproj").flatMap(Bundle.init(path:))
    }
}

extension Bundle {
    /// Traductions de la langue choisie — à passer à `String(localized:bundle:)` : contrairement aux
    /// textes SwiftUI, `String(localized:)` ne passe pas par `Bundle.main.localizedString` et
    /// resterait sinon dans la langue de lancement (constaté par test, it31).
    static var appLanguage: Bundle { AppLanguageBundle.bundle ?? .main }
}

private final class RedirectingBundle: Bundle, @unchecked Sendable {
    override func localizedString(forKey key: String, value: String?, table tableName: String?) -> String {
        if let bundle = AppLanguageBundle.bundle {
            return bundle.localizedString(forKey: key, value: value, table: tableName)
        }
        return super.localizedString(forKey: key, value: value, table: tableName)
    }
}
