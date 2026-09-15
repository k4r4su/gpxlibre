import XCTest
@testable import GPXlibre

/// Spec "rotating-symbols-cap-up" (it18, Bloc 7) : vérifie que le patch de style vectoriel
/// force `viewport` (lisible à l'écran, jamais tourné avec le cap) sur les calques symbol à
/// placement POINT (labels de lieu/POI), et laisse INTACTS les calques à placement LINE (noms
/// de route/rivière, flèches de sens unique — doivent continuer à suivre la ligne).
final class SymbolCapUpAlignmentTests: XCTestCase {
    func testPointPlacementLabelGetsViewportAlignment() {
        let layer: [String: Any] = [
            "id": "label_city",
            "type": "symbol",
            "layout": ["text-field": "{name}"],
        ]

        let patched = MapEngineConstants.patchedSymbolLayerForCapUp(layer)

        let layout = patched["layout"] as? [String: Any]
        XCTAssertEqual(layout?["text-rotation-alignment"] as? String, "viewport")
    }

    func testPointPlacementIconGetsViewportAlignment() {
        let layer: [String: Any] = [
            "id": "poi_r7",
            "type": "symbol",
            "layout": ["icon-image": "poi-icon", "text-field": "{name}"],
        ]

        let patched = MapEngineConstants.patchedSymbolLayerForCapUp(layer)

        let layout = patched["layout"] as? [String: Any]
        XCTAssertEqual(layout?["icon-rotation-alignment"] as? String, "viewport")
        XCTAssertEqual(layout?["text-rotation-alignment"] as? String, "viewport")
    }

    func testLinePlacementTextGetsExplicitMapAlignment() {
        let layer: [String: Any] = [
            "id": "highway-name-major",
            "type": "symbol",
            "layout": ["symbol-placement": "line", "text-field": "{name}"],
        ]

        let patched = MapEngineConstants.patchedSymbolLayerForCapUp(layer)

        let layout = patched["layout"] as? [String: Any]
        XCTAssertEqual(layout?["text-rotation-alignment"] as? String, "map", "les noms de route doivent suivre la carte/la ligne, pas rester droits à l'écran")
    }

    func testLinePlacementIconArrowGetsExplicitMapAlignment() {
        let layer: [String: Any] = [
            "id": "road_one_way_arrow",
            "type": "symbol",
            "layout": ["symbol-placement": "line", "icon-image": "arrow"],
        ]

        let patched = MapEngineConstants.patchedSymbolLayerForCapUp(layer)

        let layout = patched["layout"] as? [String: Any]
        XCTAssertEqual(layout?["icon-rotation-alignment"] as? String, "map", "les flèches de sens unique doivent suivre la route, jamais rester droites à l'écran")
    }

    /// Zoom-dépendant (tableau `step`, ex. les badges numéro de route) : jamais un `"line"` fixe,
    /// traité comme un placement point — doit rester lisible à l'écran comme un badge/icône,
    /// jamais collé à la ligne.
    func testZoomDependentPlacementExpressionIsTreatedAsPoint() {
        let layer: [String: Any] = [
            "id": "highway-shield-non-us",
            "type": "symbol",
            "layout": ["symbol-placement": ["step", ["zoom"], "point", 11, "line"], "icon-image": "shield"],
        ]

        let patched = MapEngineConstants.patchedSymbolLayerForCapUp(layer)

        let layout = patched["layout"] as? [String: Any]
        XCTAssertEqual(layout?["icon-rotation-alignment"] as? String, "viewport")
    }

    func testNonSymbolLayerIsLeftUntouched() {
        let layer: [String: Any] = ["id": "background", "type": "background"]

        let patched = MapEngineConstants.patchedSymbolLayerForCapUp(layer)

        XCTAssertNil(patched["layout"])
    }
}
