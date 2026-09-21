import Foundation

/// Catégorie d'un repère OSM détecté à proximité d'un point de manœuvre (spec "roadbook-mode",
/// it23sexies, retour terrain : "à côté de la flèche il y ait des pictogrammes [emoji] afin
/// d'augmenter l'aide au niveau du prochain virage" — liste étendue à 50 tags OSM en it24,
/// point 3) — chaque catégorie porte son PROPRE emoji, affiché en grand à côté du pictogramme de
/// direction (voir `RoadBookTabView`/`RoadbookFocusedView`), le texte (`RoadbookLandmarkInfo.
/// label`) restant disponible en complément (table écran, colonne Note du PDF).
///
/// `CaseIterable` — permet à `RoadbookLandmarkTests.testEveryCategoryProducesANonEmptyEmoji` de
/// rester exhaustif sans lister les cas deux fois (énumération + test), important vu le nombre
/// de catégories désormais couvertes.
enum RoadbookLandmarkCategory: String, Codable, Equatable, CaseIterable {
    // Palier 1 : sécurité route / code de la route.
    case unpavedRoad, levelCrossing, bridge, ford, tunnel, tollBooth, borderControl, citySign,
         giveWay, speedBump, pedestrianCrossing, gate
    // Palier 2 : repères visuels forts.
    case roundabout, church, powerLine, trafficSignals, fuel, railway, restArea, tower, castle,
         station, townHall, hospital, police, fireStation, school, hotel, supermarket, restaurant
    // Palier 3 : repères visuels faibles / nature / historique secondaire.
    case tree, house, campSite, park, viewpoint, peak, caveEntrance, cliff, spring, waterfall,
         water, ruins, monument, waysideCross, cemetery
    // Palier 4 : repli générique.
    case genericName

