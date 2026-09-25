import Foundation
import CoreGraphics
import AppKit

// MARK: - Colour

package struct ColorSpec: Codable, Hashable {
    package var r: Double
    package var g: Double
    package var b: Double
    package var a: Double

    package init(r: Double, g: Double, b: Double, a: Double = 1) {
        self.r = r; self.g = g; self.b = b; self.a = a
    }

    package static let black = ColorSpec(r: 0, g: 0, b: 0)
    package static let white = ColorSpec(r: 1, g: 1, b: 1)

    package init(color: NSColor) {
        let c = color.usingColorSpace(.sRGB) ?? NSColor.black
        r = Double(c.redComponent)
        g = Double(c.greenComponent)
        b = Double(c.blueComponent)
        a = Double(c.alphaComponent)
    }

    package var nsColor: NSColor { NSColor(srgbRed: r, green: g, blue: b, alpha: a) }

    package var hexString: String {
        String(format: "#%02X%02X%02X",
               Int((r * 255).rounded()),
               Int((g * 255).rounded()),
               Int((b * 255).rounded()))
    }

    package static func hex(_ s: String) -> ColorSpec {
        var t = s.trimmingCharacters(in: .whitespacesAndNewlines)
        if t.hasPrefix("#") { t.removeFirst() }
        guard t.count == 6, let v = UInt32(t, radix: 16) else { return ColorSpec(r: 0, g: 0, b: 0) }
        return ColorSpec(r: Double((v >> 16) & 0xFF) / 255,
                         g: Double((v >> 8) & 0xFF) / 255,
                         b: Double(v & 0xFF) / 255)
    }

    package func mixed(toward target: ColorSpec, fraction f: Double) -> ColorSpec {
        ColorSpec(r: r + (target.r - r) * f,
                  g: g + (target.g - g) * f,
                  b: b + (target.b - b) * f,
                  a: a + (target.a - a) * f)
    }

    package func darkened(_ f: Double) -> ColorSpec { mixed(toward: ColorSpec.black, fraction: f) }
    package func lightened(_ f: Double) -> ColorSpec { mixed(toward: ColorSpec.white, fraction: f) }

    // Curated LCARS / TNG palette ("Okudagram" classics).
    package static let lcarsPresets: [(String, ColorSpec)] = [
        // First in the bank on purpose (Peet's own request, 2026-09-09):
        // the shared light-panel background flavour, exactly the value
        // already saved in GTO_Light.panelgen/GTS_Light.panelgen's own
        // `background`, so every Serge light panel can pick the identical
        // colour in one click -- for a document's Theme ▸ Light bg well and
        // for any element's own Fill. Distinct from "Vanilla" below, which
        // is an unrelated bright LCARS accent (#FFFF99), not a background.
        ("Serge Light BG", .hex("#E7E4DE")),
        ("Orange",     .hex("#FF9C00")),
        ("Amber",      .hex("#FFAA33")),
        ("Gold",       .hex("#FFCC66")),
        ("Peach",      .hex("#FFCC99")),
        ("Apricot",    .hex("#FF9966")),
        ("Salmon",     .hex("#CC8F99")),
        ("Cardassian", .hex("#CC6666")),
        ("Alert Red",  .hex("#DD4444")),
        ("Lavender",   .hex("#CC99CC")),
        ("Periwinkle", .hex("#9999CC")),
        ("Sky",        .hex("#99CCFF")),
        ("Steel",      .hex("#6688AA")),
        ("Vanilla",    .hex("#FFFF99")),
        ("Ink",        .hex("#101018")),
        // Serge-style jack rings -- matte/material colours (not the glowy
        // Okudagram set above), matched to the ring stroke the .jack
        // shape already draws in its own `fill` colour. Red/White/Black
        // mirror current-day Serge; Blue/Orange/Green are Peet's own
        // extension of that scheme, picked to sit in the same muted
        // material family rather than reading as decorative accents.
        ("Ring Red",    .hex("#C0392B")),
        ("Ring White",  .hex("#E8E6DE")),
        ("Ring Black",  .hex("#303034")),
        ("Ring Blue",   .hex("#2C5C8A")),
        ("Ring Orange", .hex("#C46A28")),
        ("Ring Green",  .hex("#3C7A4E")),
        // LED lens colours -- vivid/glowing rather than matte, since
        // these represent lit indicators, not plastic jack hardware.
        ("LED White",  .hex("#F5F5F0")),
        ("LED Red",    .hex("#FF3B30")),
        ("LED Blue",   .hex("#2F80ED")),
        ("LED Yellow", .hex("#FFD400")),
        ("LED Green",  .hex("#2ECC55")),
    ]

    /// Look up a curated swatch by name, so element defaults can cite
    /// "Orange" instead of repeating "#FF9C00" -- one moves, the other
    /// follows. Falls back to the first swatch on a typo'd name rather
    /// than crashing.
    package static func lcars(_ name: String) -> ColorSpec {
        lcarsPresets.first { $0.0 == name }?.1 ?? lcarsPresets[0].1
    }
}
