import Foundation
import CoreGraphics

/// Reads component positions out of a Rack `ModuleWidget` constructor.
///
/// For adopting an existing plugin the panel SVG is the wrong file. It carries
/// the artwork and nothing else; the positions, the widget types and the
/// identifiers all live in the C++:
///
/// ```cpp
/// addParam(createParamCentered<RoundBlackKnob>(mm2px(Vec(15.24, 38.95)), module, Module::CUTOFF_PARAM));
/// ```
///
/// One pass over that gives a bound PanelGenerator document. Pair it with the
/// panel SVG imported as artwork and the module comes back whole.
///
/// This is a reader, not a compiler. It understands the shapes that real
/// module sources are written in — named constants, `7.0f` literals, simple
/// arithmetic, namespaced widget types, `#ifdef METAMODULE` — and reports
/// everything it could not resolve rather than guessing a position.
package enum CppImport {

    package struct Outcome {
        package var elements: [PanelElement] = []
        package var moduleSlug: String? = nil
        /// The panel resource the widget sets, e.g. "res/Muse.svg".
        package var panelResource: String? = nil
        /// Only when the source sets `box.size` explicitly; normally the panel
        /// SVG is what says how wide the module is.
        package var widthHP: Int? = nil
        package var warnings: [String] = []
    }

    /// Rack constants a module source may use in a position expression.
    package static let builtinConstants: [String: CGFloat] = [
        "RACK_GRID_WIDTH": 15,
        "RACK_GRID_HEIGHT": 380,
        "SVG_DPI": 75,
        "MM_PER_IN": 25.4,
    ]

    // MARK: - Entry point

    /// - Parameters:
    ///   - source: the module source.
    ///   - headers: sibling headers to scan for constants. A module that
    ///     writes `mm2px(Vec(7.0f, grid::PRIMARY_Y))` is unreadable without
    ///     them, and that style is common in any panel laid out on a grid.
    /// - Parameter panelSize: the module's own box, in panel pixels, when it is
    ///   known. Rack's module template positions its screws with
    ///   `Vec(box.size.x - 2 * RACK_GRID_WIDTH, 0)`, so without this the two
    ///   right-hand screws of nearly every third-party plugin are unreadable.
    ///   `setPanel` names the panel it is taken from, which is how the caller
    ///   knows it.
    package static func outcome(from source: String, headers: [String] = [],
                        panelSize: CGSize? = nil,
                        widgetSize: ((_ type: String, _ custom: Bool) -> CGSize?)? = nil) -> Outcome {
        var out = Outcome()

        let (rawText, preprocessorWarnings) = preprocess(source)
        out.warnings.append(contentsOf: preprocessorWarnings)
        let headerTexts = headers.map { preprocess($0).text }

        // Plugin helpers that place controls or labels — a header lockup, a
        // two-button switch — are expanded at their call sites, so what they
        // place is read like anything written out in the constructor.
        let helpers = inlinableHelpers(in: headerTexts + [rawText])
        let text = inlineHelpers(rawText, helpers: helpers)

        // Types the plugin defines itself are its own widgets, namespaced or
        // not; a type from Rack's library is never defined in the plugin.
        let ownTypes = definedTypes(in: headerTexts + [rawText])
        let strings = stringArrays(in: headerTexts + [text])

        var table = builtinConstants
        if let panelSize {
            table["box.size.x"] = panelSize.width
            table["box.size.y"] = panelSize.height
        }
        for header in headers {
            merge(&table, constants(in: preprocess(header).text))
        }
        merge(&table, constants(in: text))

        var labelSizes = labelHelpers(in: text)
        for header in headers {
            for (k, v) in labelHelpers(in: preprocess(header).text) where labelSizes[k] == nil {
                labelSizes[k] = v
            }
        }

        // Loops with constant bounds are unrolled, so `for (int i = 0; i < 4;
        // i++) addInput(… mm2px(Vec(X0 + i * PITCH, Y)) …)` gives four jacks.
        let (unrolled, loopWarnings) = unrollLoops(text, table: table)
        out.warnings.append(contentsOf: loopWarnings)

        var labels = 0
        let found = calls(in: unrolled)
        // Locals are evaluated in source order, so `float y = 30.f;` before a
        // call and `y = 50.f;` before the next give each its own value.
        // Only from the widget onwards: generated DSP code ahead of it (Faust
        // output runs to megabytes) holds no panel positions.
        let widgetStart = (unrolled as NSString).range(of: "ModuleWidget").location
        let assignments = localAssignments(in: unrolled,
                                           from: widgetStart == NSNotFound ? 0 : widgetStart)
        var nextAssignment = 0
        var scope = table
        if found.filter({ $0.name == "setPanel" }).count > 1 {
            out.warnings.append("More than one setPanel call — either the file holds several module "
                + "widgets, or a theme switch. Everything found was imported into one panel.")
        }

        for call in found {
            while nextAssignment < assignments.count, assignments[nextAssignment].offset < call.offset {
                let a = assignments[nextAssignment]
                nextAssignment += 1
                let current = scope[a.name]
                let rhs = Expression.evaluate(a.expression, constants: scope)
                switch (a.op, rhs, current) {
                case ("=", let v?, _):            scope[a.name] = v
                case ("+=", let v?, let c?):      scope[a.name] = c + v
                case ("-=", let v?, let c?):      scope[a.name] = c - v
                case ("*=", let v?, let c?):      scope[a.name] = c * v
                case ("/=", let v?, let c?) where abs(v) > 1e-12: scope[a.name] = c / v
                default:
                    // Unknown now: better unresolved than stale.
                    if table[a.name] == nil { scope[a.name] = nil }
                }
            }
            let table = scope
            switch call.name {
            case "setPanel":
                guard out.panelResource == nil else { break }
                // A themed panel is setPanel(light, dark); the dark one is the
                // default, so the last SVG named wins.
                let literals = stringLiterals(in: call.args.joined(separator: ","))
                    .filter { $0.lowercased().hasSuffix(".svg") }
                out.panelResource = literals.last
                if literals.count > 1 {
                    out.warnings.append("setPanel names \(literals.count) panels (a theme switch); "
                        + "took \(literals.last ?? "the last").")
                }

            case "createModel":
                if out.moduleSlug == nil {
                    out.moduleSlug = stringLiterals(in: call.args.joined(separator: ",")).first
                }

            default:
                if let role = role(for: call.name) {
                    append(call, role: role, table: table, ownTypes: ownTypes,
                           widgetSize: widgetSize, into: &out)
                } else if let made = label(call, table: table, sizes: labelSizes, strings: strings) {
                    out.elements.append(made)
                    labels += 1
                } else if isLabelShaped(call, strings: strings) {
                    // Shaped like a label but positioned by something we cannot
                    // evaluate. Silence here would read as "this panel has no
                    // labels", which is a different and much more misleading
                    // thing to conclude.
                    out.warnings.append("Line \(call.line): \(call.name) looks like a label helper, "
                        + "but its position could not be worked out — it was skipped.")
                }
            }
        }

        if labels > 0 {
            let sized = labelSizes.isEmpty
                ? "at a default size, because the helper's own size could not be found"
                : "at the size their helper passes"
            out.warnings.append("\(labels) label\(labels == 1 ? "" : "s") were read from helper calls "
                + "and placed \(sized). They are centred on the position given, which is what "
                + "NVG_ALIGN_CENTER|NVG_ALIGN_MIDDLE labels do; a helper that aligns differently will "
                + "need them nudged.")
        }

        if let size = boxSize(in: text, table: table), size > 0 {
            out.widthHP = max(1, Int((size / PanelMetrics.pixelsPerHP).rounded()))
        }

        if out.elements.isEmpty {
            out.warnings.append("No component calls were found. This reader looks for "
                + "createParam/Input/Output/Light(Centered) inside a ModuleWidget constructor; "
                + "a module that positions its widgets some other way needs doing by hand.")
        }
        return out
    }

    // MARK: - One component

    private static func append(_ call: Call, role: ComponentRole,
                               table: [String: CGFloat], ownTypes: Set<String> = [],
                               widgetSize: ((String, Bool) -> CGSize?)? = nil,
                               into out: inout Outcome) {
        guard let positionArg = call.args.first else { return }
        guard let point = position(positionArg, table: table) else {
            out.warnings.append("Line \(call.line): could not work out the position from "
                + "\"\(condensed(positionArg))\" — that component was skipped.")
            return
        }

        let widget = call.template.isEmpty ? "" : String(call.template.split(separator: ":").last ?? "")
        var el = kind(for: widget, role: role).defaultElement(at: .zero)
        el.role = role

        // A switch's position count is in its name and nowhere else. Importing
        // a Switch3Way as the palette's default four-way is wrong in the one
        // way that matters: the generated code would offer a value the module
        // has no case for.
        if el.kind == .buttonGroup, let positions = switchPositions(widget) {
            el.params.segments = positions
            el.h = 22 * positions            // the palette's own pitch
        }

        // A namespaced type is not from Rack's ComponentLibrary, so it is one
        // of the plugin's own widgets. Saying so is what lets the generated
        // code name it again instead of silently substituting a Rack knob.
        let isOwn = call.template.contains("::") || ownTypes.contains(widget)
        if isOwn {
            el.widgetSource = .custom
            el.customWidgetName = widget
            el.stockWidget = ""
        } else if !widget.isEmpty {
            el.widgetSource = .stock
            el.stockWidget = call.template
        }

        if call.args.count > 2 {
            el.enumName = enumStem(call.args[2], role: role)
        }
        el.name = el.enumName.isEmpty ? el.kind.displayName : el.enumName

        // The widget's real size, from its own SVG, when it can be found: the
        // on-canvas guide then matches what Rack draws, and an uncentred
        // call can be placed exactly.
        let known = widget.isEmpty ? nil : widgetSize?(call.template, isOwn)
        if let s = known, s.width > 0, s.height > 0 {
            el.w = s.width
            el.h = s.height
        }

        if call.isCentered {
            el.x = point.x - el.w / 2
            el.y = point.y - el.h / 2
        } else if known != nil {
            el.x = point.x
            el.y = point.y
        } else {
            // createParam (no Centered) takes a top-left corner, and the offset
            // to the centre is the widget's own size — which lives in Rack's
            // SVG for that type, not here. Placed as given, and flagged: the
            // alternative is a table of ComponentLibrary sizes that goes stale
            // without telling anyone.
            el.x = point.x
            el.y = point.y
            // Screws and other createWidget decoration are always positioned by
            // corner and always will be; warning about each one would bury the
            // cases that matter.
            if role.isComponent {
                out.warnings.append("Line \(call.line): \(call.name) positions by top-left corner, not centre. "
                    + "\(el.enumName.isEmpty ? widget : el.enumName) was placed at that corner using "
                    + "PanelGenerator's default size for the kind — check it against the panel.")
            }
        }

        out.elements.append(el)
    }

    /// A panel's text is often not in its SVG at all. Muse draws every label
    /// from code — `museui::addCvLabel(this, 7.0f, grid::PRIMARY_LABEL_Y, "X CV")`
    /// — and a reader that ignored those would import a panel with nothing
    /// written on it.
    ///
    /// The shape is what identifies these, not the name: four arguments, the
    /// first literally `this`, two that evaluate to numbers, and a string. That
    /// is tight enough that a draw call like `nvgText(args.vg, …)` cannot match.
    package static func isLabelShaped(_ call: Call, strings: [String: String] = [:]) -> Bool {
        call.args.count == 4 && call.args[0] == "this" && labelText(call.args[3], strings: strings) != nil
    }

    /// A label's text: a string literal, or an element of a constant string
    /// array (`in1[2]`, after a loop has been unrolled).
    private static func labelText(_ arg: String, strings: [String: String]) -> String? {
        let a = arg.trimmingCharacters(in: .whitespacesAndNewlines)
        if a.hasPrefix("\"") { return stringLiterals(in: a).first }
        let bare = a.components(separatedBy: "::").last ?? a
        return strings[bare.replacingOccurrences(of: " ", with: "")]
    }

    /// NanoVG sizes a font by its line height (ascent − descent), which for
    /// the label fonts plugins use is about 1.25 em; PanelGenerator, like every
    /// Mac text system, sizes by the em. Measured on SpaceTime's Head panel:
    /// size 7 draws capitals 1.33 mm tall in Rack.
    package static let nanoVGToEm: CGFloat = 0.8

    private static func label(_ call: Call, table: [String: CGFloat],
                              sizes: [String: CGFloat], strings: [String: String] = [:]) -> PanelElement? {
        guard isLabelShaped(call, strings: strings),
              let x = Expression.evaluate(call.args[1], constants: table),
              let y = Expression.evaluate(call.args[2], constants: table),
              let text = labelText(call.args[3], strings: strings) else { return nil }

        var el = ElementKind.text.defaultElement(at: .zero)
        el.params.text = text
        el.params.fontSize = (sizes[call.name] ?? 7) * nanoVGToEm
        el.params.bold = true
        el.role = .decoration
        el.name = "Label · \(text)"

        let size = Renderer.textSize(for: el)
        el.w = max(size.width, 4)
        el.h = max(size.height, 4)
        // The helper's coordinates are millimetres, like every other position
        // in a panel laid out this way.
        el.x = x / PanelMetrics.mmPerPixel - el.w / 2
        el.y = y / PanelMetrics.mmPerPixel - el.h / 2
        return el
    }

    /// Font size per label helper, read from the helper's own definition.
    ///
    /// The idiom is a one-line forwarder — `addKnobLabel` calls
    /// `addLabel(w, x, y, text, font, 7.5f, …)` — so the sixth argument of the
    /// first call in the body is the size. Where that does not hold, the label
    /// falls back to a default and the report says so.
    package static func labelHelpers(in text: String) -> [String: CGFloat] {
        let pattern = #"(?:inline\s+)?(?:static\s+)?void\s+(\w+)\s*\([^)]*\)\s*\{([^}]*)\}"#
        guard let re = try? NSRegularExpression(pattern: pattern, options: [.dotMatchesLineSeparators]) else {
            return [:]
        }
        var out: [String: CGFloat] = [:]
        let ns = text as NSString
        for m in re.matches(in: text, range: NSRange(location: 0, length: ns.length))
        where m.numberOfRanges == 3 {
            let name = ns.substring(with: m.range(at: 1))
            let body = ns.substring(with: m.range(at: 2))
            guard let inner = calls(in: body).first, inner.args.count >= 6 else { continue }
            if let size = Expression.evaluate(inner.args[5], constants: builtinConstants), size > 0 {
                out[name] = size
            }
        }
        return out
    }

    /// Positions in a switch, read from its type name: `Switch3Way` and
    /// `CKSS4` by their digit, `CKSSThree` by its word, and the two Rack types
    /// whose count is only in the documentation.
    ///
    /// The size that follows is a placeholder — Rack takes it from the widget's
    /// own SVG — but the count is not, and it is the one the generated code
    /// depends on.
    package static func switchPositions(_ widget: String) -> CGFloat? {
        let bare = widget.components(separatedBy: "::").last ?? widget
        if let digit = bare.first(where: { $0.isNumber }), let n = Int(String(digit)), n >= 2, n <= 12 {
            return CGFloat(n)
        }
        let words: [(String, CGFloat)] = [
            ("Twelve", 12), ("Eleven", 11), ("Three", 3), ("Four", 4), ("Five", 5),
            ("Six", 6), ("Seven", 7), ("Eight", 8), ("Nine", 9), ("Ten", 10), ("Two", 2),
        ]
        let lower = bare.lowercased()
        if let hit = words.first(where: { lower.contains($0.0.lowercased()) }) { return hit.1 }
        // Rack's own two, whose counts live only in the documentation.
        if lower.hasSuffix("ckss") { return 2 }
        if lower.contains("nkk") { return 3 }
        return nil
    }

    private static func role(for name: String) -> ComponentRole? {
        switch name {
        case "createParam", "createParamCentered":   return .param
        case "createInput", "createInputCentered":   return .input
        case "createOutput", "createOutputCentered": return .output
        case "createLight", "createLightCentered":   return .light
        // createWidget is how screws and other decoration are added. Those are
        // artwork here, which is right: Rack draws them, but nothing binds to
        // them and no enum mentions them.
        case "createWidget", "createWidgetCentered": return .decoration
        default: return nil
        }
    }

    /// `Muse::X_ATTEN_PARAM` → `X_ATTEN`. The suffix is re-added on export from
    /// the role, so keeping it here would generate `X_ATTEN_PARAM_PARAM`.
    private static func enumStem(_ raw: String, role: ComponentRole) -> String {
        // `Mod::IN_INPUT + 2`, from an unrolled loop: the third of a family,
        // named IN_3 so the generated enum reads like the original array.
        let plus = raw.components(separatedBy: "+")
        if plus.count == 2, let n = Int(plus[1].trimmingCharacters(in: .whitespacesAndNewlines)) {
            return enumStem(plus[0], role: role) + "_\(n + 1)"
        }
        var s = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if let last = s.components(separatedBy: "::").last { s = last }
        s = s.trimmingCharacters(in: .whitespacesAndNewlines)
        let suffix = role.enumSuffix
        if !suffix.isEmpty, s.hasSuffix(suffix) { s.removeLast(suffix.count) }
        return s
    }

    /// What to draw for a Rack widget type. The name is all there is to go on,
    /// and it is enough: nobody calls a jack "Knob".
    private static func kind(for widget: String, role: ComponentRole) -> ElementKind {
        let w = widget.lowercased()
        if w.contains("port") || w.contains("jack") { return .jack }
        if w.contains("light") || w.contains("led") { return .led }
        if w.contains("screw") { return .screw }
        if w.contains("slider") || w.contains("fader") || w.contains("slidepot") { return .faderVertical }
        if w.contains("switch") || w.contains("ckss") || w.contains("nkk") { return .buttonGroup }
        if w.contains("button") || w.contains("latch") || w.contains("bezel")
            || w.contains("push") || w.contains("ckd") { return .pushButton }
        if w.contains("large") || w.contains("big") || w.contains("huge") { return .knobLarge }
        if w.contains("small") || w.contains("tiny") || w.contains("trimpot")
            || w.contains("atten") { return .knobSmall }
        if w.contains("knob") || w.contains("pot") { return .knobMedium }

        switch role {
        case .param:  return .knobMedium
        case .input, .output: return .jack
        case .light:  return .led
        default:      return .screw
        }
    }

    // MARK: - Positions

    /// `mm2px(Vec(15.24, 38.95))` or a bare `Vec(x, y)` in panel pixels.
    ///
    /// The distinction is not cosmetic: read a millimetre position as pixels
    /// and every component lands at a third of its proper place.
    package static func position(_ text: String, table: [String: CGFloat]) -> CGPoint? {
        // Vec arithmetic: `centre.plus(mm2px(Vec(0, 3)))`, `a.minus(b)`.
        let chained = splitVecChain(stripOuterParens(text.trimmingCharacters(in: .whitespacesAndNewlines)))
        if chained.count > 1 {
            guard var p = position(chained[0].1, table: table) else { return nil }
            for (op, term) in chained.dropFirst() {
                guard let q = position(term, table: table) else { return nil }
                p = op == "plus" ? CGPoint(x: p.x + q.x, y: p.y + q.y) : CGPoint(x: p.x - q.x, y: p.y - q.y)
            }
            return p
        }
        var trimmed = stripOuterParens(text.trimmingCharacters(in: .whitespacesAndNewlines))
        for prefix in ["rack::math::", "rack::window::", "rack::", "math::", "window::"] {
            trimmed = trimmed.replacingOccurrences(of: prefix, with: "")
        }

        // Helpers plugins define for the same thing: Sanguine's
        // millimetersToPixelsVec(x, y), and mm2px applied per coordinate.
        for helper in ["millimetersToPixelsVec", "mm2pxVec", "mmVec"] {
            if let inner = call(named: helper, in: trimmed), let p = pair(inner, table: table) {
                return CGPoint(x: p.x / PanelMetrics.mmPerPixel, y: p.y / PanelMetrics.mmPerPixel)
            }
        }
        if let vec = call(named: "Vec", in: trimmed) {
            let parts = splitTopLevel(vec)
            if parts.count == 2,
               let xs = call(named: "mm2px", in: parts[0]), let ys = call(named: "mm2px", in: parts[1]),
               let x = Expression.evaluate(xs, constants: table), let y = Expression.evaluate(ys, constants: table) {
                return CGPoint(x: x / PanelMetrics.mmPerPixel, y: y / PanelMetrics.mmPerPixel)
            }
        }

        if let inner = call(named: "mm2px", in: trimmed),
           let vec = call(named: "Vec", in: inner.trimmingCharacters(in: .whitespacesAndNewlines)),
           let p = pair(vec, table: table) {
            return CGPoint(x: p.x / PanelMetrics.mmPerPixel, y: p.y / PanelMetrics.mmPerPixel)
        }
        if let vec = call(named: "Vec", in: trimmed), let p = pair(vec, table: table) {
            return p
        }
        return nil
    }

    private static func pair(_ text: String, table: [String: CGFloat]) -> CGPoint? {
        let parts = splitTopLevel(text)
        guard parts.count >= 2,
              let x = Expression.evaluate(parts[0], constants: table),
              let y = Expression.evaluate(parts[1], constants: table) else { return nil }
        return CGPoint(x: x, y: y)
    }

    /// The argument text of `name(...)` when `text` is exactly that call.
    private static func call(named name: String, in text: String) -> String? {
        guard text.hasPrefix(name) else { return nil }
        let after = text.dropFirst(name.count).drop { $0 == " " }
        guard after.first == "(" else { return nil }
        let chars = Array(after)
        guard let close = matching(chars, from: 0, open: "(", close: ")") else { return nil }
        return String(chars[1..<close])
    }

    private static func boxSize(in text: String, table: [String: CGFloat]) -> CGFloat? {
        guard let range = text.range(of: "box.size") else { return nil }
        let rest = text[range.upperBound...]
        guard let eq = rest.firstIndex(of: "="), let semi = rest.firstIndex(of: ";"), eq < semi else { return nil }
        let expression = String(rest[rest.index(after: eq)..<semi]).trimmingCharacters(in: .whitespaces)
        guard let p = position(expression, table: table) else { return nil }
        return p.x
    }

    // MARK: - Constants

    private static func merge(_ table: inout [String: CGFloat], _ new: [String: CGFloat]) {
        for (k, v) in new where table[k] == nil { table[k] = v }
    }

    /// `constexpr float PRIMARY_Y = 27.2f;` and its relatives, resolved in a
    /// few passes so a constant defined in terms of another one lands.
    package static func constants(in text: String) -> [String: CGFloat] {
        // A declaration may hold several declarators, and arrays:
        //   constexpr float JACK_X0 = 9.4f, JACK_PITCH = 11.f;
        //   constexpr float laneY[5] = {27.2f, 48.2f, 69.2f, 90.2f, 111.2f};
        let patterns = [
            #"(?:static\s+)?(?:inline\s+)?constexpr\s+(?:float|double|int|unsigned|size_t|auto)\s+([^;]+);"#,
            #"(?:static\s+)?const\s+(?:float|double|int|unsigned|size_t)\s+([^;]+);"#,
        ]
        var pending: [(String, String)] = []
        for pattern in patterns {
            guard let re = try? NSRegularExpression(pattern: pattern) else { continue }
            let ns = text as NSString
            for m in re.matches(in: text, range: NSRange(location: 0, length: ns.length)) where m.numberOfRanges == 2 {
                pending.append(contentsOf: declarators(ns.substring(with: m.range(at: 1))))
            }
        }
        if let re = try? NSRegularExpression(pattern: #"#define\s+(\w+)\s+([^\n]+)"#) {
            let ns = text as NSString
            for m in re.matches(in: text, range: NSRange(location: 0, length: ns.length)) where m.numberOfRanges == 3 {
                pending.append((ns.substring(with: m.range(at: 1)), ns.substring(with: m.range(at: 2))))
            }
        }

        var table: [String: CGFloat] = [:]
        for _ in 0..<4 {
            var progressed = false
            for (name, expression) in pending where table[name] == nil {
                var scope = builtinConstants
                for (k, v) in table { scope[k] = v }
                if let v = Expression.evaluate(expression, constants: scope) {
                    table[name] = v
                    progressed = true
                }
            }
            if !progressed { break }
        }
        return table
    }

    /// `A = 1, B = A + 2, C[3] = {1, 2, 3}` → (A, 1), (B, A + 2), (C[0], 1) …
    static func declarators(_ list: String) -> [(String, String)] {
        var out: [(String, String)] = []
        for part in splitTopLevel(list) {
            guard let eq = part.firstIndex(of: "=") else { continue }
            var name = part[..<eq].trimmingCharacters(in: .whitespacesAndNewlines)
            let value = part[part.index(after: eq)...].trimmingCharacters(in: .whitespacesAndNewlines)
            if let bracket = name.firstIndex(of: "[") {
                name = String(name[..<bracket]).trimmingCharacters(in: .whitespaces)
                guard value.hasPrefix("{"), value.hasSuffix("}") else { continue }
                for (i, item) in splitTopLevel(String(value.dropFirst().dropLast())).enumerated() {
                    out.append(("\(name)[\(i)]", item))
                }
            } else if name.range(of: #"^\w+$"#, options: .regularExpression) != nil {
                out.append((name, value))
            }
        }
        return out
    }

    /// `a.plus(b).minus(c)` → [("", a), ("plus", b), ("minus", c)], split at
    /// the top level only.
    /// `((x))` → `x`, only when the outer pair encloses the whole text.
    static func stripOuterParens(_ s: String) -> String {
        var t = s
        while t.hasPrefix("("), let close = matching(Array(t), from: 0, open: "(", close: ")"), close == t.count - 1 {
            t = String(t.dropFirst().dropLast()).trimmingCharacters(in: .whitespacesAndNewlines)
        }
        return t
    }

    static func splitVecChain(_ s: String) -> [(String, String)] {
        let chars = Array(s)
        var out: [(String, String)] = []
        var depth = 0, i = 0
        var base: String?
        while i < chars.count {
            let c = chars[i]
            if c == "(" { depth += 1 } else if c == ")" { depth -= 1 }
            if depth == 0, c == "." {
                var matched = false
                for name in ["plus", "minus"] {
                    let n = Array(name + "(")
                    let open = i + 1 + name.count
                    guard open < chars.count, Array(chars[(i + 1)...open]) == n,
                          let close = matching(chars, from: open, open: "(", close: ")") else { continue }
                    if base == nil { base = String(chars[0..<i]) }
                    out.append((name, String(chars[(open + 1)..<close])))
                    i = close + 1
                    matched = true
                    // Only another .plus/.minus may follow.
                    if i < chars.count, chars[i] != "." {
                        let rest = String(chars[i...]).trimmingCharacters(in: .whitespacesAndNewlines)
                        if !rest.isEmpty { return [("", s)] }
                    }
                    break
                }
                if matched { continue }
                if base != nil { return [("", s)] }
            } else if base != nil, depth == 0, !c.isWhitespace {
                return [("", s)]
            }
            i += 1
        }
        guard let b = base, !out.isEmpty else { return [("", s)] }
        return [("", b)] + out
    }

    // MARK: - Plugin helpers, string arrays, own types

    struct Helper {
        var params: [(name: String, defaultValue: String?)]
        var body: String
    }

    /// `inline void name(params) { body }` whose body places controls or
    /// labels, keyed by name. Pure label forwarders (`addCvLabel` → `addLabel`)
    /// are left alone: their call sites are read as labels directly.
    static func inlinableHelpers(in texts: [String]) -> [String: Helper] {
        let forwarders = Set(texts.flatMap { labelHelpers(in: $0).keys })
        guard let re = try? NSRegularExpression(pattern: #"(?:static\s+)?inline\s+(?:void|\w+\s*\*)\s+(\w+)\s*\("#)
        else { return [:] }
        var out: [String: Helper] = [:]
        for text in texts {
            let ns = text as NSString
            let u = Array(text.utf16)
            for m in re.matches(in: text, range: NSRange(location: 0, length: ns.length)) {
                let name = ns.substring(with: m.range(at: 1))
                guard !forwarders.contains(name), out[name] == nil else { continue }
                // Parameter list, then the body's braces, in UTF-16 units.
                var j = m.range.location + m.range.length, depth = 1
                let paramStart = j
                while j < u.count, depth > 0 { if u[j] == 40 { depth += 1 } else if u[j] == 41 { depth -= 1 }; j += 1 }
                let params = ns.substring(with: NSRange(location: paramStart, length: max(0, j - 1 - paramStart)))
                while j < u.count, u[j] != 123, u[j] != 59 { j += 1 }
                guard j < u.count, u[j] == 123 else { continue }
                let bodyStart = j
                depth = 0
                var end = -1
                while j < u.count {
                    if u[j] == 123 { depth += 1 } else if u[j] == 125 { depth -= 1; if depth == 0 { end = j; break } }
                    j += 1
                }
                guard end > bodyStart else { continue }
                let body = ns.substring(with: NSRange(location: bodyStart + 1, length: end - bodyStart - 1))
                guard body.contains("create") || body.contains("add") else { continue }
                let names: [(String, String?)] = splitTopLevel(params).compactMap { p in
                    let parts = p.split(separator: "=", maxSplits: 1).map { $0.trimmingCharacters(in: .whitespaces) }
                    guard let decl = parts.first,
                          let n = decl.range(of: #"\w+\s*$"#, options: .regularExpression).map({ String(decl[$0]).trimmingCharacters(in: .whitespaces) })
                    else { return nil }
                    return (n, parts.count > 1 ? parts[1] : nil)
                }
                out[name] = Helper(params: names, body: body)
            }
        }
        return out
    }

    /// Replaces calls to `helpers` from the widget onwards with their bodies,
    /// parameters substituted, two levels deep. Line breaks inside a call are
    /// kept as trailing newlines so later line numbers do not move.
    static func inlineHelpers(_ source: String, helpers: [String: Helper]) -> String {
        guard !helpers.isEmpty else { return source }
        var text = source
        for _ in 0..<2 {
            let found = calls(in: text)
            let ns = text as NSString
            let begin = ns.range(of: "ModuleWidget").location
            guard begin != NSNotFound else { return text }
            var replacements: [(NSRange, String)] = []
            for call in found where call.offset > begin {
                guard let h = helpers[call.name] else { continue }
                // The call's extent: from its name to the matching parenthesis.
                let u = Array(text.utf16)
                var j = call.offset
                while j < u.count, u[j] != 40 { j += 1 }
                var depth = 0, end = -1
                while j < u.count {
                    if u[j] == 40 { depth += 1 } else if u[j] == 41 { depth -= 1; if depth == 0 { end = j; break } }
                    j += 1
                }
                guard end > 0 else { continue }
                // Include a qualifier written before the name (spacetime::).
                var start = call.offset
                while start >= 2, u[start - 1] == 58, u[start - 2] == 58 {
                    var k = start - 2
                    while k > 0, let s = UnicodeScalar(u[k - 1]), CharacterSet.alphanumerics.contains(s) || u[k - 1] == 95 { k -= 1 }
                    start = k
                }
                var body = h.body
                for (i, p) in h.params.enumerated() {
                    let arg = i < call.args.count ? call.args[i] : (p.defaultValue ?? "0")
                    let value = arg.rangeOfCharacter(from: CharacterSet(charactersIn: "+-*/ ")) != nil
                        && !arg.hasPrefix("\"") ? "(\(arg))" : arg
                    guard let re = try? NSRegularExpression(pattern: #"(?<![\w.>])"# + NSRegularExpression.escapedPattern(for: p.name) + #"(?!\w)"#)
                    else { continue }
                    body = re.stringByReplacingMatches(in: body, range: NSRange(location: 0, length: (body as NSString).length),
                                                       withTemplate: NSRegularExpression.escapedTemplate(for: value))
                }
                let original = ns.substring(with: NSRange(location: start, length: end + 1 - start))
                let newlines = original.filter { $0 == "\n" }.count
                let flat = body.replacingOccurrences(of: "\n", with: " ")
                replacements.append((NSRange(location: start, length: end + 1 - start),
                                     "{ " + flat + " }" + String(repeating: "\n", count: newlines)))
            }
            guard !replacements.isEmpty else { break }
            let m = NSMutableString(string: text)
            for (r, s) in replacements.sorted(by: { $0.0.location > $1.0.location }) {
                m.replaceCharacters(in: r, with: s)
            }
            text = m as String
        }
        return text
    }

    /// `static const char* in1[4] = {"START", "STOP"};` → in1[0] = START, …
    static func stringArrays(in texts: [String]) -> [String: String] {
        guard let re = try? NSRegularExpression(pattern: #"(\w+)\s*\[\s*\w*\s*\]\s*=\s*\{([^{}]*)\}"#) else { return [:] }
        var out: [String: String] = [:]
        for text in texts {
            let ns = text as NSString
            for m in re.matches(in: text, range: NSRange(location: 0, length: ns.length)) {
                let name = ns.substring(with: m.range(at: 1))
                let items = splitTopLevel(ns.substring(with: m.range(at: 2)))
                guard !items.isEmpty, items.allSatisfy({ $0.hasPrefix("\"") }) else { continue }
                for (i, item) in items.enumerated() {
                    if let s = stringLiterals(in: item).first { out["\(name)[\(i)]"] = s }
                }
            }
        }
        return out
    }

    /// Names of the structs the plugin itself defines.
    static func definedTypes(in texts: [String]) -> Set<String> {
        guard let re = try? NSRegularExpression(pattern: #"\bstruct\s+(\w+)\s*(?::[^{;]*)?\{"#) else { return [] }
        var out = Set<String>()
        for text in texts {
            let ns = text as NSString
            for m in re.matches(in: text, range: NSRange(location: 0, length: ns.length)) {
                out.insert(ns.substring(with: m.range(at: 1)))
            }
        }
        return out
    }

    // MARK: - Locals and loops

    struct Assignment {
        var name: String
        var op: String
        var expression: String
        var offset: Int
    }

    /// Assignments to plain variables, in source order: `float y = 30.f;`,
    /// `y += 10.f;`, `float a = 1, b = 2;`. Member and pointer assignments
    /// (`box.size = …`, `w->x = …`) and comparisons are not matched.
    static func localAssignments(in text: String, from start: Int = 0) -> [Assignment] {
        let pattern = #"(?<![\w.>:])((?:(?:const|constexpr|static)\s+)*(?:float|double|int|unsigned|auto|size_t)\s+)?\b([A-Za-z_]\w*(?:\s*\[\s*\d+\s*\])?)\s*(\+=|-=|\*=|/=|=)(?!=)\s*([^;{}]+);"#
        guard let re = try? NSRegularExpression(pattern: pattern) else { return [] }
        let ns = text as NSString
        var out: [Assignment] = []
        for m in re.matches(in: text, range: NSRange(location: start, length: ns.length - start)) {
            let typed = m.range(at: 1).location != NSNotFound
            let name = ns.substring(with: m.range(at: 2)).replacingOccurrences(of: " ", with: "")
            let op = ns.substring(with: m.range(at: 3))
            let rhs = ns.substring(with: m.range(at: 4))
            let offset = m.range.location
            if typed && op == "=" {
                // `float a = 1, b = 2;` — the regex caught `a = 1, b = 2`.
                for (n, e) in declarators(name + " = " + rhs) {
                    out.append(Assignment(name: n, op: "=", expression: e, offset: offset))
                }
            } else {
                out.append(Assignment(name: name, op: op, expression: rhs, offset: offset))
            }
        }
        return out
    }

    /// Unrolls `for` loops whose bounds evaluate to constants and whose body
    /// creates widgets, substituting the loop variable's value into each copy.
    /// Inner loops first, at most 64 iterations per loop. Line numbers after
    /// a loop are preserved: copies after the first are joined onto one line.
    static func unrollLoops(_ source: String, table: [String: CGFloat]) -> (String, [String]) {
        var text = source
        var warnings: [String] = []
        let header = try? NSRegularExpression(pattern:
            #"\bfor\s*\(\s*(?:int|unsigned|size_t|auto|long)?\s*(\w+)\s*=\s*([^;]+);\s*(\w+)\s*(<=|<|!=)\s*([^;]+);\s*(?:(\w+)\s*\+\+|\+\+\s*(\w+)|(\w+)\s*\+=\s*([^)]+))\s*\)"#)
        guard let header else { return (text, warnings) }
        // One pass, last header first. Unrolling a loop only changes text at
        // and after its own header, so the offsets of earlier headers stay
        // valid, and an inner loop is always unrolled before its outer one.
        let begin = (text as NSString).range(of: "ModuleWidget").location
        let from = begin == NSNotFound ? 0 : begin
        let starts = header.matches(in: text, range: NSRange(location: from, length: (text as NSString).length - from))
            .map { $0.range.location }
        for location in starts.reversed() {
            let ns = text as NSString
            guard let m = header.firstMatch(in: text, range: NSRange(location: location, length: ns.length - location)),
                  m.range.location == location else { continue }
            let variable = ns.substring(with: m.range(at: 1))
            // Work in UTF-16 throughout, the unit NSRegularExpression ranges use.
            let u = Array(text.utf16)
            func isSpace(_ c: UInt16) -> Bool { c == 32 || c == 9 || c == 10 || c == 13 }
            var bodyStart = m.range.location + m.range.length
            while bodyStart < u.count, isSpace(u[bodyStart]) { bodyStart += 1 }
            var bodyEnd = -1
            if bodyStart < u.count, u[bodyStart] == 123 {          // {
                var depth = 0, j = bodyStart, inString = false
                while j < u.count {
                    let c = u[j]
                    if inString {
                        if c == 92 { j += 2; continue }            // backslash
                        if c == 34 { inString = false }
                    } else if c == 34 { inString = true
                    } else if c == 123 { depth += 1
                    } else if c == 125 { depth -= 1; if depth == 0 { bodyEnd = j + 1; break } }
                    j += 1
                }
            } else if let semi = u[bodyStart...].firstIndex(of: 59) {   // ;
                bodyEnd = semi + 1
            }
            guard bodyEnd > bodyStart else { continue }
            let body = ns.substring(with: NSRange(location: bodyStart, length: bodyEnd - bodyStart))
            // Loops that place widgets, or labels through a helper (`addIoLabel`).
            guard body.contains("create") || body.contains("add"), ns.substring(with: m.range(at: 3)) == variable,
                  let start = Expression.evaluate(ns.substring(with: m.range(at: 2)), constants: table),
                  let bound = Expression.evaluate(ns.substring(with: m.range(at: 5)), constants: table)
            else { continue }
            let op = ns.substring(with: m.range(at: 4))
            var step: CGFloat = 1
            if m.range(at: 9).location != NSNotFound {
                guard let s = Expression.evaluate(ns.substring(with: m.range(at: 9)), constants: table), s > 0
                else { continue }
                step = s
            }
            var values: [Int] = []
            var v = start
            while (op == "<=" ? v <= bound : v < bound), values.count <= 64 {
                values.append(Int(v.rounded()))
                v += step
            }
            guard values.count <= 64 else {
                warnings.append("A loop over \(variable) creating widgets runs more than 64 times; it was not unrolled.")
                continue
            }
            let word = try? NSRegularExpression(pattern: #"(?<![\w.>])"# + NSRegularExpression.escapedPattern(for: variable) + #"(?!\w)"#)
            var copies: [String] = []
            for (i, value) in values.enumerated() {
                let range = NSRange(location: 0, length: (body as NSString).length)
                var copy = word?.stringByReplacingMatches(in: body, range: range, withTemplate: "\(value)") ?? body
                if i > 0 { copy = copy.replacingOccurrences(of: "\n", with: " ") }
                copies.append(copy)
            }
            // Braced, so an enclosing brace-less loop still sees one statement.
            let replacement = "{ " + copies.joined(separator: " ") + " }"
            text = ns.replacingCharacters(in: NSRange(location: m.range.location, length: bodyEnd - m.range.location),
                                          with: replacement)
        }
        return (text, warnings)
    }

    // MARK: - Preprocessor and comments

    /// Comments out, and `#ifdef METAMODULE` resolved to its Rack branch.
    ///
    /// A ported module keeps both builds in one file, and reading both would
    /// import the same panel twice. METAMODULE is taken as undefined, because
    /// the Rack branch is the one whose positions are authoritative; any other
    /// condition keeps its first branch and says so.
    package static func preprocess(_ source: String) -> (text: String, warnings: [String]) {
        var warnings: [String] = []
        let uncommented = stripComments(source)

        var out: [String] = []
        // Each entry: is this branch being kept, and has a kept branch been
        // taken yet in this #if chain?
        var stack: [(keeping: Bool, taken: Bool)] = []
        var sawUnknown = false

        func active() -> Bool { stack.allSatisfy { $0.keeping } }

        for line in uncommented.components(separatedBy: "\n") {
            let t = line.trimmingCharacters(in: .whitespaces)
            if t.hasPrefix("#if") || t.hasPrefix("#el") || t.hasPrefix("#endif") {
                if t.hasPrefix("#ifdef") || t.hasPrefix("#ifndef") || t.hasPrefix("#if") {
                    let negated = t.hasPrefix("#ifndef")
                    let mentionsMetaModule = t.contains("METAMODULE")
                    var keep = true
                    if mentionsMetaModule {
                        // #ifdef METAMODULE is dropped; #ifndef and
                        // #if !defined(METAMODULE) are the Rack branch and stay.
                        keep = negated || t.contains("!defined")
                    } else if t.hasPrefix("#if ") && !t.contains("defined") {
                        sawUnknown = true
                    }
                    stack.append((keeping: keep, taken: keep))
                } else if t.hasPrefix("#else") {
                    if var last = stack.popLast() {
                        last.keeping = !last.taken
                        last.taken = last.taken || last.keeping
                        stack.append(last)
                    }
                } else if t.hasPrefix("#elif") {
                    if var last = stack.popLast() {
                        last.keeping = !last.taken
                        last.taken = last.taken || last.keeping
                        stack.append(last)
                    }
                    sawUnknown = true
                } else if t.hasPrefix("#endif") {
                    _ = stack.popLast()
                }
                out.append("")          // keep line numbers honest
                continue
            }
            out.append(active() ? line : "")
        }

        if uncommented.contains("METAMODULE") {
            warnings.append("This file builds for both Rack and MetaModule. The Rack branch was read; "
                + "positions inside #ifdef METAMODULE were skipped.")
        }
        if sawUnknown {
            warnings.append("Conditional compilation other than METAMODULE was resolved by keeping the "
                + "first branch. If the module has variants, check the result against the one you want.")
        }
        return (out.joined(separator: "\n"), warnings)
    }

    /// Comments out, string and character literals intact, newlines kept so
    /// the line numbers in warnings still point at the source.
    package static func stripComments(_ s: String) -> String {
        let chars = Array(s)
        var out = ""
        out.reserveCapacity(chars.count)
        var i = 0

        while i < chars.count {
            let c = chars[i]
            let next = i + 1 < chars.count ? chars[i + 1] : "\0"

            if c == "\"" || c == "'" {
                let quote = c
                out.append(c)
                i += 1
                while i < chars.count {
                    if chars[i] == "\\", i + 1 < chars.count {
                        out.append(chars[i]); out.append(chars[i + 1])
                        i += 2
                        continue
                    }
                    out.append(chars[i])
                    let closed = chars[i] == quote
                    i += 1
                    if closed { break }
                }
                continue
            }

            if c == "/" && next == "/" {
                while i < chars.count, chars[i] != "\n" { i += 1 }
                continue
            }

            if c == "/" && next == "*" {
                i += 2
                while i < chars.count {
                    if chars[i] == "*", i + 1 < chars.count, chars[i + 1] == "/" {
                        i += 2
                        break
                    }
                    if chars[i] == "\n" { out.append("\n") }
                    i += 1
                }
                continue
            }

            out.append(c)
            i += 1
        }
        return out
    }

    // MARK: - Call scanning

    package struct Call {
        package var name: String
        package var template: String
        package var args: [String]
        package var line: Int
        /// Character offset in the scanned text, for ordering against
        /// assignments to locals.
        package var offset: Int = 0
        package var isCentered: Bool { name.hasSuffix("Centered") }
    }

    /// Every `name<T>(args)` call in the text, outer before inner.
    ///
    /// Scanning continues from just after each name rather than past the call,
    /// which matters more than it looks: the calls that carry the positions are
    /// nested inside others — `addParam(createParamCentered<T>(…))` — and a
    /// scanner that consumed the outer call would never see the inner one.
    /// Recording calls we have no use for is cheaper than missing those.
    package static func calls(in text: String) -> [Call] {
        let chars = Array(text)
        var lineOf: [Int] = []
        var running = 1
        lineOf.reserveCapacity(chars.count + 1)
        for c in chars { lineOf.append(running); if c == "\n" { running += 1 } }
        lineOf.append(running)

        var out: [Call] = []
        var i = 0
        while i < chars.count {
            guard isIdentifierStart(chars[i]) else { i += 1; continue }
            var j = i
            while j < chars.count, isIdentifier(chars[j]) { j += 1 }
            let name = String(chars[i..<j])

            var k = skipSpace(chars, j)
            var template = ""
            if k < chars.count, chars[k] == "<",
               let close = matching(chars, from: k, open: "<", close: ">") {
                template = String(chars[(k + 1)..<close]).trimmingCharacters(in: .whitespacesAndNewlines)
                k = skipSpace(chars, close + 1)
            }
            if k < chars.count, chars[k] == "(",
               let close = matching(chars, from: k, open: "(", close: ")") {
                out.append(Call(name: name, template: template,
                                args: splitTopLevel(String(chars[(k + 1)..<close])),
                                line: lineOf[i], offset: i))
            }
            i = j
        }
        return out
    }

    // MARK: - Text helpers

    private static func isIdentifierStart(_ c: Character) -> Bool { c.isLetter || c == "_" }
    private static func isIdentifier(_ c: Character) -> Bool { c.isLetter || c.isNumber || c == "_" }

    private static func skipSpace(_ chars: [Character], _ from: Int) -> Int {
        var i = from
        while i < chars.count, chars[i] == " " || chars[i] == "\n" || chars[i] == "\t" || chars[i] == "\r" {
            i += 1
        }
        return i
    }

    /// Index of the bracket matching the one at `from`, or nil.
    private static func matching(_ chars: [Character], from: Int, open: Character, close: Character) -> Int? {
        guard from < chars.count, chars[from] == open else { return nil }
        var depth = 0
        var i = from
        var inString = false
        while i < chars.count {
            let c = chars[i]
            if inString {
                if c == "\\" { i += 2; continue }
                if c == "\"" { inString = false }
                i += 1
                continue
            }
            if c == "\"" { inString = true; i += 1; continue }
            if c == open { depth += 1 }
            if c == close {
                depth -= 1
                if depth == 0 { return i }
            }
            i += 1
        }
        return nil
    }

    /// Split on commas that are not inside brackets or a string.
    package static func splitTopLevel(_ text: String) -> [String] {
        var parts: [String] = []
        var current = ""
        var depth = 0
        var inString = false
        var previous: Character = " "
        for c in text {
            if inString {
                current.append(c)
                if c == "\"" && previous != "\\" { inString = false }
                previous = c
                continue
            }
            switch c {
            case "\"": inString = true; current.append(c)
            case "(", "[", "{", "<": depth += 1; current.append(c)
            case ")", "]", "}", ">": depth -= 1; current.append(c)
            case "," where depth == 0:
                parts.append(current.trimmingCharacters(in: .whitespacesAndNewlines))
                current = ""
            default: current.append(c)
            }
            previous = c
        }
        let last = current.trimmingCharacters(in: .whitespacesAndNewlines)
        if !last.isEmpty { parts.append(last) }
        return parts
    }

    private static func stringLiterals(in text: String) -> [String] {
        var out: [String] = []
        var current = ""
        var inString = false
        var previous: Character = " "
        for c in text {
            if inString {
                if c == "\"" && previous != "\\" {
                    inString = false
                    if !current.isEmpty { out.append(current) }
                    current = ""
                } else {
                    current.append(c)
                }
            } else if c == "\"" {
                inString = true
                current = ""
            }
            previous = c
        }
        return out
    }

    private static func condensed(_ text: String) -> String {
        let flat = text.components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty }.joined(separator: " ")
        return flat.count > 60 ? String(flat.prefix(57)) + "…" : flat
    }
}

// MARK: - Arithmetic

/// A four-function evaluator over numbers and named constants.
///
/// Panel positions are written as `7.0f`, `RACK_GRID_WIDTH * 2`,
/// `grid::PRIMARY_Y`, `panelW / 2` — arithmetic simple enough to evaluate and
/// too common to refuse. Anything it cannot resolve returns nil, which becomes
/// a skipped component and a warning naming the line.
package enum Expression {

    package static func evaluate(_ text: String, constants: [String: CGFloat]) -> CGFloat? {
        var parser = Parser(text: text, constants: constants)
        guard let v = parser.expression(), parser.atEnd else { return nil }
        return v
    }

    private struct Parser {
        let chars: [Character]
        let constants: [String: CGFloat]
        var i = 0

        init(text: String, constants: [String: CGFloat]) {
            chars = Array(text)
            self.constants = constants
        }

        var atEnd: Bool {
            var j = i
            while j < chars.count, chars[j].isWhitespace { j += 1 }
            return j >= chars.count
        }

        mutating func skip() {
            while i < chars.count, chars[i].isWhitespace { i += 1 }
        }

        mutating func expression() -> CGFloat? {
            guard var value = term() else { return nil }
            while true {
                skip()
                guard i < chars.count, chars[i] == "+" || chars[i] == "-" else { return value }
                let op = chars[i]
                i += 1
                guard let rhs = term() else { return nil }
                value = op == "+" ? value + rhs : value - rhs
            }
        }

        mutating func term() -> CGFloat? {
            guard var value = factor() else { return nil }
            while true {
                skip()
                guard i < chars.count, chars[i] == "*" || chars[i] == "/" else { return value }
                let op = chars[i]
                i += 1
                guard let rhs = factor() else { return nil }
                if op == "/" {
                    guard abs(rhs) > 1e-12 else { return nil }
                    value /= rhs
                } else {
                    value *= rhs
                }
            }
        }

        mutating func factor() -> CGFloat? {
            skip()
            guard i < chars.count else { return nil }

            if chars[i] == "-" { i += 1; guard let v = factor() else { return nil }; return -v }
            if chars[i] == "+" { i += 1; return factor() }

            if chars[i] == "(" {
                // A C-style cast, `(float) x` or `(int)i`: the type changes nothing here.
                for cast in ["(float)", "(double)", "(int)", "(unsigned)"] {
                    let c = Array(cast)
                    if i + c.count <= chars.count, Array(chars[i..<(i + c.count)]) == c {
                        i += c.count
                        return factor()
                    }
                }
                i += 1
                guard let v = expression() else { return nil }
                skip()
                guard i < chars.count, chars[i] == ")" else { return nil }
                i += 1
                return v
            }

            // A cast, as in `(float) x` — already handled by the parenthesis
            // branch failing, so nothing to do but refuse.

            if chars[i].isNumber || chars[i] == "." {
                let start = i
                while i < chars.count, chars[i].isNumber || chars[i] == "." { i += 1 }
                // Float and unsigned suffixes: 7.0f, 12u, 3L.
                while i < chars.count, "fFuUlL".contains(chars[i]) { i += 1 }
                let text = String(chars[start..<i]).trimmingCharacters(in: CharacterSet(charactersIn: "fFuUlL"))
                guard let v = Double(text) else { return nil }
                return CGFloat(v)
            }

            if chars[i].isLetter || chars[i] == "_" {
                let start = i
                // Dots belong to the name: `box.size.x` is one thing to look
                // up, not an identifier followed by punctuation. A number never
                // reaches here — the digit branch above takes it — so this
                // cannot swallow a decimal point.
                while i < chars.count, chars[i].isLetter || chars[i].isNumber
                    || chars[i] == "_" || chars[i] == ":" || chars[i] == "." {
                    i += 1
                }
                var raw = String(chars[start..<i])
                if raw.hasPrefix("static_cast") || raw.hasPrefix("float") || raw.hasPrefix("double")
                    || raw.hasPrefix("int") {
                    // static_cast<float>(x), float(x)
                    var j = i
                    if raw == "static_cast", j < chars.count, chars[j] == "<",
                       let close = chars[j...].firstIndex(of: ">") { j = close + 1 }
                    while j < chars.count, chars[j].isWhitespace { j += 1 }
                    if ["static_cast", "float", "double", "int"].contains(raw), j < chars.count, chars[j] == "(" {
                        i = j
                        return factor()
                    }
                }
                // A subscript into a constant array: laneY[2].
                skip()
                if i < chars.count, chars[i] == "[" {
                    i += 1
                    guard let index = expression() else { return nil }
                    skip()
                    guard i < chars.count, chars[i] == "]" else { return nil }
                    i += 1
                    raw += "[\(Int(index.rounded()))]"
                }
                // A qualified name is looked up by its last component:
                // museui::grid::PRIMARY_Y is PRIMARY_Y wherever it was declared.
                let bare = raw.components(separatedBy: "::").last ?? raw
                return constants[raw] ?? constants[bare]
            }

            return nil
        }
    }
}
