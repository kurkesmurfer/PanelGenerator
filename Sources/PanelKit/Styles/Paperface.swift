import Foundation
import CoreGraphics

/// Paperface (after the 1970s Serge paper-faced panels, as reissued for the
/// 50th anniversary): an ivory face divided into a one-inch grid of square
/// cells, outlined in thin grey. A cell's outline says what its control does —
/// a dome over an attenuator, a gabled roof over a plain pot, a split diamond
/// round an output, a V funnelling into an input — so the graphics are a
/// small vocabulary of cell shapes rather than free drawing. Hardware is
/// solid-colour banana jacks coded by signal, black scalloped knobs with a
/// white line, and ring-lens lamps.
///
/// Measured on the Helios / Paris Flash / Tempo di Roma reference renders
/// (2914 px across 84 HP, 4U): cell pitch 171 px = 25.4 mm. Every size below
/// is that measurement scaled to Rack's 3U, a factor 128.5 / 177 = 0.726, so a
/// cell is 18.44 mm.
package enum Paperface {

    // MARK: - Measurements (3U)

    package static let scale3U: CGFloat = 128.5 / 177.0
    package static let cellMM: CGFloat = 25.4 * scale3U            // 18.44
    package static var cellPx: CGFloat { cellMM / PanelMetrics.mmPerPixel }
    /// Line work: 3 px of 2914 → 0.45 mm on the 4U face.
    package static let lineWidthMM: CGFloat = 0.45 * scale3U
    /// Top of the cell grid, below the section titles (82 of 1198 px).
    package static let gridTopMM: CGFloat = 128.5 * 82 / 1198

    // Fractions of a cell, from the renders.
    static let jackDia: CGFloat = 0.43
    static let knobDia: CGFloat = 0.47
    static let lampDia: CGFloat = 0.29
    static let screwDia: CGFloat = 0.17

    // MARK: - Colours

    package static let face = ColorSpec.hex("#E9E3D8")
    package static let line = ColorSpec.hex("#797B7A")
    package static let ink  = ColorSpec.hex("#222322")

    package static let colours = SwatchGroup(title: "Paperface", swatches: [
        Swatch("PF Face",        face),
        Swatch("PF Line",        line),
        Swatch("PF Ink",         ink),
        Swatch("PF Jack White",  .hex("#FFFFFF")),
        Swatch("PF Jack Black",  .hex("#1E1E1E")),
        Swatch("PF Jack Red",    .hex("#AD2B2B")),
        Swatch("PF Jack Purple", .hex("#8569A6")),
        Swatch("PF Jack Grey",   .hex("#A3A39F")),
        Swatch("PF Lamp",        .hex("#EDB44F")),
        Swatch("PF Knob",        .hex("#1D1E1C")),
    ])

    // MARK: - Cell shapes, in a unit box (scaled to the element's frame)

    /// Chord 1, sagitta `s`: the radius of the dome's arc in unit space.
    private static func arcRadius(_ s: CGFloat) -> CGFloat { (0.25 + s * s) / (2 * s) }

    package static let shapes: [String: String] = {
        let s: CGFloat = 0.28
        let r = String(format: "%.4f", arcRadius(s))
        return [
            "pfCell":       "M0 0H1V1H0Z",
            // Attenuator: arched top with a centre tick for the knob's zero.
            "pfDome":       "M0 1V\(s)A\(r) \(r) 0 0 1 1 \(s)V1Z M0.5 0V0.11",
            // Plain (unipolar) pot: a gable.
            "pfRoof":       "M0 1V0.3L0.5 0L1 0.3V1Z",
            // An input fed from above: two lines from the top corners to the jack.
            "pfFunnel":     "M0 0L0.5 1M1 0L0.5 1",
            // Output: half-diamonds either side of a two-line spine.
            "pfDiamond":    "M0.39 0V1M0.61 0V1M0.39 0L0 0.5L0.39 1M0.61 0L1 0.5L0.61 1",
            // Attenuverter scale under a dome: − … +.
            "pfScale":      "M0 0H1V1H0ZM0.07 0.5H0.13M0.86 0.5H0.93M0.895 0.3V0.7",
            // Name strip under a knob (FREQ, WINDOW).
            "pfLabelStrip": "M0 0H1V1H0Z",
            // Signal-flow arrow, outlined (IN ⇨ BAL. OUT).
            "pfArrow":      "M0 0.3H0.6V0H0.62L1 0.5L0.62 1H0.6V0.7H0Z",
        ]
    }()

    /// Default frame of each cell shape, in cells.
    static let shapeSize: [String: CGSize] = [
        "pfCell": CGSize(width: 1, height: 1),
        "pfDome": CGSize(width: 1, height: 0.63),
        "pfRoof": CGSize(width: 1, height: 0.96),
        "pfFunnel": CGSize(width: 1, height: 0.42),
        "pfDiamond": CGSize(width: 0.96, height: 1.05),
        "pfScale": CGSize(width: 1, height: 0.17),
        "pfLabelStrip": CGSize(width: 1, height: 0.2),
        "pfArrow": CGSize(width: 0.16, height: 0.09),
    ]

    // MARK: - Palette

    package static let palette: [PaletteSection] = [
        PaletteSection(title: "Paperface · Hardware", entries: [
            PaletteEntry(.jack, "pfJackWhite", "Banana · White (CV 0–5 V)"),
            PaletteEntry(.jack, "pfJackBlack", "Banana · Black (audio, ±)"),
            PaletteEntry(.jack, "pfJackRed", "Banana · Red (trigger / logic)"),
            PaletteEntry(.jack, "pfJackPurple", "Banana · Purple (sync)"),
            PaletteEntry(.jack, "pfJackGrey", "Banana · Grey (special)"),
            PaletteEntry(.knobMedium, "pfKnob", "Scalloped Knob"),
            PaletteEntry(.led, "pfLamp", "Lamp"),
            PaletteEntry(.screw, "pfScrew", "Screw"),
        ]),
        PaletteSection(title: "Paperface · Cells", entries: [
            PaletteEntry(.path, "pfCell", "Cell"),
            PaletteEntry(.path, "pfDome", "Dome (attenuator)"),
            PaletteEntry(.path, "pfRoof", "Roof (pot)"),
            PaletteEntry(.path, "pfScale", "Scale − +"),
            PaletteEntry(.path, "pfLabelStrip", "Label Strip"),
            PaletteEntry(.path, "pfFunnel", "Funnel (input)"),
            PaletteEntry(.path, "pfDiamond", "Diamond (output)"),
            PaletteEntry(.path, "pfArrow", "Arrow"),
            PaletteEntry(.line, "pfConnector", "Connector"),
        ]),
        PaletteSection(title: "Paperface · Glyphs & Text", entries: [
            PaletteEntry(.symbol, "pfSine", "Sine"),
            PaletteEntry(.symbol, "pfSaw", "Saw"),
            PaletteEntry(.symbol, "pfSquare", "Square"),
            PaletteEntry(.symbol, "pfPulse", "Pulse"),
            PaletteEntry(.text, "pfLabel", "Label"),
            PaletteEntry(.text, "pfTitle", "Section Title"),
        ]),
    ]

    // MARK: - Presets

    static func applyPreset(_ id: String, to e: inout PanelElement) -> Bool {
        let cell = cellPx
        let stroke = lineWidthMM / PanelMetrics.mmPerPixel
        func size(_ d: CGFloat) { e.w = cell * d; e.h = cell * d }
        func jack(_ hex: String) { size(jackDia); e.fill = .hex(hex); e.params.jackStyle = 1 }

        switch (e.kind, id) {
        case (.jack, "pfJackWhite"):  jack("#FFFFFF")
        case (.jack, "pfJackBlack"):  jack("#1E1E1E")
        case (.jack, "pfJackRed"):    jack("#AD2B2B")
        case (.jack, "pfJackPurple"): jack("#8569A6")
        case (.jack, "pfJackGrey"):   jack("#A3A39F")
        case (_, "pfKnob") where e.kind.isKnob:
            size(knobDia); e.fill = .hex("#1D1E1C"); e.params.knobStyle = 3
        case (.led, "pfLamp"):
            size(lampDia); e.fill = .hex("#EDB44F"); e.params.ledStyle = 1
        case (.screw, "pfScrew"):
            size(screwDia); e.fill = .hex("#595C56"); e.params.knobStyle = 1

        case (.path, let shape) where shapes[shape] != nil:
            let s = shapeSize[shape] ?? CGSize(width: 1, height: 1)
            e.w = cell * s.width; e.h = cell * s.height
            e.pathData = shapes[shape]
            e.fill = ColorSpec(r: 0, g: 0, b: 0, a: 0)
            e.stroke = shape == "pfArrow" ? ink : line
            e.strokeWidth = stroke
            e.name = "Paperface · " + shape.dropFirst(2)

        case (.line, "pfConnector"):
            e.w = 4; e.h = cell * 0.5
            e.stroke = line; e.strokeWidth = stroke
            e.params.lineBow = 0

        case (.symbol, "pfSine"), (.symbol, "pfSaw"), (.symbol, "pfSquare"), (.symbol, "pfPulse"):
            let map = ["pfSine": "sine", "pfSaw": "sawUp", "pfSquare": "square", "pfPulse": "pulse"]
            e.applySymbol(map[id]!)
            e.w = cell * 0.26; e.h = cell * 0.17
            e.fill = ink
            e.params.weight = 0.12

        case (.text, "pfLabel"), (.text, "pfTitle"):
            let title = id == "pfTitle"
            e.params.text = title ? "SECTION" : "LABEL"
            e.params.fontName = "Futura-Medium"
            e.params.bold = false
            e.params.fontSize = title ? 8.4 : 7
            e.params.tracking = title ? 0.6 : 0.3
            e.fill = ink
            let s = Renderer.textSize(for: e)
            e.w = s.width; e.h = s.height

        default:
            return false
        }
        return true
    }

    package static let language = DesignLanguage(
        id: "paperface", name: "Paperface",
        swatchGroups: [colours],
        paletteSections: palette,
        applyPreset: applyPreset)
}
