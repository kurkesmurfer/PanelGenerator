import Foundation
import CoreGraphics

/// Generates the C++ that pairs with an exported panel.
///
/// The document already holds every component's centre, kind and widget
/// binding — the expensive information. Emitting the widget code from the same
/// source as the artwork is what stops the two drifting apart, which is the
/// failure mode that eats an afternoon every time a panel is revised.
///
/// Idioms follow the Rack SDK and working plugin code rather than memory:
/// `window::Svg::load(asset::plugin(...))`; a knob as a static `bg` SvgWidget
/// below the TransformWidget with only the foreground rotating, exactly as
/// `RoundKnob` does it; `momentary` plus one `addFrame` per switch position;
/// `setHandlePosCentered` for a slider; and the `…Centered` constructors
/// throughout, which is also what MetaModule's `Coords::Center` expects.
enum CodeGen {

    // MARK: - Small helpers

    /// Millimetres, at helper.py's precision.
    static func mm3(_ v: CGFloat) -> String { String(format: "%.3f", Double(v)) }

    static func cppIdentifier(_ raw: String, fallback: String) -> String {
        var out = ""
        for ch in raw {
            if ch.isLetter || ch.isNumber || ch == "_" { out.append(ch) } else { out.append("_") }
        }
        while out.contains("__") { out = out.replacingOccurrences(of: "__", with: "_") }
        out = out.trimmingCharacters(in: CharacterSet(charactersIn: "_"))
        if let f = out.first, f.isNumber { out = "_" + out }
        return out.isEmpty ? fallback : out
    }

    /// PascalCase struct name to the hyphenated lowercase used for asset files
    /// (`KnobLarge` → `knob-large`).
    static func kebab(_ s: String) -> String {
        var out = ""
        var prevWasLowerOrDigit = false
        for ch in s {
            if ch == "_" || ch == " " || ch == "-" {
                out += "-"
                prevWasLowerOrDigit = false
                continue
            }
            if ch.isUppercase && prevWasLowerOrDigit { out += "-" }
            out += ch.lowercased()
            prevWasLowerOrDigit = ch.isLowercase || ch.isNumber
        }
        while out.contains("--") { out = out.replacingOccurrences(of: "--", with: "-") }
        return out.trimmingCharacters(in: CharacterSet(charactersIn: "-"))
    }

    /// Rack's own rule, from helper.py: ^[a-zA-Z0-9_\-]+$
    ///
    /// Worth checking here rather than leaving it to Rack, because a slug also
    /// becomes the panel's filename and the string in createModel — so an
    /// invalid one is wrong in three places at once and only fails at load.
    static func isValidSlug(_ slug: String) -> Bool {
        !slug.isEmpty && slug.allSatisfy { ch in
            (ch.isASCII && (ch.isLetter || ch.isNumber)) || ch == "_" || ch == "-"
        }
    }

    /// The nearest valid slug, for the "try this instead" half of the warning.
    /// A slug Rack will accept, from whatever was typed.
    ///
    /// Spaces become underscores rather than hyphens on purpose. A slug names
    /// two things that cannot both take a hyphen: the panel file
    /// (`res/<slug>.svg`, verbatim) and the C++ identifiers derived from it
    /// (`<Slug>_panel.hpp`, `<Slug>Panel`), where a hyphen is not a legal
    /// character and becomes an underscore anyway. Choose the hyphen and one
    /// panel is spelled two ways in one directory; choose the underscore and
    /// the slug, the filename and the C++ name are the same string.
    static func slugSuggestion(_ slug: String) -> String {
        var out = ""
        for ch in slug {
            if ch.isASCII && (ch.isLetter || ch.isNumber) { out.append(ch) }
            else if ch == "_" || ch == "-" { out.append(ch) }
            else if ch == " " || ch == "." || ch == "/" { out.append("_") }
        }
        while out.contains("__") { out = out.replacingOccurrences(of: "__", with: "_") }
        out = out.trimmingCharacters(in: CharacterSet(charactersIn: "-_"))
        return out.isEmpty ? "MyModule" : out
    }

    static func moduleIdentifier(_ doc: PanelDocument) -> String {
        cppIdentifier(doc.moduleSlug, fallback: "MyModule")
    }

    /// `museui::`, or empty when the document declares no namespace.
    /// A stamp naming the panel a generated file came from.
    ///
    /// Comparing two generated files is only meaningful when both came from the
    /// same document and the same version of this tool. Without a stamp, a
    /// stale file compares as a panel full of moved and missing components —
    /// which reads as a broken panel rather than an old file, and costs an hour
    /// before anyone checks the timestamps.
    static func provenance(_ doc: PanelDocument) -> String {
        "// PanelGenerator-Source: \(doc.name) · \(doc.components.count) components · digest \(digest(doc))"
    }

    /// Digest of the component contract — identifier, role, widget and position
    /// — not of the artwork. Two files agree when they place the same controls
    /// in the same places, whatever colour the panel is.
    ///
    /// FNV-1a rather than Hasher: Swift seeds Hasher per process, so the same
    /// document would stamp differently on every run.
    static func digest(_ doc: PanelDocument) -> String {
        let ids = identifiers(doc)
        var canonical = ""
        for el in doc.components {
            let p = doc.componentCentreMM(el)
            canonical += "\(ids[el.id] ?? el.identifierStem)\(el.role.enumSuffix)"
                + "|\(el.role.rawValue)|\(widgetClass(el))|\(mm3(p.x)),\(mm3(p.y));"
        }
        var hash: UInt64 = 0xcbf29ce484222325
        for byte in canonical.utf8 {
            hash ^= UInt64(byte)
            hash = hash &* 0x100000001b3
        }
        return String(format: "%08x", UInt32(truncatingIfNeeded: hash))
    }

