import Foundation
import CoreGraphics

// The SVG reader behind Import SVG.
//
// The file is read into a small element tree first and walked second. Walking
// a tree rather than reacting to parser events is what makes references
// resolvable: a <use> can draw a <symbol> defined later in the file, a
// clip-path can be intersected with what it clips, a gradient can be looked
// up by id, and CSS from a <style> block applies to elements before or after
// it.
//
// What the reader understands:
//  * presentation attributes, `style="…"`, and simple CSS rules in <style>
//    (`.class`, `#id`, `tag`, `tag.class`, `*`), with the cascade the spec
//    gives: attributes < rules by specificity < style attribute
//  * inheritance of fill, stroke, opacity, font and colour down the tree
//  * display:none and visibility:hidden (hidden Inkscape layers stay out)
//  * <use> of shapes, groups and <symbol>s
//  * clip-path, applied by intersecting the geometry
//  * fill-rule:evenodd, by normalising the path so the non-zero renderer
//    draws the same holes
//  * gradients, as their average colour
// Masks, filters, patterns and embedded images are reported, not drawn.

extension SVGImport {

    package final class Reader {

        package struct Shape {
            package var tag: String
            package var path: CGPath
            package var ctm: CGAffineTransform
            package var fill: ColorSpec?
            package var stroke: ColorSpec?
            package var strokeWidth: CGFloat?
            package var radius: CGFloat?          // rect rx, in the shape's own units
            package var label: String?
            package var role: ComponentRole?      // from a helper.py components layer
            package var identifier: String?       // from data-name
        }

        /// Inherited presentation state.
        package struct State {
            package var ctm: CGAffineTransform = .identity
            package var fill: ColorSpec? = .black          // SVG's initial fill is black
            package var stroke: ColorSpec? = nil
            package var strokeWidth: CGFloat? = nil
            package var fillOpacity: CGFloat = 1
            package var strokeOpacity: CGFloat = 1
            /// Product of every `opacity` on the way down. Not inherited in
            /// the spec's sense, but group opacity fades everything inside,
            /// and multiplying it in is the flat-colour equivalent.
            package var opacity: CGFloat = 1
            package var evenOdd = false
            package var visible = true
            package var currentColour: ColorSpec = .black
            /// Accumulated clip, in root user space.
            package var clip: CGPath? = nil
            package var inComponents = false
            package var fontSize: CGFloat = 3
            package var anchor: String = "start"
            package var bold = false
        }

        /// A label as the file gives it: a baseline position, an anchor, and
        /// the words.
        package struct TextRun {
            package var text: String
            package var origin: CGPoint          // the SVG's x,y — a baseline point
            package var ctm: CGAffineTransform
            package var fontSize: CGFloat        // user units
            package var anchor: String
            package var bold: Bool
            package var fill: ColorSpec?
        }

        package var viewBox: CGRect?
        package var widthAttribute: String?
        package var heightAttribute: String?
        package var shapes: [Shape] = []
        package var texts: [TextRun] = []
        package var warnings: [String] = []
        package var suggestedName: String? = nil
        /// Why the XML could not be read, when it could not.
        package var parseError: String? = nil

        private var ids: [String: Node] = [:]
        private var css: [CSSRule] = []
        private var reported = Set<String>()
        private var hiddenCount = 0
        private var clippedAway = 0
        private var useDepth = 0
        private var unsupported: [String: Set<String>] = [:]   // feature → ids

        package init() {}

        // MARK: Entry

        /// Reads `data`. Returns false if it is not well-formed XML.
        package func read(_ data: Data) -> Bool {
            guard let root = Reader.parseTree(data, error: &parseError) else { return false }
            index(root)
            css = CSSRule.parse(styleText(root))
            if let vb = root.attrs["viewBox"] {
                var t = SVGPath.Tokens(vb)
                if let x = t.number(), let y = t.number(), let w = t.number(), let h = t.number() {
                    viewBox = CGRect(x: x, y: y, width: w, height: h)
                }
            }
            widthAttribute = root.attrs["width"]
            heightAttribute = root.attrs["height"]
            walk(root, State(), isRoot: true)
            finish()
            return true
        }

        /// Only the root element's size attributes — cheap enough to run just
        /// to learn how wide a module is.
        package func readSize(_ data: Data) -> Bool {
            guard let root = Reader.parseTree(data, error: &parseError) else { return false }
            if let vb = root.attrs["viewBox"] {
                var t = SVGPath.Tokens(vb)
                if let x = t.number(), let y = t.number(), let w = t.number(), let h = t.number() {
                    viewBox = CGRect(x: x, y: y, width: w, height: h)
                }
            }
            widthAttribute = root.attrs["width"]
            heightAttribute = root.attrs["height"]
            return true
        }

        private func warnOnce(_ key: String, _ message: String) {
            guard reported.insert(key).inserted else { return }
            warnings.append(message)
        }

        private func finish() {
            if hiddenCount > 0 {
                warnings.append("\(hiddenCount) hidden element\(hiddenCount == 1 ? "" : "s") (display:none or "
                    + "visibility:hidden, e.g. a hidden Inkscape layer) stayed out of the import.")
            }
            if clippedAway > 0 {
                warnings.append("\(clippedAway) shape\(clippedAway == 1 ? " lies" : "s lie") entirely outside "
                    + "\(clippedAway == 1 ? "its" : "their") clip path and \(clippedAway == 1 ? "was" : "were") left out.")
            }
            for feature in unsupported.keys.sorted() {
                let names = unsupported[feature]!.sorted().filter { !$0.isEmpty }
                let which = names.isEmpty ? "" : " (#" + names.joined(separator: ", #") + ")"
                warnings.append("\(feature)\(which) not supported — the affected shapes come in without it.")
            }
        }

        // MARK: Tree

        final class Node {
            let tag: String            // local name, lowercased
            var attrs: [String: String]
            var children: [Node] = []
            /// Character data and child elements in document order, for text.
            var items: [Item] = []
            enum Item { case text(String), node(Node) }

            init(tag: String, attrs: [String: String]) {
                self.tag = tag
                self.attrs = attrs
            }

            var allText: String {
                items.map { item -> String in
                    switch item {
                    case .text(let s): return s
                    case .node(let n): return n.allText
                    }
                }.joined()
            }

            var classes: [String] {
                (attrs["class"] ?? "").split(whereSeparator: { $0 == " " || $0 == "\t" || $0 == "\n" }).map(String.init)
            }
        }

        private final class TreeBuilder: NSObject, XMLParserDelegate {
            var root: Node?
            var stack: [Node] = []
            var comments: [String] = []

            func parser(_ parser: XMLParser, didStartElement name: String, namespaceURI: String?,
                        qualifiedName: String?, attributes a: [String: String]) {
                let local = (name.split(separator: ":").last.map(String.init) ?? name).lowercased()
                let node = Node(tag: local, attrs: a)
                if let parent = stack.last {
                    parent.children.append(node)
                    parent.items.append(.node(node))
                } else if root == nil {
                    root = node
                }
                stack.append(node)
            }

            func parser(_ parser: XMLParser, didEndElement name: String, namespaceURI: String?,
                        qualifiedName: String?) {
                if !stack.isEmpty { stack.removeLast() }
            }

            func parser(_ parser: XMLParser, foundCharacters string: String) {
                stack.last?.items.append(.text(string))
            }

            func parser(_ parser: XMLParser, foundCDATA data: Data) {
                if let s = String(data: data, encoding: .utf8) { stack.last?.items.append(.text(s)) }
            }

            func parser(_ parser: XMLParser, foundComment comment: String) {
                comments.append(comment)
            }
        }

        private static func parseTree(_ data: Data, error: inout String?) -> Node? {
            func attempt(_ d: Data) -> (TreeBuilder, Bool, String?) {
                let builder = TreeBuilder()
                let parser = XMLParser(data: d)
                parser.delegate = builder
                parser.shouldProcessNamespaces = false
                parser.shouldResolveExternalEntities = false
                let ok = parser.parse()
                let why = ok ? nil : "line \(parser.lineNumber): "
                    + (parser.parserError?.localizedDescription ?? "not well-formed XML")
                return (builder, ok, why)
            }
            var (builder, ok, why) = attempt(data)
            if !ok, let text = String(data: data, encoding: .utf8) ?? String(data: data, encoding: .isoLatin1) {
                // HTML entities are not XML. Tools that write SVG through an
                // HTML serializer leave &nbsp; and friends in labels.
                let fixed = replacingHTMLEntities(text)
                if fixed != text {
                    (builder, ok, why) = attempt(Data(fixed.utf8))
                }
            }
            guard ok, let root = builder.root else { error = why; return nil }
            guard root.tag == "svg" else { error = "the top element is <\(root.tag)>, not <svg>"; return nil }
            builder.root?.attrs["__comments"] = builder.comments.joined(separator: "\u{1}")
            return root
        }

        private static func replacingHTMLEntities(_ s: String) -> String {
            let table = ["&nbsp;": "&#160;", "&copy;": "&#169;", "&reg;": "&#174;", "&deg;": "&#176;",
                         "&micro;": "&#181;", "&middot;": "&#183;", "&times;": "&#215;", "&ndash;": "&#8211;",
                         "&mdash;": "&#8212;", "&hellip;": "&#8230;", "&plusmn;": "&#177;", "&frac12;": "&#189;"]
            var out = s
            for (k, v) in table { out = out.replacingOccurrences(of: k, with: v) }
            return out
        }

        private func index(_ node: Node) {
            if let id = node.attrs["id"], ids[id] == nil { ids[id] = node }
            if node.tag == "svg", let comments = node.attrs["__comments"] {
                for c in comments.split(separator: "\u{1}") where suggestedName == nil {
                    // PanelGenerator's own export starts with
                    // <!-- Generated by PanelGenerator — "NAME", 8HP 3U -->;
                    // reading NAME back keeps a re-imported panel's title.
                    guard c.contains("Generated by PanelGenerator"),
                          let open = c.firstIndex(of: "\""),
                          let close = c[c.index(after: open)...].firstIndex(of: "\"") else { continue }
                    let name = String(c[c.index(after: open)..<close])
                    if !name.isEmpty { suggestedName = name }
                }
            }
            for child in node.children { index(child) }
        }

        private func styleText(_ node: Node) -> String {
            var out = node.tag == "style" ? node.allText + "\n" : ""
            for child in node.children { out += styleText(child) }
            return out
        }

        // MARK: Walk

        /// Elements that are drawn only where something references them.
        private static let definitionTags: Set<String> = [
            "defs", "clippath", "mask", "marker", "pattern", "filter", "symbol",
            "lineargradient", "radialgradient", "style", "title", "desc", "metadata",
            "namedview", "script", "font", "font-face",
        ]

        private func walk(_ node: Node, _ inherited: State, isRoot: Bool = false) {
            let tag = node.tag
            if Reader.definitionTags.contains(tag) { return }

            var props = properties(of: node)
            // helper.py's components layer is normally hidden — it is data,
            // not artwork — so it is read whatever its visibility.
            if isComponentsLayer(node.attrs) {
                props["display"] = nil
                props["visibility"] = "visible"
            }
            if props["display"]?.lowercased() == "none", !inherited.inComponents {
                if hasDrawable(node) { hiddenCount += 1 }
                return
            }

            var s = inherited
            if let t = node.attrs["transform"] {
                if let parsed = SVGPath.transform(from: t) {
                    s.ctm = parsed.concatenating(s.ctm)
                } else {
                    warnOnce("transform:" + t, "Could not read transform \"\(t)\" — that subtree is out of place.")
                }
            }
            // A nested <svg> is a viewport at x,y. Its own viewBox scaling is
            // rare in panel art and not applied.
            if tag == "svg", !isRoot {
                let x = num(node.attrs["x"]) ?? 0, y = num(node.attrs["y"]) ?? 0
                s.ctm = CGAffineTransform(translationX: x, y: y).concatenating(s.ctm)
                if node.attrs["viewBox"] != nil {
                    warnOnce("nestedsvg", "A nested <svg> with its own viewBox was placed but not rescaled.")
                }
            }
            apply(props, to: &s)
            if isComponentsLayer(node.attrs) { s.inComponents = true }

            if let ref = urlRef(props["clip-path"]) {
                if let clip = clipPath(ref, ctm: s.ctm) {
                    s.clip = s.clip.map { $0.intersection(clip) } ?? clip
                } else {
                    unsupported["Clip paths that could not be resolved", default: []].insert(ref)
                }
            }
            if let ref = urlRef(props["mask"]) { unsupported["Masks", default: []].insert(ref) }
            if let ref = urlRef(props["filter"]) { unsupported["Filters (shadows, blurs, glows)", default: []].insert(ref) }

            let a = node.attrs
            switch tag {
            case "rect":
                let x = num(a["x"]) ?? 0, y = num(a["y"]) ?? 0
                let w = num(a["width"]) ?? 0, h = num(a["height"]) ?? 0
                guard w > 0, h > 0 else { return }
                let rx = num(a["rx"]) ?? num(a["ry"]) ?? 0
                let ry = num(a["ry"]) ?? rx
                let rect = CGRect(x: x, y: y, width: w, height: h)
                let path = rx > 0
                    ? CGPath(roundedRect: rect, cornerWidth: min(rx, w / 2),
                             cornerHeight: min(ry, h / 2), transform: nil)
                    : CGPath(rect: rect, transform: nil)
                emit("rect", path, s, a, radius: rx)

            case "circle":
                let cx = num(a["cx"]) ?? 0, cy = num(a["cy"]) ?? 0, r = num(a["r"]) ?? 0
                guard r > 0 else { return }
                emit("circle", CGPath(ellipseIn: CGRect(x: cx - r, y: cy - r, width: r * 2, height: r * 2),
                                      transform: nil), s, a, radius: r)

            case "ellipse":
                let cx = num(a["cx"]) ?? 0, cy = num(a["cy"]) ?? 0
                let rx = num(a["rx"]) ?? 0, ry = num(a["ry"]) ?? 0
                guard rx > 0, ry > 0 else { return }
                emit("ellipse", CGPath(ellipseIn: CGRect(x: cx - rx, y: cy - ry, width: rx * 2, height: ry * 2),
                                       transform: nil), s, a, radius: nil)

            case "line":
                let p = CGMutablePath()
                p.move(to: CGPoint(x: num(a["x1"]) ?? 0, y: num(a["y1"]) ?? 0))
                p.addLine(to: CGPoint(x: num(a["x2"]) ?? 0, y: num(a["y2"]) ?? 0))
                emit("line", p, s, a, radius: nil)

            case "polyline", "polygon":
                guard let points = a["points"], let p = polyPath(points, close: tag == "polygon") else { return }
                emit(tag, p, s, a, radius: nil)

            case "path":
                guard let d = a["d"], !d.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
                if let p = SVGPath.path(fromD: d) {
                    emit("path", p, s, a, radius: nil)
                } else if let partial = SVGPath.partialPath(fromD: d) {
                    // Browsers draw a path up to its first error; so do we,
                    // and say so.
                    warnOnce("pathpartial", "A path with malformed data was drawn up to the error, as browsers do "
                        + "(\(d.prefix(40))…).")
                    emit("path", partial, s, a, radius: nil)
                } else {
                    warnings.append("Skipped a path whose data could not be read (\(d.prefix(40))…).")
                }

            case "text":
                let text = node.allText.trimmingCharacters(in: .whitespacesAndNewlines)
                    .replacingOccurrences(of: "\u{00A0}", with: " ")
                guard !text.isEmpty, s.visible else { return }
                if node.children.contains(where: { $0.tag == "tspan" && ($0.attrs["x"] != nil || $0.attrs["y"] != nil) }) {
                    warnOnce("tspan", "A label is split across positioned tspans — multi-line text "
                        + "came in as one line. Split it by hand if it should be two.")
                }
                // Inkscape puts the position on the first tspan, not the text.
                let firstSpan = node.children.first { $0.tag == "tspan" }
                let x = num(a["x"]) ?? num(firstSpan?.attrs["x"]) ?? 0
                let y = num(a["y"]) ?? num(firstSpan?.attrs["y"]) ?? 0
                var spanState = s
                if let span = firstSpan { apply(properties(of: span), to: &spanState) }
                texts.append(TextRun(text: text, origin: CGPoint(x: x, y: y), ctm: s.ctm,
                                     fontSize: spanState.fontSize, anchor: spanState.anchor,
                                     bold: spanState.bold, fill: paintedFill(spanState)))

            case "use":
                guard let ref = (a["href"] ?? a["xlink:href"]).flatMap(hashRef), let target = ids[ref] else {
                    warnOnce("usemissing", "A <use> pointing at nothing was skipped.")
                    return
                }
                guard useDepth < 16 else {
                    warnOnce("userecursion", "A <use> chain refers back to itself; it was cut off.")
                    return
                }
                var u = s
                let x = num(a["x"]) ?? 0, y = num(a["y"]) ?? 0
                u.ctm = CGAffineTransform(translationX: x, y: y).concatenating(u.ctm)
                useDepth += 1
                defer { useDepth -= 1 }
                if target.tag == "symbol" {
                    var sym = u
                    if let vb = target.attrs["viewBox"].flatMap(rect),
                       let w = num(a["width"]), let h = num(a["height"]), vb.width > 0, vb.height > 0 {
                        let k = min(w / vb.width, h / vb.height)
                        sym.ctm = CGAffineTransform(translationX: -vb.minX, y: -vb.minY)
                            .concatenating(CGAffineTransform(scaleX: k, y: k))
                            .concatenating(sym.ctm)
                    }
                    apply(properties(of: target), to: &sym)
                    for child in target.children { walk(child, sym) }
                } else {
                    walk(target, u)
                }

            case "image":
                if s.visible { warnOnce("image", "An embedded image was skipped — PanelGenerator draws vectors only.") }

            default:
                for child in node.children { walk(child, s) }
            }
        }

        private func hasDrawable(_ node: Node) -> Bool {
            let drawable: Set<String> = ["rect", "circle", "ellipse", "line", "polyline", "polygon", "path", "text", "use", "image"]
            return drawable.contains(node.tag) || node.children.contains(where: hasDrawable)
        }

        // MARK: Emitting

        private func paintedFill(_ s: State) -> ColorSpec? {
            guard var c = s.fill else { return nil }
            c.a *= Double(s.fillOpacity * s.opacity)
            return c
        }

        private func paintedStroke(_ s: State) -> ColorSpec? {
            guard var c = s.stroke else { return nil }
            c.a *= Double(s.strokeOpacity * s.opacity)
            return c
        }

        private func emit(_ tag: String, _ geometry: CGPath, _ s: State,
                          _ a: [String: String], radius: CGFloat?) {
            guard s.visible || s.inComponents else { hiddenCount += 1; return }
            let fill = paintedFill(s)
            let stroke = paintedStroke(s)
            var path = geometry
            var tag = tag
            var ctm = s.ctm
            var strokeWidth = s.strokeWidth

            if s.evenOdd, fill != nil, tag == "path" || tag == "polygon" || tag == "polyline" {
                path = path.normalized(using: .evenOdd)
            }

            if let clip = s.clip {
                guard let absolute = path.copy(using: &ctm) else { return }
                let clipped = fill != nil ? absolute.intersection(clip) : absolute.lineIntersection(clip)
                if clipped.isEmpty { clippedAway += 1; return }
                let before = absolute.boundingBoxOfPath, after = clipped.boundingBoxOfPath
                let untouched = abs(before.minX - after.minX) < 1e-4 && abs(before.minY - after.minY) < 1e-4
                    && abs(before.maxX - after.maxX) < 1e-4 && abs(before.maxY - after.maxY) < 1e-4
                if untouched {
                    ctm = s.ctm        // the clip changed nothing: keep it recognisable
                } else {
                    // The geometry now lives in root user space; carry the
                    // stroke's scale across with it.
                    let k = sqrt(abs(s.ctm.a * s.ctm.d - s.ctm.b * s.ctm.c))
                    strokeWidth = (strokeWidth ?? 1) * (k.isFinite && k > 0 ? k : 1)
                    path = clipped
                    ctm = .identity
                    tag = "path"
                }
            }

            var role: ComponentRole? = nil
            if s.inComponents, let hex = s.fill?.hexString.lowercased() {
                role = ComponentRole.allCases.first { $0.helperFill?.lowercased() == hex }
            }
            shapes.append(Shape(tag: tag, path: path, ctm: ctm,
                                fill: fill, stroke: stroke,
                                strokeWidth: strokeWidth, radius: radius,
                                label: a["inkscape:label"] ?? a["data-name"] ?? a["id"],
                                role: role,
                                identifier: a["data-name"] ?? a["id"]))
        }

        // MARK: References

        private func hashRef(_ s: String) -> String? {
            let t = s.trimmingCharacters(in: .whitespaces)
            return t.hasPrefix("#") ? String(t.dropFirst()) : nil
        }

        /// `url(#id)` → "id".
        private func urlRef(_ value: String?) -> String? {
            guard let v = value?.trimmingCharacters(in: .whitespaces), v.lowercased().hasPrefix("url(") else { return nil }
            guard let open = v.firstIndex(of: "("), let close = v.firstIndex(of: ")") else { return nil }
            let inner = v[v.index(after: open)..<close]
                .trimmingCharacters(in: CharacterSet(charactersIn: " '\""))
            return inner.hasPrefix("#") ? String(inner.dropFirst()) : nil
        }

        /// The union of a clipPath's children, in root user space.
        private func clipPath(_ id: String, ctm: CGAffineTransform) -> CGPath? {
            guard let node = ids[id], node.tag == "clippath" else { return nil }
            if node.attrs["clipPathUnits"] == "objectBoundingBox" {
                unsupported["Bounding-box clip paths", default: []].insert(id)
                return nil
            }
            var base = ctm
            if let t = node.attrs["transform"], let parsed = SVGPath.transform(from: t) {
                base = parsed.concatenating(base)
            }
            var combined: CGPath? = nil
            func add(_ child: Node, _ outer: CGAffineTransform) {
                var m = outer
                if let t = child.attrs["transform"], let parsed = SVGPath.transform(from: t) {
                    m = parsed.concatenating(m)
                }
                if child.tag == "use", let ref = (child.attrs["href"] ?? child.attrs["xlink:href"]).flatMap(hashRef),
                   let target = ids[ref] {
                    let x = num(child.attrs["x"]) ?? 0, y = num(child.attrs["y"]) ?? 0
                    add(target, CGAffineTransform(translationX: x, y: y).concatenating(m))
                    return
                }
                if child.tag == "g" {
                    for c in child.children { add(c, m) }
                    return
                }
                guard var g = geometry(of: child) else { return }
                if properties(of: child)["clip-rule"] == "evenodd" { g = g.normalized(using: .evenOdd) }
                guard let placed = g.copy(using: &m) else { return }
                combined = combined.map { $0.union(placed) } ?? placed
            }
            for child in node.children { add(child, base) }
            return combined
        }

        /// Plain geometry of a basic shape element, ignoring style.
        private func geometry(of n: Node) -> CGPath? {
            let a = n.attrs
            switch n.tag {
            case "rect":
                let w = num(a["width"]) ?? 0, h = num(a["height"]) ?? 0
                guard w > 0, h > 0 else { return nil }
                let rect = CGRect(x: num(a["x"]) ?? 0, y: num(a["y"]) ?? 0, width: w, height: h)
                let rx = num(a["rx"]) ?? num(a["ry"]) ?? 0
                return rx > 0 ? CGPath(roundedRect: rect, cornerWidth: min(rx, w / 2),
                                       cornerHeight: min(num(a["ry"]) ?? rx, h / 2), transform: nil)
                              : CGPath(rect: rect, transform: nil)
            case "circle":
                let r = num(a["r"]) ?? 0
                guard r > 0 else { return nil }
                let cx = num(a["cx"]) ?? 0, cy = num(a["cy"]) ?? 0
                return CGPath(ellipseIn: CGRect(x: cx - r, y: cy - r, width: 2 * r, height: 2 * r), transform: nil)
            case "ellipse":
                let rx = num(a["rx"]) ?? 0, ry = num(a["ry"]) ?? 0
                guard rx > 0, ry > 0 else { return nil }
                let cx = num(a["cx"]) ?? 0, cy = num(a["cy"]) ?? 0
                return CGPath(ellipseIn: CGRect(x: cx - rx, y: cy - ry, width: 2 * rx, height: 2 * ry), transform: nil)
            case "polygon", "polyline":
                return a["points"].flatMap { polyPath($0, close: true) }
            case "path":
                return a["d"].flatMap { SVGPath.path(fromD: $0) ?? SVGPath.partialPath(fromD: $0) }
            default:
                return nil
            }
        }

        /// A gradient's stops averaged into one colour — the flat fill that
        /// best stands in for it, and far closer than the grey this used to be.
        private func gradientColour(_ id: String) -> ColorSpec? {
            var node = ids[id]
            var hops = 0
            while let n = node, n.children.filter({ $0.tag == "stop" }).isEmpty, hops < 8,
                  let next = (n.attrs["href"] ?? n.attrs["xlink:href"]).flatMap(hashRef) {
                node = ids[next]
                hops += 1
            }
            guard let n = node else { return nil }
            let stops = n.children.filter { $0.tag == "stop" }
            guard !stops.isEmpty else { return nil }
            var r = 0.0, g = 0.0, b = 0.0, alpha = 0.0
            for stop in stops {
                let p = properties(of: stop)
                let c = p["stop-color"].flatMap(SVGColour.parse) ?? .black
                let o = p["stop-opacity"].flatMap { Double($0) } ?? 1
                r += c.r; g += c.g; b += c.b; alpha += c.a * o
            }
            let k = Double(stops.count)
            return ColorSpec(r: r / k, g: g / k, b: b / k, a: alpha / k)
        }

        // MARK: Style

        /// Effective presentation properties of one element: attributes, then
        /// matching CSS rules by specificity and order, then `style="…"`.
        private func properties(of node: Node) -> [String: String] {
            var out: [String: String] = [:]
            for key in Reader.styleKeys {
                if let v = node.attrs[key] { out[key] = v }
            }
            for rule in css where rule.matches(node) {
                for (k, v) in rule.declarations { out[k] = v }
            }
            if let style = node.attrs["style"] {
                for (k, v) in CSSRule.declarations(style) { out[k] = v }
            }
            return out
        }

        private static let styleKeys = [
            "fill", "stroke", "stroke-width", "opacity", "fill-opacity", "stroke-opacity",
            "fill-rule", "clip-rule", "display", "visibility", "color", "clip-path", "mask", "filter",
            "font-size", "text-anchor", "font-weight", "stop-color", "stop-opacity",
        ]

        private func apply(_ p: [String: String], to s: inout State) {
            if let c = p["color"], let colour = SVGColour.parse(c) { s.currentColour = colour }
            if let v = p["fill"] { s.fill = paint(v, s) }
            if let v = p["stroke"] { s.stroke = paint(v, s) }
            if let v = p["stroke-width"], let w = num(v) { s.strokeWidth = w }
            if let v = p["fill-opacity"] { s.fillOpacity = opacityValue(v) }
            if let v = p["stroke-opacity"] { s.strokeOpacity = opacityValue(v) }
            if let v = p["opacity"] { s.opacity *= opacityValue(v) }
            if let v = p["fill-rule"] { s.evenOdd = v.trimmingCharacters(in: .whitespaces) == "evenodd" }
            if let v = p["visibility"] {
                let t = v.trimmingCharacters(in: .whitespaces)
                s.visible = !(t == "hidden" || t == "collapse")
            }
            if let v = p["font-size"], let size = num(v) { s.fontSize = size }
            if let v = p["text-anchor"] { s.anchor = v.trimmingCharacters(in: .whitespaces) }
            if let v = p["font-weight"] {
                let t = v.trimmingCharacters(in: .whitespaces)
                s.bold = t == "bold" || t == "bolder" || (num(t).map { $0 >= 600 } ?? false)
            }
        }

        private func opacityValue(_ v: String) -> CGFloat {
            let t = v.trimmingCharacters(in: .whitespaces)
            if t.hasSuffix("%"), let p = num(String(t.dropLast())) { return max(0, min(1, p / 100)) }
            return max(0, min(1, num(t) ?? 1))
        }

        private func paint(_ value: String, _ s: State) -> ColorSpec? {
            let v = value.trimmingCharacters(in: .whitespaces)
            let lower = v.lowercased()
            if lower == "none" || lower == "transparent" { return nil }
            if lower == "currentcolor" { return s.currentColour }
            if lower.hasPrefix("url(") {
                if let ref = urlRef(v) {
                    if let g = gradientColour(ref) {
                        warnOnce("gradient", "Gradients came in as their average colour — PanelGenerator fills are solid.")
                        return g
                    }
                    if ids[ref]?.tag == "pattern" {
                        unsupported["Pattern fills", default: []].insert(ref)
                        return .hex("#808080")
                    }
                }
                // Fallback colour after the url, per the spec: url(#x) red.
                if let close = v.firstIndex(of: ")") {
                    let rest = v[v.index(after: close)...].trimmingCharacters(in: .whitespaces)
                    if !rest.isEmpty { return paint(rest, s) }
                }
                warnOnce("paintref", "A fill referring to something that is not in the file was left unfilled.")
                return nil
            }
            if let c = SVGColour.parse(v) { return c }
            warnOnce("colour:" + lower, "Unrecognised colour \"\(v)\" — drawn black.")
            return .black
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

        private func rect(_ s: String) -> CGRect? {
            var t = SVGPath.Tokens(s)
            guard let x = t.number(), let y = t.number(), let w = t.number(), let h = t.number() else { return nil }
            return CGRect(x: x, y: y, width: w, height: h)
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
    }
}

// MARK: - CSS

/// One rule from a <style> block, restricted to the selectors panel files
/// actually use: `.cls`, `#id`, `tag`, `tag.cls`, `.a.b` and `*`. A rule with
/// combinators or pseudo-classes is ignored rather than mis-applied.
struct CSSRule {
    let tag: String?
    let id: String?
    let classes: [String]
    let specificity: Int
    let order: Int
    let declarations: [(String, String)]

    func matches(_ node: SVGImport.Reader.Node) -> Bool {
        if let tag, tag != node.tag { return false }
        if let id, node.attrs["id"] != id { return false }
        if !classes.isEmpty {
            let have = Set(node.classes)
            if !classes.allSatisfy(have.contains) { return false }
        }
        return true
    }

    static func declarations(_ text: String) -> [(String, String)] {
        text.split(separator: ";").compactMap { pair in
            let parts = pair.split(separator: ":", maxSplits: 1)
            guard parts.count == 2 else { return nil }
            let key = parts[0].trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            let value = parts[1].replacingOccurrences(of: "!important", with: "")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            return key.isEmpty ? nil : (key, value)
        }
    }

    /// Rules sorted so applying them in order honours specificity, then
    /// source order.
    static func parse(_ sheet: String) -> [CSSRule] {
        var text = sheet
        while let open = text.range(of: "/*") {
            let close = text.range(of: "*/", range: open.upperBound..<text.endIndex)?.upperBound ?? text.endIndex
            text.removeSubrange(open.lowerBound..<close)
        }
        var rules: [CSSRule] = []
        var order = 0
        for block in text.split(separator: "}") {
            let parts = block.split(separator: "{", maxSplits: 1)
            guard parts.count == 2 else { continue }
            let decls = declarations(String(parts[1]))
            guard !decls.isEmpty else { continue }
            for raw in parts[0].split(separator: ",") {
                let sel = raw.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !sel.isEmpty, sel.rangeOfCharacter(from: CharacterSet(charactersIn: " >+~:[@")) == nil
                else { continue }
                var tag: String? = nil, id: String? = nil, classes: [String] = []
                var current = ""
                var kind: Character = "t"
                func flush() {
                    guard !current.isEmpty else { return }
                    switch kind {
                    case "#": id = current
                    case ".": classes.append(current)
                    default: if current != "*" { tag = current.lowercased() }
                    }
                    current = ""
                }
                for ch in sel {
                    if ch == "." || ch == "#" { flush(); kind = ch } else { current.append(ch) }
                }
                flush()
                let spec = (id == nil ? 0 : 100) + classes.count * 10 + (tag == nil ? 0 : 1)
                rules.append(CSSRule(tag: tag, id: id, classes: classes, specificity: spec,
                                     order: order, declarations: decls))
                order += 1
            }
        }
        return rules.sorted { ($0.specificity, $0.order) < ($1.specificity, $1.order) }
    }
}
