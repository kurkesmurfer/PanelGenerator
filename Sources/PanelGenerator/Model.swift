import Foundation
import CoreGraphics
import AppKit

// MARK: - Panel format

enum PanelFormat: String, Codable, CaseIterable {
    case u1 = "1U"
    case u3 = "3U"
}

// MARK: - Colour

struct ColorSpec: Codable, Hashable {
    var r: Double
    var g: Double
    var b: Double
    var a: Double

    init(r: Double, g: Double, b: Double, a: Double = 1) {
        self.r = r; self.g = g; self.b = b; self.a = a
    }

    static let black = ColorSpec(r: 0, g: 0, b: 0)
    static let white = ColorSpec(r: 1, g: 1, b: 1)

    init(color: NSColor) {
        let c = color.usingColorSpace(.sRGB) ?? NSColor.black
        r = Double(c.redComponent)
        g = Double(c.greenComponent)
        b = Double(c.blueComponent)
        a = Double(c.alphaComponent)
    }

    var nsColor: NSColor { NSColor(srgbRed: r, green: g, blue: b, alpha: a) }

    var hexString: String {
        String(format: "#%02X%02X%02X",
               Int((r * 255).rounded()),
               Int((g * 255).rounded()),
               Int((b * 255).rounded()))
    }

    static func hex(_ s: String) -> ColorSpec {
        var t = s.trimmingCharacters(in: .whitespacesAndNewlines)
        if t.hasPrefix("#") { t.removeFirst() }
        guard t.count == 6, let v = UInt32(t, radix: 16) else { return ColorSpec(r: 0, g: 0, b: 0) }
        return ColorSpec(r: Double((v >> 16) & 0xFF) / 255,
                         g: Double((v >> 8) & 0xFF) / 255,
                         b: Double(v & 0xFF) / 255)
    }

    func mixed(toward target: ColorSpec, fraction f: Double) -> ColorSpec {
        ColorSpec(r: r + (target.r - r) * f,
                  g: g + (target.g - g) * f,
                  b: b + (target.b - b) * f,
                  a: a + (target.a - a) * f)
    }

    func darkened(_ f: Double) -> ColorSpec { mixed(toward: ColorSpec.black, fraction: f) }
    func lightened(_ f: Double) -> ColorSpec { mixed(toward: ColorSpec.white, fraction: f) }

    // Curated LCARS / TNG palette ("Okudagram" classics).
    static let lcarsPresets: [(String, ColorSpec)] = [
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
    ]
}

// MARK: - Export units

/// Unit written into an exported SVG's `width`/`height`. The viewBox stays in
/// panel pixels either way, so no geometry is rescaled — only the declared
/// physical size of the canvas changes.
///
/// Millimetres are what Rack's own documentation, helper.py's `mm` branch and
/// every MetaModule rasteriser expect. A unitless pixel size is not merely
/// less idiomatic: a rasteriser that reads `width="…mm"` fails outright on it.
enum SVGUnits: String, Codable, CaseIterable {
    case millimetres, pixels
    var displayName: String { self == .millimetres ? "Millimetres" : "Pixels" }
}

// MARK: - Component binding

/// What an element becomes in the generated widget code. `.decoration` is
/// artwork — it stays in the exported panel. Everything else is a live
/// component: Rack and MetaModule draw those themselves, so they are excluded
/// from the panel artwork and exported as positions instead.
enum ComponentRole: String, Codable, CaseIterable {
    case decoration, param, input, output, light, custom

    var displayName: String {
        switch self {
        case .decoration: return "Decoration (artwork)"
        case .param:      return "Param"
        case .input:      return "Input"
        case .output:     return "Output"
        case .light:      return "Light"
        case .custom:     return "Custom widget"
        }
    }

    /// Fill colour Rack's `helper.py` classifies a components-layer shape by.
    var helperFill: String? {
        switch self {
        case .decoration: return nil
        case .param:      return "#ff0000"
        case .input:      return "#00ff00"
        case .output:     return "#0000ff"
        case .light:      return "#ff00ff"
        case .custom:     return "#ffff00"
        }
    }

    /// Suffix `helper.py` appends to the identifier it reads from `data-name`.
    var enumSuffix: String {
        switch self {
        case .param:  return "_PARAM"
        case .input:  return "_INPUT"
        case .output: return "_OUTPUT"
        case .light:  return "_LIGHT"
        default:      return ""
        }
    }

    var isComponent: Bool { self != .decoration }

    /// One-letter badge for the layer list. The colours are helper.py's own
    /// classification colours, so what you see in the list is what lands in the
    /// components layer.
    var badge: String {
        switch self {
        case .decoration: return ""
        case .param:      return "P"
        case .input:      return "I"
        case .output:     return "O"
        case .light:      return "L"
        case .custom:     return "C"
        }
    }
}

