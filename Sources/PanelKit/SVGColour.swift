import Foundation
import CoreGraphics

// MARK: - Colours

package enum SVGColour {

    /// A CSS colour as SVG files write it: #rgb, #rgba, #rrggbb, #rrggbbaa,
    /// rgb()/rgba() with numbers or percentages, hsl()/hsla(), or one of the
    /// 147 CSS named colours. nil for anything else, so the caller can warn
    /// rather than guess.
    package static func parse(_ text: String) -> ColorSpec? {
        let v = text.trimmingCharacters(in: .whitespaces).lowercased()
        if v.hasPrefix("#") {
            let hex = Array(v.dropFirst())
            guard hex.allSatisfy({ $0.isHexDigit }) else { return nil }
            func byte(_ s: [Character]) -> Double { Double(Int(String(s), radix: 16) ?? 0) / 255 }
            switch hex.count {
            case 3, 4:
                let d = hex.map { [$0, $0] }
                return ColorSpec(r: byte(d[0]), g: byte(d[1]), b: byte(d[2]),
                                 a: hex.count == 4 ? byte(d[3]) : 1)
            case 6, 8:
                let c = ColorSpec.hex("#" + String(hex[0..<6]))
                if hex.count == 6 { return c }
                return ColorSpec(r: c.r, g: c.g, b: c.b, a: byte(Array(hex[6..<8])))
            default:
                return nil
            }
        }
        if v.hasPrefix("rgb") || v.hasPrefix("hsl") {
            guard let open = v.firstIndex(of: "("), let close = v.lastIndex(of: ")") else { return nil }
            let parts = v[v.index(after: open)..<close]
                .replacingOccurrences(of: "/", with: " ")
                .split(whereSeparator: { $0 == "," || $0 == " " })
                .map(String.init)
            guard parts.count >= 3 else { return nil }
            func value(_ s: String, scale: Double) -> Double? {
                if s.hasSuffix("%") { return Double(s.dropLast()).map { $0 / 100 } }
                return Double(s).map { $0 / scale }
            }
            let alpha = parts.count > 3 ? (value(parts[3], scale: 1) ?? 1) : 1
            if v.hasPrefix("rgb") {
                guard let r = value(parts[0], scale: 255), let g = value(parts[1], scale: 255),
                      let b = value(parts[2], scale: 255) else { return nil }
                return ColorSpec(r: clamp(r), g: clamp(g), b: clamp(b), a: clamp(alpha))
            }
            guard let h = Double(parts[0].replacingOccurrences(of: "deg", with: "")),
                  let s = value(parts[1], scale: 100), let l = value(parts[2], scale: 100) else { return nil }
            let (r, g, b) = hslToRGB(h, clamp(s), clamp(l))
            return ColorSpec(r: r, g: g, b: b, a: clamp(alpha))
        }
        guard let hex = named[v] else { return nil }
        return .hex(hex)
    }

    private static func clamp(_ x: Double) -> Double { min(max(x, 0), 1) }

    private static func hslToRGB(_ h: Double, _ s: Double, _ l: Double) -> (Double, Double, Double) {
        let hue = (h.truncatingRemainder(dividingBy: 360) + 360).truncatingRemainder(dividingBy: 360) / 360
        guard s > 0 else { return (l, l, l) }
        let q = l < 0.5 ? l * (1 + s) : l + s - l * s
        let p = 2 * l - q
        func channel(_ t0: Double) -> Double {
            var t = t0
            if t < 0 { t += 1 }
            if t > 1 { t -= 1 }
            if t < 1.0 / 6 { return p + (q - p) * 6 * t }
            if t < 0.5 { return q }
            if t < 2.0 / 3 { return p + (q - p) * (2.0 / 3 - t) * 6 }
            return p
        }
        return (channel(hue + 1.0 / 3), channel(hue), channel(hue - 1.0 / 3))
    }

    /// The full CSS table. A panel exported from a browser-based tool or
    /// written by hand uses names like "darkgray" or "whitesmoke"; an unknown
    /// name used to make the shape vanish.
    private static let named: [String: String] = [
        "aliceblue": "#F0F8FF", "antiquewhite": "#FAEBD7", "aqua": "#00FFFF", "aquamarine": "#7FFFD4",
        "azure": "#F0FFFF", "beige": "#F5F5DC", "bisque": "#FFE4C4", "black": "#000000",
        "blanchedalmond": "#FFEBCD", "blue": "#0000FF", "blueviolet": "#8A2BE2", "brown": "#A52A2A",
        "burlywood": "#DEB887", "cadetblue": "#5F9EA0", "chartreuse": "#7FFF00", "chocolate": "#D2691E",
        "coral": "#FF7F50", "cornflowerblue": "#6495ED", "cornsilk": "#FFF8DC", "crimson": "#DC143C",
        "cyan": "#00FFFF", "darkblue": "#00008B", "darkcyan": "#008B8B", "darkgoldenrod": "#B8860B",
        "darkgray": "#A9A9A9", "darkgreen": "#006400", "darkgrey": "#A9A9A9", "darkkhaki": "#BDB76B",
        "darkmagenta": "#8B008B", "darkolivegreen": "#556B2F", "darkorange": "#FF8C00", "darkorchid": "#9932CC",
        "darkred": "#8B0000", "darksalmon": "#E9967A", "darkseagreen": "#8FBC8F", "darkslateblue": "#483D8B",
        "darkslategray": "#2F4F4F", "darkslategrey": "#2F4F4F", "darkturquoise": "#00CED1", "darkviolet": "#9400D3",
        "deeppink": "#FF1493", "deepskyblue": "#00BFFF", "dimgray": "#696969", "dimgrey": "#696969",
        "dodgerblue": "#1E90FF", "firebrick": "#B22222", "floralwhite": "#FFFAF0", "forestgreen": "#228B22",
        "fuchsia": "#FF00FF", "gainsboro": "#DCDCDC", "ghostwhite": "#F8F8FF", "gold": "#FFD700",
        "goldenrod": "#DAA520", "gray": "#808080", "green": "#008000", "greenyellow": "#ADFF2F",
        "grey": "#808080", "honeydew": "#F0FFF0", "hotpink": "#FF69B4", "indianred": "#CD5C5C",
        "indigo": "#4B0082", "ivory": "#FFFFF0", "khaki": "#F0E68C", "lavender": "#E6E6FA",
        "lavenderblush": "#FFF0F5", "lawngreen": "#7CFC00", "lemonchiffon": "#FFFACD", "lightblue": "#ADD8E6",
        "lightcoral": "#F08080", "lightcyan": "#E0FFFF", "lightgoldenrodyellow": "#FAFAD2", "lightgray": "#D3D3D3",
        "lightgreen": "#90EE90", "lightgrey": "#D3D3D3", "lightpink": "#FFB6C1", "lightsalmon": "#FFA07A",
        "lightseagreen": "#20B2AA", "lightskyblue": "#87CEFA", "lightslategray": "#778899", "lightslategrey": "#778899",
        "lightsteelblue": "#B0C4DE", "lightyellow": "#FFFFE0", "lime": "#00FF00", "limegreen": "#32CD32",
        "linen": "#FAF0E6", "magenta": "#FF00FF", "maroon": "#800000", "mediumaquamarine": "#66CDAA",
        "mediumblue": "#0000CD", "mediumorchid": "#BA55D3", "mediumpurple": "#9370DB", "mediumseagreen": "#3CB371",
        "mediumslateblue": "#7B68EE", "mediumspringgreen": "#00FA9A", "mediumturquoise": "#48D1CC", "mediumvioletred": "#C71585",
        "midnightblue": "#191970", "mintcream": "#F5FFFA", "mistyrose": "#FFE4E1", "moccasin": "#FFE4B5",
        "navajowhite": "#FFDEAD", "navy": "#000080", "oldlace": "#FDF5E6", "olive": "#808000",
        "olivedrab": "#6B8E23", "orange": "#FFA500", "orangered": "#FF4500", "orchid": "#DA70D6",
        "palegoldenrod": "#EEE8AA", "palegreen": "#98FB98", "paleturquoise": "#AFEEEE", "palevioletred": "#DB7093",
        "papayawhip": "#FFEFD5", "peachpuff": "#FFDAB9", "peru": "#CD853F", "pink": "#FFC0CB",
        "plum": "#DDA0DD", "powderblue": "#B0E0E6", "purple": "#800080", "rebeccapurple": "#663399",
        "red": "#FF0000", "rosybrown": "#BC8F8F", "royalblue": "#4169E1", "saddlebrown": "#8B4513",
        "salmon": "#FA8072", "sandybrown": "#F4A460", "seagreen": "#2E8B57", "seashell": "#FFF5EE",
        "sienna": "#A0522D", "silver": "#C0C0C0", "skyblue": "#87CEEB", "slateblue": "#6A5ACD",
        "slategray": "#708090", "slategrey": "#708090", "snow": "#FFFAFA", "springgreen": "#00FF7F",
        "steelblue": "#4682B4", "tan": "#D2B48C", "teal": "#008080", "thistle": "#D8BFD8",
        "tomato": "#FF6347", "turquoise": "#40E0D0", "violet": "#EE82EE", "wheat": "#F5DEB3",
        "white": "#FFFFFF", "whitesmoke": "#F5F5F5", "yellow": "#FFFF00", "yellowgreen": "#9ACD32",
    ]
}
