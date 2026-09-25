import Foundation
import CoreGraphics
import AppKit

// MARK: - Element

package struct PanelElement: Codable, Hashable, Identifiable {
    package var id = UUID()
    package var kind: ElementKind
    package var name: String = ""
    package var isHidden: Bool? = nil            // optional so old documents decode cleanly
    package var groupID: UUID? = nil             // elements sharing a groupID act as one
    package var x: CGFloat = 0, y: CGFloat = 0, w: CGFloat = 30, h: CGFloat = 30
    package var rotation: CGFloat = 0            // degrees clockwise
    package var fill: ColorSpec = .lcars("Orange")
    /// Theme facility: when true, this element ignores its own `fill` and
    /// draws in the document's active ink colour instead (`PanelDocument.
    /// ink(for:)`) -- e.g. a text label that should read white on a dark
    /// panel and black on a light one. `fill` is left untouched either way,
    /// so turning this off (or opening the document somewhere theme-unaware)
    /// falls straight back to whatever colour was last set explicitly.
    package var followsInk: Bool = false
    /// The other half of the theme facility: draws in the document's active
    /// *paper* colour (`PanelDocument.paper(for:)`) instead of ink. For a
    /// shape whose job is to blend into the panel background rather than
    /// read as foreground content -- e.g. a small patch that obscures part
    /// of a delineation box's boundary line -- not the same thing as
    /// `followsInk` with the roles swapped: ink and paper are deliberately
    /// near-opposites of each other (that contrast is the whole point of
    /// ink), so following ink on a background-matching shape makes it stand
    /// out instead of disappear. `fill` is left untouched either way, same
    /// as `followsInk`.
    package var followsPaper: Bool = false
    package var stroke: ColorSpec? = nil         // outline (shapes only); nil = none
    package var strokeWidth: CGFloat = 1.5
    package var params = ElementParams()

    // Component binding — what this element becomes in generated widget code.
    // Defaults to .decoration so documents written before this existed keep
    // exporting exactly as they always did.
    package var role: ComponentRole = .decoration
    /// Identifier stem, e.g. "CUTOFF" → CUTOFF_PARAM. Empty means "derive it".
    package var enumName: String = ""
    package var widgetSource: WidgetSource = .stock
    /// Rack ComponentLibrary type when `widgetSource == .stock`.
    package var stockWidget: String = ""
    /// Struct name to generate when `widgetSource == .custom`, e.g. LcarsKnob.
    package var customWidgetName: String = ""
    /// For a composed widget: this part turns with the parameter, so it lands
    /// in the `-fg` file that Rack rotates. Everything else is background.
    /// Only knobs rotate; for other widget types the split is not used yet.
    package var rotatesWithValue: Bool = false
    /// Set on a text element made by "Label Selection…": the component it
    /// annotates. Re-running the command replaces its own labels rather than
    /// stacking a second copy on the first — invisible on canvas, doubled in
    /// the export.
    package var labelOwner: UUID? = nil
    /// SVG path data for a `.path` element, normalised into a 0…1 box so the
    /// frame drives its size. Optional so every document written before the
    /// importer existed decodes unchanged.
    package var pathData: String? = nil
    /// Imported tracing template: drawn faintly, never exported, and not
    /// selectable by clicking through it. Draw over it, then delete it.
    package var isTemplate: Bool? = nil

    package var frame: CGRect {
        get { CGRect(x: x, y: y, width: w, height: h) }
        set { x = newValue.origin.x; y = newValue.origin.y
              w = newValue.size.width; h = newValue.size.height }
    }
    package var center: CGPoint { CGPoint(x: x + w / 2, y: y + h / 2) }

    /// Centre in millimetres — the unit both `mm2px()` and MetaModule's
    /// `x_mm`/`y_mm` are expressed in, so one table serves both targets.
    package var centerMM: CGPoint {
        CGPoint(x: PanelMetrics.mm(center.x), y: PanelMetrics.mm(center.y))
    }

    /// Widget type to instantiate: the custom struct name when there is one,
    /// otherwise the chosen Rack type.
    package var widgetClass: String {
        widgetSource == .custom
            ? (customWidgetName.isEmpty ? "SvgKnob" : customWidgetName)
            : stockWidget
    }

    /// `enumName` if set, otherwise something usable derived from the layer
    /// name — uppercased, non-alphanumerics collapsed to underscores.
    package var identifierStem: String {
        var raw = enumName.isEmpty ? name : enumName
        // An untouched layer name is the kind's display name — good in the
        // palette, useless in an enum.
        if enumName.isEmpty && name == kind.displayName { raw = kind.shortIdentifier }
        let mapped = raw.uppercased().map { ch -> Character in
            ch.isLetter || ch.isNumber ? ch : "_"
        }
        var s = String(mapped)
        while s.contains("__") { s = s.replacingOccurrences(of: "__", with: "_") }
        s = s.trimmingCharacters(in: CharacterSet(charactersIn: "_"))
        if let first = s.first, first.isNumber { s = "_" + s }
        return s.isEmpty ? "UNNAMED" : s
    }

    /// Apply a palette preset. The palette carries these as a suffix on the
    /// pasteboard (`kind#preset`), which is how one element kind appears as
    /// several entries without multiplying ElementKind — and the same hook the
    /// symbol grid already used.
    package mutating func applyPreset(_ id: String) {
        switch kind {
        case .symbol:
            applySymbol(id)
        case .knobLarge, .knobMedium, .knobSmall:
            switch id {
            case "ring":  params.knobStyle = 2
            case "plain": params.knobStyle = 0
            default: break
            }
        case .box:
            // Real values, not guesses: SpaceTime's own panel SVGs (e.g.
            // ~/Development/SpaceTime/vcv/res/Program.svg) draw their group
            // boxes as `fill="none" stroke="#50463c" stroke-width="0.3"
            // rx="1.8"` (all mm) -- that is the Kurkesmurfer-thin values
            // below, verbatim. Serge's hardware boxes read roughly twice as
            // thick per Peet; the colour/corner radius are carried over
            // unconfirmed for Serge since only the thickness ratio was
            // given.
            let brownBlack = ColorSpec(r: Double(0x50) / 255, g: Double(0x46) / 255, b: Double(0x3C) / 255)
            let cornerMM: CGFloat = 1.8
            let cornerPx = cornerMM / PanelMetrics.mmPerPixel
            func setCorners(_ r: CGFloat) {
                params.cornerTL = r; params.cornerTR = r
                params.cornerBR = r; params.cornerBL = r
            }
            switch id {
            case "delineationKM":
                fill = ColorSpec(r: 0, g: 0, b: 0, a: 0)
                stroke = { var c = brownBlack; c.a = 0.5; return c }()
                strokeWidth = 0.3 / PanelMetrics.mmPerPixel
                setCorners(cornerPx)
            case "delineationSerge":
                fill = ColorSpec(r: 0, g: 0, b: 0, a: 0)
                stroke = brownBlack
                strokeWidth = 0.6 / PanelMetrics.mmPerPixel
                setCorners(cornerPx)
            case "bracketSerge":
                // A starting template for the GTO-style channel bracket --
                // a tall box with a demo notch on its right edge, sized to
                // wrap around a neighbouring box. Every number here is a
                // reasonable starting point, not a rule; drag the notch
                // sliders in the Inspector to fit the actual neighbour.
                w = 60; h = 110
                fill = ColorSpec(r: 0, g: 0, b: 0, a: 0)
                stroke = brownBlack
                strokeWidth = 0.6 / PanelMetrics.mmPerPixel
                setCorners(cornerPx)
                params.notchEdge = 2   // right
                params.notchStart = h * 0.4
                params.notchLength = h * 0.2
                params.notchDepth = w * 0.25
                params.notchRadius = cornerPx
            case "bracketSergeInverted":
                // The other direction: a bite taken OUT of this box so a
                // bigger neighbour can overlap into what would otherwise be
                // this box's own territory, rather than this box reaching
                // out to wrap a smaller one.
                w = 90; h = 110
                fill = ColorSpec(r: 0, g: 0, b: 0, a: 0)
                stroke = brownBlack
                strokeWidth = 0.6 / PanelMetrics.mmPerPixel
                setCorners(cornerPx)
                params.notchEdge = 2   // right
                params.notchStart = h * 0.4
                params.notchLength = h * 0.2
                params.notchDepth = w * 0.3
                params.notchRadius = cornerPx
                params.notchInvert = true
            default: break
            }
        case .line:
            switch id {
            case "connectorSerge":
                // Serge's own convention: a thin, gently bowed line tying a
                // knob to the jack it belongs to (e.g. GTO's CYCLE knob to
                // its IN jack) -- same stroke weight as the Serge
                // delineation box, since both read as the hardware's own
                // line work rather than a UI accent.
                let brownBlack = ColorSpec(r: Double(0x50) / 255, g: Double(0x46) / 255, b: Double(0x3C) / 255)
                w = 26; h = 56
                stroke = brownBlack
                strokeWidth = 0.6 / PanelMetrics.mmPerPixel
                params.lineBow = 10
            default: break
            }
        default:
            break
        }
    }

    /// Switch this element to a symbol, taking that symbol's own defaults for
    /// the four parameter slots — otherwise a pulse's width would survive as
    /// an ADSR's attack.
    package mutating func applySymbol(_ id: String) {
        let spec = SymbolCatalogue.spec(id)
        params.symbol = spec.id
        params.symbolA = spec.defaults[0]
        params.symbolB = spec.defaults[1]
        params.symbolC = spec.defaults[2]
        params.symbolD = spec.defaults[3]
    }

    package func contains(globalPoint p: CGPoint) -> Bool {
        frame.contains(Geo.rotate(p, around: center, degrees: -rotation))
    }
}

