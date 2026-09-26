import Foundation

/// Traductions (it31, point 4). Les textes écrits dans le code passent par `String(localized:)`
/// (ou par les initialiseurs SwiftUI à littéral), extraits par le compilateur. Ce helper sert aux
/// seuls textes CONNUS SEULEMENT À L'EXÉCUTION : libellés de repères stockés en clé française dans
/// le cache (`RoadbookLandmarkInfo.label`, "Pont", "Chapelle"…). Une clé sans traduction — un nom
/// propre OSM — est rendue telle quelle. Ces clés sont listées dans `L10n.dynamicKeys` pour que
/// les tests vérifient qu'elles sont traduites dans chaque langue.
enum L10n {
    static func dynamic(_ key: String) -> String {
        Bundle.appLanguage.localizedString(forKey: key, value: key, table: nil)
    }

    /// Libellés génériques du catalogue de repères + libellés précis produits au décodage.
    static var dynamicKeys: [String] {
        RoadbookLandmarkCategory.allCases.map(\.genericLabel) + RoadbookLandmark.specificLabelKeys
    }
}