/// Where a component's artwork comes from.
enum WidgetSource: String, Codable, CaseIterable {
    /// A Rack ComponentLibrary type. Its size is fixed by Rack's own SVG, so
    /// the on-canvas element is a placement guide only — resizing it here
    /// changes nothing in Rack.
    case stock
    /// PanelGenerator's own artwork, exported as res/components/<name>.svg.
    /// `setSvg()` takes the widget's size from that file, so resizing here is
    /// the way you resize the control.
    case custom

    var displayName: String { self == .stock ? "Rack default" : "Custom (own art)" }
}

// MARK: - Label placement

/// Where "Label Selection…" puts a generated label relative to its component.
enum LabelPlacement: String, Codable, CaseIterable {
    case above, below, left, right
    var displayName: String { rawValue.capitalized }
}

// MARK: - Element kinds

enum ElementKind: String, Codable, CaseIterable {
    // Primitives
    case jack
    case knobLarge, knobMedium, knobSmall
    case faderVertical, faderHorizontal
    case led
    case pushButton
    case buttonGroup     // n buttons: column / row / cross / circular
    case screw
    // Shapes (backdrop)
    case box            // rounded rect with per-corner radii → pills/capsules too
    case ellipse
    case triangle
    case elbow          // LCARS elbow: two arms joined by a curved corner
    case ringSector     // annulus arc — the big sweeping TNG curves
    case symbol         // parametric synth iconography — see SymbolCatalogue
    // Text
    case text

    enum Category { case primitive, shape, text }

    var isKnob: Bool { self == .knobLarge || self == .knobMedium || self == .knobSmall }

    var category: Category {
        switch self {
        case .box, .ellipse, .triangle, .elbow, .ringSector, .symbol: return .shape
        case .text: return .text
        default: return .primitive
        }
    }

    var displayName: String {
        switch self {
        case .jack: return "Jack (3.5 mm)"
        case .knobLarge: return "Knob · Large"
        case .knobMedium: return "Knob · Medium"
        case .knobSmall: return "Knob · Small"
        case .faderVertical: return "Fader · Vertical"
        case .faderHorizontal: return "Fader · Horizontal"
        case .led: return "LED"
        case .pushButton: return "Push Button"
        case .buttonGroup: return "Button Group"
        case .screw: return "Screw"
        case .box: return "Box / Rounded Rect"
        case .ellipse: return "Ellipse"
        case .triangle: return "Triangle"
        case .elbow: return "LCARS Elbow"
        case .ringSector: return "Ring Sector"
        case .symbol: return "Symbol"
        case .text: return "Text Label"
        }
    }

    /// What a freshly dropped element most likely is. Jacks default to input
    /// because that is the commoner case; flip it in the inspector.
    var defaultRole: ComponentRole {
        switch self {
        case .jack: return .input
        case .knobLarge, .knobMedium, .knobSmall,
             .faderVertical, .faderHorizontal,
             .pushButton, .buttonGroup: return .param
        case .led: return .light
        default: return .decoration
        }
    }

    /// Rack ComponentLibrary type that matches this primitive most closely.
    var defaultStockWidget: String {
        switch self {
        case .jack: return "PJ301MPort"
        case .knobLarge: return "RoundLargeBlackKnob"
        case .knobMedium: return "RoundBlackKnob"
        case .knobSmall: return "RoundSmallBlackKnob"
        case .faderVertical, .faderHorizontal: return "VCVSlider"
        case .led: return "MediumLight<RedLight>"
        case .pushButton, .buttonGroup: return "VCVButton"
        case .screw: return "ScrewSilver"
        default: return ""
        }
    }

    /// Rack types worth offering for this primitive. Free text either way —
    /// the list is a shortcut, not a constraint.
    var stockWidgetChoices: [String] {
        switch self {
        case .jack:
            return ["PJ301MPort", "PJ3410Port"]
        case .knobLarge, .knobMedium, .knobSmall:
            return ["RoundBlackKnob", "RoundSmallBlackKnob", "RoundLargeBlackKnob",
                    "RoundBigBlackKnob", "RoundHugeBlackKnob", "Trimpot",
                    "BefacoBigKnob", "BefacoTinyKnob"]
        case .faderVertical, .faderHorizontal:
            return ["VCVSlider", "VCVLightSlider", "BefacoSlidePot",
                    "LEDSliderGreen", "LEDSliderRed"]
        case .led:
            return ["MediumLight<RedLight>", "SmallLight<GreenLight>",
                    "LargeLight<BlueLight>", "MediumLight<GreenRedLight>",
                    "TinyLight<WhiteLight>"]
        case .pushButton, .buttonGroup:
            return ["VCVButton", "VCVLatch", "BefacoPush", "CKD6",
                    "VCVBezel", "NKK", "CKSS", "CKSSThree"]
        case .screw:
            return ["ScrewSilver", "ScrewBlack"]
        default:
            return []
        }
    }