    static func pluginIdentifier(_ doc: PanelDocument) -> String {
        cppIdentifier(doc.pluginSlug, fallback: "MyPlugin")
    }

    /// Namespace holding the plugin's widget library.
    ///
    /// One per plugin, not one per module: two modules that both use the same
    /// jack should compile to one struct and load one SVG, and a widget is a
    /// property of the plugin's visual language rather than of any module.
    static func uiNamespace(_ doc: PanelDocument) -> String {
        doc.widgetNamespace.isEmpty
            ? pluginIdentifier(doc).lowercased() + "ui"
            : cppIdentifier(doc.widgetNamespace, fallback: "ui")
    }

    static func widgetsHeaderName(_ doc: PanelDocument) -> String {
        pluginIdentifier(doc) + "Widgets.hpp"
    }

    static func widgetBaseHeaderName(_ doc: PanelDocument) -> String {
        pluginIdentifier(doc) + "WidgetBase.hpp"
    }

    /// The Rack base a widget needs, and so which of the plugin's own bases it
    /// derives from. One per family rather than one per widget: what a knob and
    /// a port need from a plugin's visual language differs, what two knobs need
    /// does not.
    enum WidgetFamily: String, CaseIterable {
        case knob = "KnobBase"
        case port = "PortBase"
        case toggle = "SwitchBase"
        case slider = "SliderBase"
        case plain = "PlainBase"

        var rackBase: String {
            switch self {
            case .knob:   return "app::SvgKnob"
            case .port:   return "app::SvgPort"
            case .toggle: return "app::SvgSwitch"
            case .slider: return "app::SvgSlider"
            case .plain:  return "widget::SvgWidget"
            }
        }
    }

    static func family(for el: PanelElement, in doc: PanelDocument) -> WidgetFamily {
        if doc.widgetMembers(of: el).count > 1 {
            switch composedBase(for: el, in: doc) {
            case "port":   return .port
            case "knob":   return .knob
            case "switch": return .toggle
            default:       return .plain
            }
        }
        switch el.role {
        case .input, .output: return .port
        case .param where el.kind.isKnob: return .knob
        case .param where el.kind == .faderVertical || el.kind == .faderHorizontal: return .slider
        case .param where isSwitch(el): return .toggle
        default: return .plain
        }
    }

    /// Written once and never overwritten. This is the seam: policy that every
    /// widget of a family shares lives here and is yours to edit, while the
    /// generated structs below hold only what PanelGenerator actually knows —
    /// which files to load. Regeneration cannot touch your edits because it
    /// never writes this file twice.
    static func widgetBaseHeader(_ doc: PanelDocument) -> String {
        let ns = uiNamespace(doc)
        return lines([
            "// Created once by PanelGenerator. YOURS TO EDIT — it is never overwritten.",
            "//",
            "// Every generated widget derives from one of these, so anything you put in a",
            "// base reaches all of that family and survives every regeneration. Theme",
            "// switching, shadows, tooltips, hover behaviour: here, not in the generated",
            "// file, which is rewritten on every emit.",
            "//",
            "// Delete this file to have it written again from scratch.",
            "",
            "#pragma once",
            "#include \"plugin.hpp\"",
            "",
            "namespace \(ns) {",
            "",
            "using namespace rack;",
            "",
            "/// Rack sweeps a knob from minAngle to maxAngle itself; ±0.83·π is its own",
            "/// default and what every ComponentLibrary knob uses.",
            "struct KnobBase : app::SvgKnob {",
            "    KnobBase() {",
            "        minAngle = -0.83f * M_PI;",
            "        maxAngle =  0.83f * M_PI;",
            "    }",
            "};",
            "",
            "struct PortBase : app::SvgPort {};",
            "",
            "/// Flat panel artwork reads better without Rack's circular drop shadow.",
            "struct SwitchBase : app::SvgSwitch {",
            "    SwitchBase() {",
            "        shadow->opacity = 0.f;",
            "    }",
            "};",
            "",
            "struct SliderBase : app::SvgSlider {};",
            "",
            "struct PlainBase : widget::SvgWidget {};",
            "",
            "} // namespace \(ns)",
        ])
    }

    /// A C++ name for a Rack type, usable as a `using` alias.
    ///
    /// Templates are the reason this exists: `MediumLight<RedLight>` cannot be
    /// an alias name, so it becomes `MediumLightRedLight`. Everything else
    /// keeps the name you would have typed.
    /// Whether a Rack type can be aliased into the plugin's namespace.
    ///
    /// Only ComponentLibrary types can: the alias resolves to
    /// `rack::componentlibrary::<type>`, so anything already namespaced is
    /// someone else's and anything not in that library would alias to a name
    /// that does not exist. Those are named verbatim in placement code instead,
    /// which is correct if less tidy — a header that does not compile is worse
    /// than one that is inconsistent.
    static func isAliasable(_ type: String) -> Bool {
        guard !type.isEmpty, !type.contains("::"), type != "Widget" else { return false }
        return type.allSatisfy { $0.isLetter || $0.isNumber || $0 == "_" || $0 == "<" || $0 == ">" }
    }

