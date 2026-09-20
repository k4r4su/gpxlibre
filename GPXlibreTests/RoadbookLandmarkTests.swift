import XCTest
@testable import GPXlibre

/// Spec "roadbook-mode" (it23quater, retour terrain : "si on tourne à une église, un
/// rond-point, etc., est-ce possible d'avoir des infos pertinentes depuis la map") — logique
/// PURE de choix du meilleur repère parmi des tags OSM, jamais de vrai réseau ici (voir
/// `RoadbookLandmarkService`, non testé directement pour la même raison que
/// `NominatimGeocodingService`).
final class RoadbookLandmarkTests: XCTestCase {
    func testReturnsNilWhenNoTagsFound() {
        XCTAssertNil(RoadbookLandmark.bestDescription(for: []))
    }

    /// `building` seul est désormais un repère valide au palier 3 ("maison isolée", voir plus
    /// bas) — `landuse` seul (jamais un repère à aucun palier) reste, lui, ignoré.
    func testIgnoresGenericUninterestingTags() {
        XCTAssertNil(RoadbookLandmark.bestDescription(for: [["landuse": "residential"]]))
    }

    func testDetectsRoundabout() {
        let tags = [["junction": "roundabout"]]
        XCTAssertEqual(RoadbookLandmark.bestDescription(for: tags), "Rond-point")
    }

    func testDetectsPlaceOfWorshipWithName() {
        let tags = [["amenity": "place_of_worship", "name": "Saint-Martin"]]
        XCTAssertEqual(RoadbookLandmark.bestDescription(for: tags), "Église Saint-Martin")
    }

    func testDetectsPlaceOfWorshipWithoutName() {
        let tags = [["amenity": "place_of_worship"]]
        XCTAssertEqual(RoadbookLandmark.bestDescription(for: tags), "Église")
    }

    func testDetectsUnpavedSurface() {
        XCTAssertEqual(RoadbookLandmark.bestDescription(for: [["surface": "gravel"]]), "Route non goudronnée")
        XCTAssertEqual(RoadbookLandmark.bestDescription(for: [["surface": "dirt"]]), "Route non goudronnée")
        XCTAssertNil(RoadbookLandmark.bestDescription(for: [["surface": "asphalt"]]), "un revêtement goudronné n'est pas un repère à signaler")
    }

    func testDetectsLevelCrossing() {
        XCTAssertEqual(RoadbookLandmark.bestDescription(for: [["railway": "level_crossing"]]), "Passage à niveau")
    }

    func testDetectsPowerLine() {
        XCTAssertEqual(RoadbookLandmark.bestDescription(for: [["power": "line"]]), "Ligne électrique")
    }

    /// Priorité : les singularités de ROUTE (revêtement, passage à niveau, pont) passent avant
    /// les repères visuels — une route non goudronnée à CE virage précis est plus pertinente à
    /// signaler pour un pilote qu'un rond-point plus loin dans la liste des tags trouvés.
    func testRoadSurfaceTakesPriorityOverVisualLandmarks() {
        let tags = [["junction": "roundabout"], ["surface": "gravel"]]
        XCTAssertEqual(RoadbookLandmark.bestDescription(for: tags), "Route non goudronnée")
    }

    func testFallsBackToGenericNameWhenNothingElseMatches() {
        let tags = [["name": "Le Petit Village", "shop": "bakery"]]
        XCTAssertEqual(RoadbookLandmark.bestDescription(for: tags), "Le Petit Village")
    }

    // MARK: - Maisons/arbres (retour terrain it23quater : "rajouter des maisons, des arbres,
    // des points clés qui permettent de se diriger")

    func testDetectsRemarkableTreeWithName() {
        let tags = [["natural": "tree", "name": "Chêne centenaire"]]
        XCTAssertEqual(RoadbookLandmark.bestDescription(for: tags), "Arbre (Chêne centenaire)")
    }

    func testDetectsRemarkableTreeWithoutName() {
        XCTAssertEqual(RoadbookLandmark.bestDescription(for: [["natural": "tree"]]), "Arbre remarquable")
    }

    func testDetectsIsolatedHouseWhenFewBuildingsNearby() {
        let tags = [["building": "house"]]
        XCTAssertEqual(RoadbookLandmark.bestDescription(for: tags), "Maison isolée")
    }

    /// Coeur du garde-fou : dans une zone densément bâtie, "Maison" à chaque virage serait du
    /// bruit, pas un repère — au-delà du seuil, aucune description n'est produite pour ce
    /// palier (repli sur un nom générique si disponible, sinon nil).
    func testDoesNotReportHouseWhenManyBuildingsNearby() {
        let tags = (0..<10).map { _ in ["building": "yes"] }
        XCTAssertNil(RoadbookLandmark.bestDescription(for: tags))
    }

    func testTreeTakesPriorityOverIsolatedHouse() {
        let tags = [["building": "house"], ["natural": "tree"]]
        XCTAssertEqual(RoadbookLandmark.bestDescription(for: tags), "Arbre remarquable")
    }

    func testNamedIsolatedHouseUsesItsName() {
        let tags = [["building": "house", "name": "Ferme du Moulin"]]
        XCTAssertEqual(RoadbookLandmark.bestDescription(for: tags), "Maison Ferme du Moulin")
    }

    /// Priorité inchangée : un rond-point reste plus pertinent qu'une maison isolée détectée au
    /// même endroit (ex. une maison juste à côté d'un giratoire).
    func testRoundaboutTakesPriorityOverHouse() {
        let tags = [["building": "house"], ["junction": "roundabout"]]
        XCTAssertEqual(RoadbookLandmark.bestDescription(for: tags), "Rond-point")
    }

    func testPicksFirstMatchingElementInDistanceOrder() {
        // Le plus proche (premier de la liste) doit gagner si les deux matchent la même
        // catégorie de priorité.
        let tags = [["amenity": "fuel", "name": "Total"], ["amenity": "fuel", "name": "Esso"]]
        XCTAssertEqual(RoadbookLandmark.bestDescription(for: tags), "Station Total")
    }
}