    func defaultElement(at point: CGPoint) -> PanelElement {
        var e = PanelElement(kind: self)
        e.role = defaultRole
        e.stockWidget = defaultStockWidget
        switch self {
        case .jack:
            e.w = 22; e.h = 22; e.fill = .hex("#9AA0AB")
        case .knobLarge:
            e.w = 30; e.h = 30; e.fill = .hex("#FF9C00")
        case .knobMedium:
            e.w = 25; e.h = 25; e.fill = .hex("#FF9C00")
        case .knobSmall:
            e.w = 19; e.h = 19; e.fill = .hex("#99CCFF")
        case .faderVertical:
            e.w = 17; e.h = 64; e.fill = .hex("#CC99CC")
        case .faderHorizontal:
            e.w = 64; e.h = 17; e.fill = .hex("#CC99CC")
        case .led:
            e.w = 8; e.h = 8; e.fill = .hex("#EE4444")
        case .pushButton:
            e.w = 14; e.h = 14; e.fill = .hex("#DD4444")
        case .buttonGroup:
            e.w = 24; e.h = 88; e.fill = .hex("#FF9C00")
        case .screw:
            e.w = 11; e.h = 11; e.fill = .hex("#B9BEC8")
        case .box:
            e.w = 90; e.h = 34; e.fill = .hex("#FF9C00")
            e.params.cornerTL = 10; e.params.cornerTR = 10
            e.params.cornerBR = 10; e.params.cornerBL = 10
        case .ellipse:
            e.w = 56; e.h = 38; e.fill = .hex("#CC99CC")
        case .triangle:
            e.w = 46; e.h = 40; e.fill = .hex("#FFCC66")
        case .elbow:
            e.w = 96; e.h = 96; e.fill = .hex("#FF9C00")
            e.params.thickness = 16; e.params.innerRadius = 8
            e.params.armH = 56; e.params.armV = 56
        case .ringSector:
            e.w = 84; e.h = 84; e.fill = .hex("#99CCFF")
            e.params.thickness = 14; e.params.startAngle = -90; e.params.sweepAngle = 100
        case .symbol:
            e.w = 44; e.h = 30; e.fill = .hex("#99CCFF")
            e.params.symbol = "sine"
            e.params.weight = SymbolCatalogue.defaultWeight
            let d = SymbolCatalogue.spec("sine").defaults
            e.params.symbolA = d[0]; e.params.symbolB = d[1]
            e.params.symbolC = d[2]; e.params.symbolD = d[3]
        case .text:
            e.w = 120; e.h = 20; e.fill = .hex("#E8E8F0")
            e.params.text = "LABEL"; e.params.fontSize = 12; e.params.bold = true
        }
        e.frame.origin = point
        e.name = displayName
        return e
    }
}

// MARK: - Element parameters (flat & robust for JSON round-trips)

struct ElementParams: Codable, Hashable {
    // Box per-corner radii
    var cornerTL: CGFloat = 0
    var cornerTR: CGFloat = 0
    var cornerBR: CGFloat = 0
    var cornerBL: CGFloat = 0
    // Elbow
    var thickness: CGFloat = 16
    var innerRadius: CGFloat = 8
    var armH: CGFloat = 56
    var armV: CGFloat = 56
    var flipX: Bool = false
    var flipY: Bool = false
    // Ring sector
    var startAngle: CGFloat = -90
    var sweepAngle: CGFloat = 100
    // Knobs
    var pointerAngle: CGFloat = 45       // degrees, 0 = pointing up
    /// 0 pointer only, 1 position ring only, 2 both. A plain knob is what Rack
    /// draws, so it stays the default and the ring is a separate palette entry
    /// rather than a changed meaning for an existing one.
    var knobStyle: CGFloat = 0
    /// Total sweep of the open ring, degrees. 298.8 is Rack's own ±0.83·π.
    var arcSpan: CGFloat = 298.8
    /// Ring thickness as a fraction of the knob's diameter.
    var arcWidth: CGFloat = 0.10
    // Faders
    var value: CGFloat = 0.5             // 0..1
    // Button groups
    var segments: CGFloat = 4            // buttons in the group (2…12)
    var layout: CGFloat = 0              // 0 column, 1 row, 2 cross, 3 circular
    // Text
    var text: String = "LABEL"
    var fontSize: CGFloat = 12
    var bold: Bool = true
    // Symbols. `weight` is a fraction of the symbol's short side, so a glyph
    // keeps its proportions at any size. The four slots are generic: what each
    // means is declared by the symbol's SymbolSpec, which is what lets the
    // catalogue grow without touching the model.
    var symbol: String = "sine"
    var weight: CGFloat = 0.16
    var symbolA: CGFloat = 0.5
    var symbolB: CGFloat = 0.5
    var symbolC: CGFloat = 0.5
    var symbolD: CGFloat = 0.5
}

// MARK: - Element

