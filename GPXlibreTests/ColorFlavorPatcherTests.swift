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

    /// Fix "flavor-still-imperceptible" (it22bis) : remplace l'ancien modèle "étirement autour
    /// de 50 %" (une couleur claire devenait plus claire, une sombre plus sombre) — ce modèle
    /// poussait justement les couleurs claires (majorité d'un fond de carte clair) vers le
    /// plafond où elles s'écrêtaient en blanc optiquement invisible, LA cause du bug remonté.
    /// Nouveau modèle : décalage de luminosité PLAT, dans le MÊME sens (plus sombre) quelle que
    /// soit la luminosité de départ — clair ou sombre, `hauteContraste` assombrit légèrement et
    /// sature toujours davantage.
    func testHauteContrasteBoostsSaturationAndDarkensFlatly() {
        let darkColor = ColorFlavorPatcher.transformedColorString("hsl(200,40%,20%)", flavor: .hauteContraste)!
        let darkParsed = ColorFlavorPatcher.parseColor(darkColor)!
        XCTAssertGreaterThan(darkParsed.s, 0.4, "la saturation doit augmenter (comble une fraction de l'espace restant)")
        XCTAssertEqual(darkParsed.l, 0.20 - 0.07, accuracy: 0.01, "décalage plat, pas un étirement proportionnel")

        let lightColor = ColorFlavorPatcher.transformedColorString("hsl(200,40%,80%)", flavor: .hauteContraste)!
        let lightParsed = ColorFlavorPatcher.parseColor(lightColor)!
        XCTAssertGreaterThan(lightParsed.s, 0.4, "même boost de saturation, indépendant de la luminosité de départ")
        XCTAssertEqual(lightParsed.l, 0.80 - 0.07, accuracy: 0.01, "une couleur déjà claire doit aussi s'assombrir légèrement (jamais repoussée vers le blanc)")
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

    /// Historique : bug initial (it22, "map-flavors-clamp-to-white") diagnostiqué sur la VRAIE
    /// couleur `background` du style embarqué (`#f8f4f0`, HSL(30°, 36.4%, 95.7%), qui domine la
    /// surface visible à la plupart des zooms) — l'ancien étirement de contraste écrêtait cette
    /// couleur en blanc quasi pur. Le fix it22 (clamp à 92 %) restait lui-même insuffisant
    /// (delta RGB réel ~30/765, toujours imperceptible, 2e retour terrain) — remplacé en it22bis
    /// par le décalage plat + boost proportionnel ci-dessus (voir MapColorFlavor). Ce test
    /// reste valide : la luminosité ne doit toujours jamais atteindre un blanc pur.
    func testNearWhiteBackgroundColorIsNeverClampedToPureWhiteUnderHauteContraste() {
        let transformed = ColorFlavorPatcher.transformedColorString("#f8f4f0", flavor: .hauteContraste)!
        let reparsed = ColorFlavorPatcher.parseColor(transformed)!

        XCTAssertLessThan(reparsed.l, 1.0, "un écrêtage à 100% de luminosité rend teinte/saturation invisibles, peu importe leur valeur")
        XCTAssertGreaterThan(reparsed.s, 0.3, "la saturation doit rester perceptible, pas noyée par l'écrêtage à blanc")
    }

    /// Cœur du retour terrain : la couleur DOMINANTE du fond de carte ne doit plus produire un
    /// résultat identique (ou visuellement indiscernable) entre les 3 thèmes.
    func testTheThreeFlavorsProduceDistinguishableResultsForTheDominantBackgroundColor() {
        let background = "#f8f4f0"
        let standard = ColorFlavorPatcher.parseColor(background)!
        let hauteContraste = ColorFlavorPatcher.parseColor(ColorFlavorPatcher.transformedColorString(background, flavor: .hauteContraste)!)!
        let terreux = ColorFlavorPatcher.parseColor(ColorFlavorPatcher.transformedColorString(background, flavor: .terreux)!)!

        // "Visuellement identique" pour une couleur quasi-neutre veut surtout dire : même
        // luminosité ET même saturation quasi nulle. On vérifie qu'au moins un des deux diffère
        // significativement pour chaque paire, pas juste un delta non-nul microscopique.
        XCTAssertGreaterThan(abs(hauteContraste.l - standard.l) + abs(hauteContraste.s - standard.s), 0.1, "Contraste élevé doit être perceptiblement différent de Standard")
        XCTAssertGreaterThan(abs(terreux.l - standard.l) + abs(terreux.s - standard.s) + abs(terreux.h - standard.h) / 360, 0.05, "Terreux doit être perceptiblement différent de Standard")
    }

    /// Fix "flavor-gray-tint-bug" (it22bis, découvert en simulant le patch sur les vraies
    /// couleurs de texte du style : `#333`/`#666`, utilisées pour les labels de lieux/POI). Un
    /// gris pur (`s == 0`) n'a AUCUNE teinte réelle — `h` vaut `0` par pure convention numérique
    /// du parseur (aucune direction n'existe quand max==min du RGB). Appliquer un décalage de
    /// teinte + un boost de saturation à cette valeur par défaut teintait les textes neutres
    /// d'un rouge/brun parasite (`#666` → ~(106,78,78) au lieu d'un gris simplement plus sombre)
    /// — inacceptable pour du texte de navigation, jamais vérifié avant ce fix.
    func testPureGrayColorsNeverGetTintedOnlyDarkened() {
        for flavor in [MapColorFlavor.hauteContraste, .terreux] {
            let transformed = ColorFlavorPatcher.transformedColorString("#666666", flavor: flavor)!
            let reparsed = ColorFlavorPatcher.parseColor(transformed)!
            XCTAssertEqual(reparsed.s, 0, accuracy: 0.001, "\(flavor) : un gris pur doit rester un gris pur, jamais teinté")
        }
    }

    /// Cœur du 2e retour terrain (it22bis) : vérifie que les couleurs RÉELLES et DOMINANTES du
    /// style embarqué (celles qui couvrent le plus de surface visible à l'écran, pas une
    /// couleur de test arbitraire) produisent désormais un delta RGB clairement perceptible —
    /// pas seulement "non-nul", comme le fix it22 le garantissait déjà sans être suffisant.
    ///
    /// Comparaison faite en RGB (converti depuis HSL), pas en somme brute des composantes HSL —
    /// cette dernière SOUS-ESTIME l'effet perçu d'un simple décalage de luminosité sur une
    /// couleur DÉJÀ pleinement saturée (ex. l'eau, `s = 1.0` : aucune marge de saturation
    /// restante à gagner, tout l'effet visible vient de la luminosité, largement perceptible en
    /// RGB malgré un delta HSL en apparence faible).
    func testRealDominantStyleColorsProduceAPerceptibleDeltaUnderBothFlavors() {
        // Couleurs extraites directement de GPXlibre/Resources/vector-style-liberty.json —
        // background/park/landcover_wood/water/building, les calques qui dominent la surface
        // visible (voir simulation faite avant ce fix).
        let dominantColors = ["#f8f4f0", "#d8e8c8", "hsla(98,61%,72%,0.7)", "rgb(158,189,255)", "hsl(35,8%,85%)"]
        for raw in dominantColors {
            let standard = ColorFlavorPatcher.parseColor(raw)!
            let standardRGB = Self.hslToRGB(standard)
            for flavor in [MapColorFlavor.hauteContraste, .terreux] {
                let transformed = ColorFlavorPatcher.parseColor(ColorFlavorPatcher.transformedColorString(raw, flavor: flavor)!)!
                let transformedRGB = Self.hslToRGB(transformed)
                let rgbDelta = abs(transformedRGB.r - standardRGB.r) + abs(transformedRGB.g - standardRGB.g) + abs(transformedRGB.b - standardRGB.b)
                XCTAssertGreaterThan(rgbDelta, 30, "\(flavor) sur \(raw) : delta RGB trop faible (\(rgbDelta)/765), resterait imperceptible à l'écran")
            }
        }
    }

    /// Conversion HSL → RGB (0-255), utilisée UNIQUEMENT par les tests pour juger de l'effet
    /// perceptible réel d'une transformation — `ColorFlavorPatcher` lui-même n'a jamais besoin
    /// de repasser par le RGB (il émet directement `hsla(...)`, que MapLibre consomme tel quel).
    private static func hslToRGB(_ hsl: (h: Double, s: Double, l: Double, a: Double)) -> (r: Double, g: Double, b: Double) {
        guard hsl.s > 0 else {
            let v = hsl.l * 255
            return (v, v, v)
        }
        let c = (1 - abs(2 * hsl.l - 1)) * hsl.s
        let x = c * (1 - abs((hsl.h / 60).truncatingRemainder(dividingBy: 2) - 1))
        let m = hsl.l - c / 2
        let (r1, g1, b1): (Double, Double, Double)
        switch hsl.h {
        case 0..<60: (r1, g1, b1) = (c, x, 0)
        case 60..<120: (r1, g1, b1) = (x, c, 0)
        case 120..<180: (r1, g1, b1) = (0, c, x)
        case 180..<240: (r1, g1, b1) = (0, x, c)
        case 240..<300: (r1, g1, b1) = (x, 0, c)
        default: (r1, g1, b1) = (c, 0, x)
        }
        return ((r1 + m) * 255, (g1 + m) * 255, (b1 + m) * 255)
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
