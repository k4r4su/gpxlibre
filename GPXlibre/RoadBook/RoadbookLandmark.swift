import Foundation

/// Catégorie d'un repère OSM détecté à proximité d'un point de manœuvre (spec "roadbook-mode",
/// it23sexies, retour terrain : "à côté de la flèche il y ait des pictogrammes [emoji] afin
/// d'augmenter l'aide au niveau du prochain virage") — chaque catégorie porte son PROPRE emoji,
/// affiché en grand à côté du pictogramme de direction (voir `RoadBookTabView`/
/// `RoadbookFocusedView`), le texte (`RoadbookLandmarkInfo.label`) restant disponible en
/// complément (table écran, colonne Note du PDF).
enum RoadbookLandmarkCategory: String, Codable, Equatable {
    // Palier 1 : sécurité route.
    case unpavedRoad, levelCrossing, bridge, ford
    // Palier 2 : repères visuels forts.
    case roundabout, church, powerLine, trafficSignals, giveWay, fuel, railway
    // Palier 3 : repères visuels faibles.
    case tree, house
    // Palier 4 : repli générique.
    case genericName

    /// Emoji Unicode natif — rendu direct dans `Text` (SwiftUI) ET `NSString.draw` (PDF/UIKit),
    /// aucun asset image à maintenir, aucune dépendance à SF Symbols pour ce besoin précis
    /// (l'utilisateur demande explicitement "niveau emoji on a ce qu'il faut").
    var emoji: String {
        switch self {
        case .unpavedRoad: return "🚧"
        case .levelCrossing: return "🚂"
        case .bridge: return "🌉"
        case .ford: return "💧"
        case .roundabout: return "🔄"
        case .church: return "⛪"
        case .powerLine: return "⚡"
        case .trafficSignals: return "🚦"
        case .giveWay: return "🛑"
        case .fuel: return "⛽"
        case .railway: return "🚆"
        case .tree: return "🌳"
        case .house: return "🏠"
        case .genericName: return "📍"
        }
    }
}

/// Résultat complet d'une recherche de repère — catégorie (pour l'emoji) + libellé texte (pour
/// l'affichage détaillé table/PDF). `Codable` pour le cache disque (`RoadbookLandmarkCache`).
struct RoadbookLandmarkInfo: Codable, Equatable {
    let category: RoadbookLandmarkCategory
    let label: String
}

/// Choisit le repère le plus PERTINENT pour un pilote moto parmi les tags OSM trouvés à
/// proximité d'un point de manœuvre (spec "roadbook-mode" it23quater/it23sexies). Logique
/// PURE — aucun accès réseau ici, voir `RoadbookLandmarkService` pour la récupération des tags
/// eux-mêmes (Overpass API).
///
/// Ordre de priorité délibéré, en 4 paliers : (1) singularités de la ROUTE elle-même
/// (revêtement qui change, passage à niveau, pont) — information de SÉCURITÉ/pilotage, pas un
/// simple repère visuel ; (2) repères visuels FORTS et sans ambiguïté (église, rond-point,
/// ligne électrique, feux) ; (3) repères visuels FAIBLES mais utiles pour se diriger à vue
/// (retour terrain, it23quater : "rajouter des maisons, des arbres, des points clés qui
/// permettent de se diriger") — une maison isolée ou un arbre remarquable n'ont d'intérêt que
/// s'ils sont peu nombreux à proximité (sinon "Maison" à chaque virage en zone habitée serait
/// du bruit, pas un repère) ; (4) repli sur un nom générique. Un tag générique sans intérêt réel
/// (`landuse=residential`, un `building=yes` en pleine ville...) n'est JAMAIS retenu au palier 3
/// — seul un décompte FAIBLE de bâtiments à proximité (isolement réel) qualifie.
enum RoadbookLandmark {
    private static let unpavedSurfaces: Set<String> = ["unpaved", "gravel", "dirt", "ground", "sand", "grass", "mud"]
    /// Au-delà de ce nombre de bâtiments trouvés dans le même rayon, on est en zone habitée
    /// dense — "Maison" cesserait d'être un repère distinctif, voir palier 3.
    static let maxBuildingCountForIsolatedHouse = 2

    /// `tagsList` : les jeux de tags de CHAQUE élément OSM trouvé à proximité (peut être vide),
    /// dans l'ordre de distance croissante au point recherché (le plus proche en premier) —
    /// voir `RoadbookLandmarkService`, qui trie déjà ainsi avant d'appeler cette fonction.
    static func bestLandmark(for tagsList: [[String: String]]) -> RoadbookLandmarkInfo? {
        for tags in tagsList {
            if let surface = tags["surface"], unpavedSurfaces.contains(surface) {
                return RoadbookLandmarkInfo(category: .unpavedRoad, label: "Route non goudronnée")
            }
            if tags["railway"] == "level_crossing" { return RoadbookLandmarkInfo(category: .levelCrossing, label: "Passage à niveau") }
            if tags["bridge"] == "yes" { return RoadbookLandmarkInfo(category: .bridge, label: "Pont") }
            if tags["ford"] == "yes" { return RoadbookLandmarkInfo(category: .ford, label: "Gué") }
        }
        for tags in tagsList {
            if tags["junction"] == "roundabout" { return RoadbookLandmarkInfo(category: .roundabout, label: "Rond-point") }
            if tags["amenity"] == "place_of_worship" || tags["religion"] != nil {
                return RoadbookLandmarkInfo(category: .church, label: tags["name"].map { "Église \($0)" } ?? "Église")
            }
            if tags["power"] == "line" || tags["power"] == "tower" { return RoadbookLandmarkInfo(category: .powerLine, label: "Ligne électrique") }
            if tags["highway"] == "traffic_signals" { return RoadbookLandmarkInfo(category: .trafficSignals, label: "Feux tricolores") }
            if tags["highway"] == "give_way" || tags["highway"] == "stop" { return RoadbookLandmarkInfo(category: .giveWay, label: "Cédez-le-passage / Stop") }
            if tags["amenity"] == "fuel" { return RoadbookLandmarkInfo(category: .fuel, label: tags["name"].map { "Station \($0)" } ?? "Station essence") }
            if tags["railway"] == "rail" { return RoadbookLandmarkInfo(category: .railway, label: "Voie ferrée") }
        }
        // Palier 3 : arbre remarquable (toujours pertinent, un arbre isolé cartographié dans
        // OSM l'est déjà par nature) puis maison isolée (seulement si peu de bâtiments autour —
        // voir maxBuildingCountForIsolatedHouse).
        for tags in tagsList {
            if tags["natural"] == "tree" {
                return RoadbookLandmarkInfo(category: .tree, label: tags["name"].map { "Arbre (\($0))" } ?? "Arbre remarquable")
            }
        }
        let buildingCount = tagsList.filter { $0["building"] != nil }.count
        if buildingCount > 0, buildingCount <= maxBuildingCountForIsolatedHouse,
           let firstBuilding = tagsList.first(where: { $0["building"] != nil }) {
            return RoadbookLandmarkInfo(category: .house, label: firstBuilding["name"].map { "Maison \($0)" } ?? "Maison isolée")
        }
        // Repli : un nom générique (village, lieu-dit, commerce) reste plus utile que rien.
        for tags in tagsList {
            if let name = tags["name"], !name.isEmpty { return RoadbookLandmarkInfo(category: .genericName, label: name) }
        }
        return nil
    }
}