struct PanelElement: Codable, Hashable, Identifiable {
    var id = UUID()
    var kind: ElementKind
    var name: String = ""
    var isHidden: Bool? = nil            // optional so old documents decode cleanly
    var groupID: UUID? = nil             // elements sharing a groupID act as one
    var x: CGFloat = 0, y: CGFloat = 0, w: CGFloat = 30, h: CGFloat = 30
    var rotation: CGFloat = 0            // degrees clockwise
    var fill: ColorSpec = .hex("#FF9C00")
    var stroke: ColorSpec? = nil         // outline (shapes only); nil = none
    var strokeWidth: CGFloat = 1.5
    var params = ElementParams()

    // Component binding — what this element becomes in generated widget code.
    // Defaults to .decoration so documents written before this existed keep
    // exporting exactly as they always did.
    var role: ComponentRole = .decoration
    /// Identifier stem, e.g. "CUTOFF" → CUTOFF_PARAM. Empty means "derive it".
    var enumName: String = ""
    var widgetSource: WidgetSource = .stock
    /// Rack ComponentLibrary type when `widgetSource == .stock`.
    var stockWidget: String = ""
    /// Struct name to generate when `widgetSource == .custom`, e.g. LcarsKnob.
    var customWidgetName: String = ""
    /// For a composed widget: this part turns with the parameter, so it lands
    /// in the `-fg` file that Rack rotates. Everything else is background.
    /// Only knobs rotate; for other widget types the split is not used yet.
    var rotatesWithValue: Bool = false
    /// Set on a text element made by "Label Selection…": the component it
    /// annotates. Re-running the command replaces its own labels rather than
    /// stacking a second copy on the first — invisible on canvas, doubled in
    /// the export.
    var labelOwner: UUID? = nil

    var frame: CGRect {
        get { CGRect(x: x, y: y, width: w, height: h) }
        set { x = newValue.origin.x; y = newValue.origin.y
              w = newValue.size.width; h = newValue.size.height }
    }
    var center: CGPoint { CGPoint(x: x + w / 2, y: y + h / 2) }

    /// Centre in millimetres — the unit both `mm2px()` and MetaModule's
    /// `x_mm`/`y_mm` are expressed in, so one table serves both targets.
    var centerMM: CGPoint {
        CGPoint(x: PanelMetrics.mm(center.x), y: PanelMetrics.mm(center.y))
    }

    /// Widget type to instantiate: the custom struct name when there is one,
    /// otherwise the chosen Rack type.
    var widgetClass: String {
        widgetSource == .custom
            ? (customWidgetName.isEmpty ? "SvgKnob" : customWidgetName)
            : stockWidget
    }

    /// `enumName` if set, otherwise something usable derived from the layer
    /// name — uppercased, non-alphanumerics collapsed to underscores.
    var identifierStem: String {
        let raw = enumName.isEmpty ? name : enumName
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
    mutating func applyPreset(_ id: String) {
        switch kind {
        case .symbol:
            applySymbol(id)
        case .knobLarge, .knobMedium, .knobSmall:
            switch id {
            case "ring":  params.knobStyle = 2
            case "plain": params.knobStyle = 0
            default: break
            }
        default:
            break
        }
    }

    /// Switch this element to a symbol, taking that symbol's own defaults for
    /// the four parameter slots — otherwise a pulse's width would survive as
    /// an ADSR's attack.
    mutating func applySymbol(_ id: String) {
        let spec = SymbolCatalogue.spec(id)
        params.symbol = spec.id
        params.symbolA = spec.defaults[0]
        params.symbolB = spec.defaults[1]
        params.symbolC = spec.defaults[2]
        params.symbolD = spec.defaults[3]
    }

    func contains(globalPoint p: CGPoint) -> Bool {
        frame.contains(Geo.rotate(p, around: center, degrees: -rotation))
    }
}

// MARK: - Document

struct PanelDocument: Codable, Hashable {
    /// On-disk shape version. Decoding is tolerant (a missing key falls back to
    /// the property default), so this is for diagnostics and future migrations,
    /// not for gating loads. 0 means "read from a file written before versioning
    /// existed"; `save` stamps the current version, so it never survives a
    /// round-trip.
    static let currentSchemaVersion = 1
    var schemaVersion: Int = PanelDocument.currentSchemaVersion
    var name: String = "Untitled"
    var widthHP: Int = 8
    var format: PanelFormat = .u3
    var background: ColorSpec = .hex("#17171E")
    /// Export labels as glyph outlines. Must stay on for VCV Rack: its SVG
    /// parser (nanosvg) has no text support and silently drops <text>. Turn it
    /// off only to hand editable text to Illustrator / Inkscape.
    var textAsPaths: Bool = true
    /// Plugin and module slugs used by the generated widget code. Slugs are
    /// permanent once a patch has been saved with the module — treat them as
    /// immutable from first use.
    var pluginSlug: String = "MyPlugin"
    var moduleSlug: String = "MyModule"
    /// Namespace to wrap generated custom widgets in, e.g. `museui`. Empty
    /// puts them at file scope.
    var widgetNamespace: String = ""
    var svgUnits: SVGUnits = .millimetres
    var elements: [PanelElement] = []