    /// Rack types used across these panels that can be aliased, as type → alias.
    static func stockAliases(for docs: [PanelDocument]) -> [String: String] {
        var out: [String: String] = [:]
        for panel in docs {
            for el in panel.components where el.widgetSource == .stock {
                let type = widgetClass(el)
                guard isAliasable(type) else { continue }
                out[type] = widgetAlias(type)
            }
        }
        return out
    }

    static func widgetAlias(_ type: String) -> String {
        let mapped = type.map { $0.isLetter || $0.isNumber || $0 == "_" ? $0 : Character(" ") }
        return String(mapped).split(separator: " ").joined()
    }

    static func namespacePrefix(_ doc: PanelDocument) -> String {
        doc.widgetNamespace.isEmpty
            ? ""
            : cppIdentifier(doc.widgetNamespace, fallback: "ui") + "::"
    }

    private static func lines(_ l: [String]) -> String { l.joined(separator: "\n") + "\n" }

    private static func asset(_ file: String) -> String {
        "window::Svg::load(asset::plugin(pluginInstance, \"res/components/\(file)\"))"
    }

    /// The widget type to instantiate, falling back to Rack's own defaults —
    /// the same ones helper.py uses when a shape carries no `#Class` suffix.
    static func widgetClass(_ el: PanelElement) -> String {
        let w = el.widgetClass
        if !w.isEmpty { return w }
        switch el.role {
        case .param:          return "RoundBlackKnob"
        case .input, .output: return "PJ301MPort"
        case .light:          return "MediumLight<RedLight>"
        default:              return "Widget"
        }
    }

    // MARK: - Artwork a custom widget needs

    /// Files to write for a custom component, and which slice of the element
    /// each one holds. A knob needs two: Rack rotates only the foreground.
    static func componentFiles(for el: PanelElement,
                               in doc: PanelDocument? = nil) -> [(name: String, layer: SVGExporter.ComponentLayer)] {
        let base = kebab(el.customWidgetName.isEmpty ? el.identifierStem : el.customWidgetName)

        // A composed widget splits only if something in it actually turns.
        if let doc, doc.widgetMembers(of: el).count > 1 {
            if doc.widgetMembers(of: el).contains(where: \.rotatesWithValue) {
                return [(base + "-bg.svg", .knobBackground), (base + "-fg.svg", .knobForeground)]
            }
            // A composed switch still needs a frame per position: the housing
            // is the same in each, the anchor moves.
            if el.role == .param, isSwitch(el) {
                let n = switchPositions(el)
                return (0..<n).map { (base + "-\($0).svg", .switchFrame(index: $0, of: n)) }
            }
            return [(base + ".svg", .whole)]
        }

        if el.role == .param && el.kind.isKnob {
            return [(base + "-bg.svg", .knobBackground), (base + "-fg.svg", .knobForeground)]
        }
        if el.role == .param, isSwitch(el) {
            let n = switchPositions(el)
            return (0..<n).map { (base + "-\($0).svg", .switchFrame(index: $0, of: n)) }
        }
        return [(base + ".svg", .whole)]
    }

    /// Anything Rack draws with an `SvgSwitch`: a button is the two-position
    /// case of the same widget.
    static func isSwitch(_ el: PanelElement) -> Bool {
        el.kind == .pushButton || el.kind == .buttonGroup
    }

    /// Positions the switch has, and so frames it needs. A button has two; a
    /// group has as many as it draws — and Cross is four by definition, which
    /// is why the inspector disables Count for it.
    static func switchPositions(_ el: PanelElement) -> Int {
        guard el.kind == .buttonGroup else { return 2 }
        if Int(el.params.layout.rounded()) == 2 { return 4 }
        return max(2, min(12, Int(el.params.segments.rounded())))
    }

    // MARK: - Identifiers

    /// One identifier per component, disambiguated by suffix. Dropping seven
    /// faders on a panel leaves them all named "Fader · Vertical", which would
    /// otherwise emit seven FADER_VERTICAL_PARAM entries — a C++ error, not a
    /// subtlety. Numbering them keeps the output compiling; the warning tells
    /// you to name them properly.
    static func identifiers(_ doc: PanelDocument) -> [UUID: String] {
        // Numbering is per enum, not per panel. Rack keeps ParamId, InputId,
        // OutputId and LightId apart, so ANIMATE_PARAM and ANIMATE_INPUT are
        // not a clash — and treating them as one renamed five perfectly legal
        // identifiers on the first real module put through this. A CV input and
        // the knob it feeds sharing a name is the normal case, not an accident.
        var used: [String: Int] = [:]
        var out: [UUID: String] = [:]
        for el in doc.components {
            let stem = el.identifierStem
            let key = "\(el.role.rawValue).\(stem)"
            let n = (used[key] ?? 0) + 1
            used[key] = n
            out[el.id] = n == 1 ? stem : "\(stem)_\(n)"
        }
        return out
    }

    // MARK: - Warnings

