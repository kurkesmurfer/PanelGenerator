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
/// Deliberately unsupported, each with a warning rather than a silent wrong
/// drawing: gradients (the renderer has no gradient), clip paths, masks,
/// filters, `<use>`, embedded rasters, and CSS in `<style>` blocks. `<text>`
/// is reported too, though no Rack panel has any: nanosvg drops text, so
/// every panel in the wild has its labels already converted to outlines.
enum SVGImport {

    struct Options {
        /// Import as a locked tracing template rather than as editable artwork.
        var asTemplate = false
        /// Treat a viewBox-sized opaque rect as the panel background rather
        /// than as an element.
        var adoptBackground = true
        /// Read a helper.py-style components layer, if there is one.
        var bindComponents = true
    }

    struct Outcome {
        var elements: [PanelElement] = []
        var widthHP: Int = 8
        var format: PanelFormat = .u3
        var background: ColorSpec? = nil
        var warnings: [String] = []
        /// Panel size in pixels as the file declares it, before rounding to HP.
        var sourceSize: CGSize = .zero
    }

    enum Failure: LocalizedError {
        case notSVG
        case noViewBox
        case empty

        var errorDescription: String? {
            switch self {
            case .notSVG:    return "That file is not an SVG PanelGenerator can read."
            case .noViewBox: return "The SVG has no viewBox, so its coordinates cannot be placed on a panel."
            case .empty:     return "The SVG has no shapes PanelGenerator can import."
            }
        }
    }

    // MARK: - Entry point

    static func outcome(from data: Data, options: Options = Options()) throws -> Outcome {
        let reader = Reader()
        let parser = XMLParser(data: data)
        parser.delegate = reader
        parser.shouldProcessNamespaces = false
        guard parser.parse() else { throw Failure.notSVG }
        guard let viewBox = reader.viewBox, viewBox.width > 0, viewBox.height > 0 else {
            throw Failure.noViewBox
        }
        return try build(reader, viewBox: viewBox, options: options)
    }

    /// A panel SVG's size in panel pixels, without building any elements.
    ///
    /// Cheap enough to run just to learn how wide a module is — which is what
    /// resolves `box.size.x` in a module's constructor.
    static func panelSize(from data: Data) -> CGSize? {
        let reader = Reader()
        let parser = XMLParser(data: data)
        parser.delegate = reader
        parser.shouldProcessNamespaces = false
        guard parser.parse(), let viewBox = reader.viewBox,
              viewBox.width > 0, viewBox.height > 0 else { return nil }
        let (unitScale, _) = scale(viewBox: viewBox, declaredWidth: Length.parse(reader.widthAttribute))
        return CGSize(width: viewBox.width * unitScale, height: viewBox.height * unitScale)
    }

    // MARK: - Geometry

    /// Panel pixels per SVG user unit.
    ///
    /// This is the whole ballgame for placement. A Rack panel is normally
    /// authored with its viewBox in millimetres (`viewBox="0 0 71.12 128.5"`,
    /// `width="71.12mm"`), and PanelGenerator works in 75-dpi pixels. Import
    /// such a file at 1:1 and everything lands at a third of its size, which
    /// looks like a broken importer rather than a unit mismatch.
    private static func scale(viewBox: CGRect, declaredWidth: Length?) -> (scale: CGFloat, note: String?) {
        guard let declared = declaredWidth else {
            // No width attribute: assume user units are already 75-dpi pixels,
            // which is what an SVG written without physical size means to Rack.
            return (1, "No width attribute — assuming the viewBox is already in 75-dpi pixels.")
        }
        let px = declared.pixels
        guard px > 0 else { return (1, "Unreadable width attribute — assuming 75-dpi pixels.") }
        let s = px / viewBox.width
        // 0.99–1.01 means the file was already in pixels; ~2.95 means mm.
        return (s, nil)
    }

    struct Length {
        var value: CGFloat
        var unit: String

        /// In 75-dpi panel pixels — Rack's own SVG_DPI, the scale at which
        /// 1 HP is 15 px and a 3U panel is 380 px tall.
        var pixels: CGFloat {
            switch unit {
            case "mm": return value * 75.0 / 25.4
            case "cm": return value * 10 * 75.0 / 25.4
            case "in": return value * 75.0
            case "pt": return value * 75.0 / 72.0
            case "pc": return value * 12 * 75.0 / 72.0
            default:   return value          // px or unitless
            }
        }

