import Foundation

/// CATALOGUE des repères du Road Book — seule liste de ce qui peut apparaître (jalon it28,
/// "repères = uniquement ce que le conducteur voit"). Principe produit non négociable : un repère
/// n'apparaît que si le pilote peut le VOIR en roulant (panneau, infrastructure, bâtiment ou
/// ouvrage remarquable, service identifiable) ; jamais une frontière abstraite ni une donnée
/// administrative. Tout élément OSM hors catalogue est ignoré.
///
/// Chaque catégorie déclare AU MÊME ENDROIT (`definition`) sa famille, son libellé, son
/// pictogramme, ses sélecteurs Overpass et sa règle de reconnaissance — ajouter une catégorie =
/// un `case` + une entrée dans `definition` + son rayon dans `RoadBookConstants`. Activation par
/// défaut : `RoadBookConstants.landmarkDefaultEnabledCategories` ; choix de l'utilisateur :
/// Réglages > Repères du Road Book (`RideSettingsStore.roadbookLandmarkCategories`).
///
/// Rond-point et mini rond-point volontairement ABSENTS : ce sont déjà des manœuvres (palier
/// `.roundabout`), jamais dupliqués en repère. Passage piéton RETIRÉ (it28) : trop fréquent en
/// agglomération, bruit plus que repère.
enum RoadbookLandmarkCategory: String, Codable, Equatable, CaseIterable, Identifiable {
    // Panneaux
    case citySign, stopSign, giveWaySign, trafficSignals, levelCrossing
    // Infrastructure
    case speedBump, bridge, tunnel
    // Bâtiments et ouvrages remarquables
    case church, townHall, waterTower, mill, waysideCross, castle
    // Services
    case fuel, chargingStation
    // Autres (désactivées par défaut)
    case parking, restArea, drinkingWater, restaurant, cafe, bakery, supermarket, pharmacy, hotel,
         campsite, trainStation, school, cemetery, memorial, windTurbine, antenna, lighthouse, tower

    var id: String { rawValue }

    /// Famille : regroupement du menu Réglages ET priorité entre repères
    /// (`RoadBookConstants.landmarkGroupPriority`).
    enum Group: String, Codable, CaseIterable, Identifiable {
        case sign, infrastructure, building, service, other

        var id: String { rawValue }

        var label: String {
            switch self {
            case .sign: return String(localized: "Panneaux", bundle: .appLanguage)
            case .infrastructure: return String(localized: "Infrastructure", bundle: .appLanguage)
            case .building: return String(localized: "Bâtiments", bundle: .appLanguage)
            case .service: return String(localized: "Services", bundle: .appLanguage)
            case .other: return String(localized: "Autres", bundle: .appLanguage)
            }
        }

        var categories: [RoadbookLandmarkCategory] { RoadbookLandmarkCategory.allCases.filter { $0.group == self } }
    }

    struct Definition {
        let group: Group
        let genericLabel: String
        /// Emoji Unicode natif — rendu direct dans `Text` (SwiftUI) ET `NSString.draw` (PDF).
        let emoji: String
        /// Filtres Overpass QL (type d'élément + filtres de tags), sans la clause `around` —
        /// ajoutée par `RoadbookLandmarkOverpassService.query` avec le rayon de la catégorie.
        let overpassSelectors: [String]
        /// Reconnaissance d'un élément OSM déjà renvoyé (`RoadbookLandmark.classify`).
        let matches: ([String: String]) -> Bool
    }

