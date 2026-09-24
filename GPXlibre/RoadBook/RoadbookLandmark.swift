import Foundation

/// Catégories de repères AUTORISÉES dans le Road Book — itération "repères = uniquement ce que le
/// conducteur voit". Principe produit non négociable : un repère n'apparaît que si le pilote peut
/// le VOIR en roulant (panneau, marquage/infrastructure au sol, bâtiment ou ouvrage remarquable) ;
/// jamais une frontière abstraite ni une donnée administrative (les anciens checkpoints "limite de
/// commune" ont été supprimés). Toute catégorie absente de cette énumération est ignorée — en
/// ajouter une = un `case` + une ligne dans `RoadbookLandmark.classify`, rien d'autre.
///
/// Rond-point et mini rond-point volontairement ABSENTS : ce sont déjà des manœuvres (palier
/// `.roundabout`), jamais dupliqués en repère.
enum RoadbookLandmarkCategory: String, Codable, Equatable, CaseIterable {
    // Panneaux
    case citySign, stopSign, giveWaySign, trafficSignals, levelCrossing
    // Au sol / infrastructure visible
    case pedestrianCrossing, speedBump, bridge, tunnel
    // Bâtiments et ouvrages remarquables
    case church, townHall, fuel, waterTower, mill, waysideCross, remarkableStructure

    /// Famille, qui fixe la PRIORITÉ entre repères (voir `RoadBookConstants.landmarkGroupPriority`).
    enum Group: String, Codable {
        case sign, ground, building
    }

    var group: Group {
        switch self {
        case .citySign, .stopSign, .giveWaySign, .trafficSignals, .levelCrossing: return .sign
        case .pedestrianCrossing, .speedBump, .bridge, .tunnel: return .ground
        case .church, .townHall, .fuel, .waterTower, .mill, .waysideCross, .remarkableStructure: return .building
        }
    }

    /// Un panneau ne vaut que pour le sens de circulation qu'il regarde (vu de dos : ignoré).
    var isDirectional: Bool {
        switch self {
        case .citySign, .stopSign, .giveWaySign, .trafficSignals: return true
        default: return false
        }
    }

    /// Élément posé SUR une chaussée : il ne concerne le pilote que si cette chaussée est la sienne
    /// (route porteuse dans l'axe de sa trajectoire) — un stop ou un passage piéton de la rue qui
    /// débouche sur la sienne est à quelques mètres de la trace mais ne le concerne pas.
    var requiresRoadAlignment: Bool {
        switch self {
        case .citySign, .stopSign, .giveWaySign, .trafficSignals, .levelCrossing, .pedestrianCrossing, .speedBump: return true
        default: return false
        }
    }

    /// Libellé générique, affiché quand l'élément OSM n'a pas de nom.
    var genericLabel: String {
        switch self {
        case .citySign: return "Entrée d'agglomération"
        case .stopSign: return "Stop"
        case .giveWaySign: return "Cédez-le-passage"
        case .trafficSignals: return "Feux tricolores"
        case .levelCrossing: return "Passage à niveau"
        case .pedestrianCrossing: return "Passage piéton"
        case .speedBump: return "Ralentisseur"
        case .bridge: return "Pont"
        case .tunnel: return "Tunnel"
        case .church: return "Église"
        case .townHall: return "Mairie"
        case .fuel: return "Station-service"
        case .waterTower: return "Château d'eau"
        case .mill: return "Moulin"
        case .waysideCross: return "Calvaire"
        case .remarkableStructure: return "Ouvrage remarquable"
        }
    }

    /// Emoji Unicode natif — rendu direct dans `Text` (SwiftUI) ET `NSString.draw` (PDF). L'entrée
    /// d'agglomération a en plus un pictogramme dessiné (`RoadbookCitySignIcon`).
    var emoji: String {
        switch self {
        case .citySign: return "🏘️"
        case .stopSign: return "🛑"
        case .giveWaySign: return "🔻"
        case .trafficSignals: return "🚦"
        case .levelCrossing: return "🚂"
        case .pedestrianCrossing: return "🚸"
        case .speedBump: return "〰️"
        case .bridge: return "🌉"
        case .tunnel: return "🚇"
        case .church: return "⛪"
        case .townHall: return "🏛️"
        case .fuel: return "⛽"
        case .waterTower: return "🗼"
        case .mill: return "🌬️"
        case .waysideCross: return "✝️"
        case .remarkableStructure: return "🏰"
        }
    }
}

/// Côté du repère par rapport au SENS DE MARCHE.
enum RoadbookLandmarkSide: String, Codable, Equatable {
    case left, right

    var label: String { self == .left ? "à gauche" : "à droite" }
}

/// Repère affiché (à côté d'un virage, ou en ligne dédiée) — catégorie (pictogramme), libellé
/// (nom OSM s'il existe, sinon libellé générique) et côté quand il est déductible.
struct RoadbookLandmarkInfo: Codable, Equatable, Hashable {
    let category: RoadbookLandmarkCategory
    let label: String
    let side: RoadbookLandmarkSide?