    /// Elements Rack / MetaModule will draw themselves, in stable top-left
    /// reading order so generated code and enums keep a sensible sequence.
    var components: [PanelElement] {
        elements
            .filter { $0.role.isComponent && $0.isHidden != true && !isWidgetArtwork($0) }
            .sorted(by: PanelDocument.readingOrder)
    }

    /// Top row first, left to right within a row.
    ///
    /// The row tolerance matters: a row of jacks aligned by eye is not aligned
    /// to the micron, and exact equality on y would order a row by that noise
    /// instead of by position — scrambling the generated enum.
    static func readingOrder(_ a: PanelElement, _ b: PanelElement) -> Bool {
        let rowHeight: CGFloat = 8
        let rowA = (a.center.y / rowHeight).rounded()
        let rowB = (b.center.y / rowHeight).rounded()
        return rowA == rowB ? a.center.x < b.center.x : rowA < rowB
    }

    /// Number these elements from one prefix, in reading order. Naming fifteen
    /// jacks one at a time is the tedium this removes; the identifiers are what
    /// make the generated enum readable as IN_1 rather than JACK_3_5_MM_7.
    mutating func nameSequentially(ids: Set<UUID>, prefix: String) {
        let trimmed = prefix.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return }
        let ordered = elements.filter { ids.contains($0.id) }.sorted(by: PanelDocument.readingOrder)
        for (index, element) in ordered.enumerated() {
            guard let i = elements.firstIndex(where: { $0.id == element.id }) else { continue }
            elements[i].enumName = ordered.count == 1 ? trimmed : "\(trimmed)_\(index + 1)"
        }
    }

    /// The text a generated label should carry: the identifier you gave the
    /// element, not the kind it happens to be. An element still holding its
    /// default layer name gets no label — twenty jacks all reading
    /// "Jack (3.5 mm)" is worse than none, and the fix is to name them first.
    func labelText(for el: PanelElement, uppercase: Bool, spaceUnderscores: Bool) -> String? {
        var raw = el.enumName.trimmingCharacters(in: .whitespaces)
        if raw.isEmpty && el.name != el.kind.displayName {
            raw = el.name.trimmingCharacters(in: .whitespaces)
        }
        guard !raw.isEmpty else { return nil }
        // Underscores are an identifier artefact: CUTOFF_FREQ is how the enum
        // must read, "CUTOFF FREQ" is how the panel must read.
        if spaceUnderscores { raw = raw.replacingOccurrences(of: "_", with: " ") }
        return uppercase ? raw.uppercased() : raw
    }

    /// Give every selected component a text label carrying its name, in one
    /// action. Returns how many were made and how many selected elements had
    /// nothing to say, so the caller can tell you to name those first rather
    /// than leaving you to count labels.
    ///
    /// Labels are positioned against `widgetBounds`, not the element's own
    /// frame: for a composed widget that is the whole artwork, so a label sits
    /// under the knob rather than under whichever part happens to be the anchor.
    @discardableResult
    mutating func labelSelection(ids: Set<UUID>,
                                 placement: LabelPlacement,
                                 gap: CGFloat,
                                 fontSize: CGFloat,
                                 bold: Bool,
                                 uppercase: Bool,
                                 spaceUnderscores: Bool,
                                 colour: ColorSpec) -> (created: Int, skipped: Int) {
        // Read the document through a snapshot: the geometry a label is placed
        // against must be the panel as it stands, not as it is part-way through
        // having last run's labels removed from it.
        let doc = self
        let targets = elements
            .filter { ids.contains($0.id) && $0.kind != .text && !doc.isWidgetArtwork($0) }
            .sorted(by: PanelDocument.readingOrder)
        guard !targets.isEmpty else { return (0, 0) }

        // Re-labelling replaces. Without this, changing the size and running
        // again leaves the old labels underneath the new ones.
        let owned = Set(targets.map(\.id))
        elements.removeAll { $0.kind == .text && ($0.labelOwner.map(owned.contains) ?? false) }

        var created = 0
        var skipped = 0
        for target in targets {
            guard let text = doc.labelText(for: target, uppercase: uppercase,
                                       spaceUnderscores: spaceUnderscores) else {
                skipped += 1
                continue
            }
            var label = ElementKind.text.defaultElement(at: .zero)
            label.params.text = text
            label.params.fontSize = max(4, fontSize)
            label.params.bold = bold
            label.fill = colour
            label.name = "Label · \(text)"
            label.labelOwner = target.id
            label.role = .decoration

            let size = Renderer.textSize(for: label)
            label.w = max(size.width, 4)
            label.h = max(size.height, 4)

            let box = doc.widgetBounds(of: target)
            switch placement {
            case .above:
                label.x = box.midX - label.w / 2
                label.y = box.minY - gap - label.h
            case .below:
                label.x = box.midX - label.w / 2
                label.y = box.maxY + gap
            case .left:
                label.x = box.minX - gap - label.w
                label.y = box.midY - label.h / 2
            case .right:
                label.x = box.maxX + gap
                label.y = box.midY - label.h / 2
            }
            elements.append(label)
            created += 1
        }
        return (created, skipped)
    }