        static func parse(_ text: String?) -> Length? {
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

        let width = Length.parse(reader.widthAttribute)
        let (unitScale, note) = scale(viewBox: viewBox, declaredWidth: width)
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

    // MARK: - XML reader

    final class Reader: NSObject, XMLParserDelegate {

        struct Shape {
            var tag: String
            var path: CGPath
            var ctm: CGAffineTransform
            var fill: ColorSpec?
            var stroke: ColorSpec?
            var strokeWidth: CGFloat?
            var radius: CGFloat?          // rect rx, in the shape's own units
            var label: String?
            var role: ComponentRole?      // from a helper.py components layer
            var identifier: String?       // from data-name
        }

        /// Inherited presentation state. SVG inherits fill and stroke down the
        /// tree, so a group's fill is every child's default.
        struct State {
            var ctm: CGAffineTransform = .identity
            var fill: ColorSpec? = .black          // SVG's initial fill is black
            var stroke: ColorSpec? = nil
            var strokeWidth: CGFloat? = nil
            var inComponents = false
            // Text inherits down the tree like everything else: a group can
            // carry the size and the anchor for every label inside it.
            var fontSize: CGFloat = 3
            var anchor: String = "start"
            var bold = false
        }

        /// A label as the file gives it: a baseline position, an anchor, and
        /// the words. Kept separate from shapes because it is placed by its
        /// baseline, not by a bounding box.
        struct TextRun {
            var text: String
            var origin: CGPoint          // the SVG's x,y — a baseline point
            var ctm: CGAffineTransform
            var fontSize: CGFloat        // user units
            var anchor: String
            var bold: Bool
            var fill: ColorSpec?
        }

        var viewBox: CGRect?
        var widthAttribute: String?
        var heightAttribute: String?
        var shapes: [Shape] = []
        var texts: [TextRun] = []
        var warnings: [String] = []
        private var pendingText: TextRun? = nil
        private var textDepth = 0

        private var stack: [State] = [State()]
        private var skipDepth = 0
        private var reported = Set<String>()

        private var top: State { stack[stack.count - 1] }

        private func warnOnce(_ tag: String, _ message: String) {
            guard reported.insert(tag).inserted else { return }
            warnings.append(message)
        }

        func parser(_ parser: XMLParser, didStartElement name: String, namespaceURI: String?,
                    qualifiedName: String?, attributes a: [String: String]) {
            let tag = name.contains(":") ? String(name.split(separator: ":").last!) : name

            if skipDepth > 0 { skipDepth += 1; return }

            // Definitions are drawn only where they are referenced, and we do
            // not resolve references. Walking into them would scatter a
            // clipPath's outline across the panel as real artwork.
            if ["defs", "clippath", "mask", "marker", "pattern", "filter", "symbol"]
                .contains(tag.lowercased()) {
                skipDepth = 1
                warnOnce(tag, "\(tag) is not supported and was skipped; artwork depending on it will differ.")
                return
            }

            var state = top
            if let t = a["transform"] {
                if let parsed = SVGPath.transform(from: t) {
                    state.ctm = parsed.concatenating(state.ctm)
                } else {
                    warnOnce("transform:" + t, "Could not read transform \"\(t)\" — that subtree is out of place.")
                }
            }
            let style = presentation(a)
            if let f = style.fill { state.fill = f.isNone ? nil : f.colour }
            if let s = style.stroke { state.stroke = s.isNone ? nil : s.colour }
            if let w = style.strokeWidth { state.strokeWidth = w }
            if let size = style.fontSize { state.fontSize = size }
            if let anchor = style.anchor { state.anchor = anchor }
            if let weight = style.weight { state.bold = weight }
            if isComponentsLayer(a) { state.inComponents = true }

            switch tag.lowercased() {
            case "svg":
                if viewBox == nil, let vb = a["viewBox"] {
                    var t = SVGPath.Tokens(vb)
                    if let x = t.number(), let y = t.number(), let w = t.number(), let h = t.number() {
                        viewBox = CGRect(x: x, y: y, width: w, height: h)
                    }
                }
                widthAttribute = widthAttribute ?? a["width"]
                heightAttribute = heightAttribute ?? a["height"]

            case "rect":
                let x = num(a["x"]) ?? 0, y = num(a["y"]) ?? 0
                let w = num(a["width"]) ?? 0, h = num(a["height"]) ?? 0
                guard w > 0, h > 0 else { break }
                let rx = num(a["rx"]) ?? num(a["ry"]) ?? 0
                let rect = CGRect(x: x, y: y, width: w, height: h)
                let path = rx > 0
                    ? CGPath(roundedRect: rect, cornerWidth: min(rx, w / 2),
                             cornerHeight: min(num(a["ry"]) ?? rx, h / 2), transform: nil)
                    : CGPath(rect: rect, transform: nil)
                append(tag: "rect", path: path, state: state, attrs: a, radius: rx)

            case "circle":
                let cx = num(a["cx"]) ?? 0, cy = num(a["cy"]) ?? 0, r = num(a["r"]) ?? 0
                guard r > 0 else { break }
                let path = CGPath(ellipseIn: CGRect(x: cx - r, y: cy - r, width: r * 2, height: r * 2),
                                  transform: nil)
                append(tag: "circle", path: path, state: state, attrs: a, radius: r)

            case "ellipse":
                let cx = num(a["cx"]) ?? 0, cy = num(a["cy"]) ?? 0
                let rx = num(a["rx"]) ?? 0, ry = num(a["ry"]) ?? 0
                guard rx > 0, ry > 0 else { break }
                let path = CGPath(ellipseIn: CGRect(x: cx - rx, y: cy - ry, width: rx * 2, height: ry * 2),
                                  transform: nil)
                append(tag: "ellipse", path: path, state: state, attrs: a, radius: nil)

            case "line":
                let p = CGMutablePath()
                p.move(to: CGPoint(x: num(a["x1"]) ?? 0, y: num(a["y1"]) ?? 0))
                p.addLine(to: CGPoint(x: num(a["x2"]) ?? 0, y: num(a["y2"]) ?? 0))
                append(tag: "line", path: p, state: state, attrs: a, radius: nil)

            case "polyline", "polygon":
                guard let points = a["points"], let p = polyPath(points, close: tag.lowercased() == "polygon")
                else { break }
                append(tag: tag.lowercased(), path: p, state: state, attrs: a, radius: nil)

            case "path":
                guard let d = a["d"] else { break }
                guard let p = SVGPath.path(fromD: d) else {
                    warnings.append("Skipped a path whose data could not be read (\(d.prefix(40))…).")
                    break
                }
                append(tag: "path", path: p, state: state, attrs: a, radius: nil)

            case "text":
                // The baseline, not a box. A tspan carrying its own x/y is a
                // second line; the first one wins and the reader says so.
                textDepth = 1
                pendingText = TextRun(text: "",
                                      origin: CGPoint(x: num(a["x"]) ?? 0, y: num(a["y"]) ?? 0),
                                      ctm: state.ctm,
                                      fontSize: state.fontSize,
                                      anchor: state.anchor,
                                      bold: state.bold,
                                      fill: state.fill)

            case "tspan":
                if pendingText != nil {
                    textDepth += 1
                    if a["x"] != nil || a["y"] != nil {
                        warnOnce("tspan", "A label is split across positioned tspans — multi-line text "
                            + "came in as one line. Split it by hand if it should be two.")
                    }
                } else {
                    warnOnce("tspan", "A tspan outside any <text> was skipped.")
                }

            case "use":
                warnOnce("use", "<use> references were skipped — that artwork is missing from the import.")

            case "image":
                warnOnce("image", "An embedded image was skipped.")

            case "style":
                warnOnce("style", "A CSS <style> block was ignored; shapes styled only by class come in unfilled.")

            case "lineargradient", "radialgradient":
                warnOnce("gradient", "Gradients were flattened away — PanelGenerator fills are solid.")

            default:
                break
            }

            stack.append(state)
        }

        func parser(_ parser: XMLParser, didEndElement name: String, namespaceURI: String?,
                    qualifiedName: String?) {
            if skipDepth > 0 { skipDepth -= 1; return }
            let tag = (name.contains(":") ? String(name.split(separator: ":").last!) : name).lowercased()
            if tag == "text" || tag == "tspan", textDepth > 0 {
                textDepth -= 1
                if textDepth == 0, var run = pendingText {
                    run.text = run.text.trimmingCharacters(in: .whitespacesAndNewlines)
                    if !run.text.isEmpty { texts.append(run) }
                    pendingText = nil
                }
            }
            if stack.count > 1 { stack.removeLast() }
        }

        func parser(_ parser: XMLParser, foundCharacters string: String) {
            guard skipDepth == 0, pendingText != nil else { return }
            pendingText?.text += string
        }

        private func append(tag: String, path: CGPath, state: State,
                            attrs a: [String: String], radius: CGFloat?) {
            let fill = state.fill
            var role: ComponentRole? = nil
            if state.inComponents, let hex = fill?.hexString.lowercased() {
                role = ComponentRole.allCases.first { $0.helperFill?.lowercased() == hex }
            }
            shapes.append(Shape(tag: tag, path: path, ctm: state.ctm,
                                fill: fill, stroke: state.stroke,
                                strokeWidth: state.strokeWidth, radius: radius,
                                label: a["inkscape:label"] ?? a["data-name"] ?? a["id"],
                                role: role,
                                identifier: a["data-name"] ?? a["id"]))
        }

        private func isComponentsLayer(_ a: [String: String]) -> Bool {
            let names = [a["inkscape:label"], a["data-name"], a["id"]].compactMap { $0?.lowercased() }
            return names.contains("components")
        }

        private func num(_ s: String?) -> CGFloat? {
            guard let s else { return nil }
            var t = SVGPath.Tokens(s)
            return t.number()
        }

        private func polyPath(_ points: String, close: Bool) -> CGPath? {
            var t = SVGPath.Tokens(points)
            let p = CGMutablePath()
            var first = true
            while let x = t.number(), let y = t.number() {
                let pt = CGPoint(x: x, y: y)
                if first { p.move(to: pt); first = false } else { p.addLine(to: pt) }
            }
            if first { return nil }
            if close { p.closeSubpath() }
            return p
        }

        // MARK: Presentation attributes

        struct Paint {
            var colour: ColorSpec?
            var isNone: Bool
        }

        struct Presentation {
            var fill: Paint?
            var stroke: Paint?
            var strokeWidth: CGFloat?
            var fontSize: CGFloat?
            var anchor: String?
            var weight: Bool?
        }

        /// Presentation attributes, with `style="…"` overriding them — which is
        /// the order the spec gives and the order Inkscape relies on.
        private func presentation(_ a: [String: String]) -> Presentation {
            var out = Presentation()
            var opacity: CGFloat = 1
            var fillOpacity: CGFloat = 1

            func take(_ key: String, _ value: String) {
                switch key {
                case "fill":           out.fill = paint(value)
                case "stroke":         out.stroke = paint(value)
                case "stroke-width":   out.strokeWidth = num(value)
                case "font-size":      out.fontSize = num(value)
                case "text-anchor":    out.anchor = value
                case "font-weight":
                    // "bold", or any numeric weight at or above semibold.
                    out.weight = value == "bold" || (num(value).map { $0 >= 600 } ?? false)
                case "opacity":        opacity = num(value) ?? 1
                case "fill-opacity":   fillOpacity = num(value) ?? 1
                default: break
                }
            }

            for key in ["fill", "stroke", "stroke-width", "opacity", "fill-opacity",
                        "font-size", "text-anchor", "font-weight"] {
                if let v = a[key] { take(key, v) }
            }
            if let style = a["style"] {
                for pair in style.split(separator: ";") {
                    let parts = pair.split(separator: ":", maxSplits: 1)
                    guard parts.count == 2 else { continue }
                    take(parts[0].trimmingCharacters(in: .whitespaces),
                         parts[1].trimmingCharacters(in: .whitespaces))
                }
            }

            let alpha = max(0, min(1, opacity * fillOpacity))
            if alpha < 1, let existing = out.fill?.colour {
                var faded = existing
                faded.a *= alpha
                out.fill?.colour = faded
            }
            return out
        }

        private func paint(_ value: String) -> Paint {
            let v = value.trimmingCharacters(in: .whitespaces).lowercased()
            if v == "none" || v == "transparent" { return Paint(colour: nil, isNone: true) }
            if v.hasPrefix("url(") {
                warnOnce("paintref", "A gradient or pattern fill was replaced with a flat colour.")
                return Paint(colour: .hex("#808080"), isNone: false)
            }
            return Paint(colour: SVGColour.parse(v), isNone: false)
        }
    }
}

// MARK: - Colours

enum SVGColour {