    /// Problems that would produce C++ that does not compile, or compiles into
    /// the wrong thing. Emitted at the top of the file rather than silently.
    static func warnings(_ doc: PanelDocument) -> [String] {
        var out: [String] = []

        // The plugin slug names the widget library, its header and its
        // namespace, so leaving it at the default quietly produces a
        // MyPluginWidgets.hpp that no plugin wants to include.
        if doc.pluginSlug == "MyPlugin" {
            out.append("The plugin slug is still \"MyPlugin\". It names \(widgetsHeaderName(doc)), "
                + "\(widgetBaseHeaderName(doc)) and the \(uiNamespace(doc)) namespace — set it in Panel settings.")
        }

        for (label, slug) in [("Module", doc.moduleSlug), ("Plugin", doc.pluginSlug)]
        where !isValidSlug(slug) {
            out.append("\(label) slug \"\(slug)\" is not a valid Rack slug — letters, digits, - and _ only. Rack rejects the plugin at load. Try \"\(slugSuggestion(slug))\"."
                + (label == "Module" ? " It is also the panel's filename." : ""))
        }

        // Same rule as `identifiers`: only a clash inside one enum is a clash.
        var seen: [String: (role: ComponentRole, stem: String, count: Int)] = [:]
        for el in doc.components {
            let key = "\(el.role.rawValue).\(el.identifierStem)"
            let previous = seen[key]?.count ?? 0
            seen[key] = (el.role, el.identifierStem, previous + 1)
        }
        for (_, clash) in seen.sorted(by: { $0.key < $1.key }) where clash.count > 1 {
            let renamed = clash.count == 2
                ? "the second became \(clash.stem)_2"
                : "the rest became \(clash.stem)_2 … \(clash.stem)_\(clash.count)"
            out.append("\(clash.count) \(clash.role.rawValue)s share the name \(clash.stem) — "
                + "the first keeps it, \(renamed). It compiles, but name them yourself.")
        }

        // A switch with more than two positions needs its parameter range set
        // in the module, and nothing here can do that. Left unsaid, the module
        // loads with a control that will not move past its second frame, which
        // reads as broken artwork rather than a missing line of module code.
        for el in doc.components where el.role == .param && isSwitch(el) && switchPositions(el) > 2 {
            let n = switchPositions(el)
            out.append("\(el.identifierStem) is a \(n)-position switch. Its parameter must be configured "
                + "0…\(n - 1) — configSwitch(\(el.identifierStem)\(el.role.enumSuffix), 0.f, \(n - 1).f, 0.f, …) "
                + "— or Rack can only ever reach the first two positions.")
        }

        // Artwork filenames come from the class name, so two classes that
        // reduce to the same filename overwrite each other's SVGs in silence
        // and every instance of both draws whichever won.
        var byFile: [String: Set<String>] = [:]
        for el in doc.components where el.widgetSource == .custom && !el.customWidgetName.isEmpty {
            byFile[kebab(el.customWidgetName), default: []].insert(el.customWidgetName)
        }
        for (file, names) in byFile.sorted(by: { $0.key < $1.key }) where names.count > 1 {
            out.append("\(names.sorted().joined(separator: " and ")) both export as \(file)*.svg — "
                + "one overwrites the other. Rename one of them.")
        }

        // A custom widget with no struct name falls back to the *instance*
        // identifier, which breaks the rule the rest of this relies on: one
        // class, one set of files, however many times it is placed.
        for el in doc.components where el.widgetSource == .custom && el.customWidgetName.isEmpty {
            out.append("\(el.identifierStem) is custom but unnamed, so its artwork is filed under its own "
                + "identifier rather than a widget name. Two placements would write two sets of files "
                + "for one control — give it a struct name.")
        }

        let unnamed = doc.components.filter(\.enumName.isEmpty)
        if !unnamed.isEmpty {
            out.append("\(unnamed.count) component\(unnamed.count == 1 ? " has" : "s have") no explicit Name, so identifiers were derived from layer names — they will change if you rename a layer.")
        }
        for el in doc.components where el.widgetSource == .custom && el.customWidgetName.isEmpty {
            out.append("A custom \(el.kind.displayName) has no struct name — it will not generate.")
        }
        for el in doc.components where doc.widgetMembers(of: el).count > 1 {
            let bounds = doc.widgetBounds(of: el)
            if composedBase(for: el, in: doc) == "knob",
               abs(bounds.width - bounds.height) > 0.5 {
                out.append("\(el.identifierStem) is a composed knob whose bounds are \(Geo.fmt(bounds.width))×\(Geo.fmt(bounds.height)) — Rack rotates the artwork about the centre of its own box, so a knob that is not square will wobble as it turns.")
            }
            if el.role == .param, !isSwitch(el),
               !doc.widgetMembers(of: el).contains(where: \.rotatesWithValue) {
                out.append("\(el.identifierStem) is a composed param with no part marked as turning; it generates as a switch. Tick \"Rotates with value\" on the indicator if it is a knob.")
            }
        }
        for el in doc.components
        where el.widgetSource == .custom && el.kind.isKnob && el.params.knobStyle >= 1 {
            out.append("\(el.identifierStem) uses a position ring. Rack rotates one SVG over a static one, so a value arc cannot follow the parameter — the track exports, the filled arc freezes at its current angle. Use the pointer for the moving indicator.")
        }
        for el in doc.components where el.rotation != 0 {
            out.append("\(el.identifierStem) is rotated \(Geo.fmt(el.rotation))° — component artwork exports unrotated; Rack rotates knobs itself.")
        }
        if doc.svgUnits == .pixels {
            out.append("SVG export is in pixels. Rasterisers that read width=\"…mm\" will reject the artwork; Panel ▸ SVG units ▸ Millimetres fixes it.")
        }
        return out
    }

    // MARK: - ID enums