    var definition: Definition {
        switch self {
        case .citySign:
            let values = RoadbookLandmark.citySignValues.joined(separator: "|")
            return Definition(group: .sign, genericLabel: "Entrée d'agglomération", emoji: "🏘️",
                              overpassSelectors: [
                                "node[\"traffic_sign\"~\"\(values)\",i]", "node[\"traffic_sign:forward\"~\"\(values)\",i]",
                                "node[\"traffic_sign:backward\"~\"\(values)\",i]", "node[\"highway\"=\"city_limit\"]",
                                "node[\"city_limit\"~\"^(begin|both)$\"]",
                              ],
                              matches: RoadbookLandmark.isCityEntrySign)
        case .stopSign:
            return Definition(group: .sign, genericLabel: "Stop", emoji: "🛑", overpassSelectors: ["node[\"highway\"=\"stop\"]"], matches: { $0["highway"] == "stop" })
        case .giveWaySign:
            return Definition(group: .sign, genericLabel: "Cédez-le-passage", emoji: "🔻", overpassSelectors: ["node[\"highway\"=\"give_way\"]"], matches: { $0["highway"] == "give_way" })
        case .trafficSignals:
            return Definition(group: .sign, genericLabel: "Feux tricolores", emoji: "🚦", overpassSelectors: ["node[\"highway\"=\"traffic_signals\"]"], matches: { $0["highway"] == "traffic_signals" })
        case .levelCrossing:
            return Definition(group: .sign, genericLabel: "Passage à niveau", emoji: "🚂", overpassSelectors: ["node[\"railway\"=\"level_crossing\"]"], matches: { $0["railway"] == "level_crossing" })
        case .speedBump:
            return Definition(group: .infrastructure, genericLabel: "Ralentisseur", emoji: "〰️",
                              overpassSelectors: ["node[\"traffic_calming\"~\"^(bump|hump|table|cushion)$\"]"],
                              matches: { RoadbookLandmark.speedBumps.contains($0["traffic_calming"] ?? "") })
        case .bridge:
            return Definition(group: .infrastructure, genericLabel: "Pont", emoji: "🌉",
                              overpassSelectors: ["way[\"highway\"][\"bridge\"~\"^(yes|viaduct)$\"]"],
                              matches: { ["yes", "viaduct"].contains($0["bridge"] ?? "") && $0["highway"] != nil })
        case .tunnel:
            return Definition(group: .infrastructure, genericLabel: "Tunnel", emoji: "🚇",
                              overpassSelectors: ["way[\"highway\"][\"tunnel\"=\"yes\"]"],
                              matches: { $0["tunnel"] == "yes" && $0["highway"] != nil })
        case .church:
            return Definition(group: .building, genericLabel: "Église", emoji: "⛪",
                              overpassSelectors: ["nwr[\"amenity\"=\"place_of_worship\"]", "nwr[\"building\"~\"^(church|chapel)$\"]", "nwr[\"man_made\"=\"bell_tower\"]"],
                              matches: { $0["amenity"] == "place_of_worship" || ["church", "chapel"].contains($0["building"] ?? "") || $0["man_made"] == "bell_tower" })
        case .townHall:
            return Definition(group: .building, genericLabel: "Mairie", emoji: "🏛️", overpassSelectors: ["nwr[\"amenity\"=\"townhall\"]"], matches: { $0["amenity"] == "townhall" })
        case .waterTower:
            return Definition(group: .building, genericLabel: "Château d'eau", emoji: "💧", overpassSelectors: ["nwr[\"man_made\"=\"water_tower\"]"], matches: { $0["man_made"] == "water_tower" })
        case .mill:
            return Definition(group: .building, genericLabel: "Moulin", emoji: "🌬️",
                              overpassSelectors: ["nwr[\"man_made\"~\"^(windmill|watermill)$\"]"],
                              matches: { ["windmill", "watermill"].contains($0["man_made"] ?? "") })
        case .waysideCross:
            return Definition(group: .building, genericLabel: "Calvaire", emoji: "✝️",
                              overpassSelectors: ["nwr[\"historic\"~\"^(wayside_cross|wayside_shrine)$\"]"],
                              matches: { ["wayside_cross", "wayside_shrine"].contains($0["historic"] ?? "") })
        case .castle:
            return Definition(group: .building, genericLabel: "Château", emoji: "🏰",
                              overpassSelectors: ["nwr[\"historic\"=\"castle\"]", "nwr[\"building\"=\"castle\"]"],
                              matches: { $0["historic"] == "castle" || $0["building"] == "castle" })
        case .fuel:
            return Definition(group: .service, genericLabel: "Station-service", emoji: "⛽", overpassSelectors: ["nwr[\"amenity\"=\"fuel\"]"], matches: { $0["amenity"] == "fuel" })
        case .chargingStation:
            return Definition(group: .service, genericLabel: "Borne de recharge", emoji: "🔌", overpassSelectors: ["nwr[\"amenity\"=\"charging_station\"]"], matches: { $0["amenity"] == "charging_station" })
        case .parking:
            return Definition(group: .other, genericLabel: "Parking", emoji: "🅿️",
                              overpassSelectors: ["nwr[\"amenity\"=\"parking\"]"],
                              matches: { $0["amenity"] == "parking" && !["private", "no"].contains($0["access"] ?? "") })
        case .restArea:
            return Definition(group: .other, genericLabel: "Aire de repos", emoji: "🚻",
                              overpassSelectors: ["nwr[\"highway\"~\"^(rest_area|services)$\"]"],
                              matches: { ["rest_area", "services"].contains($0["highway"] ?? "") })
        case .drinkingWater:
            return Definition(group: .other, genericLabel: "Point d'eau", emoji: "🚰",
                              overpassSelectors: ["node[\"amenity\"~\"^(drinking_water|water_point)$\"]"],
                              matches: { ["drinking_water", "water_point"].contains($0["amenity"] ?? "") })
        case .restaurant:
            return Definition(group: .other, genericLabel: "Restaurant", emoji: "🍽️", overpassSelectors: ["nwr[\"amenity\"=\"restaurant\"]"], matches: { $0["amenity"] == "restaurant" })
        case .cafe:
            return Definition(group: .other, genericLabel: "Café", emoji: "☕", overpassSelectors: ["nwr[\"amenity\"=\"cafe\"]"], matches: { $0["amenity"] == "cafe" })
        case .bakery:
            return Definition(group: .other, genericLabel: "Boulangerie", emoji: "🥖", overpassSelectors: ["nwr[\"shop\"=\"bakery\"]"], matches: { $0["shop"] == "bakery" })
        case .supermarket:
            return Definition(group: .other, genericLabel: "Supermarché", emoji: "🛒", overpassSelectors: ["nwr[\"shop\"=\"supermarket\"]"], matches: { $0["shop"] == "supermarket" })
        case .pharmacy:
            return Definition(group: .other, genericLabel: "Pharmacie", emoji: "💊", overpassSelectors: ["nwr[\"amenity\"=\"pharmacy\"]"], matches: { $0["amenity"] == "pharmacy" })
        case .hotel:
            return Definition(group: .other, genericLabel: "Hôtel", emoji: "🏨",
                              overpassSelectors: ["nwr[\"tourism\"~\"^(hotel|motel)$\"]"],
                              matches: { ["hotel", "motel"].contains($0["tourism"] ?? "") })
        case .campsite:
            return Definition(group: .other, genericLabel: "Camping", emoji: "⛺", overpassSelectors: ["nwr[\"tourism\"=\"camp_site\"]"], matches: { $0["tourism"] == "camp_site" })
        case .trainStation:
            return Definition(group: .other, genericLabel: "Gare", emoji: "🚉",
                              overpassSelectors: ["nwr[\"railway\"~\"^(station|halt)$\"]"],
                              matches: { ["station", "halt"].contains($0["railway"] ?? "") })
        case .school:
            return Definition(group: .other, genericLabel: "École", emoji: "🏫", overpassSelectors: ["nwr[\"amenity\"=\"school\"]"], matches: { $0["amenity"] == "school" })
        case .cemetery:
            return Definition(group: .other, genericLabel: "Cimetière", emoji: "🪦",
                              overpassSelectors: ["nwr[\"landuse\"=\"cemetery\"]", "nwr[\"amenity\"=\"grave_yard\"]"],
                              matches: { $0["landuse"] == "cemetery" || $0["amenity"] == "grave_yard" })
        case .memorial:
            return Definition(group: .other, genericLabel: "Monument", emoji: "🎖️",
                              overpassSelectors: ["nwr[\"historic\"~\"^(memorial|monument)$\"]"],
                              matches: { ["memorial", "monument"].contains($0["historic"] ?? "") })
        case .windTurbine:
            return Definition(group: .other, genericLabel: "Éolienne", emoji: "🌀", overpassSelectors: ["nwr[\"generator:source\"=\"wind\"]"], matches: { $0["generator:source"] == "wind" })
        case .antenna:
            return Definition(group: .other, genericLabel: "Antenne", emoji: "📡",
                              overpassSelectors: ["nwr[\"man_made\"~\"^(mast|communications_tower)$\"]", "nwr[\"man_made\"=\"tower\"][\"tower:type\"=\"communication\"]"],
                              matches: { ["mast", "communications_tower"].contains($0["man_made"] ?? "") || ($0["man_made"] == "tower" && $0["tower:type"] == "communication") })
        case .lighthouse:
            return Definition(group: .other, genericLabel: "Phare", emoji: "🔦", overpassSelectors: ["nwr[\"man_made\"=\"lighthouse\"]"], matches: { $0["man_made"] == "lighthouse" })
        case .tower:
            return Definition(group: .other, genericLabel: "Tour", emoji: "🗼",
                              overpassSelectors: ["nwr[\"man_made\"=\"tower\"]"],
                              matches: { $0["man_made"] == "tower" && $0["tower:type"] != "communication" })
        }
    }

