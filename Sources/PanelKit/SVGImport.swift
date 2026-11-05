import Foundation
import CoreGraphics

/// Reads an existing panel SVG into PanelGenerator's model.
///
/// What this is for, in order of how well it works:
///
///  * A tracing template. Import the panel you want to answer, draw over it,
///    delete it. Template elements never reach an export.
///  * Artwork. Rects, circles and ellipses come back as real Box and Ellipse
///    elements with their parameters intact. Everything else becomes a Path
///    element: movable, scalable, recolourable — not parametric. That is not
///    a shortcoming of the importer but of the input: a bezier blob does not
///    carry the fact that it was once an elbow.
///  * Components. A panel drawn for Rack's `helper.py` carries a components
///    layer whose circles are classified by fill; those come back bound, with
///    their identifiers. Panels without that layer keep their positions in the
///    C++ instead, which is a different reader.
///
/// What it reads is listed in SVGReader.swift. Masks, filters, patterns and
/// embedded rasters are reported rather than drawn; gradients come in as
/// their average colour, because the renderer fills flat.
package enum SVGImport {

    package struct Options {
        /// Import as a locked tracing template rather than as editable artwork.
        package var asTemplate = false
        /// Treat a viewBox-sized opaque rect as the panel background rather
        /// than as an element.
        package var adoptBackground = true
        /// Read a helper.py-style components layer, if there is one.
        package var bindComponents = true

        package init() {}
    }

    package struct Outcome {
        package var elements: [PanelElement] = []
        package var widthHP: Int = 8
        package var format: PanelFormat = .u3
        package var background: ColorSpec? = nil
        package var warnings: [String] = []
        /// Panel size in pixels as the file declares it, before rounding to HP.
        package var sourceSize: CGSize = .zero
        /// The document's own name, when the file says what it is: a
        /// PanelGenerator export's header comment names itself, so
        /// re-importing one recovers its title instead of landing as
        /// "Untitled". nil for any other SVG -- the caller falls back to
        /// the file's own name on disk.
        package var suggestedName: String? = nil
    }

    package enum Failure: LocalizedError {
        case notSVG
        case unreadable(String)
        case noViewBox
        case empty

        package var errorDescription: String? {
            switch self {
            case .notSVG:    return "That file is not an SVG PanelGenerator can read."
            case .unreadable(let why): return "That file is not an SVG PanelGenerator can read (\(why))."
            case .noViewBox: return "The SVG has neither a viewBox nor a width and height, so its coordinates cannot be placed on a panel."
            case .empty:     return "The SVG has no shapes PanelGenerator can import."
            }
        }
    }

    // MARK: - Entry point

    package static func outcome(from data: Data, options: Options = Options()) throws -> Outcome {
        guard !data.isEmpty else { throw Failure.unreadable("the file is empty") }
        let reader = Reader()
        guard reader.read(data) else { throw Failure.unreadable(reader.parseError ?? "not well-formed XML") }
        guard let viewBox = effectiveViewBox(reader), viewBox.width > 0, viewBox.height > 0 else {
            throw Failure.noViewBox
        }
        return try build(reader, viewBox: viewBox, options: options)
    }

    /// A panel SVG's size in panel pixels, without building any elements.
    ///
    /// Cheap enough to run just to learn how wide a module is — which is what
    /// resolves `box.size.x` in a module's constructor.
    package static func panelSize(from data: Data) -> CGSize? {
        let reader = Reader()
        guard reader.readSize(data), let viewBox = effectiveViewBox(reader),
              viewBox.width > 0, viewBox.height > 0 else { return nil }
        let (unitScale, _) = scale(viewBox: viewBox,
                                   declaredWidth: Length.parse(reader.widthAttribute),
                                   declaredHeight: Length.parse(reader.heightAttribute))
        return CGSize(width: viewBox.width * unitScale, height: viewBox.height * unitScale)
    }

    /// The viewBox, or — for a file that only says width="…" height="…" — the
    /// one that implies: user units are CSS pixels, 96 to the inch.
    private static func effectiveViewBox(_ reader: Reader) -> CGRect? {
        if let vb = reader.viewBox { return vb }
        guard let w = Length.parse(reader.widthAttribute), let h = Length.parse(reader.heightAttribute)
        else { return nil }
        let k: CGFloat = 96.0 / 75.0
        return CGRect(x: 0, y: 0, width: w.pixels * k, height: h.pixels * k)
    }

    // MARK: - Geometry

    /// Panel pixels per SVG user unit.
    ///
    /// This is the whole ballgame for placement. A Rack panel is normally
    /// authored with its viewBox in millimetres (`viewBox="0 0 71.12 128.5"`,
    /// `width="71.12mm"`), and PanelGenerator works in 75-dpi pixels. Import
    /// such a file at 1:1 and everything lands at a third of its size, which
    /// looks like a broken importer rather than a unit mismatch.
    private static func scale(viewBox: CGRect, declaredWidth: Length?,
                              declaredHeight: Length?) -> (scale: CGFloat, note: String?) {
        // A physical width settles it: the file says how big it is.
        if let w = declaredWidth, w.unit != "px", w.pixels > 0 {
            return (w.pixels / viewBox.width, nil)
        }
        // Otherwise the width is pixels of unknown density, or missing. Trust
        // it if it gives a panel of a real Eurorack height; if not, the
        // viewBox height says which unit the file was drawn in. That catches
        // Illustrator's point-based exports (4% small at 1:1) and 96-dpi web
        // pixels (22% large).
        let stated = declaredWidth.map { $0.pixels / viewBox.width } ?? 1
        if isPanelHeight(viewBox.height * stated) {
            return (stated, declaredWidth == nil
                ? "No width attribute — the viewBox is already in 75-dpi pixels." : nil)
        }
        let guesses: [(String, CGFloat)] = [
            ("millimetres", 75.0 / 25.4), ("points (72 dpi)", 75.0 / 72.0), ("96-dpi pixels", 75.0 / 96.0),
        ]
        // Both dimensions must fit, so a 12 mm knob drawn without units is
        // not mistaken for a 1U strip.
        for (unit, k) in guesses where isPanelHeight(viewBox.height * k) && isWholeHP(viewBox.width * k) {
            return (k, "The file does not state a physical size; its height says it was drawn in \(unit), "
                + "so it was imported at that scale.")
        }
        return (stated, declaredWidth == nil
            ? "No width attribute, and the height is not a Eurorack panel height — assuming 75-dpi pixels."
            : nil)
    }

    /// 3U (128.5 mm = 380 px) or a 1U strip (Pulp Logic 43.18 mm, Intellijel
    /// 39.65 mm), give or take a pixel or two of exporter rounding.
    private static func isPanelHeight(_ px: CGFloat) -> Bool {
        [380.0, 127.5, 117.1].contains { abs(px - $0) < 2.5 }
    }

    private static func isWholeHP(_ px: CGFloat) -> Bool {
        let hp = px / PanelMetrics.pixelsPerHP
        return hp >= 1 && abs(hp - hp.rounded()) * PanelMetrics.pixelsPerHP < 1.5
    }

    package struct Length {
        package var value: CGFloat
        package var unit: String

        /// In 75-dpi panel pixels — Rack's own SVG_DPI, the scale at which
        /// 1 HP is 15 px and a 3U panel is 380 px tall.
        package var pixels: CGFloat {
            switch unit {
            case "mm": return value * 75.0 / 25.4
            case "cm": return value * 10 * 75.0 / 25.4
            case "in": return value * 75.0
            case "pt": return value * 75.0 / 72.0
            case "pc": return value * 12 * 75.0 / 72.0
            default:   return value          // px or unitless
            }
        }

        package static func parse(_ text: String?) -> Length? {
            guard let text else { return nil }
            var tokens = SVGPath.Tokens(text)
            guard let v = tokens.number() else { return nil }
            let unit = text
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .lowercased()
                .suffix(2)
            let known = ["mm", "cm", "in", "pt", "pc", "px"]
            return Length(value: v, unit: known.contains(String(unit)) ? String(unit) : "px")
        }
    }

    // MARK: - Building the document

    private static func build(_ reader: Reader, viewBox: CGRect, options: Options) throws -> Outcome {
        var out = Outcome()
        out.warnings = reader.warnings
        out.suggestedName = reader.suggestedName

        let (unitScale, note) = scale(viewBox: viewBox,
                                      declaredWidth: Length.parse(reader.widthAttribute),
                                      declaredHeight: Length.parse(reader.heightAttribute))
        if let note { out.warnings.append(note) }

        let pxWidth = viewBox.width * unitScale
        let pxHeight = viewBox.height * unitScale
        out.sourceSize = CGSize(width: pxWidth, height: pxHeight)

        // A panel's height decides its format; its width decides its HP. Both
        // are rounded, because a file written by another tool will be a
        // fraction of a pixel off and a 8.02 HP panel does not exist.
        let midHeight = (PanelMetrics.height(for: .u3) + PanelMetrics.height(for: .u1)) / 2
        out.format = pxHeight < midHeight ? .u1 : .u3
        out.widthHP = max(PanelMetrics.minPanelWidthHP,
                          min(PanelMetrics.maxPanelWidthHP,
                              Int((pxWidth / PanelMetrics.pixelsPerHP).rounded())))

        let expected = CGFloat(out.widthHP) * PanelMetrics.pixelsPerHP
        if abs(expected - pxWidth) > 1 {
            out.warnings.append(String(format: "Panel width %.2f px is not a whole number of HP; imported as %d HP (%.0f px).",
                                       pxWidth, out.widthHP, expected))
        }

        // viewBox origin to panel origin, then user units to panel pixels.
        let place = CGAffineTransform(translationX: -viewBox.minX, y: -viewBox.minY)
            .concatenating(CGAffineTransform(scaleX: unitScale, y: unitScale))

        var elements: [PanelElement] = []
        var bound = 0
        for (index, shape) in reader.shapes.enumerated() {
            var ctm = shape.ctm.concatenating(place)
            guard let placed = shape.path.copy(using: &ctm) else { continue }
            let box = placed.boundingBoxOfPath
            guard box.width.isFinite, box.height.isFinite, !box.isNull else { continue }

            // The full-bleed background rect is the panel's colour, not a shape
            // sitting on it — importing it as an element would put an
            // unselectable slab over everything.
            if options.adoptBackground, out.background == nil, shape.tag == "rect",
               let fill = shape.fill,
               box.width >= pxWidth - 1, box.height >= pxHeight - 1 {
                out.background = fill
                continue
            }

            var el = element(for: shape, placed: placed, box: box, ctm: ctm)
            el.name = shape.label ?? "\(el.kind.displayName) \(index + 1)"

            // A shape from a helper.py components layer is a marker for a
            // control, not artwork: that is the whole difference between
            // importing a picture and importing a module.
            if options.bindComponents, !options.asTemplate, let role = shape.role {
                el.role = role
                el.widgetSource = .stock
                el.stockWidget = stockWidget(for: role, kind: el.kind)
                // helper.py reads `data-name` as "IDENT" or "IDENT#WidgetClass";
                // the suffix is the Rack type to instantiate, which is exactly
                // what the stock widget field is for.
                if let ident = shape.identifier, !ident.isEmpty {
                    let parts = ident.split(separator: "#", maxSplits: 1)
                    el.enumName = String(parts[0])
                    if parts.count == 2 { el.stockWidget = String(parts[1]) }
                }
                bound += 1
            }

            if options.asTemplate {
                el.isTemplate = true
                el.role = .decoration
            }
            elements.append(el)
        }

        // Labels, placed by their baseline.
        //
        // A Rack panel has its text converted to outlines because nanosvg drops
        // <text>, so this used to be dead code — until a plugin turned up
        // keeping a MetaModule panel of the same design with the text still
        // live. Reading it gives editable labels instead of dumb outlines, and
        // labels are what Adopt Identifiers matches on.
        var labels = 0
        for run in reader.texts {
            let ctm = run.ctm.concatenating(place)
            let baseline = run.origin.applying(ctm)
            // Scale carried by the transform, so a label inside a scaled group
            // keeps its drawn size.
            let carried = sqrt(abs(ctm.a * ctm.d - ctm.b * ctm.c))
            let size = run.fontSize * (carried.isFinite && carried > 0 ? carried : 1)

            var el = ElementKind.text.defaultElement(at: .zero)
            el.params.text = run.text
            el.params.fontSize = max(4, size)
            el.params.bold = run.bold
            el.fill = run.fill ?? .hex("#E8E8F0")
            el.name = "Label · \(run.text)"
            el.role = .decoration
            if options.asTemplate { el.isTemplate = true }

            let measured = Renderer.textSize(for: el)
            el.w = max(measured.width, 4)
            el.h = max(measured.height, 4)

            // PanelGenerator centres the cap-height box in the frame; SVG puts
            // the baseline at y. Line them up rather than leaving every label a
            // half cap-height too low.
            let capHeight = el.h / 1.5
            let advance = max(el.w - el.params.fontSize * 0.3, 1)
            let dx: CGFloat
            switch run.anchor {
            case "middle": dx = 0
            case "end":    dx = -advance / 2
            default:       dx = advance / 2
            }
            el.x = baseline.x + dx - el.w / 2
            el.y = baseline.y - capHeight / 2 - el.h / 2
            elements.append(el)
            labels += 1
        }
        if labels > 0 {
            out.warnings.append("\(labels) label\(labels == 1 ? "" : "s") came in as editable text. "
                + "Rack cannot draw <text> — nanosvg has no text support — so these export as outlines, "
                + "which is what a Rack panel needs anyway.")
        }

        guard !elements.isEmpty || out.background != nil else { throw Failure.empty }

        if bound > 0 {
            out.warnings.append("\(bound) component\(bound == 1 ? "" : "s") read from the components layer. "
                + "Check the roles before generating code: helper.py classifies by fill colour, "
                + "and it cannot tell an input from an output any other way.")
        }

        out.elements = elements
        return out
    }

    /// A components-layer marker is a circle, so its kind implies nothing
    /// about the control. helper.py has the same problem and solves it the same
    /// way: fall back to the ordinary Rack type for the role, and let the
    /// inspector correct it.
    private static func stockWidget(for role: ComponentRole, kind: ElementKind) -> String {
        let byKind = kind.defaultStockWidget
        if !byKind.isEmpty { return byKind }
        switch role {
        case .param:           return "RoundBlackKnob"
        case .input, .output:  return "PJ301MPort"
        case .light:           return "MediumLight<RedLight>"
        default:               return ""
        }
    }

    /// One shape, recognised where recognising it is honest.
    private static func element(for shape: Reader.Shape,
                                placed: CGPath,
                                box: CGRect,
                                ctm: CGAffineTransform) -> PanelElement {
        // A rotated or skewed basis means the recognisers would lie: a rotated
        // rect is not a Box with an origin and a size, and pretending it is
        // moves the artwork. Those fall through to a Path.
        let upright = abs(ctm.b) < 1e-6 && abs(ctm.c) < 1e-6
        let uniform = abs(abs(ctm.a) - abs(ctm.d)) < 1e-6
        let isRect = shape.tag == "rect" && upright
        let isRound = (shape.tag == "ellipse" && upright)
            || (shape.tag == "circle" && upright && uniform)

        var el: PanelElement
        if isRect {
            el = ElementKind.box.defaultElement(at: box.origin)
            el.frame = box
            let r = (shape.radius ?? 0) * abs(ctm.a)
            el.params.cornerTL = r; el.params.cornerTR = r
            el.params.cornerBR = r; el.params.cornerBL = r
        } else if isRound {
            el = ElementKind.ellipse.defaultElement(at: box.origin)
            el.frame = box
        } else {
            el = ElementKind.path.defaultElement(at: box.origin)
            el.frame = normalisedFrame(box)
            el.pathData = unitPathData(placed, box: box)
        }

        el.fill = shape.fill ?? ColorSpec(r: 0, g: 0, b: 0, a: 0)
        el.stroke = shape.stroke
        el.strokeWidth = max(0.1, (shape.strokeWidth ?? 1) * abs(ctm.a))
        el.role = .decoration
        return el
    }

    /// A perfectly horizontal or vertical path has a zero-height or zero-width
    /// bounding box, which would divide by zero on the way into the unit box
    /// and make the element unselectable. Give it something to hold.
    private static func normalisedFrame(_ box: CGRect) -> CGRect {
        CGRect(x: box.minX, y: box.minY,
               width: max(box.width, 0.5), height: max(box.height, 0.5))
    }

    /// The path re-expressed in a 0…1 box, so the element's frame drives its
    /// size the way every other element's does — drag a corner and the artwork
    /// scales with it.
    private static func unitPathData(_ path: CGPath, box: CGRect) -> String {
        let w = max(box.width, 0.5), h = max(box.height, 0.5)
        var t = CGAffineTransform(translationX: -box.minX, y: -box.minY)
            .concatenating(CGAffineTransform(scaleX: 1 / w, y: 1 / h))
        guard let unit = path.copy(using: &t) else { return "" }
        return PathSVG.d(unit, decimals: 6)
    }
}
