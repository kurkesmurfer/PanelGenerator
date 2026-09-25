import Foundation
import CoreGraphics

/// Serge paperface: a standardised background and grid (see SergeGrid), all
/// parts drawn from a small set of similarly sized pieces, matte hardware
/// colours, and thin line work tying controls together.
package enum Serge {

    /// Light-panel paper. The value saved as `background` in the GTO_Light and
    /// GTS_Light documents, so every Serge light panel matches.
    package static let paper = SwatchGroup(title: "Serge paper", swatches: [
        Swatch("Serge Light BG", .hex("#E7E4DE")),
    ])

    /// Jack-ring colours: matte material colours, matched to the ring stroke a
    /// `.jack` draws in its own fill. Red, White and Black are current-day
    /// Serge; Blue, Orange and Green extend the scheme in the same muted family.
    package static let jackRings = SwatchGroup(title: "Serge jack rings", swatches: [
        Swatch("Ring Red",    .hex("#C0392B")),
        Swatch("Ring White",  .hex("#E8E6DE")),
        Swatch("Ring Black",  .hex("#303034")),
        Swatch("Ring Blue",   .hex("#2C5C8A")),
        Swatch("Ring Orange", .hex("#C46A28")),
        Swatch("Ring Green",  .hex("#3C7A4E")),
    ])

    /// Hardware line work reads about twice as heavy as Kurkesmurfer's. Colour
    /// and corner radius are Kurkesmurfer's, not yet measured on a Serge panel.
    package static let lineColor = Kurkesmurfer.lineColor
    package static let lineWidthMM: CGFloat = 0.6
    package static let cornerRadiusMM = Kurkesmurfer.cornerRadiusMM

    package static let palette: [PaletteSection] = [
        PaletteSection(title: "Serge", entries: [
            PaletteEntry(.box, "delineationSerge", "Delineation"),
            PaletteEntry(.box, "bracketSerge", "Bracket (notch demo)"),
            PaletteEntry(.box, "bracketSergeInverted", "Bracket (inverted notch demo)"),
            PaletteEntry(.line, "connectorSerge", "Connector (knob-to-jack)"),
        ]),
    ]

    static func applyPreset(_ id: String, to e: inout PanelElement) -> Bool {
        let cornerPx = cornerRadiusMM / PanelMetrics.mmPerPixel
        func outline() {
            e.fill = ColorSpec(r: 0, g: 0, b: 0, a: 0)
            e.stroke = lineColor
            e.strokeWidth = lineWidthMM / PanelMetrics.mmPerPixel
            e.setCornerRadii(cornerPx)
        }
        switch (e.kind, id) {
        case (.box, "delineationSerge"):
            outline()
        case (.box, "bracketSerge"):
            // GTO-style channel bracket: a tall box with a notch on its right
            // edge, reaching round a smaller neighbour. Starting values only;
            // the notch sliders fit it to the real neighbour.
            e.w = 60; e.h = 110
            outline()
            e.params.notchEdge = 2   // right
            e.params.notchStart = e.h * 0.4
            e.params.notchLength = e.h * 0.2
            e.params.notchDepth = e.w * 0.25
            e.params.notchRadius = cornerPx
        case (.box, "bracketSergeInverted"):
            // The other direction: a bite out of this box so a bigger
            // neighbour can overlap into it.
            e.w = 90; e.h = 110
            outline()
            e.params.notchEdge = 2   // right
            e.params.notchStart = e.h * 0.4
            e.params.notchLength = e.h * 0.2
            e.params.notchDepth = e.w * 0.3
            e.params.notchRadius = cornerPx
            e.params.notchInvert = true
        case (.line, "connectorSerge"):
            // A thin, gently bowed line tying a knob to its jack (GTO's CYCLE
            // knob to its IN jack), at the same weight as the delineation box.
            e.w = 26; e.h = 56
            e.stroke = lineColor
            e.strokeWidth = lineWidthMM / PanelMetrics.mmPerPixel
            e.params.lineBow = 10
        default:
            return false
        }
        return true
    }

    package static let language = DesignLanguage(
        id: "serge", name: "Serge",
        swatchGroups: [paper, jackRings],
        paletteSections: palette,
        applyPreset: applyPreset)
}