    static func idEnums(_ doc: PanelDocument) -> String {
        let ids = identifiers(doc)
        func block(_ typeName: String, _ role: ComponentRole, _ lenName: String) -> String {
            var l = ["enum \(typeName) {"]
            for el in doc.components where el.role == role {
                l.append("    \(ids[el.id] ?? el.identifierStem)\(role.enumSuffix),")
            }
            l.append("    \(lenName)")
            l.append("};")
            return lines(l)
        }
        return block("ParamId", .param, "PARAMS_LEN") + "\n"
            + block("InputId", .input, "INPUTS_LEN") + "\n"
            + block("OutputId", .output, "OUTPUTS_LEN") + "\n"
            + block("LightId", .light, "LIGHTS_LEN")
    }

    // MARK: - Custom widget structs

    static func customWidgetStructs(_ doc: PanelDocument) -> String {
        var seen = Set<String>()
        var out = ""
        for el in doc.components where el.widgetSource == .custom {
            let name = el.customWidgetName
            guard !name.isEmpty, seen.insert(name).inserted else { continue }
            out += structSource(for: el, named: name, in: doc) + "\n"
        }
        return out
    }

    /// What a composed widget should subclass. The anchor's own kind says
    /// nothing useful — it might be a ring sector — so the base comes from the
    /// role plus whether any part turns.
    private static func composedBase(for el: PanelElement, in doc: PanelDocument) -> String {
        switch el.role {
        case .input, .output: return "port"
        case .param:          return doc.widgetMembers(of: el).contains(where: \.rotatesWithValue) ? "knob" : "switch"
        default:              return "plain"
        }
    }

    /// An SvgSwitch with one frame per position.
    ///
    /// `momentary` is the difference between a button and a switch, and it is
    /// not cosmetic: a momentary widget snaps back on mouse-up, so a
    /// three-position rotary declared momentary can never rest anywhere but
    /// its first position.
    ///
    /// The parameter's range matters just as much and lives in the module, not
    /// here — a switch with three frames whose param is still 0…1 can only ever
    /// reach frames 0 and 1. The comment carries the call that fixes it, since
    /// this is the failure that looks like "the artwork is broken".
    private static func switchStruct(name: String, files: [String], element el: PanelElement,
                                     base: String? = nil) -> String {
        let momentary = el.kind == .pushButton
        var body = [
            "struct \(name) : \(base ?? "app::SvgSwitch") {",
            "    \(name)() {",
        ]
        if momentary { body.append("        momentary = true;") }
        // Without a base to carry it, each struct turns the shadow off itself.
        if base == nil {
            body.append("        shadow->opacity = 0.f;   // flat artwork reads better without it")
        }
        for file in files { body.append("        addFrame(\(asset(file)));") }
        body.append("    }")
        body.append("};")
        if !momentary && files.count > 2 {
            let labels = (0..<files.count).map { "\"\($0)\"" }.joined(separator: ", ")
            body.append("// \(name) has \(files.count) positions. In the module\'s constructor:")
            body.append("//   configSwitch(\(el.identifierStem)\(el.role.enumSuffix), 0.f, "
                + "\(files.count - 1).f, 0.f, \"\(el.identifierStem)\", {\(labels)});")
            body.append("// Without that range the extra frames are unreachable.")
        }
        return lines(body)
    }

    /// - Parameter base: the plugin's own base for this widget's family, when
    ///   generating into a plugin that has one. nil derives straight from Rack,
    ///   which is what the single-file export must do — it has no header to
    ///   include.
    private static func structSource(for el: PanelElement, named name: String,
                                     in doc: PanelDocument,
                                     base: String? = nil) -> String {
        let files = componentFiles(for: el, in: doc).map(\.name)
        let composed = doc.widgetMembers(of: el).count > 1
        // With a base, the shared settings live there and are not repeated.
        let knobBase = base ?? "app::SvgKnob"
        let portBase = base ?? "app::SvgPort"
        let switchBase = base ?? "app::SvgSwitch"
        let sliderBase = base ?? "app::SvgSlider"
        let plainBase = base ?? "widget::SvgWidget"
        let knobAngles = base == nil
            ? ["        minAngle = -0.83f * M_PI;", "        maxAngle =  0.83f * M_PI;"]
            : []

        if composed {
            switch composedBase(for: el, in: doc) {
            case "port":
                return lines([
                    "struct \(name) : \(portBase) {",
                    "    \(name)() {",
                    "        setSvg(\(asset(files[0])));",
                    "    }",
                    "};",
                ])
            case "knob":
                return lines([
                    "struct \(name) : \(knobBase) {",
                    "    widget::SvgWidget* bg;",
                    "    \(name)() {",
                ] + knobAngles + [
                    "        bg = new widget::SvgWidget;",
                    "        fb->addChildBelow(bg, tw);",
                    "        bg->setSvg(\(asset(files[0])));",
                    "        setSvg(\(asset(files.count > 1 ? files[1] : files[0])));",
                    "    }",
                    "};",
                ])
            case "switch":
                return switchStruct(name: name, files: files, element: el, base: switchBase)
            default:
                return lines([
                    "struct \(name) : \(plainBase) {",
                    "    \(name)() {",
                    "        setSvg(\(asset(files[0])));",
                    "    }",
                    "};",
                ])
            }
        }

        switch el.role {

        case .input, .output:
            return lines([
                "struct \(name) : \(portBase) {",
                "    \(name)() {",
                "        setSvg(\(asset(files[0])));",
                "    }",
                "};",
            ])

        case .param where el.kind.isKnob:
            // Rack's own RoundKnob shape: a static background below the
            // TransformWidget, and only the indicator turning above it.
            return lines([
                "struct \(name) : \(knobBase) {",
                "    widget::SvgWidget* bg;",
                "    \(name)() {",
            ] + knobAngles + [
                "        bg = new widget::SvgWidget;",
                "        fb->addChildBelow(bg, tw);",
                "        bg->setSvg(\(asset(files[0])));",
                "        setSvg(\(asset(files[1])));",
                "    }",
                "};",
            ])

        case .param where el.kind == .faderVertical || el.kind == .faderHorizontal:
            let vertical = el.kind == .faderVertical
            let handle = vertical ? max(9, el.h * 0.14) : max(9, el.w * 0.14)
            // Widget-local pixels, matching the exported background artwork.
            let zero = vertical
                ? "Vec(\(Geo.fmt(el.w / 2)), \(Geo.fmt(el.h - handle / 2)))"
                : "Vec(\(Geo.fmt(handle / 2)), \(Geo.fmt(el.h / 2)))"
            let one = vertical
                ? "Vec(\(Geo.fmt(el.w / 2)), \(Geo.fmt(handle / 2)))"
                : "Vec(\(Geo.fmt(el.w - handle / 2)), \(Geo.fmt(el.h / 2)))"
            return lines([
                "struct \(name) : \(sliderBase) {",
                "    \(name)() {",
                "        // A slider needs two files; PanelGenerator exports the track.",
                "        setBackgroundSvg(\(asset(files[0])));",
                "        setHandleSvg(\(asset(kebab(name) + "-handle.svg")));  // TODO: draw the handle",
                "        setHandlePosCentered(\(zero), \(one));",
                "    }",
                "};",
            ])

        case .param where isSwitch(el):
            return switchStruct(name: name, files: files, element: el, base: switchBase)

        case .light:
            return lines([
                "// \(name): Rack draws lights itself from a light class, not from an SVG.",
                "// Choose a ComponentLibrary light (MediumLight<RedLight> and friends) as the",
                "// Rack type instead of a custom struct, or subclass app::ModuleLightWidget.",
            ])

        default:
            return lines([
                "struct \(name) : \(plainBase) {",
                "    \(name)() {",
                "        setSvg(\(asset(files[0])));",
                "    }",
                "};",
            ])
        }
    }

