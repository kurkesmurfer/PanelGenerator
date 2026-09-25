import Foundation
import CoreGraphics

/// The Kurkesmurfer house style (www.kurkesmurfer.com), after the SpaceTime
/// plugin's panels: a warm near-black panel with thin brown-black group boxes.
package enum Kurkesmurfer {

    /// Panel background, measured from SpaceTime's own panels. Also the
    /// default background of a new document.
    package static let background: ColorSpec = .hex("#1D1713")

    /// Line work for group boxes and connectors, taken from SpaceTime's panel
    /// SVGs (`stroke="#50463c"`). Serge's hardware boxes use the same colour.
    package static let lineColor = ColorSpec(r: Double(0x50) / 255, g: Double(0x46) / 255, b: Double(0x3C) / 255)
    /// Group-box corner radius, `rx="1.8"` in SpaceTime's SVGs.
    package static let cornerRadiusMM: CGFloat = 1.8
    /// Group-box stroke, `stroke-width="0.3"` in SpaceTime's SVGs.
    package static let delineationWidthMM: CGFloat = 0.3

    package static let palette: [PaletteSection] = [
        PaletteSection(title: "Kurkesmurfer", entries: [
            PaletteEntry(.box, "delineationKM", "Delineation"),
        ]),
    ]

    static func applyPreset(_ id: String, to e: inout PanelElement) -> Bool {
        guard e.kind == .box, id == "delineationKM" else { return false }
        e.fill = ColorSpec(r: 0, g: 0, b: 0, a: 0)
        e.stroke = { var c = lineColor; c.a = 0.5; return c }()
        e.strokeWidth = delineationWidthMM / PanelMetrics.mmPerPixel
        e.setCornerRadii(cornerRadiusMM / PanelMetrics.mmPerPixel)
        return true
    }

    package static let language = DesignLanguage(
        id: "kurkesmurfer", name: "Kurkesmurfer",
        swatchGroups: [],
        paletteSections: palette,
        applyPreset: applyPreset)
}

extension PanelElement {
    /// Same radius on all four corners of a box.
    package mutating func setCornerRadii(_ r: CGFloat) {
        params.cornerTL = r; params.cornerTR = r
        params.cornerBR = r; params.cornerBL = r
    }
}