    var pixelSize: CGSize { PanelMetrics.size(hp: widthHP, format: format) }

    /// Give every still-unbound primitive the role its kind implies, returning
    /// how many changed.
    ///
    /// A panel made before component binding existed opens with everything as
    /// decoration — correct, because it keeps old exports byte-identical, but
    /// it means one trip through the inspector per control. This is the escape
    /// hatch. Only elements still sitting at `.decoration` whose kind actually
    /// implies a component are touched, so a role set by hand is never
    /// overwritten, and shapes, text and screws stay as artwork.
    // MARK: - Composed widgets
    //
    // A widget is a group with a name. One member is the anchor — it carries
    // the role and the struct name, exactly as a single custom component does —
    // and the rest are its artwork. Reusing groups rather than inventing a
    // second kind of container means Group/Ungroup, move, align and the layer
    // list all keep working on a widget without knowing it is one.

    /// Members of the composed widget anchored on `anchor`, in draw order.
    /// A custom component that is not grouped is a widget of one.
    func widgetMembers(of anchor: PanelElement) -> [PanelElement] {
        // Only a promoted widget unions its group. A group is also just a
        // selection convenience — rows of controls grouped so they move
        // together — and treating those as widgets collapsed every component in
        // a row onto the group's centre. The custom anchor is the marker that
        // says "this group is one control".
        guard anchor.widgetSource == .custom, !anchor.customWidgetName.isEmpty,
              let group = anchor.groupID else { return [anchor] }
        return elements.filter { $0.groupID == group }
    }

    /// The widget's own frame: the union of its members. This is what the
    /// generated code positions by and what the artwork is sized to — not the
    /// anchor's frame, which is just one piece of the drawing.
    func widgetBounds(of anchor: PanelElement) -> CGRect {
        let members = widgetMembers(of: anchor)
        guard let first = members.first else { return anchor.frame }
        return members.dropFirst().reduce(first.frame) { $0.union($1.frame) }
    }

    /// Centre in millimetres of the thing Rack positions: the widget's bounds
    /// for a composed widget, the element itself otherwise.
    func componentCentreMM(_ el: PanelElement) -> CGPoint {
        let bounds = widgetBounds(of: el)
        return CGPoint(x: PanelMetrics.mm(bounds.midX), y: PanelMetrics.mm(bounds.midY))
    }

    /// True when this element is artwork belonging to someone else's widget,
    /// and so must not be drawn into the panel or treated as a component.
    func isWidgetArtwork(_ el: PanelElement) -> Bool {
        guard let group = el.groupID, !el.role.isComponent else { return false }
        return elements.contains {
            $0.groupID == group && $0.role.isComponent && $0.widgetSource == .custom
        }
    }

    /// Promote a selection to a composed widget: one group, one anchor holding
    /// the name and role, the rest its artwork. The anchor is the member
    /// nearest the centre of the whole, which for a knob is the piece you would
    /// expect the control to be positioned by.
    @discardableResult
    mutating func makeWidget(ids: Set<UUID>, name: String, role: ComponentRole) -> Bool {
        let members = elements.filter { ids.contains($0.id) }
        guard members.count >= 1, !name.isEmpty else { return false }

        var bounds = members[0].frame
        for m in members.dropFirst() { bounds = bounds.union(m.frame) }
        let middle = CGPoint(x: bounds.midX, y: bounds.midY)
        let anchorID = members.min {
            hypot($0.center.x - middle.x, $0.center.y - middle.y)
                < hypot($1.center.x - middle.x, $1.center.y - middle.y)
        }?.id

        let group = members.compactMap(\.groupID).first ?? UUID()
        for i in elements.indices where ids.contains(elements[i].id) {
            elements[i].groupID = group
            if elements[i].id == anchorID {
                elements[i].role = role
                elements[i].widgetSource = .custom
                elements[i].customWidgetName = name
                if elements[i].enumName.isEmpty { elements[i].enumName = name }
            } else {
                // Artwork, not a component in its own right.
                elements[i].role = .decoration
                elements[i].widgetSource = .stock
                elements[i].customWidgetName = ""
            }
        }
        return true
    }

    /// The element whose values stand in for a homogeneous multi-selection.
    ///
    /// nil unless every selected element is the same kind — and, for symbols,
    /// the same symbol — because otherwise the inspector's rows would not mean
    /// the same thing for every element it is about to write to. Returns in
    /// document order, so the stand-in does not change between rebuilds.
    func uniformSelection(ids: Set<UUID>) -> PanelElement? {
        let selected = elements.filter { ids.contains($0.id) }
        guard selected.count > 1, let first = selected.first else { return nil }
        guard selected.allSatisfy({ $0.kind == first.kind }) else { return nil }
        if first.kind == .symbol {
            guard selected.allSatisfy({ $0.params.symbol == first.params.symbol }) else { return nil }
        }
        return first
    }

