import Foundation

/// Applique un `MapColorFlavor` à un style vectoriel MapLibre déjà chargé en `[String: Any]`
/// (spec "map-color-flavors", it19) — parcourt récursivement UNIQUEMENT la clé `paint` de
/// chaque calque (jamais `layout`, où vit `symbol-placement`/`rotation-alignment` : contrainte
/// non négociable du prompt, "ne pas toucher au code de rotation, seulement aux palettes de
/// couleurs"). Une valeur de paint peut être une simple chaîne couleur OU une expression
/// (`interpolate`/`step`/`match`/`case`, tableaux imbriqués à profondeur arbitraire) — le
/// parcours est générique (String/Array/Dictionary) plutôt que ciblé propriété par propriété,
/// donc robuste à n'importe quelle forme d'expression déjà présente dans le style embarqué.
enum ColorFlavorPatcher {
    /// Point d'entrée : transforme la clé `paint` de chaque calque. `layers` = valeur brute
    /// `style["layers"]` désérialisée en `[[String: Any]]`.
    static func apply(_ flavor: MapColorFlavor, toLayers layers: [[String: Any]]) -> [[String: Any]] {
        guard !flavor.isIdentity else { return layers }
        return layers.map { layer -> [String: Any] in
            guard let paint = layer["paint"] else { return layer }
            var patched = layer
            patched["paint"] = transform(paint, flavor: flavor)
            return patched
        }
    }

    private static func transform(_ value: Any, flavor: MapColorFlavor) -> Any {
        if let string = value as? String {
            return transformedColorString(string, flavor: flavor) ?? string
        }
        if let array = value as? [Any] {
            return array.map { transform($0, flavor: flavor) }
        }
        if let dict = value as? [String: Any] {
            return dict.mapValues { transform($0, flavor: flavor) }
        }
        return value
    }

    /// `internal` pour la testabilité directe (même patron que
    /// `MapEngineConstants.patchedSymbolLayerForCapUp`). Retourne `nil` si `string` n'est pas
    /// reconnu comme une couleur (ex. un nom de police, une clé d'expression comme
    /// "interpolate"/"zoom", un nom de source d'icône) — l'appelant garde alors la valeur telle
    /// quelle, jamais une modification à l'aveugle.
    static func transformedColorString(_ string: String, flavor: MapColorFlavor) -> String? {
        guard let color = parseColor(string) else { return nil }
        var hue = (color.h + flavor.hueShiftDegrees).truncatingRemainder(dividingBy: 360)
        if hue < 0 { hue += 360 }
        // Fix "flavor-parameters-imperceptible" (it19-bis) : terme ADDITIF après le
        // multiplicateur — un multiplicateur seul n'a aucun effet visible sur une couleur déjà
        // proche du gris/neutre (majorité de la surface d'un fond de carte clair), voir
        // MapColorFlavor.saturationBoost.
        let saturation = min(max(color.s * flavor.saturationMultiplier + flavor.saturationBoost, 0), 1)
        let contrasted = 0.5 + (color.l - 0.5) * flavor.contrastFactor
        let lightness = min(max(contrasted + flavor.lightnessDelta, 0), 1)
        return "hsla(\(formatted(hue)), \(formatted(saturation * 100))%, \(formatted(lightness * 100))%, \(formatted(color.a, decimals: 3)))"
    }

    private static func formatted(_ value: Double, decimals: Int = 1) -> String {
        String(format: "%.\(decimals)f", value)
    }

    // MARK: - Parsing (hex #rgb/#rrggbb, rgb()/rgba(), hsl()/hsla()) → (h, s, l, a)

    static func parseColor(_ raw: String) -> (h: Double, s: Double, l: Double, a: Double)? {
        let value = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if value.hasPrefix("#") {
            return parseHex(value)
        }
        if value.hasPrefix("hsla(") || value.hasPrefix("hsl(") {
            return parseHSLFunction(value)
        }
        if value.hasPrefix("rgba(") || value.hasPrefix("rgb(") {
            return parseRGBFunction(value).map(rgbToHSL)
        }
        return nil
    }

    private static func parseHex(_ value: String) -> (h: Double, s: Double, l: Double, a: Double)? {
        var hex = String(value.dropFirst())
        guard !hex.isEmpty, hex.allSatisfy(\.isHexDigit) else { return nil }
        if hex.count == 3 {
            hex = hex.map { "\($0)\($0)" }.joined()
        }
        guard hex.count == 6, let intValue = UInt32(hex, radix: 16) else { return nil }
        let r = Double((intValue >> 16) & 0xFF) / 255
        let g = Double((intValue >> 8) & 0xFF) / 255
        let b = Double(intValue & 0xFF) / 255
        return rgbToHSL((r, g, b, 1))
    }

    private static func innerParenContent(_ value: String) -> [String]? {
        guard let open = value.firstIndex(of: "("), let close = value.lastIndex(of: ")"), open < close else { return nil }
        return value[value.index(after: open)..<close].split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }
    }

    private static func parseHSLFunction(_ value: String) -> (h: Double, s: Double, l: Double, a: Double)? {
        guard let parts = innerParenContent(value), parts.count >= 3,
              let h = Double(parts[0]),
              let sPercent = Double(parts[1].replacingOccurrences(of: "%", with: "")),
              let lPercent = Double(parts[2].replacingOccurrences(of: "%", with: ""))
        else { return nil }
        let a = parts.count >= 4 ? (Double(parts[3]) ?? 1) : 1
        return (h, sPercent / 100, lPercent / 100, a)
    }

    private static func parseRGBFunction(_ value: String) -> (r: Double, g: Double, b: Double, a: Double)? {
        guard let parts = innerParenContent(value), parts.count >= 3,
              let r = Double(parts[0]), let g = Double(parts[1]), let b = Double(parts[2])
        else { return nil }
        let a = parts.count >= 4 ? (Double(parts[3]) ?? 1) : 1
        return (r / 255, g / 255, b / 255, a)
    }

    private static func rgbToHSL(_ rgb: (r: Double, g: Double, b: Double, a: Double)) -> (h: Double, s: Double, l: Double, a: Double) {
        let maxc = max(rgb.r, rgb.g, rgb.b)
        let minc = min(rgb.r, rgb.g, rgb.b)
        let l = (maxc + minc) / 2
        guard maxc != minc else { return (0, 0, l, rgb.a) }
        let d = maxc - minc
        let s = l > 0.5 ? d / (2 - maxc - minc) : d / (maxc + minc)
        var h: Double
        if maxc == rgb.r {
            h = (rgb.g - rgb.b) / d + (rgb.g < rgb.b ? 6 : 0)
        } else if maxc == rgb.g {
            h = (rgb.b - rgb.r) / d + 2
        } else {
            h = (rgb.r - rgb.g) / d + 4
        }
        return (h * 60, s, l, rgb.a)
    }
}
