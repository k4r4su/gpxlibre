import Foundation
import Security

/// Identifiants Basic Auth pour une instance Valhalla auto-hébergée (spec "valhalla-client-
/// toggle", it19) — stockés en KEYCHAIN, jamais en UserDefaults/plist (contrairement à
/// l'endpoint, non sensible, voir `RideSettingsStore.valhallaEndpointURLString`) : demande
/// explicite du propriétaire pour un mot de passe. Username ET password tous deux des champs
/// libres (aucune valeur codée en dur) — formulaire générique dans Réglages, voir
/// `ValhallaSettingsView`.
///
/// `service` paramétrable UNIQUEMENT pour la testabilité (même esprit que
/// `tracksDirectoryOverride` sur LibraryStore) : chaque test utilise un service dédié, jamais
/// le vrai Keychain de l'app.
enum ValhallaKeychainStore {
    static let defaultService = "com.olivier.gpxlibre.valhalla"

    static func username(service: String = defaultService) -> String {
        load(account: "username", service: service) ?? ""
    }

    static func password(service: String = defaultService) -> String {
        load(account: "password", service: service) ?? ""
    }

    static func save(username: String, password: String, service: String = defaultService) {
        save(account: "username", value: username, service: service)
        save(account: "password", value: password, service: service)
    }

    /// Jamais appelé en production — nettoyage de fin de test uniquement.
    static func clear(service: String = defaultService) {
        delete(account: "username", service: service)
        delete(account: "password", service: service)
    }

    private static func load(account: String, service: String) -> String? {
        var query = baseQuery(account: account, service: service)
        query[kSecReturnData as String] = kCFBooleanTrue
        query[kSecMatchLimit as String] = kSecMatchLimitOne

        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        guard status == errSecSuccess, let data = result as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    private static func save(account: String, value: String, service: String) {
        let query = baseQuery(account: account, service: service)
        let updateAttributes: [String: Any] = [kSecValueData as String: Data(value.utf8)]

        let existsStatus = SecItemCopyMatching(query as CFDictionary, nil)
        if existsStatus == errSecSuccess {
            SecItemUpdate(query as CFDictionary, updateAttributes as CFDictionary)
        } else {
            var newItem = query
            newItem[kSecValueData as String] = Data(value.utf8)
            SecItemAdd(newItem as CFDictionary, nil)
        }
    }

    private static func delete(account: String, service: String) {
        SecItemDelete(baseQuery(account: account, service: service) as CFDictionary)
    }

    private static func baseQuery(account: String, service: String) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
    }
}