    // MARK: - ModuleWidget constructor body

    /// `receiver` is empty for a bare constructor body, or "widget->" when the
    /// lines go inside a free function taking the widget. One body serves both
    /// so the two outputs cannot disagree about a position.
    /// - Parameters:
    ///   - idPrefix: how the enum constants are reached. The one-file export
    ///     puts them inside the module struct, so they need `Module::`; the
    ///     generated header declares them in its own namespace alongside this
    ///     body, where they are already in scope. Getting this wrong produces a
    ///     header that declares an enum and then refers to a different one.
    ///   - uiNamespace: when set, every widget — the plugin's own and Rack's —
    ///     is named through that namespace, so placement code does not care
    ///     which is which and swapping one for the other is a line in the
    ///     widget header rather than an edit here.
    static func constructorBody(_ doc: PanelDocument, receiver: String = "",
                                idPrefix: String? = nil,
                                uiNamespace ui: String? = nil) -> String {
        let mod = moduleIdentifier(doc)
        let ns = namespacePrefix(doc)
        let prefix = idPrefix ?? "\(mod)::"
        let ids = identifiers(doc)
        var out = "\(receiver)setPanel(createPanel(asset::plugin(pluginInstance, \"res/\(doc.moduleSlug).svg\")));\n"

        var byRole: [ComponentRole: [String]] = [:]
        for el in doc.components {
            // Stock types live in Rack's global namespace; only our own structs
            // get the document's namespace prefix.
            let cls: String
            if let ui {
                let type = widgetClass(el)
                if el.widgetSource == .custom {
                    cls = ui + "::" + type
                } else {
                    // A type that could not be aliased is named as written; the
                    // widget library says why.
                    cls = isAliasable(type) ? ui + "::" + widgetAlias(type) : type
                }
            } else {
                cls = el.widgetSource == .custom ? ns + widgetClass(el) : widgetClass(el)
            }
            let p = doc.componentCentreMM(el)
            let vec = "mm2px(Vec(\(mm3(p.x)), \(mm3(p.y))))"
            let id = "\(prefix)\(ids[el.id] ?? el.identifierStem)\(el.role.enumSuffix)"
            switch el.role {
            case .param:
                byRole[.param, default: []].append("\(receiver)addParam(createParamCentered<\(cls)>(\(vec), module, \(id)));")
            case .input:
                byRole[.input, default: []].append("\(receiver)addInput(createInputCentered<\(cls)>(\(vec), module, \(id)));")
            case .output:
                byRole[.output, default: []].append("\(receiver)addOutput(createOutputCentered<\(cls)>(\(vec), module, \(id)));")
            case .light:
                byRole[.light, default: []].append("\(receiver)addChild(createLightCentered<\(cls)>(\(vec), module, \(id)));")
            case .custom:
                byRole[.custom, default: []].append("\(receiver)addChild(createWidgetCentered<\(cls)>(\(vec)));")
            case .decoration:
                break
            }
        }
        for role in [ComponentRole.param, .input, .output, .light, .custom] {
            if let l = byRole[role], !l.isEmpty { out += "\n" + lines(l) }
        }
        return out
    }

    // MARK: - Regenerable header