    init(category: RoadbookLandmarkCategory, label: String, side: RoadbookLandmarkSide? = nil) {
        self.category = category
        self.label = label
        self.side = side
    }

    /// "Église Saint-Martin à droite" — le côté seulement s'il est connu.
    var displayLabel: String {
        side.map { "\(label) \($0.label)" } ?? label
    }
}

/// Classification PURE d'un élément OSM en repère visible — `nil` = pas un repère autorisé, ou pas
/// identifiable (type non parlant : passage piéton non marqué, aménagement de voirie autre qu'un
/// ralentisseur...). Aucun accès réseau ici, voir `RoadbookLandmarkOverpassService`.
enum RoadbookLandmark {
    static let citySignValues: Set<String> = ["city_limit", "FR:EB10"]
    static let markedCrossings: Set<String> = ["marked", "zebra", "traffic_signals", "uncontrolled"]
    static let speedBumps: Set<String> = ["bump", "hump", "table", "cushion"]

    /// Catégorie + libellé affiché : nom OSM s'il existe (pour une entrée d'agglomération, le
    /// `name` du panneau = la localité), sinon le libellé générique PRÉCIS du type (Chapelle,
    /// Clocher, Château, Phare...), jamais un libellé vague.
    static func classify(_ tags: [String: String]) -> (category: RoadbookLandmarkCategory, label: String)? {
        let name = tags["name"].flatMap { $0.isEmpty ? nil : $0 }
        func labeled(_ category: RoadbookLandmarkCategory, _ generic: String? = nil, name override: String? = nil) -> (RoadbookLandmarkCategory, String) {
            (category, override ?? name ?? generic ?? category.genericLabel)
        }

        let signValues = [tags["traffic_sign"], tags["traffic_sign:forward"], tags["traffic_sign:backward"]]
            .compactMap { $0 }
            .flatMap { $0.split(whereSeparator: { $0 == ";" || $0 == "," }).map { String($0).trimmingCharacters(in: .whitespaces) } }
        if signValues.contains(where: { value in citySignValues.contains { value.hasPrefix($0) } }) {
            // Panneau de SORTIE d'agglomération : pas une entrée, pas un repère d'entrée.
            return tags["city_limit"] == "end" ? nil : labeled(.citySign)
        }

        switch tags["highway"] {
        case "stop": return (.stopSign, RoadbookLandmarkCategory.stopSign.genericLabel)
        case "give_way": return (.giveWaySign, RoadbookLandmarkCategory.giveWaySign.genericLabel)
        case "traffic_signals": return (.trafficSignals, RoadbookLandmarkCategory.trafficSignals.genericLabel)
        case "crossing":
            let marked = tags["crossing"].map(markedCrossings.contains) ?? false
            let zebra = tags["crossing_ref"] == "zebra"
            return (marked || zebra) ? (.pedestrianCrossing, RoadbookLandmarkCategory.pedestrianCrossing.genericLabel) : nil
        default: break
        }
        if tags["railway"] == "level_crossing" { return (.levelCrossing, RoadbookLandmarkCategory.levelCrossing.genericLabel) }
        if let calming = tags["traffic_calming"] {
            return speedBumps.contains(calming) ? (.speedBump, RoadbookLandmarkCategory.speedBump.genericLabel) : nil
        }
        // Nom PROPRE de l'ouvrage seulement : le `name` d'un pont/tunnel routier est celui de la
        // route qui le traverse ("Route de Kembs"), pas un nom de repère.
        if tags["bridge"] == "yes", tags["highway"] != nil { return (.bridge, tags["bridge:name"] ?? RoadbookLandmarkCategory.bridge.genericLabel) }
        if tags["tunnel"] == "yes", tags["highway"] != nil { return (.tunnel, tags["tunnel:name"] ?? RoadbookLandmarkCategory.tunnel.genericLabel) }

        if tags["man_made"] == "bell_tower" { return labeled(.church, "Clocher") }
        if tags["amenity"] == "place_of_worship" || ["church", "chapel"].contains(tags["building"] ?? "") {
            return labeled(.church, tags["building"] == "chapel" ? "Chapelle" : nil)
        }
        switch tags["amenity"] {
        case "townhall": return labeled(.townHall)
        case "fuel": return labeled(.fuel, name: name ?? tags["brand"])
        default: break
        }
        switch tags["man_made"] {
        case "water_tower": return labeled(.waterTower)
        case "windmill", "watermill": return labeled(.mill)
        case "lighthouse": return labeled(.remarkableStructure, "Phare")
        case "tower": return labeled(.remarkableStructure, "Tour")
        default: break
        }
        switch tags["historic"] {
        case "wayside_cross": return labeled(.waysideCross)
        case "wayside_shrine": return labeled(.waysideCross, "Oratoire")
        case "castle": return labeled(.remarkableStructure, "Château")
        default: return nil
        }
    }
}