    var group: Group { definition.group }
    /// Clé française stable (stockée dans les données de repères et le cache) — pour l'AFFICHAGE,
    /// `localizedGenericLabel`.
    var genericLabel: String { definition.genericLabel }
    var localizedGenericLabel: String { L10n.dynamic(genericLabel) }
    var emoji: String { definition.emoji }
    var isEnabledByDefault: Bool { RoadBookConstants.landmarkDefaultEnabledCategories.contains(self) }

    /// Un panneau ne vaut que pour le sens de circulation qu'il regarde (vu de dos : ignoré).
    var isDirectional: Bool {
        switch self {
        case .citySign, .stopSign, .giveWaySign, .trafficSignals: return true
        default: return false
        }
    }

    /// Élément posé SUR une chaussée : il ne concerne le pilote que si cette chaussée est la sienne
    /// (route porteuse dans l'axe de sa trajectoire) — le stop de la rue qui débouche sur la sienne
    /// est à quelques mètres de la trace mais ne le concerne pas.
    var requiresRoadAlignment: Bool {
        switch self {
        case .citySign, .stopSign, .giveWaySign, .trafficSignals, .levelCrossing, .speedBump: return true
        default: return false
        }
    }

    /// Posé SUR la route (traverse la chaussée) : jamais de côté gauche/droite.
    var isOnRoad: Bool { group == .infrastructure || self == .levelCrossing }
}