    /// Emoji Unicode natif — rendu direct dans `Text` (SwiftUI) ET `NSString.draw` (PDF/UIKit),
    /// aucun asset image à maintenir, aucune dépendance à SF Symbols pour ce besoin précis
    /// (l'utilisateur demande explicitement "niveau emoji on a ce qu'il faut"). Choix fait au
    /// mieux d'un pictogramme reconnaissable pour chaque tag — Unicode n'a pas d'emoji dédié
    /// pour certains concepts très spécifiques (moulin, phare...), un repli visuellement proche
    /// a été choisi plutôt que de laisser la catégorie sans pictogramme.
    var emoji: String {
        switch self {
        case .unpavedRoad: return "🚧"
        case .levelCrossing: return "🚂"
        case .bridge: return "🌉"
        case .ford: return "💧"
        case .tunnel: return "🚇"
        case .tollBooth: return "💶"
        case .borderControl: return "🛂"
        case .citySign: return "🏙️"
        case .giveWay: return "🛑"
        case .speedBump: return "🐢"
        case .pedestrianCrossing: return "🚸"
        case .gate: return "🚪"
        case .roundabout: return "🔄"
        case .church: return "⛪"
        case .powerLine: return "⚡"
        case .trafficSignals: return "🚦"
        case .fuel: return "⛽"
        case .railway: return "🚆"
        case .restArea: return "🅿️"
        case .tower: return "🗼"
        case .castle: return "🏰"
        case .station: return "🚉"
        case .townHall: return "🏛️"
        case .hospital: return "🏥"
        case .police: return "🚓"
        case .fireStation: return "🚒"
        case .school: return "🏫"
        case .hotel: return "🏨"
        case .supermarket: return "🛒"
        case .restaurant: return "🍽️"
        case .tree: return "🌳"
        case .house: return "🏠"
        case .campSite: return "🏕️"
        case .park: return "🏞️"
        case .viewpoint: return "🌄"
        case .peak: return "⛰️"
        case .caveEntrance: return "🕳️"
        case .cliff: return "🧗"
        case .spring: return "⛲"
        case .waterfall: return "🌊"
        case .water: return "💦"
        case .ruins: return "🏚️"
        case .monument: return "🗿"
        case .waysideCross: return "✝️"
        case .cemetery: return "⚰️"
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
/// proximité d'un point de manœuvre (spec "roadbook-mode" it23quater/it23sexies ; liste de tags
/// étendue à 50 en it24, point 3). Logique PURE — aucun accès réseau ici, voir
/// `RoadbookLandmarkService` pour la récupération des tags eux-mêmes (Overpass API).
///
/// Ordre de priorité délibéré, en 4 paliers (INCHANGÉ depuis it23quater, les nouveaux tags it24
/// sont classés par ANALOGIE avec l'esprit de chaque palier existant — la fiche it24 donne des
/// GROUPES THÉMATIQUES, pas un ordre de priorité explicite, ce classement est donc un choix
/// assumé plutôt qu'une valeur imposée) : (1) singularités de la ROUTE elle-même/code de la
/// route (revêtement, passage à niveau, pont, gué, tunnel, péage, poste-frontière, entrée
/// d'agglomération, cédez-le-passage/stop, ralentisseur, passage piéton, barrière) — information
/// de SÉCURITÉ/pilotage, pas un simple repère visuel ; (2) repères visuels FORTS et sans
/// ambiguïté, en général de grands bâtiments/structures ou des services bien identifiables
/// (église, rond-point, ligne électrique, feux, station essence, voie ferrée, aire de repos,
/// tour/moulin/cheminée/silo/phare, château, gare, mairie, hôpital, police, pompiers, école,
/// hôtel, supermarché, restaurant) ; (3) repères visuels FAIBLES ou secondaires mais utiles pour
/// se diriger à vue (retour terrain, it23quater : "rajouter des maisons, des arbres, des points
/// clés qui permettent de se diriger" — arbre remarquable/maison isolée, camping, parc, point de
/// vue, sommet, grotte, falaise, source, cascade, plan d'eau, ruines, monument, croix, cimetière)
/// — une maison isolée ou un arbre remarquable n'ont d'intérêt que s'ils sont peu nombreux à
/// proximité (sinon "Maison" à chaque virage en zone habitée serait du bruit, pas un repère) ;
/// (4) repli sur un nom générique. Un tag générique sans intérêt réel (`landuse=residential`, un
/// `building=yes` en pleine ville...) n'est JAMAIS retenu au palier 3 — seul un décompte FAIBLE
/// de bâtiments à proximité (isolement réel) qualifie.
///
/// Hors périmètre explicite (spec it24, point 3) : `highway=speed_camera` (radars) — touche au
/// même sujet que les alertes trafic déjà mises de côté en attendant la clé API TomTom, à
/// trancher indépendamment plutôt qu'ajouté ici silencieusement.
enum RoadbookLandmark {
    private static let unpavedSurfaces: Set<String> = ["unpaved", "gravel", "dirt", "ground", "sand", "grass", "mud"]
    /// Au-delà de ce nombre de bâtiments trouvés dans le même rayon, on est en zone habitée
    /// dense — "Maison" cesserait d'être un repère distinctif, voir palier 3.
    static let maxBuildingCountForIsolatedHouse = 2

    /// Un matcher = "ce jeu de tags correspond-il à MA catégorie ?" — `nil` si non, sinon le
    /// libellé à afficher. Table déclarative plutôt que des `if let` répétés à la main : ajouter
    /// un tag OSM revient à ajouter UNE ligne, sans toucher à la boucle de résolution ci-dessous.
    private struct Matcher {
        let tier: Int
        let category: RoadbookLandmarkCategory
        let match: ([String: String]) -> String?
    }

    private static let matchers: [Matcher] = [
        // MARK: Palier 1 — sécurité route / code de la route
        Matcher(tier: 1, category: .unpavedRoad) { tags in
            guard let surface = tags["surface"], unpavedSurfaces.contains(surface) else { return nil }
            return "Route non goudronnée"
        },
        Matcher(tier: 1, category: .levelCrossing) { $0["railway"] == "level_crossing" ? "Passage à niveau" : nil },
        Matcher(tier: 1, category: .bridge) { $0["bridge"] == "yes" ? "Pont" : nil },
        Matcher(tier: 1, category: .ford) { $0["ford"] == "yes" ? "Gué" : nil },
        Matcher(tier: 1, category: .tunnel) { $0["tunnel"] == "yes" ? "Tunnel" : nil },
        Matcher(tier: 1, category: .tollBooth) { $0["barrier"] == "toll_booth" ? "Péage" : nil },
        Matcher(tier: 1, category: .borderControl) { $0["barrier"] == "border_control" ? "Poste-frontière" : nil },
        Matcher(tier: 1, category: .citySign) { $0["traffic_sign"] == "city_limit" ? "Entrée d'agglomération" : nil },
        Matcher(tier: 1, category: .giveWay) { tags in
            (tags["highway"] == "give_way" || tags["highway"] == "stop") ? "Cédez-le-passage / Stop" : nil
        },
        Matcher(tier: 1, category: .speedBump) { tags in
            (tags["traffic_calming"] == "bump" || tags["traffic_calming"] == "table") ? "Ralentisseur" : nil
        },
        Matcher(tier: 1, category: .pedestrianCrossing) { $0["highway"] == "crossing" ? "Passage piéton" : nil },
        Matcher(tier: 1, category: .gate) { tags in
            if tags["barrier"] == "gate" { return "Barrière" }
            if tags["barrier"] == "lift_gate" { return "Barrière automatique" }
            return nil
        },

        // MARK: Palier 2 — repères visuels forts
        Matcher(tier: 2, category: .roundabout) { tags in
            (tags["junction"] == "roundabout" || tags["highway"] == "mini_roundabout") ? "Rond-point" : nil
        },
        Matcher(tier: 2, category: .church) { tags in
            guard tags["amenity"] == "place_of_worship" || tags["religion"] != nil else { return nil }
            return tags["name"].map { "Église \($0)" } ?? "Église"
        },
        Matcher(tier: 2, category: .powerLine) { tags in
            (tags["power"] == "line" || tags["power"] == "tower") ? "Ligne électrique" : nil
        },
        Matcher(tier: 2, category: .trafficSignals) { $0["highway"] == "traffic_signals" ? "Feux tricolores" : nil },
        Matcher(tier: 2, category: .fuel) { tags in
            guard tags["amenity"] == "fuel" else { return nil }
            return tags["name"].map { "Station \($0)" } ?? "Station essence"
        },
        Matcher(tier: 2, category: .railway) { $0["railway"] == "rail" ? "Voie ferrée" : nil },
        Matcher(tier: 2, category: .restArea) { tags in
            if tags["highway"] == "rest_area" { return "Aire de repos" }
            if tags["highway"] == "services" { return "Aire de services" }
            return nil
        },
        Matcher(tier: 2, category: .tower) { tags in
            switch tags["man_made"] {
            case "water_tower": return "Château d'eau"
            case "windmill": return "Moulin"
            case "chimney": return "Cheminée"
            case "silo": return "Silo"
            case "lighthouse": return "Phare"
            default: return nil
            }
        },
        Matcher(tier: 2, category: .castle) { $0["historic"] == "castle" ? "Château" : nil },
        Matcher(tier: 2, category: .station) { $0["railway"] == "station" ? "Gare" : nil },
        Matcher(tier: 2, category: .townHall) { $0["amenity"] == "townhall" ? "Mairie" : nil },
        Matcher(tier: 2, category: .hospital) { $0["amenity"] == "hospital" ? "Hôpital" : nil },
        Matcher(tier: 2, category: .police) { $0["amenity"] == "police" ? "Police" : nil },
        Matcher(tier: 2, category: .fireStation) { $0["amenity"] == "fire_station" ? "Caserne de pompiers" : nil },
        Matcher(tier: 2, category: .school) { $0["amenity"] == "school" ? "École" : nil },
        Matcher(tier: 2, category: .hotel) { tags in
            guard tags["tourism"] == "hotel" else { return nil }
            return tags["name"].map { "Hôtel \($0)" } ?? "Hôtel"
        },
        Matcher(tier: 2, category: .supermarket) { tags in
            guard tags["shop"] == "supermarket" else { return nil }
            return tags["name"].map { "Supermarché \($0)" } ?? "Supermarché"
        },
        Matcher(tier: 2, category: .restaurant) { tags in
            guard tags["amenity"] == "restaurant" else { return nil }
            return tags["name"].map { "Restaurant \($0)" } ?? "Restaurant"
        },

        // MARK: Palier 3 — repères visuels faibles / nature / historique secondaire
        Matcher(tier: 3, category: .tree) { tags in
            guard tags["natural"] == "tree" else { return nil }
            return tags["name"].map { "Arbre (\($0))" } ?? "Arbre remarquable"
        },
        Matcher(tier: 3, category: .campSite) { $0["tourism"] == "camp_site" ? "Camping" : nil },
        Matcher(tier: 3, category: .park) { $0["leisure"] == "park" ? "Parc" : nil },
        Matcher(tier: 3, category: .viewpoint) { $0["tourism"] == "viewpoint" ? "Point de vue" : nil },
        Matcher(tier: 3, category: .peak) { tags in
            guard tags["natural"] == "peak" else { return nil }
            return tags["name"].map { "Sommet \($0)" } ?? "Sommet"
        },
        Matcher(tier: 3, category: .caveEntrance) { $0["natural"] == "cave_entrance" ? "Entrée de grotte" : nil },
        Matcher(tier: 3, category: .cliff) { $0["natural"] == "cliff" ? "Falaise" : nil },
        Matcher(tier: 3, category: .spring) { $0["natural"] == "spring" ? "Source" : nil },
        Matcher(tier: 3, category: .waterfall) { $0["waterway"] == "waterfall" ? "Cascade" : nil },
        Matcher(tier: 3, category: .water) { $0["natural"] == "water" ? "Plan d'eau" : nil },
        Matcher(tier: 3, category: .ruins) { tags in
            if tags["historic"] == "ruins" { return "Ruines" }
            if tags["historic"] == "archaeological_site" { return "Site archéologique" }
            return nil
        },
        Matcher(tier: 3, category: .monument) { $0["historic"] == "monument" ? "Monument" : nil },
        Matcher(tier: 3, category: .waysideCross) { $0["historic"] == "wayside_cross" ? "Croix" : nil },
        Matcher(tier: 3, category: .cemetery) { $0["landuse"] == "cemetery" ? "Cimetière" : nil },
    ]

    /// `tagsList` : les jeux de tags de CHAQUE élément OSM trouvé à proximité (peut être vide),
    /// dans l'ordre de distance croissante au point recherché (le plus proche en premier) —
    /// voir `RoadbookLandmarkService`, qui trie déjà ainsi avant d'appeler cette fonction.
    static func bestLandmark(for tagsList: [[String: String]]) -> RoadbookLandmarkInfo? {
        for tier in 1...3 {
            for tags in tagsList {
                for matcher in matchers where matcher.tier == tier {
                    if let label = matcher.match(tags) {
                        return RoadbookLandmarkInfo(category: matcher.category, label: label)
                    }
                }
            }
            // La maison isolée reste un cas à part au palier 3 : elle a besoin d'un décompte sur
            // TOUT `tagsList` (nombre de bâtiments à proximité), pas d'un simple test par élément
            // — vérifiée seulement APRÈS les matchers ci-dessus (voir `testTreeTakesPriorityOverIsolatedHouse` :
            // un arbre trouvé n'importe où dans la liste doit gagner avant même de considérer une
            // maison isolée trouvée plus tôt dans l'ordre de distance).
            if tier == 3, let house = isolatedHouseLandmark(in: tagsList) {
                return house
            }
        }
        // Palier 4 — repli : un nom générique (village, lieu-dit, commerce) reste plus utile que
        // rien.
        for tags in tagsList {
            if let name = tags["name"], !name.isEmpty { return RoadbookLandmarkInfo(category: .genericName, label: name) }
        }
        return nil
    }

    private static func isolatedHouseLandmark(in tagsList: [[String: String]]) -> RoadbookLandmarkInfo? {
        let buildingCount = tagsList.filter { $0["building"] != nil }.count
        guard buildingCount > 0, buildingCount <= maxBuildingCountForIsolatedHouse,
              let firstBuilding = tagsList.first(where: { $0["building"] != nil })
        else { return nil }
        return RoadbookLandmarkInfo(category: .house, label: firstBuilding["name"].map { "Maison \($0)" } ?? "Maison isolée")
    }
}