    /// Whether every selected element already agrees on a value. The inspector
    /// marks the ones that do not, so a slider showing a single number never
    /// implies the rest match it.
    func selectionAgrees<T: Equatable>(_ keyPath: KeyPath<PanelElement, T>, ids: Set<UUID>) -> Bool {
        let selected = elements.filter { ids.contains($0.id) }
        guard let first = selected.first else { return true }
        return selected.allSatisfy { $0[keyPath: keyPath] == first[keyPath: keyPath] }
    }

    /// Distinct colours across `ids`, most-used first, each with the elements
    /// carrying it.
    ///
    /// Ordering is stable — count, then the colour itself — because the
    /// inspector rebuilds constantly and a well that jumps position between
    /// rebuilds is worse than no well at all.
    func colourGroups(ids: Set<UUID>, strokes: Bool) -> [(colour: ColorSpec, ids: [UUID])] {
        var buckets: [ColorSpec: [UUID]] = [:]
        for el in elements where ids.contains(el.id) {
            guard let colour = strokes ? el.stroke : el.fill else { continue }
            buckets[colour, default: []].append(el.id)
        }
        func key(_ c: ColorSpec) -> String { "\(c.hexString)-\(c.a)" }
        return buckets
            .map { (colour: $0.key, ids: $0.value) }
            .sorted {
                $0.ids.count != $1.ids.count
                    ? $0.ids.count > $1.ids.count
                    : key($0.colour) < key($1.colour)
            }
    }

    /// Recolour exactly these elements. Addressed by id rather than by
    /// matching the old colour: a colour well fires continuously while the
    /// picker is open, and after the first change the old colour no longer
    /// matches anything.
    mutating func setColour(_ colour: ColorSpec, ids: [UUID], strokes: Bool) {
        let wanted = Set(ids)
        for i in elements.indices where wanted.contains(elements[i].id) {
            if strokes { elements[i].stroke = colour } else { elements[i].fill = colour }
        }
    }

    /// Align the given elements, either to their own collective bounds or to
    /// the panel.
    ///
    /// Y grows downward here, so "top" is the smallest y: aligning to top puts
    /// every selected element at the topmost edge *present in the selection*.
    /// The panel's own top edge is a different operation and has to be asked
    /// for — conflating the two is the whole reason this takes a flag.
    mutating func align(_ mode: String, ids: Set<UUID>, toPanel: Bool) {
        let bounds: CGRect
        if toPanel {
            guard !ids.isEmpty else { return }
            bounds = CGRect(origin: .zero, size: pixelSize)
        } else {
            let sel = elements.filter { ids.contains($0.id) }
            guard let first = sel.first, sel.count > 1 else { return }
            var b = first.frame
            for el in sel.dropFirst() { b = b.union(el.frame) }
            bounds = b
        }
        for i in elements.indices where ids.contains(elements[i].id) {
            switch mode {
            case "L":  elements[i].x = bounds.minX
            case "R":  elements[i].x = bounds.maxX - elements[i].w
            case "CX": elements[i].x = bounds.midX - elements[i].w / 2
            case "T":  elements[i].y = bounds.minY
            case "B":  elements[i].y = bounds.maxY - elements[i].h
            case "CY": elements[i].y = bounds.midY - elements[i].h / 2
            default: break
            }
        }
    }

    @discardableResult
    mutating func bindPrimitives() -> Int {
        var bound = 0
        for i in elements.indices {
            let kind = elements[i].kind
            guard elements[i].role == .decoration, kind.defaultRole != .decoration else { continue }
            elements[i].role = kind.defaultRole
            if elements[i].stockWidget.isEmpty { elements[i].stockWidget = kind.defaultStockWidget }
            bound += 1
        }
        return bound
    }

    mutating func addCornerScrews() {
        let inset: CGFloat = 7, side: CGFloat = 11
        let sz = pixelSize
        let origins = [
            CGPoint(x: inset, y: inset),
            CGPoint(x: sz.width - inset - side, y: inset),
            CGPoint(x: inset, y: sz.height - inset - side),
            CGPoint(x: sz.width - inset - side, y: sz.height - inset - side),
        ]
        for o in origins where !elements.contains(where: { $0.kind == .screw && $0.frame.intersects(CGRect(origin: o, size: CGSize(side, side))) }) {
            elements.append(ElementKind.screw.defaultElement(at: o))
        }
    }

    // MARK Persistence

    static let fileExtension = "panelgen"

    func save(to url: URL) throws {
        // Stamp on write: a document loaded from a pre-versioning file decodes
        // as 0, and without this it would carry that 0 for the rest of its life.
        var out = self
        out.schemaVersion = Self.currentSchemaVersion
        let enc = JSONEncoder()
        enc.outputFormatting = [.prettyPrinted, .sortedKeys]
        try enc.encode(out).write(to: url, options: [.atomic])
    }

