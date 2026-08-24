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
    // Text
    case text

    enum Category { case primitive, shape, text }

    var category: Category {
        switch self {
        case .box, .ellipse, .triangle, .elbow, .ringSector: return .shape
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
        case .text: return "Text Label"
        }
    }

    func defaultElement(at point: CGPoint) -> PanelElement {
        var e = PanelElement(kind: self)
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
    // Faders
    var value: CGFloat = 0.5             // 0..1
    // Button groups
    var segments: CGFloat = 4            // buttons in the group (2…12)
    var layout: CGFloat = 0              // 0 column, 1 row, 2 cross, 3 circular
    // Text
    var text: String = "LABEL"
    var fontSize: CGFloat = 12
    var bold: Bool = true
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

    var frame: CGRect {
        get { CGRect(x: x, y: y, width: w, height: h) }
        set { x = newValue.origin.x; y = newValue.origin.y
              w = newValue.size.width; h = newValue.size.height }
    }
    var center: CGPoint { CGPoint(x: x + w / 2, y: y + h / 2) }

    func contains(globalPoint p: CGPoint) -> Bool {
        frame.contains(Geo.rotate(p, around: center, degrees: -rotation))
    }
}

// MARK: - Document

struct PanelDocument: Codable, Hashable {
    var name: String = "Untitled"
    var widthHP: Int = 8
    var format: PanelFormat = .u3
    var background: ColorSpec = .hex("#17171E")
    var elements: [PanelElement] = []

    var pixelSize: CGSize { PanelMetrics.size(hp: widthHP, format: format) }

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
        let enc = JSONEncoder()
        enc.outputFormatting = [.prettyPrinted, .sortedKeys]
        try enc.encode(self).write(to: url, options: [.atomic])
    }

    static func load(from url: URL) throws -> PanelDocument {
        try JSONDecoder().decode(PanelDocument.self, from: Data(contentsOf: url))
    }
}

extension CGSize {
    init(_ w: CGFloat, _ h: CGFloat) { self.init(width: w, height: h) }
}
