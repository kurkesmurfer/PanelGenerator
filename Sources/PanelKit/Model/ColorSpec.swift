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
}