    /// The layout as a header the module source includes, rather than
    /// fragments to paste.
    ///
    /// This is what makes "regenerate rather than hand-edit" true instead of
    /// aspirational: the header is overwritten on every emit and contains no
    /// hand-written code, so revising a panel is one command with nothing to
    /// merge. The module, its DSP and its registration live in a file the
    /// generator never touches.
    /// The plugin's widget library: every custom widget it draws, plus an
    /// alias for every stock Rack type it uses.
    ///
    /// The aliases are the point, and they are what makes this a boundary
    /// rather than a filing cabinet. Placement code names `museui::PJ301MPort`
    /// whether that is Rack's port or yours, so replacing a stock widget with
    /// your own artwork is one line changed here and nothing changed anywhere
    /// else. Without them, swapping a widget means editing every placement that
    /// mentions it — which is exactly the edit a generated file will overwrite.
    static func widgetsHeader(_ doc: PanelDocument) -> String { widgetsHeader(for: [doc]) }

    /// - Parameter docs: every panel in the plugin. A plugin's modules share a
    ///   visual language, so two modules using the same jack must compile to
    ///   one struct and load one SVG. Emitting this per document meant the
    ///   second module's header overwrote the first's and took its widgets
    ///   with it.
    static func widgetsHeader(for docs: [PanelDocument]) -> String {
        guard let doc = docs.first else { return "" }
        let ns = uiNamespace(doc)

        var out = lines([
            "// Generated by PanelGenerator — do not edit.",
            "//",
            "// \(pluginIdentifier(doc)) widget library. One namespace for everything a panel",
            "// places: the plugin's own widgets as structs, and the Rack types it uses as",
            "// aliases, so placement code never has to know which is which.",
            "//",
            "// To replace a stock widget with your own artwork, draw it in PanelGenerator",
            "// and mark it as a custom widget — the alias below becomes a struct and every",
            "// panel that places it follows, with no edit to any placement code.",
            "",
            "#pragma once",
            "#include \"\(widgetBaseHeaderName(doc))\"",
            "",
            "namespace \(ns) {",
            "",
            "using namespace rack;",
            "using namespace rack::componentlibrary;",
            "",
        ])

        // Stock types, deduplicated and in a stable order so the file does not
        // churn between emits.
        let stock = stockAliases(for: docs)
        if !stock.isEmpty {
            out += "// Rack's own, named through this namespace.\n"
            for type in stock.keys.sorted() {
                let alias = stock[type] ?? type
                out += alias == type
                    ? "using \(alias) = rack::componentlibrary::\(type);\n"
                    : "using \(alias) = rack::componentlibrary::\(type);   // \(type)\n"
            }
            out += "\n"
        }
        let verbatim = docs.flatMap(\.components)
            .filter { $0.widgetSource == .stock && !isAliasable(widgetClass($0)) }
            .map { widgetClass($0) }
        if !Set(verbatim).isEmpty {
            out += "// Named as written in the panels, not aliased here: "
                + Set(verbatim).sorted().joined(separator: ", ") + ".\n\n"
        }

        // Deduplicated across the whole plugin: the first panel to define a
        // widget defines it for all of them.
        var seen = Set<String>()
        var structs = ""
        for panel in docs {
            for el in panel.components where el.widgetSource == .custom {
                let name = el.customWidgetName
                guard !name.isEmpty, seen.insert(name).inserted else { continue }
                structs += structSource(for: el, named: name, in: panel,
                                        base: family(for: el, in: panel).rawValue) + "\n"
            }
        }
        out += structs.isEmpty
            ? "// No custom widgets yet — everything is drawn by Rack's own.\n"
            : structs
        out += "\n} // namespace \(ns)\n"
        return out
    }

    static func panelHeader(_ doc: PanelDocument) -> String {
        let mod = moduleIdentifier(doc)
        // The panel's namespace is the module's; the widget library's is the
        // plugin's. Conflating them meant two modules in one plugin could not
        // both be included, and a shared widget had to be generated twice.
        let ns = mod + "Panel"
        let ui = uiNamespace(doc)

        var out = lines([
            "// Generated by PanelGenerator — do not edit.",
            provenance(doc),
            "//",
            "// \(doc.name) · \(doc.widthHP)HP \(doc.format.rawValue) · \(doc.components.count) component\(doc.components.count == 1 ? "" : "s").",
            "// Overwritten on every emit, so nothing written here survives.",
            "//",
            "// This file owns the panel: the component ids, their positions, and the",
            "// widgets that draw them. Your module owns the sound. The only thing the two",
            "// share is the enum below, which is why it is generated rather than typed",
            "// twice.",
            "//",
            "//   #include \"plugin.hpp\"",
            "//   #include \"\(mod)_panel.hpp\"",
            "//   using namespace \(ns);        // ids unqualified, as Rack code expects",
            "//",
            "//   struct \(mod) : Module {",
            "//       \(mod)() {",
            "//           config(PARAMS_LEN, INPUTS_LEN, OUTPUTS_LEN, LIGHTS_LEN);",
            "//       }",
            "//       void process(const ProcessArgs& args) override {}",
            "//   };",
            "//",
            "//   struct \(mod)Widget : ModuleWidget {",
            "//       \(mod)Widget(\(mod)* module) {",
            "//           setModule(module);",
            "//           \(ns)::addComponents(this, module);",
            "//       }",
            "//   };",
            "//",
            "//   Model* model\(mod) = createModel<\(mod), \(mod)Widget>(\"\(doc.moduleSlug)\");",
        ])

        let warns = warnings(doc)
        if !warns.isEmpty {
            out += "//\n// WARNINGS\n"
            for warning in warns { out += "//   ! \(warning)\n" }
        }

        out += "\n#pragma once\n#include \"\(widgetsHeaderName(doc))\"\n\n"
        out += "namespace \(ns) {\n\n"
        out += "using namespace rack;\n\n"
        out += idEnums(doc)

        out += "\ninline void addComponents(ModuleWidget* widget, Module* module) {\n"
        // No module qualification on the ids: they are declared just above, in
        // this same namespace. No bare widget names either — everything goes
        // through the widget library.
        for line in constructorBody(doc, receiver: "widget->", idPrefix: "", uiNamespace: ui)
            .split(separator: "\n", omittingEmptySubsequences: false) {
            out += line.isEmpty ? "\n" : "    " + line + "\n"
        }
        out += "}\n\n} // namespace \(ns)\n\n"
        out += metaModuleNotes(doc)
        return out
    }

