import Foundation
import CoreGraphics

/// What every panel uses whatever its house style: Rack's own primitives,
/// the plain shape kit, and indicator colours.
package enum Generic {

    /// LED lens colours: vivid, because they stand for lit indicators rather
    /// than plastic hardware.
    package static let leds = SwatchGroup(title: "LEDs", swatches: [
        Swatch("LED White",  .hex("#F5F5F0")),
        Swatch("LED Red",    .hex("#FF3B30")),
        Swatch("LED Blue",   .hex("#2F80ED")),
        Swatch("LED Yellow", .hex("#FFD400")),
        Swatch("LED Green",  .hex("#2ECC55")),
    ])

    package static let palette: [PaletteSection] = [
        PaletteSection(title: "Primitives", entries: [
            PaletteEntry(.jack, nil, "Jack (3.5 mm)"),
            PaletteEntry(.knobLarge, nil, "Knob · Large"),
            PaletteEntry(.knobMedium, nil, "Knob · Medium"),
            PaletteEntry(.knobSmall, nil, "Knob · Small"),
            PaletteEntry(.faderVertical, nil, "Fader · Vertical"),
            PaletteEntry(.faderHorizontal, nil, "Fader · Horizontal"),
            PaletteEntry(.led, nil, "LED"),
            PaletteEntry(.screw, nil, "Screw"),
            PaletteEntry(.pushButton, nil, "Push Button"),
            PaletteEntry(.buttonGroup, nil, "Button Group"),
        ]),
        // The same three knobs with the position ring on. Separate entries
        // rather than a changed default: the plain ones stay what Rack draws,
        // so a panel built from them still matches its stock widgets.
        PaletteSection(title: "Knobs · Position Ring", entries: [
            PaletteEntry(.knobLarge, "ring", "Ring Knob · Large"),
            PaletteEntry(.knobMedium, "ring", "Ring Knob · Medium"),
            PaletteEntry(.knobSmall, "ring", "Ring Knob · Small"),
        ]),
        PaletteSection(title: "Shapes · Backdrop", entries: [
            PaletteEntry(.box, nil, "Box / Rounded Rect"),
            PaletteEntry(.ellipse, nil, "Ellipse"),
            PaletteEntry(.triangle, nil, "Triangle"),
            PaletteEntry(.line, nil, "Line"),
            PaletteEntry(.ringSector, nil, "Ring Sector"),
        ]),
    ]

    static func applyPreset(_ id: String, to e: inout PanelElement) -> Bool {
        guard e.kind.isKnob else { return false }
        switch id {
        case "ring":  e.params.knobStyle = 2
        case "plain": e.params.knobStyle = 0
        default: return false
        }
        return true
    }

    package static let language = DesignLanguage(
        id: "generic", name: "Generic",
        swatchGroups: [leds],
        paletteSections: palette,
        applyPreset: applyPreset)
}
