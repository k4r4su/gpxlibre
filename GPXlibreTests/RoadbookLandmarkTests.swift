import XCTest
@testable import GPXlibre

/// Spec "roadbook-mode" (it23quater/it23sexies, retour terrain : "si on tourne à une église, un
/// rond-point, etc., est-ce possible d'avoir des infos pertinentes depuis la map" puis "à côté
/// de la flèche il y ait des pictogrammes [emoji]") — logique PURE de choix du meilleur repère
/// (catégorie + libellé) parmi des tags OSM, jamais de vrai réseau ici (voir
/// `RoadbookLandmarkService`, non testé directement pour la même raison que
/// `NominatimGeocodingService`).
final class RoadbookLandmarkTests: XCTestCase {
    private func label(_ tagsList: [[String: String]]) -> String? {
        RoadbookLandmark.bestLandmark(for: tagsList)?.label
    }

    private func category(_ tagsList: [[String: String]]) -> RoadbookLandmarkCategory? {
        RoadbookLandmark.bestLandmark(for: tagsList)?.category
    }

    func testReturnsNilWhenNoTagsFound() {
        XCTAssertNil(RoadbookLandmark.bestLandmark(for: []))
    }

    /// `building` seul est désormais un repère valide au palier 3 ("maison isolée", voir plus
    /// bas) — `landuse` seul (jamais un repère à aucun palier) reste, lui, ignoré.
    func testIgnoresGenericUninterestingTags() {
        XCTAssertNil(RoadbookLandmark.bestLandmark(for: [["landuse": "residential"]]))
    }

    func testDetectsRoundabout() {
        let tags = [["junction": "roundabout"]]
        XCTAssertEqual(label(tags), "Rond-point")
        XCTAssertEqual(category(tags), .roundabout)
        XCTAssertEqual(category(tags)?.emoji, "🔄")
    }

    func testDetectsPlaceOfWorshipWithName() {
        let tags = [["amenity": "place_of_worship", "name": "Saint-Martin"]]
        XCTAssertEqual(label(tags), "Église Saint-Martin")
        XCTAssertEqual(category(tags), .church)
    }

    func testDetectsPlaceOfWorshipWithoutName() {
        XCTAssertEqual(label([["amenity": "place_of_worship"]]), "Église")
    }

    func testDetectsUnpavedSurface() {
        XCTAssertEqual(label([["surface": "gravel"]]), "Route non goudronnée")
        XCTAssertEqual(category([["surface": "gravel"]]), .unpavedRoad)
        XCTAssertEqual(label([["surface": "dirt"]]), "Route non goudronnée")
        XCTAssertNil(label([["surface": "asphalt"]]), "un revêtement goudronné n'est pas un repère à signaler")
    }

    func testDetectsLevelCrossing() {
        XCTAssertEqual(label([["railway": "level_crossing"]]), "Passage à niveau")
        XCTAssertEqual(category([["railway": "level_crossing"]]), .levelCrossing)
    }

    func testDetectsPowerLine() {
        XCTAssertEqual(label([["power": "line"]]), "Ligne électrique")
        XCTAssertEqual(category([["power": "line"]]), .powerLine)
    }

    /// Priorité : les singularités de ROUTE (revêtement, passage à niveau, pont) passent avant
    /// les repères visuels — une route non goudronnée à CE virage précis est plus pertinente à
    /// signaler pour un pilote qu'un rond-point plus loin dans la liste des tags trouvés.
    func testRoadSurfaceTakesPriorityOverVisualLandmarks() {
        let tags = [["junction": "roundabout"], ["surface": "gravel"]]
        XCTAssertEqual(label(tags), "Route non goudronnée")
    }

    func testFallsBackToGenericNameWhenNothingElseMatches() {
        let tags = [["name": "Le Petit Village", "shop": "bakery"]]
        XCTAssertEqual(label(tags), "Le Petit Village")
        XCTAssertEqual(category(tags), .genericName)
    }

    // MARK: - Maisons/arbres (retour terrain it23quater : "rajouter des maisons, des arbres,
    // des points clés qui permettent de se diriger")

    func testDetectsRemarkableTreeWithName() {
        XCTAssertEqual(label([["natural": "tree", "name": "Chêne centenaire"]]), "Arbre (Chêne centenaire)")
    }

    func testDetectsRemarkableTreeWithoutName() {
        let tags = [["natural": "tree"]]
        XCTAssertEqual(label(tags), "Arbre remarquable")
        XCTAssertEqual(category(tags), .tree)
        XCTAssertEqual(category(tags)?.emoji, "🌳")
    }

    func testDetectsIsolatedHouseWhenFewBuildingsNearby() {
        let tags = [["building": "house"]]
        XCTAssertEqual(label(tags), "Maison isolée")
        XCTAssertEqual(category(tags), .house)
        XCTAssertEqual(category(tags)?.emoji, "🏠")
    }

    /// Coeur du garde-fou : dans une zone densément bâtie, "Maison" à chaque virage serait du
    /// bruit, pas un repère — au-delà du seuil, aucune description n'est produite pour ce
    /// palier (repli sur un nom générique si disponible, sinon nil).
    func testDoesNotReportHouseWhenManyBuildingsNearby() {
        let tags = (0..<10).map { _ in ["building": "yes"] }
        XCTAssertNil(RoadbookLandmark.bestLandmark(for: tags))
    }

    func testTreeTakesPriorityOverIsolatedHouse() {
        let tags = [["building": "house"], ["natural": "tree"]]
        XCTAssertEqual(label(tags), "Arbre remarquable")
    }

    func testNamedIsolatedHouseUsesItsName() {
        let tags = [["building": "house", "name": "Ferme du Moulin"]]
        XCTAssertEqual(label(tags), "Maison Ferme du Moulin")
    }

    /// Priorité inchangée : un rond-point reste plus pertinent qu'une maison isolée détectée au
    /// même endroit (ex. une maison juste à côté d'un giratoire).
    func testRoundaboutTakesPriorityOverHouse() {
        let tags = [["building": "house"], ["junction": "roundabout"]]
        XCTAssertEqual(label(tags), "Rond-point")
    }

    func testPicksFirstMatchingElementInDistanceOrder() {
        // Le plus proche (premier de la liste) doit gagner si les deux matchent la même
        // catégorie de priorité.
        let tags = [["amenity": "fuel", "name": "Total"], ["amenity": "fuel", "name": "Esso"]]
        XCTAssertEqual(label(tags), "Station Total")
    }

    /// Chaque catégorie doit produire un emoji NON VIDE — un repère sans pictogramme visible
    /// contredirait exactement la demande terrain ("à côté de la flèche il y ait des
    /// pictogrammes afin d'augmenter l'aide").
    func testEveryCategoryProducesANonEmptyEmoji() {
        for category in [
            RoadbookLandmarkCategory.unpavedRoad, .levelCrossing, .bridge, .ford,
            .roundabout, .church, .powerLine, .trafficSignals, .giveWay, .fuel, .railway,
            .tree, .house, .genericName,
        ] {
            XCTAssertFalse(category.emoji.isEmpty, "\(category)")
        }
    }
}
