import XCTest
@testable import GPXlibre

/// Spec "map-color-flavors" (it19) : transforme les couleurs d'un style vectoriel (teinte/
/// saturation/contraste) sans jamais toucher `layout` (donc sans effet sur la rotation des
/// labels cap-en-haut, contrainte non négociable du prompt).
final class ColorFlavorPatcherTests: XCTestCase {
    // MARK: - Parsing

    func testParsesSixDigitHex() {
        let color = ColorFlavorPatcher.parseColor("#ff0000")
        XCTAssertEqual(color?.h ?? -1, 0, accuracy: 0.5)
        XCTAssertEqual(color?.s ?? 0, 1, accuracy: 0.01)
        XCTAssertEqual(color?.l ?? 0, 0.5, accuracy: 0.01)
        XCTAssertEqual(color?.a ?? 0, 1, accuracy: 0.01)
    }

    func testParsesThreeDigitHex() {
        let color = ColorFlavorPatcher.parseColor("#0f0")
        XCTAssertEqual(color?.h ?? 0, 120, accuracy: 0.5)
    }

    func testParsesRGBA() {
        let color = ColorFlavorPatcher.parseColor("rgba(247, 239, 195, 0.8)")
        XCTAssertNotNil(color)
        XCTAssertEqual(color?.a ?? 0, 0.8, accuracy: 0.01)
    }

    func testParsesHSL() {
        let color = ColorFlavorPatcher.parseColor("hsl(36,6%,74%)")
        XCTAssertEqual(color?.h ?? 0, 36, accuracy: 0.01)
        XCTAssertEqual(color?.s ?? 0, 0.06, accuracy: 0.001)
        XCTAssertEqual(color?.l ?? 0, 0.74, accuracy: 0.001)
        XCTAssertEqual(color?.a ?? 0, 1, accuracy: 0.01)
    }

    func testParsesHSLA() {
        let color = ColorFlavorPatcher.parseColor("hsla(98,61%,72%,0.7)")
        XCTAssertEqual(color?.h ?? 0, 98, accuracy: 0.01)
        XCTAssertEqual(color?.a ?? 0, 0.7, accuracy: 0.01)
    }

    func testNonColorStringsReturnNil() {
        XCTAssertNil(ColorFlavorPatcher.parseColor("interpolate"))
        XCTAssertNil(ColorFlavorPatcher.parseColor("Noto Sans Regular"))
        XCTAssertNil(ColorFlavorPatcher.parseColor("some-icon-name"))
        XCTAssertNil(ColorFlavorPatcher.parseColor("zoom"))
    }

    // MARK: - Transform

    func testStandardFlavorPreservesHueSaturationLightness() {
        let original = ColorFlavorPatcher.parseColor("#3366cc")!
        let transformed = ColorFlavorPatcher.transformedColorString("#3366cc", flavor: .standard)!
        let reparsed = ColorFlavorPatcher.parseColor(transformed)!
        XCTAssertEqual(reparsed.h, original.h, accuracy: 0.1)
        XCTAssertEqual(reparsed.s, original.s, accuracy: 0.01)
        XCTAssertEqual(reparsed.l, original.l, accuracy: 0.01)
    }

    func testHueShiftWrapsAroundThreeSixtyDegrees() {
        // hsl(350, ...) + le décalage de "terreux" doit revenir près de 0°, jamais ≥ 360°
        // (indépendant de la valeur exacte du décalage, pour ne pas coupler ce test à une
        // constante de réglage amenée à changer).
        let transformed = ColorFlavorPatcher.transformedColorString("hsl(350,50%,50%)", flavor: .terreux)!
        let reparsed = ColorFlavorPatcher.parseColor(transformed)!
        let expectedWrapped = (350 + MapColorFlavor.terreux.hueShiftDegrees).truncatingRemainder(dividingBy: 360)
        XCTAssertEqual(reparsed.h, expectedWrapped, accuracy: 0.5)
        XCTAssertLessThan(reparsed.h, 350, "doit avoir bouclé, pas juste additionné sans borne")
    }

    func testHauteContrasteBoostsSaturationAndSpreadsLightness() {
        let darkColor = ColorFlavorPatcher.transformedColorString("hsl(200,40%,20%)", flavor: .hauteContraste)!
        let darkParsed = ColorFlavorPatcher.parseColor(darkColor)!
        XCTAssertGreaterThan(darkParsed.s, 0.4, "la saturation doit augmenter (×1.35)")
        XCTAssertLessThan(darkParsed.l, 0.20, "une couleur déjà sombre doit devenir encore plus sombre (contraste)")

        let lightColor = ColorFlavorPatcher.transformedColorString("hsl(200,40%,80%)", flavor: .hauteContraste)!
        let lightParsed = ColorFlavorPatcher.parseColor(lightColor)!
        XCTAssertGreaterThan(lightParsed.l, 0.80, "une couleur déjà claire doit devenir encore plus claire (contraste)")
    }