/// Côté du repère par rapport au SENS DE MARCHE.
enum RoadbookLandmarkSide: String, Codable, Equatable {
    case left, right

    var label: String { self == .left ? String(localized: "à gauche", bundle: .appLanguage) : String(localized: "à droite", bundle: .appLanguage) }
}

/// Repère affiché (à côté d'un virage, ou en ligne dédiée) — catégorie (pictogramme), libellé
/// (nom OSM s'il existe, sinon libellé générique), côté quand il est déductible, et pour un
/// service la distance à la trace (il peut être un peu en retrait : détour à prévoir).
struct RoadbookLandmarkInfo: Codable, Equatable, Hashable {
    let category: RoadbookLandmarkCategory
    let label: String
    let side: RoadbookLandmarkSide?
    let lateralDistanceMeters: Double?

    init(category: RoadbookLandmarkCategory, label: String, side: RoadbookLandmarkSide? = nil, lateralDistanceMeters: Double? = nil) {
        self.category = category
        self.label = label
        self.side = side
        self.lateralDistanceMeters = lateralDistanceMeters
    }

    /// "à droite, 120 m" — distance seulement pour un service en retrait de la route.
    var sideDescription: String? {
        let distance = lateralDistanceMeters.map { "\(Int(($0 / 10).rounded()) * 10) m" }
        switch (side?.label, distance) {
        case let (side?, distance?): return "\(side), \(distance)"
        case let (side?, nil): return side
        case let (nil, distance?): return String(localized: "à \(distance)", bundle: .appLanguage)
        case (nil, nil): return nil
        }
    }

    /// Libellé traduit : les libellés génériques ("Pont", "Chapelle") sont des clés françaises,
    /// un nom propre OSM reste tel quel.
    var localizedLabel: String { L10n.dynamic(label) }

