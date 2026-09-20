import Foundation

/// Choisit la description la plus PERTINENTE pour un pilote moto parmi les tags OSM trouvés à
/// proximité d'un point de manœuvre (spec "roadbook-mode" it23quater, retour terrain : "si on
/// tourne à une église, un rond-point, etc., est-ce possible d'avoir des infos pertinentes
/// depuis la map"). Logique PURE — aucun accès réseau ici, voir `RoadbookLandmarkService` pour
/// la récupération des tags eux-mêmes (Overpass API).
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
    private static let maxBuildingCountForIsolatedHouse = 2

    /// `tagsList` : les jeux de tags de CHAQUE élément OSM trouvé à proximité (peut être vide),
    /// dans l'ordre de distance croissante au point recherché (le plus proche en premier) —
    /// voir `RoadbookLandmarkService`, qui trie déjà ainsi avant d'appeler cette fonction.
    static func bestDescription(for tagsList: [[String: String]]) -> String? {
        for tags in tagsList {
            if let surface = tags["surface"], unpavedSurfaces.contains(surface) {
                return "Route non goudronnée"
            }
            if tags["railway"] == "level_crossing" { return "Passage à niveau" }
            if tags["bridge"] == "yes" { return "Pont" }
            if tags["ford"] == "yes" { return "Gué" }
        }
        for tags in tagsList {
            if tags["junction"] == "roundabout" { return "Rond-point" }
            if tags["amenity"] == "place_of_worship" || tags["religion"] != nil {
                return tags["name"].map { "Église \($0)" } ?? "Église"
            }
            if tags["power"] == "line" || tags["power"] == "tower" { return "Ligne électrique" }
            if tags["highway"] == "traffic_signals" { return "Feux tricolores" }
            if tags["highway"] == "give_way" || tags["highway"] == "stop" { return "Cédez-le-passage / Stop" }
            if tags["amenity"] == "fuel" { return tags["name"].map { "Station \($0)" } ?? "Station essence" }
            if tags["railway"] == "rail" { return "Voie ferrée" }
        }
        // Palier 3 : arbre remarquable (toujours pertinent, un arbre isolé cartographié dans
        // OSM l'est déjà par nature) puis maison isolée (seulement si peu de bâtiments autour —
        // voir maxBuildingCountForIsolatedHouse).
        for tags in tagsList {
            if tags["natural"] == "tree" { return tags["name"].map { "Arbre (\($0))" } ?? "Arbre remarquable" }
        }
        let buildingCount = tagsList.filter { $0["building"] != nil }.count
        if buildingCount > 0, buildingCount <= maxBuildingCountForIsolatedHouse,
           let firstBuilding = tagsList.first(where: { $0["building"] != nil }) {
            return firstBuilding["name"].map { "Maison \($0)" } ?? "Maison isolée"
        }
        // Repli : un nom générique (village, lieu-dit, commerce) reste plus utile que rien.
        for tags in tagsList {
            if let name = tags["name"], !name.isEmpty { return name }
        }
        return nil
    }
}