    /// Fix "flavor-parameters-imperceptible" (retour terrain, it19-bis : "standard et les
    /// autres se ressemblent") — un fond de carte quasi neutre (saturation très basse, typique
    /// d'un style clair) doit devenir VISIBLEMENT plus coloré sous "Contraste élevé"/"Terreux",
    /// pas juste marginalement (un multiplicateur seul est insuffisant sur une valeur proche de
    /// zéro, voir MapColorFlavor.saturationBoost).
    func testNearNeutralBackgroundColorBecomesVisiblyColoredUnderNonStandardFlavors() {
        let nearNeutral = "hsl(60,4%,95%)"

        let hauteContrasteResult = ColorFlavorPatcher.parseColor(ColorFlavorPatcher.transformedColorString(nearNeutral, flavor: .hauteContraste)!)!
        let terreuxResult = ColorFlavorPatcher.parseColor(ColorFlavorPatcher.transformedColorString(nearNeutral, flavor: .terreux)!)!

        XCTAssertGreaterThan(hauteContrasteResult.s, 0.15, "un multiplicateur seul (0.04×1.5=0.06) resterait imperceptible sans le terme additif")
        XCTAssertGreaterThan(terreuxResult.s, 0.08)
    }

    func testSaturationNeverExceedsValidRange() {
        let transformed = ColorFlavorPatcher.transformedColorString("hsl(100,90%,50%)", flavor: .hauteContraste)!
        let reparsed = ColorFlavorPatcher.parseColor(transformed)!
        XCTAssertLessThanOrEqual(reparsed.s, 1.0)
        XCTAssertGreaterThanOrEqual(reparsed.s, 0.0)
    }

    func testLightnessNeverExceedsValidRange() {
        let transformed = ColorFlavorPatcher.transformedColorString("hsl(100,50%,98%)", flavor: .hauteContraste)!
        let reparsed = ColorFlavorPatcher.parseColor(transformed)!
        XCTAssertLessThanOrEqual(reparsed.l, 1.0)
    }

    // MARK: - Layer traversal

    func testAppliesOnlyToPaintNeverToLayout() {
        let layers: [[String: Any]] = [[
            "id": "water",
            "type": "fill",
            "paint": ["fill-color": "#3366cc"],
            "layout": ["visibility": "visible"],
        ]]

        let patched = ColorFlavorPatcher.apply(.hauteContraste, toLayers: layers)

        let paint = patched[0]["paint"] as? [String: Any]
        XCTAssertNotEqual(paint?["fill-color"] as? String, "#3366cc", "paint doit être transformé")
        let layout = patched[0]["layout"] as? [String: Any]
        XCTAssertEqual(layout?["visibility"] as? String, "visible", "layout ne doit JAMAIS être modifié (rotation cap-en-haut)")
        XCTAssertEqual(patched[0]["id"] as? String, "water")
        XCTAssertEqual(patched[0]["type"] as? String, "fill")
    }

    func testStandardFlavorLeavesLayersEntirelyUnchanged() {
        let layers: [[String: Any]] = [[
            "id": "water",
            "type": "fill",
            "paint": ["fill-color": "#3366cc"],
        ]]

        let patched = ColorFlavorPatcher.apply(.standard, toLayers: layers)

        XCTAssertEqual(patched[0]["paint"] as? [String: String], ["fill-color": "#3366cc"], "flavor identité : aucun ré-encodage")
    }

    /// Couleur imbriquée dans une expression `interpolate` (profondeur arbitraire) — le parcours
    /// générique doit la trouver et la transformer sans toucher les opérateurs/clés d'expression
    /// ("interpolate", "linear", "zoom", les paliers numériques).
    func testTransformsColorsNestedInsideZoomInterpolateExpressions() {
        let layers: [[String: Any]] = [[
            "id": "road",
            "type": "line",
            "paint": [
                "line-color": ["interpolate", ["linear"], ["zoom"], 5, "hsl(26,87%,62%)", 10, "#ffffff"],
            ],
        ]]

        let patched = ColorFlavorPatcher.apply(.hauteContraste, toLayers: layers)

        guard let paint = patched[0]["paint"] as? [String: Any],
              let expression = paint["line-color"] as? [Any]
        else {
            return XCTFail("structure d'expression attendue")
        }
        XCTAssertEqual(expression[0] as? String, "interpolate", "les opérateurs d'expression ne doivent jamais être touchés")
        XCTAssertEqual(expression[3] as? Int, 5, "les paliers de zoom (nombres) ne doivent jamais être touchés")
        let firstColor = expression[4] as? String
        XCTAssertNotEqual(firstColor, "hsl(26,87%,62%)", "la couleur imbriquée doit être transformée")
        XCTAssertTrue(firstColor?.hasPrefix("hsla(") == true)
    }

    func testNonColorPaintValuesLikePatternNamesAreLeftUntouched() {
        let layers: [[String: Any]] = [[
            "id": "landuse",
            "type": "fill",
            "paint": ["fill-pattern": "hatched-icon", "fill-opacity": 0.5],
        ]]

        let patched = ColorFlavorPatcher.apply(.terreux, toLayers: layers)

        let paint = patched[0]["paint"] as? [String: Any]
        XCTAssertEqual(paint?["fill-pattern"] as? String, "hatched-icon")
        XCTAssertEqual(paint?["fill-opacity"] as? Double, 0.5)
    }
}
