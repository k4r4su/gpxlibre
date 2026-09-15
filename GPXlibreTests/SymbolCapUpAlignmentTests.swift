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

    func testExplicitLinePlacementIsLeftUntouched() {
        let layer: [String: Any] = [
            "id": "highway-name-major",
            "type": "symbol",
            "layout": ["symbol-placement": "line", "text-field": "{name}", "text-rotation-alignment": "map"],
        ]

        let patched = MapEngineConstants.patchedSymbolLayerForCapUp(layer)

        let layout = patched["layout"] as? [String: Any]
        XCTAssertEqual(layout?["text-rotation-alignment"] as? String, "map", "les noms de route doivent continuer à suivre la ligne")
    }

    func testLinePlacementIconArrowIsLeftUntouched() {
        let layer: [String: Any] = [
            "id": "road_one_way_arrow",
            "type": "symbol",
            "layout": ["symbol-placement": "line", "icon-image": "arrow"],
        ]

        let patched = MapEngineConstants.patchedSymbolLayerForCapUp(layer)

        let layout = patched["layout"] as? [String: Any]
        XCTAssertNil(layout?["icon-rotation-alignment"], "les flèches de sens unique suivent la route, jamais l'écran")
    }

    func testNonSymbolLayerIsLeftUntouched() {
        let layer: [String: Any] = ["id": "background", "type": "background"]

        let patched = MapEngineConstants.patchedSymbolLayerForCapUp(layer)

        XCTAssertNil(patched["layout"])
    }
}