    /// "Église Saint-Martin à droite" — le côté seulement s'il est connu.
    var displayLabel: String {
        sideDescription.map { "\(localizedLabel) \($0)" } ?? localizedLabel
    }
}

/// Classification PURE d'un élément OSM en repère du catalogue — `nil` = hors catalogue (ou
/// panneau de SORTIE d'agglomération). Aucun accès réseau ici, voir
/// `RoadbookLandmarkOverpassService`.
enum RoadbookLandmark {
    /// Libellés précis produits par `label(for:tags:)` en plus des libellés génériques (clés
    /// françaises traduites à l'affichage, voir `L10n.dynamic`).
    static let specificLabelKeys = ["Clocher", "Chapelle", "Lieu de culte", "Oratoire"]

    /// Valeurs de `traffic_sign` d'un panneau d'entrée d'agglomération (comparées sans casse, en
    /// préfixe : "FR:EB10[Hundsbach]") — générique, français, allemand (région frontalière).
    static let citySignValues: [String] = ["city_limit", "FR:EB10", "DE:310"]
    static let speedBumps: Set<String> = ["bump", "hump", "table", "cushion"]

    /// Panneau d'ENTRÉE d'agglomération (`traffic_sign` ou sa variante `:forward`/`:backward`) —
    /// jamais le panneau de sortie (`city_limit=end`).
    /// Formes rencontrées (it29) : `traffic_sign[:forward|:backward]=city_limit|FR:EB10|DE:310`
    /// (casse libre, valeurs multiples), `highway=city_limit` (hors norme mais utilisé), ou
    /// `city_limit=begin|both` seul.
    static func isCityEntrySign(_ tags: [String: String]) -> Bool {
        guard tags["city_limit"] != "end" else { return false }
        let signValues = [tags["traffic_sign"], tags["traffic_sign:forward"], tags["traffic_sign:backward"]]
            .compactMap { $0 }
            .flatMap { $0.split(whereSeparator: { $0 == ";" || $0 == "," }).map { String($0).trimmingCharacters(in: .whitespaces).lowercased() } }
        let isSign = signValues.contains { value in citySignValues.contains { value.hasPrefix($0.lowercased()) } }
        return isSign || tags["highway"] == "city_limit" || ["begin", "both"].contains(tags["city_limit"] ?? "")
    }

    /// Catégorie (première du catalogue qui reconnaît l'élément) + libellé affiché.
    static func classify(_ tags: [String: String]) -> (category: RoadbookLandmarkCategory, label: String)? {
        guard let category = RoadbookLandmarkCategory.allCases.first(where: { $0.definition.matches(tags) }) else { return nil }
        return (category, label(for: category, tags: tags))
    }

    /// Nom OSM s'il existe (pour une entrée d'agglomération, le `name` du panneau = la localité),
    /// sinon un libellé générique PRÉCIS (Chapelle, Clocher, Oratoire...). Exceptions : un panneau
    /// ou un aménagement de chaussée n'a pas de nom propre (un `name` sur un nœud de feux est
    /// celui du carrefour) ; un pont/tunnel routier porte le nom de SA route ("Route de Kembs"),
    /// seul `bridge:name`/`tunnel:name` est un vrai nom d'ouvrage.
    private static func label(for category: RoadbookLandmarkCategory, tags: [String: String]) -> String {
        let name = tags["name"].flatMap { $0.isEmpty ? nil : $0 }
        switch category {
        case .stopSign, .giveWaySign, .trafficSignals, .levelCrossing, .speedBump:
            return category.genericLabel
        case .bridge:
            return tags["bridge:name"] ?? category.genericLabel
        case .tunnel:
            return tags["tunnel:name"] ?? category.genericLabel
        case .church:
            if let name { return name }
            if tags["man_made"] == "bell_tower" { return "Clocher" }
            if tags["building"] == "chapel" { return "Chapelle" }
            if let religion = tags["religion"], religion != "christian" { return "Lieu de culte" }
            return category.genericLabel
        case .fuel, .chargingStation:
            return name ?? tags["brand"] ?? tags["operator"] ?? category.genericLabel
        case .waysideCross:
            return name ?? (tags["historic"] == "wayside_shrine" ? "Oratoire" : category.genericLabel)
        default:
            return name ?? category.genericLabel
        }
    }
}