    static func load(from url: URL) throws -> PanelDocument {
        try JSONDecoder().decode(PanelDocument.self, from: Data(contentsOf: url))
    }
}

extension CGSize {
    init(_ w: CGFloat, _ h: CGFloat) { self.init(width: w, height: h) }
}

// MARK: - Tolerant decoding
//
// Swift's synthesised Codable does NOT fall back to a property's default value
// when a key is missing — it throws .keyNotFound. So every field added to a
// model after documents have been saved makes those documents unopenable
// (`segments` and `layout` did exactly that to every panel saved before the
// button-group commit). Decoding through `decodeOr` keeps old files readable.
//
// These inits live in extensions on purpose: declaring an init inside a struct
// body suppresses its memberwise initialiser, which the rest of the code uses.
//
// When adding a stored property to any of these types, add a matching line to
// its init(from:) below — encoding is still synthesised and will write the new
// key, so a field decoded nowhere would silently reset on every round-trip.

extension KeyedDecodingContainer {
    /// Missing key → `fallback`. A key that is present but malformed still
    /// throws: that is a corrupt file, not an old one, and should be reported.
    func decodeOr<T: Decodable>(_ key: Key, _ fallback: T) throws -> T {
        try decodeIfPresent(T.self, forKey: key) ?? fallback
    }
}

// Each init below starts from the type's own defaults and then overlays what
// the file actually contains. The fallback is therefore the declared default
// itself — it cannot drift out of sync with the property declaration.

extension ElementParams {
    init(from decoder: Decoder) throws {
        self.init()
        let c = try decoder.container(keyedBy: CodingKeys.self)
        cornerTL     = try c.decodeOr(.cornerTL, cornerTL)
        cornerTR     = try c.decodeOr(.cornerTR, cornerTR)
        cornerBR     = try c.decodeOr(.cornerBR, cornerBR)
        cornerBL     = try c.decodeOr(.cornerBL, cornerBL)
        thickness    = try c.decodeOr(.thickness, thickness)
        innerRadius  = try c.decodeOr(.innerRadius, innerRadius)
        armH         = try c.decodeOr(.armH, armH)
        armV         = try c.decodeOr(.armV, armV)
        flipX        = try c.decodeOr(.flipX, flipX)
        flipY        = try c.decodeOr(.flipY, flipY)
        startAngle   = try c.decodeOr(.startAngle, startAngle)
        sweepAngle   = try c.decodeOr(.sweepAngle, sweepAngle)
        pointerAngle = try c.decodeOr(.pointerAngle, pointerAngle)
        knobStyle    = try c.decodeOr(.knobStyle, knobStyle)
        arcSpan      = try c.decodeOr(.arcSpan, arcSpan)
        arcWidth     = try c.decodeOr(.arcWidth, arcWidth)
        value        = try c.decodeOr(.value, value)
        segments     = try c.decodeOr(.segments, segments)
        layout       = try c.decodeOr(.layout, layout)
        text         = try c.decodeOr(.text, text)
        fontSize     = try c.decodeOr(.fontSize, fontSize)
        bold         = try c.decodeOr(.bold, bold)
        symbol       = try c.decodeOr(.symbol, symbol)
        weight       = try c.decodeOr(.weight, weight)
        symbolA      = try c.decodeOr(.symbolA, symbolA)
        symbolB      = try c.decodeOr(.symbolB, symbolB)
        symbolC      = try c.decodeOr(.symbolC, symbolC)
        symbolD      = try c.decodeOr(.symbolD, symbolD)
    }
}

extension PanelElement {
    init(from decoder: Decoder) throws {
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
    }
}

extension PanelDocument {
    init(from decoder: Decoder) throws {
        self.init()
        let c = try decoder.container(keyedBy: CodingKeys.self)
        // Explicit 0, not the current default: no key means the file predates
        // versioning, which is worth being able to tell apart from a v1 file.
        schemaVersion = try c.decodeOr(.schemaVersion, 0)
        name          = try c.decodeOr(.name, name)
        widthHP       = try c.decodeOr(.widthHP, widthHP)
        format        = try c.decodeOr(.format, format)
        background    = try c.decodeOr(.background, background)
        textAsPaths   = try c.decodeOr(.textAsPaths, textAsPaths)
        pluginSlug    = try c.decodeOr(.pluginSlug, pluginSlug)
        moduleSlug      = try c.decodeOr(.moduleSlug, moduleSlug)
        widgetNamespace = try c.decodeOr(.widgetNamespace, widgetNamespace)
        svgUnits        = try c.decodeOr(.svgUnits, svgUnits)
        // Strict: one undecodable element must not silently yield a blank panel.
        elements      = try c.decodeIfPresent([PanelElement].self, forKey: .elements) ?? []
    }
}