    static func parse(_ text: String) -> ColorSpec? {
        let v = text.trimmingCharacters(in: .whitespaces).lowercased()
        if v.hasPrefix("#") {
            let hex = String(v.dropFirst())
            if hex.count == 3 {
                let expanded = hex.map { "\($0)\($0)" }.joined()
                return .hex("#" + expanded)
            }
            if hex.count == 6 { return .hex(v) }
            return nil
        }
        if v.hasPrefix("rgb") {
            var t = SVGPath.Tokens(v.replacingOccurrences(of: "%", with: ""))
            guard let r = t.number(), let g = t.number(), let b = t.number() else { return nil }
            let a = t.number() ?? 1
            return ColorSpec(r: Double(r) / 255, g: Double(g) / 255, b: Double(b) / 255,
                             a: Double(min(max(a, 0), 1)))
        }
        return named[v]
    }

    /// The handful of named colours that actually turn up in panel art. A full
    /// CSS colour table would be 148 entries of noise.
    private static let named: [String: ColorSpec] = [
        "black": .hex("#000000"), "white": .hex("#FFFFFF"),
        "red": .hex("#FF0000"), "lime": .hex("#00FF00"), "blue": .hex("#0000FF"),
        "green": .hex("#008000"), "yellow": .hex("#FFFF00"), "magenta": .hex("#FF00FF"),
        "fuchsia": .hex("#FF00FF"), "cyan": .hex("#00FFFF"), "aqua": .hex("#00FFFF"),
        "gray": .hex("#808080"), "grey": .hex("#808080"), "silver": .hex("#C0C0C0"),
        "orange": .hex("#FFA500"), "purple": .hex("#800080"), "navy": .hex("#000080"),
        "maroon": .hex("#800000"), "olive": .hex("#808000"), "teal": .hex("#008080"),
    ]
}