// MARK: - Tolerant decoding (see Decoding.swift)
//
// Kept beside the type: the synthesised CodingKeys are only visible in the
// file that declares it.

extension PanelElement {
    package init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        // `kind` stays strict: there is no sane default, and guessing one would
        // quietly turn an element the reader does not understand into a box.
        let decodedKind = try c.decode(ElementKind.self, forKey: .kind)
        self.init(kind: decodedKind)
        id          = try c.decodeOr(.id, id)
        name        = try c.decodeOr(.name, name)
        isHidden    = try c.decodeIfPresent(Bool.self, forKey: .isHidden)
        groupID     = try c.decodeIfPresent(UUID.self, forKey: .groupID)
        x           = try c.decodeOr(.x, x)
        y           = try c.decodeOr(.y, y)
        w           = try c.decodeOr(.w, w)
        h           = try c.decodeOr(.h, h)
        rotation    = try c.decodeOr(.rotation, rotation)
        fill        = try c.decodeOr(.fill, fill)
        followsInk  = try c.decodeOr(.followsInk, followsInk)
        followsPaper = try c.decodeOr(.followsPaper, followsPaper)
        stroke      = try c.decodeIfPresent(ColorSpec.self, forKey: .stroke)
        strokeWidth = try c.decodeOr(.strokeWidth, strokeWidth)
        params      = try c.decodeOr(.params, params)
        role             = try c.decodeOr(.role, role)
        enumName         = try c.decodeOr(.enumName, enumName)
        widgetSource     = try c.decodeOr(.widgetSource, widgetSource)
        stockWidget      = try c.decodeOr(.stockWidget, stockWidget)
        customWidgetName = try c.decodeOr(.customWidgetName, customWidgetName)
        rotatesWithValue = try c.decodeOr(.rotatesWithValue, rotatesWithValue)
        labelOwner       = try c.decodeIfPresent(UUID.self, forKey: .labelOwner)
        pathData         = try c.decodeIfPresent(String.self, forKey: .pathData)
        isTemplate       = try c.decodeIfPresent(Bool.self, forKey: .isTemplate)
    }
}
