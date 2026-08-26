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
    static func slugSuggestion(_ slug: String) -> String {
        var out = ""
        for ch in slug {
            if ch.isASCII && (ch.isLetter || ch.isNumber) { out.append(ch) }
            else if ch == "_" || ch == "-" { out.append(ch) }
            else if ch == " " || ch == "." { out.append("-") }
        }
        while out.contains("--") { out = out.replacingOccurrences(of: "--", with: "-") }
        out = out.trimmingCharacters(in: CharacterSet(charactersIn: "-_"))
        return out.isEmpty ? "MyModule" : out
    }

    static func moduleIdentifier(_ doc: PanelDocument) -> String {
        cppIdentifier(doc.moduleSlug, fallback: "MyModule")
    }

    /// `museui::`, or empty when the document declares no namespace.
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
            return doc.widgetMembers(of: el).contains(where: \.rotatesWithValue)
                ? [(base + "-bg.svg", .knobBackground), (base + "-fg.svg", .knobForeground)]
                : [(base + ".svg", .whole)]
        }

        if el.role == .param && el.kind.isKnob {
            return [(base + "-bg.svg", .knobBackground), (base + "-fg.svg", .knobForeground)]
        }
        if el.role == .param && (el.kind == .pushButton || el.kind == .buttonGroup) {
            return [(base + "-0.svg", .whole)]
        }
        return [(base + ".svg", .whole)]
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
            if el.role == .param, !doc.widgetMembers(of: el).contains(where: \.rotatesWithValue) {
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

    private static func structSource(for el: PanelElement, named name: String,
                                     in doc: PanelDocument) -> String {
        let files = componentFiles(for: el, in: doc).map(\.name)
        let composed = doc.widgetMembers(of: el).count > 1

        if composed {
            switch composedBase(for: el, in: doc) {
            case "port":
                return lines([
                    "struct \(name) : app::SvgPort {",
                    "    \(name)() {",
                    "        setSvg(\(asset(files[0])));",
                    "    }",
                    "};",
                ])
            case "knob":
                return lines([
                    "struct \(name) : app::SvgKnob {",
                    "    widget::SvgWidget* bg;",
                    "    \(name)() {",
                    "        minAngle = -0.83f * M_PI;",
                    "        maxAngle =  0.83f * M_PI;",
                    "        bg = new widget::SvgWidget;",
                    "        fb->addChildBelow(bg, tw);",
                    "        bg->setSvg(\(asset(files[0])));",
                    "        setSvg(\(asset(files.count > 1 ? files[1] : files[0])));",
                    "    }",
                    "};",
                ])
            case "switch":
                return lines([
                    "struct \(name) : app::SvgSwitch {",
                    "    \(name)() {",
                    "        momentary = true;",
                    "        shadow->opacity = 0.f;",
                    "        addFrame(\(asset(files[0])));",
                    "        addFrame(\(asset(kebab(name) + "-1.svg")));  // TODO: draw the second position",
                    "    }",
                    "};",
                ])
            default:
                return lines([
                    "struct \(name) : widget::SvgWidget {",
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
                "struct \(name) : app::SvgPort {",
                "    \(name)() {",
                "        setSvg(\(asset(files[0])));",
                "    }",
                "};",
            ])

        case .param where el.kind.isKnob:
            // Rack's own RoundKnob shape: a static background below the
            // TransformWidget, and only the indicator turning above it.
            return lines([
                "struct \(name) : app::SvgKnob {",
                "    widget::SvgWidget* bg;",
                "    \(name)() {",
                "        minAngle = -0.83f * M_PI;",
                "        maxAngle =  0.83f * M_PI;",
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
                "struct \(name) : app::SvgSlider {",
                "    \(name)() {",
                "        // A slider needs two files; PanelGenerator exports the track.",
                "        setBackgroundSvg(\(asset(files[0])));",
                "        setHandleSvg(\(asset(kebab(name) + "-handle.svg")));  // TODO: draw the handle",
                "        setHandlePosCentered(\(zero), \(one));",
                "    }",
                "};",
            ])

        case .param where el.kind == .pushButton || el.kind == .buttonGroup:
            return lines([
                "struct \(name) : app::SvgSwitch {",
                "    \(name)() {",
                "        momentary = true;",
                "        shadow->opacity = 0.f;   // flat artwork reads better without it",
                "        addFrame(\(asset(files[0])));",
                "        addFrame(\(asset(kebab(name) + "-1.svg")));  // TODO: draw the pressed state",
                "    }",
                "};",
            ])

        case .light:
            return lines([
                "// \(name): Rack draws lights itself from a light class, not from an SVG.",
                "// Choose a ComponentLibrary light (MediumLight<RedLight> and friends) as the",
                "// Rack type instead of a custom struct, or subclass app::ModuleLightWidget.",
            ])

        default:
            return lines([
                "struct \(name) : widget::SvgWidget {",
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
    static func constructorBody(_ doc: PanelDocument, receiver: String = "") -> String {
        let mod = moduleIdentifier(doc)
        let ns = namespacePrefix(doc)
        let ids = identifiers(doc)
        var out = "\(receiver)setPanel(createPanel(asset::plugin(pluginInstance, \"res/\(doc.moduleSlug).svg\")));\n"

        var byRole: [ComponentRole: [String]] = [:]
        for el in doc.components {
            // Stock types live in Rack's global namespace; only our own structs
            // get the document's namespace prefix.
            let cls = el.widgetSource == .custom ? ns + widgetClass(el) : widgetClass(el)
            let p = doc.componentCentreMM(el)
            let vec = "mm2px(Vec(\(mm3(p.x)), \(mm3(p.y))))"
            let id = "\(mod)::\(ids[el.id] ?? el.identifierStem)\(el.role.enumSuffix)"
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
    static func panelHeader(_ doc: PanelDocument) -> String {
        let mod = moduleIdentifier(doc)
        let ns = doc.widgetNamespace.isEmpty
            ? mod + "Panel"
            : cppIdentifier(doc.widgetNamespace, fallback: "ui")

        var out = lines([
            "// Generated by PanelGenerator — do not edit.",
            "//",
            "// \(doc.name) · \(doc.widthHP)HP \(doc.format.rawValue) · \(doc.components.count) component\(doc.components.count == 1 ? "" : "s").",
            "// Overwritten on every emit, so nothing written here survives.",
            "//",
            "// Include after plugin.hpp — the declarations below are unqualified and",
            "// rely on the `using namespace rack;` that plugin.hpp brings in.",
            "//",
            "//   #include \"plugin.hpp\"",
            "//   #include \"\(mod)_panel.hpp\"",
            "//",
            "//   struct \(mod) : Module {",
            "//       \(mod)() {",
            "//           config(\(ns)::PARAMS_LEN, \(ns)::INPUTS_LEN,",
            "//                  \(ns)::OUTPUTS_LEN, \(ns)::LIGHTS_LEN);",
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

        out += "\n#pragma once\n\nnamespace \(ns) {\n\n"
        out += idEnums(doc)

        let structs = customWidgetStructs(doc)
        if !structs.isEmpty { out += "\n" + structs }

        out += "\ninline void addComponents(ModuleWidget* widget, Module* module) {\n"
        for line in constructorBody(doc, receiver: "widget->").split(separator: "\n", omittingEmptySubsequences: false) {
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