    // MARK: - Registration

    /// The `createModel` line and the plugin.json entry that go with it.
    /// Without these the generated file is a widget with nothing registering
    /// it, which is the one piece helper.py does emit and we did not.
    static func registration(_ doc: PanelDocument) -> String {
        let mod = moduleIdentifier(doc)
        return lines([
            "Model* model\(mod) = createModel<\(mod), \(mod)Widget>(\"\(doc.moduleSlug)\");",
            "",
            "/* plugin.json — add to \"modules\":",
            "",
            "     {",
            "       \"slug\": \"\(doc.moduleSlug)\",",
            "       \"name\": \"\(doc.name)\",",
            "       \"description\": \"\",",
            "       \"tags\": []",
            "     }",
            "",
            "   The plugin's own slug is \"\(doc.pluginSlug)\" — the plugin directory and",
            "   the top-level \"slug\" in plugin.json. That is not the brand: brand is a",
            "   separate display field and may be anything.",
            "",
            "   Both slugs are permanent from the first saved patch. Renaming either",
            "   breaks every patch that uses this module, silently.",
            "*/",
        ])
    }

    // MARK: - MetaModule notes

    /// MetaModule needs no separate element array when the plugin compiles its
    /// VCV sources through the SDK's rack adaptor — the widget code above is
    /// read for the element list. What differs between the targets is artwork.
    static func metaModuleNotes(_ doc: PanelDocument) -> String {
        lines([
            "/* ---- MetaModule ----------------------------------------------------",
            "   If the MetaModule build compiles these same VCV sources through the",
            "   SDK's rack adaptor (a CMakeLists pointing at ../vcv), the code above",
            "   is all there is: MetaModule derives its elements from this",
            "   ModuleWidget, so there is no element array to keep in step.",
            "",
            "   What does differ is the artwork — MetaModule draws PNGs, not SVGs.",
            "   Mirror the res/ tree into assets/ and rasterise; the adaptor rewrites",
            "   res/*.svg references to the matching assets/*.png at load time.",
            "   Faceplates are 240 px for 128.5 mm (47.44 dpi).",
            "",
            "   Exporting in millimetres matters here: rasterisers read the physical",
            "   size from the SVG's width attribute, and one that expects \"…mm\" will",
            "   reject a unitless pixel size outright.",
            "",
            "   Thin lines, subtle gradients and shadows do not survive the 240x320",
            "   screen — worth checking the panel at that size before committing.",
            "   ------------------------------------------------------------------- */",
        ])
    }

    // MARK: - Whole file

    static func rackSource(_ doc: PanelDocument) -> String {
        let mod = moduleIdentifier(doc)
        let comps = doc.components
        let hasCustom = comps.contains { $0.widgetSource == .custom && !$0.customWidgetName.isEmpty }
        var out = ""

        out += lines([
            provenance(doc),
            "// Generated by PanelGenerator — \(doc.name), \(doc.widthHP)HP \(doc.format.rawValue), "
                + "\(comps.count) component\(comps.count == 1 ? "" : "s").",
            "// Regenerate rather than hand-edit: these positions come straight from the",
            "// .panelgen, which is the whole point — artwork and widget code cannot drift",
            "// apart if both are generated from one source.",
            "//",
            "// Expects in your plugin:",
            "//   res/\(doc.moduleSlug).svg",
        ])
        if hasCustom { out += "//   res/components/*.svg   (exported alongside this file)\n" }

        let warns = warnings(doc)
        if !warns.isEmpty {
            out += "//\n// WARNINGS\n"
            for w in warns { out += "//   ! \(w)\n" }
        }

        out += "\n// ---- 1. IDs — into your Module struct ------------------------------\n\n"
        out += idEnums(doc)

        let structs = customWidgetStructs(doc)
        var section = 2
        if !structs.isEmpty {
            out += "\n// ---- 2. Custom components — above your ModuleWidget ----------------\n\n"
            let nsName = doc.widgetNamespace.isEmpty
                ? "" : cppIdentifier(doc.widgetNamespace, fallback: "ui")
            if !nsName.isEmpty { out += "namespace \(nsName) {\n\n" }
            out += structs
            if !nsName.isEmpty { out += "} // namespace \(nsName)\n" }
            section = 3
        }

        out += "\n// ---- \(section). \(mod)Widget constructor body ---------------------\n\n"
        out += constructorBody(doc)

        out += "\n// ---- \(section + 1). Registration ----------------------------------\n\n"
        out += registration(doc)

        out += "\n"
        out += metaModuleNotes(doc)
        return out
    }
}
