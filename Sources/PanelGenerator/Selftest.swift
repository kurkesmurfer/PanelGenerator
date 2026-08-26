import Foundation
import CoreGraphics

/// Headless verification harness: builds a showcase panel exercising every
/// element kind, exports SVG + PNG, and exits. Runs without a window server,
/// so it doubles as the CI smoke test.
enum Selftest {

    static func demoDocument() -> PanelDocument {
        var doc = PanelDocument()
        doc.name = "Demo"
        doc.widthHP = 12
        doc.format = .u3
        doc.background = .hex("#0D0D13")

        func add(_ kind: ElementKind, _ x: CGFloat, _ y: CGFloat, _ w: CGFloat? = nil, _ h: CGFloat? = nil,
                 fill: ColorSpec? = nil, mutate: (inout PanelElement) -> Void = { _ in }) {
            var e = kind.defaultElement(at: CGPoint(x: x, y: y))
            if let w { e.w = w }
            if let h { e.h = h }
            if let fill { e.fill = fill }
            mutate(&e)
            doc.elements.append(e)
        }

        // LCARS backdrop
        add(.box, 8, 10, 164, 24) { $0.params.cornerTL = 12; $0.params.cornerTR = 12; $0.params.cornerBR = 12; $0.params.cornerBL = 12 }
        add(.box, 8, 42, 88, 18, fill: .hex("#FFCC99")) { $0.params.cornerTL = 9; $0.params.cornerTR = 9; $0.params.cornerBR = 9; $0.params.cornerBL = 9 }
        add(.box, 152, 74, 20, 118, fill: .hex("#CC99CC")) { $0.params.cornerTL = 10; $0.params.cornerTR = 10; $0.params.cornerBR = 10; $0.params.cornerBL = 10 }
        add(.elbow, 8, 234) { $0.w = 106; $0.h = 138
            $0.params.thickness = 16; $0.params.innerRadius = 8
            $0.params.armH = 66; $0.params.armV = 98; $0.params.flipY = true }
        add(.ringSector, 108, 66, 64, 64) { $0.params.thickness = 12; $0.params.startAngle = -90; $0.params.sweepAngle = 95 }

        // Titles
        add(.text, 30, 46, 96, 18, fill: .hex("#FFCC66")) { $0.params.text = "NX-1786"; $0.params.fontSize = 15 }
        add(.text, 30, 68, 116, 10, fill: .hex("#9999CC")) { $0.params.text = "PANELGEN CONTROL"; $0.params.fontSize = 7.5 }

        // Primitives
        add(.jack, 20, 128); add(.jack, 48, 128); add(.jack, 76, 128)
        add(.knobMedium, 112, 126)
        add(.knobLarge, 20, 168)
        add(.faderVertical, 62, 160)
        add(.faderHorizontal, 92, 204)
        add(.led, 100, 172, fill: .hex("#EE4444"))
        add(.led, 100, 188, fill: .hex("#44DD66"))
        add(.knobSmall, 116, 170)

        add(.text, 92, 360, 80, 9, fill: .hex("#8888A8")) { $0.params.text = "SN 4071-GK"; $0.params.fontSize = 6.5 }

        doc.addCornerScrews()
        // The demo is a pure-artwork panel: primitives here are illustration,
        // not bound components, so the exported demo shows the whole design.
        for i in doc.elements.indices { doc.elements[i].role = .decoration }
        return doc
    }

    static func run(outDir rawPath: String) -> Never {
        let dir = (rawPath as NSString).expandingTildeInPath
        do {
            try FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
            let doc = demoDocument()

            let svg = SVGExporter.documentSVG(doc)
            let svgURL = URL(fileURLWithPath: dir).appendingPathComponent("pg_demo.svg")
            try svg.write(to: svgURL, atomically: true, encoding: .utf8)

            let png = try PNGExporter.pngData(doc, scale: 4)
            let pngURL = URL(fileURLWithPath: dir).appendingPathComponent("pg_demo.png")
            try png.write(to: pngURL)

            let failures = persistenceChecks()
                + textExportChecks() + bindingChecks() + symbolChecks()
                + widgetChecks() + uniformChecks() + presetChecks()
                + colourChecks() + alignChecks() + bulkBindChecks()
                + labelChecks() + svgPathChecks() + svgImportChecks()
                + cppImportChecks() + compareChecks() + codegenChecks()

            print(failures.isEmpty ? "SELFTEST OK" : "SELFTEST FAILED")
            print("  elements : \(doc.elements.count)")
            print("  panel    : \(doc.widthHP)HP \(doc.format.rawValue) (\(Int(doc.pixelSize.width))×\(Int(doc.pixelSize.height)) px)")
            print("  svg      : \(svgURL.path) (\(svg.utf8.count) bytes)")
            print("  png      : \(pngURL.path) (\(png.count) bytes)")
            if failures.isEmpty {
                print("  checks   : persistence · export · symbols · widgets · codegen OK")
            } else {
                for f in failures { print("  ✗ \(f)") }
            }
            fflush(stdout)
            exit(failures.isEmpty ? 0 : 1)
        } catch {
            print("SELFTEST FAILED: \(error)")
            fflush(stdout)
            exit(1)
        }
    }

    // MARK: - Persistence checks
    //
    // Headless, so `make selftest` is a real regression gate. Until there is a
    // proper XCTest target these are the tests.

    static func persistenceChecks() -> [String] {
        var failures: [String] = []

        // 1. Encode → decode → identical document.
        do {
            let doc = demoDocument()
            let enc = JSONEncoder()
            enc.outputFormatting = [.sortedKeys]
            let data = try enc.encode(doc)
            let back = try JSONDecoder().decode(PanelDocument.self, from: data)
            if back != doc {
                failures.append("round-trip: decoded document differs from the original")
            }
        } catch {
            failures.append("round-trip: \(error)")
        }

        // 2. A document written before segments / layout / schemaVersion existed
        //    must still open, with those fields at their defaults. Swift's
        //    synthesised Codable throws .keyNotFound for a missing key rather
        //    than using the property default — which is what broke every
        //    pre-button-group .panelgen. Guard it here permanently.
        do {
            let doc = try JSONDecoder().decode(PanelDocument.self,
                                               from: Data(legacyDocumentJSON.utf8))
            if doc.schemaVersion != 0 {
                failures.append("legacy: schemaVersion should be 0, got \(doc.schemaVersion)")
            }
            if doc.elements.count != 2 {
                failures.append("legacy: expected 2 elements, got \(doc.elements.count)")
            }
            if let knob = doc.elements.first {
                if knob.kind != .knobLarge { failures.append("legacy: first kind is \(knob.kind.rawValue)") }
                if knob.params.pointerAngle != 45 { failures.append("legacy: pointerAngle not preserved") }
                if knob.params.segments != 4 { failures.append("legacy: segments should default to 4, got \(knob.params.segments)") }
                if knob.params.layout != 0 { failures.append("legacy: layout should default to 0, got \(knob.params.layout)") }
                if knob.isHidden != nil { failures.append("legacy: isHidden should decode as nil") }
                if knob.groupID != nil { failures.append("legacy: groupID should decode as nil") }
                if knob.w != 30 || knob.h != 30 { failures.append("legacy: size not preserved") }
            }
        } catch {
            failures.append("legacy: \(error) ← a pre-button-group .panelgen no longer opens")
        }

        // 3. An unknown element kind must be a hard error, not a blank panel.
        do {
            let bad = legacyDocumentJSON.replacingOccurrences(of: "knobLarge", with: "quantumFlux")
            _ = try JSONDecoder().decode(PanelDocument.self, from: Data(bad.utf8))
            failures.append("unknown kind: decoded without error — it should have thrown")
        } catch {
            // expected
        }

        return failures
    }

    // MARK: - Export checks

    // MARK: - Checks
    //
    // One function per topic, each with its own scope. They used to be one
    // 400-line function sharing a single scope, which cost two builds to name
    // collisions — `symDoc`, then `art` — because every new block competed for
    // names with everything already written. Scope is the fix, not vigilance.

    static func textExportChecks() -> [String] {
        var failures: [String] = []

        // Text must leave as outlines by default: Rack renders panels through
        // nanosvg, which has no text support and drops <text> without warning.
        var doc = demoDocument()
        let outlined = SVGExporter.documentSVG(doc)
        if outlined.contains("<text") {
            failures.append("text export: <text> in the default export — nanosvg (Rack) drops it")
        }
        if !outlined.contains("<path") {
            failures.append("text export: the default export contains no <path> at all")
        }

        doc.textAsPaths = false
        if !SVGExporter.documentSVG(doc).contains("<text") {
            failures.append("text export: editable mode should still emit <text>")
        }

        // A glyph token inside a label is real geometry, and an unknown one is
        // left alone rather than silently eaten.
        var withGlyph = ElementKind.text.defaultElement(at: CGPoint(x: 10, y: 40))
        withGlyph.params.text = "SN {ka}{ru} 4071"
        var plain = ElementKind.text.defaultElement(at: CGPoint(x: 10, y: 80))
        plain.params.text = "SN 4071"
        var unknown = ElementKind.text.defaultElement(at: CGPoint(x: 10, y: 120))
        unknown.params.text = "SN {nope} 4071"

        let glyphBox = Renderer.parts(for: withGlyph).first?.path.boundingBoxOfPath ?? .null
        let plainBox = Renderer.parts(for: plain).first?.path.boundingBoxOfPath ?? .null
        let unknownBox = Renderer.parts(for: unknown).first?.path.boundingBoxOfPath ?? .null
        if glyphBox.isNull || plainBox.isNull {
            failures.append("glyph text: produced no geometry")
        } else if glyphBox.width <= plainBox.width {
            failures.append("glyph text: two inline glyphs should be wider than the same label without them")
        }
        if unknownBox.isNull || unknownBox.width <= plainBox.width {
            failures.append("glyph text: an unknown token should stay as literal text, not vanish")
        }
        var probe = PanelDocument()
        var label = ElementKind.text.defaultElement(at: CGPoint(x: 10, y: 10))
        label.params.text = "PG"
        probe.elements = [label]
        if !SVGExporter.documentSVG(probe).contains("<path") {
            failures.append("text export: a text element produced no outline path")
        }

        return failures
    }

    /// One piece of artwork and one bound knob at a known position. Shared by
    /// the binding and codegen checks as a *fixture* rather than as a variable
    /// they both happen to see — which is what splitting these into separate
    /// functions was for.
    static func componentRig() -> PanelDocument {
        var doc = PanelDocument()
        var deco = ElementKind.box.defaultElement(at: CGPoint(x: 10, y: 10))
        deco.fill = .hex("#123456")
        var knob = ElementKind.knobLarge.defaultElement(at: CGPoint(x: 30, y: 100))
        knob.fill = .hex("#ABCDEF")
        knob.enumName = "CUTOFF"
        doc.elements = [deco, knob]
        return doc
    }

    static func bindingChecks() -> [String] {
        var failures: [String] = []

        // Components must not be painted into the panel: Rack and MetaModule
        // draw them on top, so the artwork would show through from underneath.
        let rig = componentRig()
        let deco = rig.elements[0]
        let knob = rig.elements[1]

        if knob.role != .param { failures.append("binding: a knob should default to .param") }
        if deco.role != .decoration { failures.append("binding: a box should default to .decoration") }
        if rig.components.count != 1 {
            failures.append("binding: expected 1 component, got \(rig.components.count)")
        }

        let panelSVG = SVGExporter.documentSVG(rig)
        if !panelSVG.contains("#123456") {
            failures.append("panel export: decoration was dropped from the artwork")
        }
        if panelSVG.contains("#ABCDEF") {
            failures.append("panel export: a bound component was painted into the artwork")
        }

        let comps = SVGExporter.componentsSVG(rig)
        if !comps.contains("id=\"components\"") {
            failures.append("components layer: helper.py needs a group with id=\"components\"")
        }
        if !comps.contains("<circle") {
            failures.append("components layer: use circles so helper.py emits the ...Centered forms")
        }
        if !comps.contains("fill=\"#ff0000\"") {
            failures.append("components layer: a param must be filled #ff0000 for helper.py")
        }
        if !comps.contains("data-name=\"CUTOFF#RoundLargeBlackKnob\"") {
            failures.append("components layer: data-name should carry NAME#WidgetClass")
        }

        // A namespaced custom widget must appear namespaced here too: helper.py
        // pastes this name into C++, and the direct emission already qualifies
        // it. If the two disagree, only one of the two routes compiles.
        var nsRig = componentRig()
        nsRig.widgetNamespace = "lcarsui"
        for i in nsRig.elements.indices where nsRig.elements[i].role == .param {
            nsRig.elements[i].widgetSource = .custom
            nsRig.elements[i].customWidgetName = "LcarsKnob"
        }
        let nsComps = SVGExporter.componentsSVG(nsRig)
        if !nsComps.contains("data-name=\"CUTOFF#lcarsui::LcarsKnob\"") {
            failures.append("components layer: a namespaced widget should be qualified for helper.py")
        }
        if !CodeGen.rackSource(nsRig).contains("createParamCentered<lcarsui::LcarsKnob>") {
            failures.append("codegen: the direct emission should qualify the same way")
        }

        return failures
    }

    static func symbolChecks() -> [String] {
        var failures: [String] = []

        // Every symbol must produce geometry, and it must stay inside its own
        // frame. The content box is inset by half the weight precisely so the
        // stroked outline — round caps included — cannot spill; test at the
        // maximum weight, where that rule is under the most strain.
        var seenIDs = Set<String>()
        for spec in SymbolCatalogue.all {
            if !seenIDs.insert(spec.id).inserted {
                failures.append("symbol \(spec.id): duplicate id in the catalogue")
            }
            if spec.parameters.count != 4 || spec.defaults.count != 4 {
                failures.append("symbol \(spec.id): needs exactly 4 parameter slots and defaults")
            }
            for (wide, tall) in [(CGFloat(60), CGFloat(30)), (CGFloat(24), CGFloat(60))] {
                var el = ElementKind.symbol.defaultElement(at: CGPoint(x: 15, y: 40))
                el.w = wide
                el.h = tall
                el.params.symbol = spec.id
                el.params.weight = SymbolCatalogue.maxWeight
                el.params.symbolA = spec.defaults[0]
                el.params.symbolB = spec.defaults[1]
                el.params.symbolC = spec.defaults[2]
                el.params.symbolD = spec.defaults[3]

                let box = SymbolCatalogue.path(for: el).boundingBoxOfPath
                if box.isNull || box.isEmpty {
                    failures.append("symbol \(spec.id): produced no geometry at \(Int(wide))×\(Int(tall))")
                    continue
                }
                // A little slack for curve flattening in boundingBoxOfPath.
                if !el.frame.insetBy(dx: -0.75, dy: -0.75).contains(box) {
                    failures.append("symbol \(spec.id): outline escapes its frame at \(Int(wide))×\(Int(tall))")
                }
            }
        }

        // And a symbol has to survive the export path like anything else.
        var symDoc = PanelDocument()
        symDoc.elements = [ElementKind.symbol.defaultElement(at: CGPoint(x: 20, y: 20))]
        if !SVGExporter.documentSVG(symDoc).contains("<path") {
            failures.append("symbol export: a symbol element produced no path in the SVG")
        }

        return failures
    }

    static func widgetChecks() -> [String] {
        var failures: [String] = []

        // Naming a selection numbers it in reading order, not in document
        // order and not by floating-point noise on y.
        var namer = PanelDocument()
        var n1 = ElementKind.jack.defaultElement(at: CGPoint(x: 200, y: 300))   // row 2, right
        var n2 = ElementKind.jack.defaultElement(at: CGPoint(x: 20, y: 300.4))  // row 2, left
        var n3 = ElementKind.jack.defaultElement(at: CGPoint(x: 110, y: 100))   // row 1, middle
        n1.name = "a"; n2.name = "b"; n3.name = "c"
        namer.elements = [n1, n2, n3]
        namer.nameSequentially(ids: Set(namer.elements.map { $0.id }), prefix: "IN")

        func named(_ id: UUID) -> String {
            namer.elements.first { $0.id == id }?.enumName ?? "?"
        }
        if named(n3.id) != "IN_1" {
            failures.append("naming: the top row should come first, got \(named(n3.id))")
        }
        if named(n2.id) != "IN_2" {
            failures.append("naming: left before right within a row, got \(named(n2.id))")
        }
        if named(n1.id) != "IN_3" {
            failures.append("naming: expected IN_3, got \(named(n1.id))")
        }

        // A plain group is not a widget. Rows of controls get grouped so they
        // move together; treating that as one composed control collapsed every
        // component in the row onto the group's centre.
        var rowDoc = PanelDocument()
        let shared = UUID()
        var rk = ElementKind.knobLarge.defaultElement(at: CGPoint(x: 20, y: 100))
        var rj = ElementKind.jack.defaultElement(at: CGPoint(x: 120, y: 100))
        rk.groupID = shared
        rj.groupID = shared
        rk.enumName = "CUTOFF"
        rj.enumName = "IN"
        rowDoc.elements = [rk, rj]

        if rowDoc.components.count != 2 {
            failures.append("group: a plain group of two components is still two components")
        }
        let rkCentre = rowDoc.componentCentreMM(rowDoc.elements[0])
        let rjCentre = rowDoc.componentCentreMM(rowDoc.elements[1])
        if abs(rkCentre.x - rjCentre.x) < 1 {
            failures.append("group: grouped components were collapsed onto one position")
        }
        if abs(rkCentre.x - PanelMetrics.mm(35)) > 0.001 {
            failures.append("group: a grouped component should keep its own centre (expected 11.853 mm)")
        }

        // Composed widgets: several elements promoted to one control.
        var wid = PanelDocument()
        var body = ElementKind.box.defaultElement(at: CGPoint(x: 100, y: 100))
        body.w = 40; body.h = 40; body.fill = .hex("#112244")
        var pointer = ElementKind.triangle.defaultElement(at: CGPoint(x: 115, y: 105))
        pointer.w = 10; pointer.h = 15; pointer.fill = .hex("#AA33BB")
        pointer.rotatesWithValue = true
        wid.elements = [body, pointer]
        let widIDs: Set<UUID> = [body.id, pointer.id]

        if !wid.makeWidget(ids: widIDs, name: "LcarsKnob", role: .param) {
            failures.append("widget: makeWidget refused a valid selection")
        }
        guard let anchor = wid.components.first else {
            failures.append("widget: no component after promotion")
            return failures
        }
        if wid.components.count != 1 {
            failures.append("widget: a widget is one component, got \(wid.components.count)")
        }
        if anchor.id != body.id {
            failures.append("widget: the anchor should be the part nearest the centre")
        }
        if anchor.customWidgetName != "LcarsKnob" || anchor.role != .param {
            failures.append("widget: the anchor did not take the name and role")
        }
        if anchor.groupID == nil || wid.widgetMembers(of: anchor).count != 2 {
            failures.append("widget: members are not grouped")
        }
        guard let widgetArt = wid.elements.first(where: { $0.id == pointer.id }) else {
            failures.append("widget: lost the artwork element")
            return failures
        }
        if widgetArt.role != .decoration || !wid.isWidgetArtwork(widgetArt) {
            failures.append("widget: the non-anchor part should be artwork, not a component")
        }

        let wBounds = wid.widgetBounds(of: anchor)
        if wBounds != CGRect(x: 100, y: 100, width: 40, height: 40) {
            failures.append("widget: bounds should be the union of the parts, got \(wBounds)")
        }

        // Artwork belongs to the widget's own SVG, never to the panel.
        let widPanel = SVGExporter.documentSVG(wid)
        if widPanel.contains("#AA33BB") || widPanel.contains("#112244") {
            failures.append("widget: parts were painted into the panel artwork")
        }

        // bg / fg split follows the per-part flag.
        let bg = SVGExporter.componentSVG(anchor, in: wid, layer: .knobBackground)
        let fg = SVGExporter.componentSVG(anchor, in: wid, layer: .knobForeground)
        if !bg.contains("#112244") || bg.contains("#AA33BB") {
            failures.append("widget: the background should hold the static part only")
        }
        if !fg.contains("#AA33BB") || fg.contains("#112244") {
            failures.append("widget: the foreground should hold the turning part only")
        }
        if !bg.contains("viewBox=\"0 0 40.00 40.00\"") {
            failures.append("widget: artwork should be sized to the widget's bounds")
        }
        let files = CodeGen.componentFiles(for: anchor, in: wid).map(\.name)
        if files != ["lcars-knob-bg.svg", "lcars-knob-fg.svg"] {
            failures.append("widget: expected a bg/fg pair, got \(files)")
        }

        // Generated code positions by the widget's bounds, not the anchor's.
        wid.moduleSlug = "WidgetTest"
        let widSrc = CodeGen.rackSource(wid)
        if !widSrc.contains("struct LcarsKnob : app::SvgKnob {") {
            failures.append("widget: a composed param with a turning part should subclass SvgKnob")
        }
        if !widSrc.contains("mm2px(Vec(40.640, 40.640))") {
            failures.append("widget: position should be the centre of the union (40.640 mm)")
        }

        // A composed param with nothing turning is a switch, and says so.
        var still = wid
        for i in still.elements.indices { still.elements[i].rotatesWithValue = false }
        if !CodeGen.warnings(still).contains(where: { $0.contains("generates as a switch") }) {
            failures.append("widget: a composed param with no turning part should warn")
        }

        return failures
    }

    static func uniformChecks() -> [String] {
        var failures: [String] = []

        // A homogeneous multi-selection gets one stand-in element; a mixed one
        // gets none, because the parameter rows would not mean the same thing
        // for every element the sliders write to.
        var uni = PanelDocument()
        let e1 = ElementKind.elbow.defaultElement(at: CGPoint(x: 10, y: 10))
        var e2 = ElementKind.elbow.defaultElement(at: CGPoint(x: 60, y: 10))
        e2.params.thickness = 24            // deliberately different
        e2.params.flipX = true
        let e3 = ElementKind.box.defaultElement(at: CGPoint(x: 10, y: 80))
        uni.elements = [e1, e2, e3]

        let elbows: Set<UUID> = [e1.id, e2.id]
        guard let stand = uni.uniformSelection(ids: elbows) else {
            failures.append("uniform: two elbows should yield a stand-in element")
            return failures
        }
        if stand.id != e1.id {
            failures.append("uniform: the stand-in should be the first in document order")
        }
        if uni.uniformSelection(ids: [e1.id, e3.id]) != nil {
            failures.append("uniform: an elbow and a box are not a homogeneous selection")
        }
        if uni.uniformSelection(ids: [e1.id]) != nil {
            failures.append("uniform: a single element is the primary selection, not a stand-in")
        }

        if uni.selectionAgrees(\.params.thickness, ids: elbows) {
            failures.append("uniform: thickness differs and should be reported as differing")
        }
        if !uni.selectionAgrees(\.params.armH, ids: elbows) {
            failures.append("uniform: armH matches and should be reported as agreeing")
        }
        if !uni.selectionAgrees(\.params.thickness, ids: [e1.id]) {
            failures.append("uniform: one element always agrees with itself")
        }

        // Symbols additionally have to be the *same* symbol: the rows are
        // labelled from the spec, so a sine and an ADSR share no meaning.
        var symA = ElementKind.symbol.defaultElement(at: .zero)
        var symB = ElementKind.symbol.defaultElement(at: CGPoint(x: 40, y: 0))
        symA.applySymbol("sine")
        symB.applySymbol("adsr")
        var symUni = PanelDocument()
        symUni.elements = [symA, symB]
        let symIDs: Set<UUID> = [symA.id, symB.id]
        if symUni.uniformSelection(ids: symIDs) != nil {
            failures.append("uniform: two different symbols are not a homogeneous selection")
        }
        symB.applySymbol("sine")
        symUni.elements = [symA, symB]
        if symUni.uniformSelection(ids: symIDs) == nil {
            failures.append("uniform: two of the same symbol should yield a stand-in")
        }

        return failures
    }

    static func presetChecks() -> [String] {
        var failures: [String] = []

        // Palette presets: one element kind appearing as several entries.
        var plainKnob = ElementKind.knobLarge.defaultElement(at: .zero)
        if plainKnob.params.knobStyle != 0 {
            failures.append("preset: a plain knob must stay what Rack draws")
        }
        plainKnob.applyPreset("ring")
        if plainKnob.params.knobStyle != 2 {
            failures.append("preset: the ring preset did not take")
        }
        plainKnob.applyPreset("plain")
        if plainKnob.params.knobStyle != 0 {
            failures.append("preset: the plain preset did not take")
        }
        var presetSymbol = ElementKind.symbol.defaultElement(at: .zero)
        presetSymbol.applyPreset("adsr")
        if presetSymbol.params.symbol != "adsr" || presetSymbol.params.symbolA != SymbolCatalogue.spec("adsr").defaults[0] {
            failures.append("preset: a symbol id should route through applySymbol with its defaults")
        }
        var unaffected = ElementKind.box.defaultElement(at: .zero)
        let before = unaffected.params
        unaffected.applyPreset("ring")
        if unaffected.params != before {
            failures.append("preset: an unknown preset must leave the element alone")
        }

        return failures
    }

    static func colourChecks() -> [String] {
        var failures: [String] = []

        // Colour grouping: distinct colours, most-used first, and recolouring
        // touches only the elements that carried that colour.
        var pal = PanelDocument()
        var c1 = ElementKind.knobSmall.defaultElement(at: CGPoint(x: 10, y: 10))
        var c2 = ElementKind.knobSmall.defaultElement(at: CGPoint(x: 30, y: 10))
        var c3 = ElementKind.knobSmall.defaultElement(at: CGPoint(x: 50, y: 10))
        var c4 = ElementKind.box.defaultElement(at: CGPoint(x: 10, y: 40))
        c1.fill = .hex("#112233"); c2.fill = .hex("#112233"); c3.fill = .hex("#112233")
        c4.fill = .hex("#AABBCC")
        c4.stroke = .hex("#FFFFFF")
        pal.elements = [c1, c2, c3, c4]
        let palIDs = Set(pal.elements.map(\.id))

        let groups = pal.colourGroups(ids: palIDs, strokes: false)
        if groups.count != 2 {
            failures.append("colours: expected 2 distinct fills, got \(groups.count)")
        } else {
            if groups[0].ids.count != 3 {
                failures.append("colours: most-used fill should come first")
            }
            if groups[0].colour.hexString != "#112233" {
                failures.append("colours: wrong colour ordered first")
            }
        }
        if pal.colourGroups(ids: palIDs, strokes: true).count != 1 {
            failures.append("colours: expected 1 distinct stroke")
        }

        var recoloured = pal
        recoloured.setColour(.hex("#FF0000"), ids: groups.first?.ids ?? [], strokes: false)
        if recoloured.elements[0].fill.hexString != "#FF0000"
            || recoloured.elements[2].fill.hexString != "#FF0000" {
            failures.append("colours: recolour did not reach every element in the group")
        }
        if recoloured.elements[3].fill.hexString != "#AABBCC" {
            failures.append("colours: recolour touched an element outside the group")
        }
        if recoloured.elements[3].stroke?.hexString != "#FFFFFF" {
            failures.append("colours: a fill recolour must not disturb strokes")
        }

        return failures
    }

    static func alignChecks() -> [String] {
        var failures: [String] = []

        // Align must use the selection's own bounds unless the panel is asked
        // for. Y grows downward, so "top" is the smallest y among the selected.
        var al = PanelDocument()
        let a1 = ElementKind.knobSmall.defaultElement(at: CGPoint(x: 20, y: 100))
        let a2 = ElementKind.knobSmall.defaultElement(at: CGPoint(x: 60, y: 160))
        al.elements = [a1, a2]
        let alIDs = Set(al.elements.map(\.id))

        var toSel = al
        toSel.align("T", ids: alIDs, toPanel: false)
        if toSel.elements[0].y != 100 || toSel.elements[1].y != 100 {
            failures.append("align: T should move both to the topmost selected edge (100), got \(toSel.elements[0].y) / \(toSel.elements[1].y)")
        }
        var toPanel = al
        toPanel.align("T", ids: alIDs, toPanel: true)
        if toPanel.elements[0].y != 0 || toPanel.elements[1].y != 0 {
            failures.append("align: T to the panel should move both to y = 0")
        }
        var leftSel = al
        leftSel.align("L", ids: alIDs, toPanel: false)
        if leftSel.elements[0].x != 20 || leftSel.elements[1].x != 20 {
            failures.append("align: L should move both to the leftmost selected edge (20)")
        }
        var single = al
        single.align("T", ids: [a1.id], toPanel: false)
        if single.elements[0].y != 100 {
            failures.append("align: a single element has no selection bounds to align to; it must not move")
        }

        return failures
    }

    static func bulkBindChecks() -> [String] {
        var failures: [String] = []

        // Bulk binding: a primitive takes the role its kind implies, artwork
        // stays artwork, and a role set by hand is never overwritten.
        var bulk = PanelDocument()
        var legacyKnob = ElementKind.knobLarge.defaultElement(at: CGPoint(x: 10, y: 10))
        legacyKnob.role = .decoration          // how a pre-binding file decodes
        legacyKnob.stockWidget = ""
        var legacyBox = ElementKind.box.defaultElement(at: CGPoint(x: 10, y: 60))
        legacyBox.role = .decoration
        var handSet = ElementKind.jack.defaultElement(at: CGPoint(x: 10, y: 110))
        handSet.role = .output                 // deliberate; must survive
        bulk.elements = [legacyKnob, legacyBox, handSet]

        let bound = bulk.bindPrimitives()
        if bound != 1 { failures.append("bind: expected 1 newly bound primitive, got \(bound)") }
        if bulk.elements[0].role != .param { failures.append("bind: a knob should become .param") }
        if bulk.elements[0].stockWidget != "RoundLargeBlackKnob" {
            failures.append("bind: a knob should pick up its default Rack type")
        }
        if bulk.elements[1].role != .decoration { failures.append("bind: a box must stay artwork") }
        if bulk.elements[2].role != .output { failures.append("bind: a hand-set role was overwritten") }
        if bulk.bindPrimitives() != 0 { failures.append("bind: a second pass should be a no-op") }

        return failures
    }

    // MARK: - SVG reading checks

    static func svgPathChecks() -> [String] {
        var failures: [String] = []

        func bbox(_ d: String, _ label: String) -> CGRect? {
            guard let p = SVGPath.path(fromD: d) else {
                failures.append("svgpath: could not parse \(label): \(d)")
                return nil
            }
            return p.boundingBoxOfPath
        }
        func near(_ a: CGFloat, _ b: CGFloat, _ tol: CGFloat = 0.01) -> Bool { abs(a - b) <= tol }

        if let r = bbox("M0 0 L10 0 L10 10 Z", "triangle"),
           !(near(r.minX, 0) && near(r.minY, 0) && near(r.width, 10) && near(r.height, 10)) {
            failures.append("svgpath: absolute lineto box wrong: \(r)")
        }

        // An implicit repeat of moveto is lineto. Get this wrong and a polygon
        // becomes a scatter of dots — silently, because it still parses.
        if let r = bbox("M0 0 5 0 5 5", "implicit lineto"),
           !(near(r.width, 5) && near(r.height, 5)) {
            failures.append("svgpath: implicit lineto after M not handled: \(r)")
        }

        // Relative commands, no separators between sign-prefixed numbers, and
        // exponent notation — all of which Double(String) alone gets wrong.
        if let r = bbox("m10 10l10 0l0 10z", "relative"),
           !(near(r.minX, 10) && near(r.width, 10)) {
            failures.append("svgpath: relative commands wrong: \(r)")
        }
        if let r = bbox("M0 0L10-5", "no separator"), !near(r.height, 5) {
            failures.append("svgpath: \"10-5\" should read as two numbers: \(r)")
        }
        if let r = bbox("M1e1 1e1L20 20", "exponent"), !near(r.minX, 10) {
            failures.append("svgpath: exponent notation wrong: \(r)")
        }

        // A half-circle arc: 10 wide, 5 tall. Arcs are where a path parser
        // usually goes quietly wrong.
        if let r = bbox("M0 0 A5 5 0 0 1 10 0", "arc"),
           !(near(r.width, 10, 0.05) && near(r.height, 5, 0.05)) {
            failures.append("svgpath: arc geometry wrong: \(r)")
        }
        // Flags may run together with the coordinate that follows them.
        if SVGPath.path(fromD: "M0 0a5 5 0 0110 0") == nil {
            failures.append("svgpath: run-together arc flags not handled")
        }

        // Garbage must fail rather than draw something plausible.
        if SVGPath.path(fromD: "M0 0 L10 Q") != nil {
            failures.append("svgpath: a truncated command should not parse")
        }
        if SVGPath.path(fromD: "10 10 L20 20") != nil {
            failures.append("svgpath: data without a leading command should not parse")
        }

        // Round trip: what PathSVG writes, SVGPath must read back.
        if let first = SVGPath.path(fromD: "M0 0 C0 5 5 10 10 10 L10 0 Z"),
           let second = SVGPath.path(fromD: PathSVG.d(first)) {
            let a = first.boundingBoxOfPath, b = second.boundingBoxOfPath
            if !(near(a.minX, b.minX) && near(a.minY, b.minY)
                 && near(a.width, b.width) && near(a.height, b.height)) {
                failures.append("svgpath: round trip through PathSVG.d moved the shape")
            }
        } else {
            failures.append("svgpath: round trip through PathSVG.d failed to parse")
        }

        // Transforms. The list applies left to right, outermost first.
        guard let t = SVGPath.transform(from: "translate(10 20) scale(2)") else {
            return failures + ["svgtransform: translate+scale did not parse"]
        }
        let p = CGPoint(x: 1, y: 1).applying(t)
        if !(near(p.x, 12) && near(p.y, 22)) {
            failures.append("svgtransform: expected (12, 22), got \(p)")
        }
        if let r = SVGPath.transform(from: "rotate(90 5 5)") {
            let q = CGPoint(x: 5, y: 0).applying(r)
            if !(near(q.x, 10, 0.001) && near(q.y, 5, 0.001)) {
                failures.append("svgtransform: rotate about a centre wrong: \(q)")
            }
        } else {
            failures.append("svgtransform: rotate(a cx cy) did not parse")
        }
        if SVGPath.transform(from: "wobble(3)") != nil {
            failures.append("svgtransform: an unknown function should fail, not be ignored")
        }
        if SVGPath.transform(from: "")?.isIdentity != true {
            failures.append("svgtransform: an empty list should be the identity")
        }

        return failures
    }

    /// A panel SVG in millimetre user units, the shape Rack panels actually
    /// take: viewBox in mm, a full-bleed background, one rounded rect, one
    /// circle, one transformed path, and a helper.py components layer.
    private static let importFixture = """
    <svg xmlns="http://www.w3.org/2000/svg" width="30.48mm" height="128.5mm" viewBox="0 0 30.48 128.5">
      <rect width="30.48" height="128.5" fill="#1d1713"/>
      <rect x="2" y="2" width="10" height="4" rx="1" style="fill:#ff9c00"/>
      <circle cx="10" cy="20" r="3" fill="#99ccff"/>
      <defs><clipPath id="c"><rect x="0" y="0" width="1" height="1"/></clipPath></defs>
      <g transform="translate(5 40)"><path d="M0 0 L8 0 L8 8 Z" fill="#cc99cc"/></g>
      <g id="components">
        <circle cx="6" cy="100" r="2" fill="#00ff00" data-name="CV_IN"/>
        <circle cx="20" cy="100" r="2" fill="#0000ff" data-name="OUT#PJ3410Port"/>
      </g>
    </svg>
    """

    static func svgImportChecks() -> [String] {
        var failures: [String] = []
        let data = Data(importFixture.utf8)

        let outcome: SVGImport.Outcome
        do {
            outcome = try SVGImport.outcome(from: data)
        } catch {
            return ["svgimport: fixture failed to import: \(error)"]
        }

        // Millimetre user units are the whole ballgame. 30.48 mm is 6 HP; at
        // 1:1 it would come in as 2 HP and every position would be a third of
        // where it belongs.
        if outcome.widthHP != 6 { failures.append("svgimport: expected 6 HP, got \(outcome.widthHP)") }
        if outcome.format != .u3 { failures.append("svgimport: expected a 3U panel") }
        if outcome.background?.hexString.lowercased() != "#1d1713" {
            failures.append("svgimport: the full-bleed rect should become the panel background")
        }
        if outcome.elements.count != 5 {
            failures.append("svgimport: expected 5 elements, got \(outcome.elements.count)")
        }

        let scale = 75.0 / 25.4 as CGFloat
        func near(_ a: CGFloat, _ b: CGFloat, _ tol: CGFloat = 0.05) -> Bool { abs(a - b) <= tol }

        // A rounded rect is a Box, with its radius scaled like everything else.
        if let box = outcome.elements.first(where: { $0.kind == .box }) {
            if !(near(box.x, 2 * scale) && near(box.w, 10 * scale)) {
                failures.append("svgimport: rect placed at \(box.frame), expected mm→px scaling")
            }
            if !near(box.params.cornerTL, 1 * scale) {
                failures.append("svgimport: corner radius not scaled: \(box.params.cornerTL)")
            }
            if box.fill.hexString.lowercased() != "#ff9c00" {
                failures.append("svgimport: style=\"fill:…\" was not read")
            }
        } else {
            failures.append("svgimport: the rounded rect should come back as a Box")
        }

        // A circle is an Ellipse, not a path — that one is worth recognising
        // because a jack outline is a circle in every panel ever drawn.
        let ellipses = outcome.elements.filter { $0.kind == .ellipse }
        if ellipses.count != 3 {
            failures.append("svgimport: expected 3 ellipses, got \(ellipses.count)")
        }

        // The transformed path keeps its place and comes back as a Path.
        if let path = outcome.elements.first(where: { $0.kind == .path }) {
            if !near(path.x, 5 * scale) {
                failures.append("svgimport: group transform not applied: x=\(path.x)")
            }
            if path.pathData?.isEmpty != false {
                failures.append("svgimport: a Path element carries no path data")
            }
            if Renderer.importedParts(for: path).isEmpty {
                failures.append("svgimport: an imported path does not render")
            }
        } else {
            failures.append("svgimport: the transformed path did not import")
        }

        // The components layer is what turns a picture into a module.
        let inputs = outcome.elements.filter { $0.role == .input }
        let outputs = outcome.elements.filter { $0.role == .output }
        if inputs.count != 1 || outputs.count != 1 {
            failures.append("svgimport: components layer gave \(inputs.count) inputs, \(outputs.count) outputs")
        }
        if inputs.first?.enumName != "CV_IN" {
            failures.append("svgimport: data-name should become the identifier")
        }
        if inputs.first?.stockWidget != "PJ301MPort" {
            failures.append("svgimport: an unqualified port should fall back to PJ301MPort")
        }
        if outputs.first?.stockWidget != "PJ3410Port" {
            failures.append("svgimport: data-name's #WidgetClass suffix should set the Rack type")
        }
        if outputs.first?.enumName != "OUT" {
            failures.append("svgimport: the #WidgetClass suffix should not survive in the identifier")
        }

        // Template mode: reference only, and never exported.
        var options = SVGImport.Options()
        options.asTemplate = true
        guard let template = try? SVGImport.outcome(from: data, options: options) else {
            return failures + ["svgimport: template import failed"]
        }
        if !template.elements.allSatisfy({ $0.isTemplate == true && $0.role == .decoration }) {
            failures.append("svgimport: template elements must be template artwork, never components")
        }
        var doc = PanelDocument()
        doc.widthHP = template.widthHP
        doc.elements = template.elements
        let svg = SVGExporter.documentSVG(doc)
        if svg.contains("#cc99cc") {
            failures.append("svgimport: a template must not reach the exported SVG")
        }

        // A file with no viewBox cannot be placed, and must say so rather than
        // importing everything at the origin.
        let noBox = Data("<svg xmlns=\"http://www.w3.org/2000/svg\"><rect width=\"5\" height=\"5\"/></svg>".utf8)
        do {
            _ = try SVGImport.outcome(from: noBox)
            failures.append("svgimport: an SVG without a viewBox should be refused")
        } catch {}

        return failures
    }

    // MARK: - C++ reading checks

    /// A module source in the shapes real ones are written in: a named grid in
    /// constants, `7.0f` literals, a namespaced custom widget, a nested light
    /// template, one uncentred call, and a METAMODULE fork.
    private static let cppFixture = """
    namespace grid {
    constexpr float PRIMARY_Y = 27.2f;
    constexpr float SECOND_Y = PRIMARY_Y + 14.0f;
    }

    inline void addKnobLabel(ModuleWidget* w, float xmm, float ymm, const std::string& text) {
        addLabel(w, xmm, ymm, text, fontLabelSemiBold(), 7.5f, colorLabel(), 0.5f);
    }

    struct DemoWidget : ModuleWidget {
        DemoWidget(Demo* module) {
            setModule(module);
    #ifdef METAMODULE
            setPanel(createPanel(asset::plugin(pluginInstance, "res/Demo-mm.svg")));
    #else
            setPanel(themed(asset::plugin(pluginInstance, "res/Demo-light.svg"),
                            asset::plugin(pluginInstance, "res/Demo.svg")));
    #endif
            addChild(createWidget<ScrewSilver>(Vec(RACK_GRID_WIDTH, 0)));

            // The main frequency control.
            addParam(createParamCentered<RoundLargeBlackKnob>(
                mm2px(Vec(15.24, grid::PRIMARY_Y)), module, Demo::CUTOFF_PARAM));
            addParam(createParam<Trimpot>(mm2px(Vec(5.0f, grid::SECOND_Y)), module, Demo::FINE_PARAM));
            addInput(createInputCentered<PJ301MPort>(
                mm2px(Vec(7.62f, 100.0f)), module, Demo::IN_INPUT));
            addOutput(createOutputCentered<museui::IoJack>(
                mm2px(Vec(22.86f, 100.0f)), module, Demo::OUT_OUTPUT));
            addChild(createLightCentered<MediumLight<GreenRedLight>>(
                mm2px(Vec(15.24f, 110.0f)), module, Demo::BUSY_LIGHT));
            ui::addKnobLabel(this, 15.24f, 33.0f, "CUTOFF");
            nvgText(args.vg, 1.0f, 2.0f, "not a label");
        }
    };

    Model* modelDemo = createModel<Demo, DemoWidget>("Demo");
    """

    static func cppImportChecks() -> [String] {
        var failures: [String] = []
        let out = CppImport.outcome(from: cppFixture)

        func near(_ a: CGFloat, _ b: CGFloat, _ tol: CGFloat = 0.05) -> Bool { abs(a - b) <= tol }
        func px(_ mm: CGFloat) -> CGFloat { mm / PanelMetrics.mmPerPixel }

        if out.elements.count != 7 {
            failures.append("cpp: expected 7 elements, got \(out.elements.count)")
        }
        if out.moduleSlug != "Demo" {
            failures.append("cpp: module slug should come from createModel, got \(out.moduleSlug ?? "nil")")
        }
        // The METAMODULE branch must not win: its panel is a different file,
        // and importing it would bring in the wrong artwork silently.
        if out.panelResource != "res/Demo.svg" {
            failures.append("cpp: panel should be res/Demo.svg, got \(out.panelResource ?? "nil")")
        }

        func element(_ name: String) -> PanelElement? {
            out.elements.first { $0.enumName == name }
        }

        // Named constants and mm2px together: the position that is unreadable
        // without resolving grid::PRIMARY_Y.
        if let cutoff = element("CUTOFF") {
            if cutoff.role != .param { failures.append("cpp: CUTOFF should be a param") }
            if cutoff.kind != .knobLarge { failures.append("cpp: RoundLargeBlackKnob should be a large knob") }
            if !(near(cutoff.center.x, px(15.24)) && near(cutoff.center.y, px(27.2))) {
                failures.append("cpp: CUTOFF centre \(cutoff.center), expected mm2px(15.24, 27.2)")
            }
            if cutoff.stockWidget != "RoundLargeBlackKnob" {
                failures.append("cpp: the Rack type should be kept verbatim")
            }
        } else {
            failures.append("cpp: CUTOFF_PARAM did not import (constant resolution?)")
        }

        // A constant defined in terms of another one.
        if let fine = element("FINE") {
            if !near(fine.y, px(41.2)) {
                failures.append("cpp: SECOND_Y = PRIMARY_Y + 14 not resolved: y=\(fine.y)")
            }
            // createParam, not createParamCentered: a top-left position, and
            // that difference has to be reported rather than absorbed.
            if !near(fine.x, px(5.0)) {
                failures.append("cpp: an uncentred call should be placed at the corner given")
            }
            if !out.warnings.contains(where: { $0.contains("top-left") }) {
                failures.append("cpp: an uncentred call must warn that it is not a centre")
            }
        } else {
            failures.append("cpp: FINE_PARAM did not import")
        }

        // A namespaced type is one of the plugin's own widgets, not Rack's.
        if let output = element("OUT") {
            if output.role != .output { failures.append("cpp: OUT should be an output") }
            if output.widgetSource != .custom || output.customWidgetName != "IoJack" {
                failures.append("cpp: museui::IoJack should import as a custom widget named IoJack")
            }
            if output.kind != .jack { failures.append("cpp: a Jack type should draw as a jack") }
        } else {
            failures.append("cpp: OUT_OUTPUT did not import")
        }

        // A nested light template must survive as written.
        if let light = element("BUSY") {
            if light.role != .light || light.kind != .led {
                failures.append("cpp: BUSY_LIGHT should be an LED light")
            }
            if light.stockWidget != "MediumLight<GreenRedLight>" {
                failures.append("cpp: nested light template mangled: \(light.stockWidget)")
            }
        } else {
            failures.append("cpp: BUSY_LIGHT did not import")
        }

        // Screws are artwork: Rack draws them, but nothing binds to them.
        if let screw = out.elements.first(where: { $0.kind == .screw }) {
            if screw.role != .decoration { failures.append("cpp: a screw is not a component") }
            if !near(screw.x, 15) { failures.append("cpp: RACK_GRID_WIDTH not evaluated: x=\(screw.x)") }
        } else {
            failures.append("cpp: createWidget<ScrewSilver> did not import")
        }

        if !out.warnings.contains(where: { $0.contains("MetaModule") }) {
            failures.append("cpp: the METAMODULE fork should be reported")
        }

        // Panel text is often not in the SVG at all — Muse draws every label
        // from code — so a reader that ignored helper calls would import a
        // panel with nothing written on it.
        let texts = out.elements.filter { $0.kind == .text }
        if texts.count != 1 {
            failures.append("cpp: expected 1 label from a helper call, got \(texts.count)")
        }
        if let label = texts.first {
            if label.params.text != "CUTOFF" {
                failures.append("cpp: label text wrong: \(label.params.text)")
            }
            // The size comes from the helper's own definition, not a guess.
            if !near(label.params.fontSize, 7.5) {
                failures.append("cpp: label size should come from the helper, got \(label.params.fontSize)")
            }
            if !(near(label.center.x, px(15.24)) && near(label.center.y, px(33.0))) {
                failures.append("cpp: a label should be centred on its position, got \(label.center)")
            }
        }
        // A switch's position count is only in its type name. Four is the
        // palette default, and a three-way switch imported as four offers the
        // module a value it has no case for.
        if CppImport.switchPositions("Switch3Way") != 3 {
            failures.append("cpp: Switch3Way should be a 3-position switch")
        }
        if CppImport.switchPositions("CKSSThree") != 3 {
            failures.append("cpp: CKSSThree should be a 3-position switch")
        }
        if CppImport.switchPositions("CKSS") != 2 {
            failures.append("cpp: a bare CKSS is a two-position switch")
        }
        if CppImport.switchPositions("RoundBlackKnob") != nil {
            failures.append("cpp: a knob is not a switch")
        }

        // A draw call has the same arity as a label helper. The receiver is
        // what tells them apart, and it has to.
        if out.elements.contains(where: { $0.params.text == "not a label" }) {
            failures.append("cpp: nvgText was mistaken for a label helper")
        }

        // The arithmetic the reader leans on.
        let table = CppImport.builtinConstants
        if Expression.evaluate("RACK_GRID_WIDTH * 2 + 1", constants: table) != 31 {
            failures.append("cpp: expression arithmetic wrong")
        }
        if Expression.evaluate("(1 + 2) * -3", constants: table) != -9 {
            failures.append("cpp: parentheses or unary minus wrong")
        }
        if Expression.evaluate("7.5f", constants: table) != 7.5 {
            failures.append("cpp: float suffix not handled")
        }
        if Expression.evaluate("module->x", constants: table) != nil {
            failures.append("cpp: an unresolvable expression must fail, not evaluate to something")
        }

        // Comments must not swallow code, and strings must survive them.
        let stripped = CppImport.stripComments("""
        int a = 1; // "not a string"
        const char* s = "keep // this";
        /* block
           comment */ int b = 2;
        """)
        if !stripped.contains("keep // this") {
            failures.append("cpp: comment stripping ate a string literal")
        }
        if stripped.contains("not a string") || stripped.contains("block") {
            failures.append("cpp: comments were not stripped")
        }
        if !stripped.contains("int b = 2;") {
            failures.append("cpp: code after a block comment was lost")
        }

        return failures
    }

    // MARK: - Comparison checks

    static func compareChecks() -> [String] {
        var failures: [String] = []

        func item(_ id: String, _ role: ComponentRole, _ widget: String,
                  _ x: CGFloat, _ y: CGFloat) -> Compare.Item {
            Compare.Item(identifier: id, role: role, widget: widget, mm: CGPoint(x: x, y: y))
        }

        let base = Compare.Side(label: "A", items: [
            item("CUTOFF_PARAM", .param, "RoundBlackKnob", 15.24, 38.95),
            item("IN_INPUT", .input, "PJ301MPort", 7.62, 100.0),
            item("OUT_OUTPUT", .output, "PJ301MPort", 22.86, 100.0),
        ])

        // The three forms round differently, so agreement has to mean "within a
        // tolerance". Zero would report every component as moved.
        var rounded = base
        rounded.label = "B"
        rounded.items[0].mm.x += 0.004
        if !Compare.differences(base, rounded, tolerance: 0.01).isEmpty {
            failures.append("compare: a rounding-sized difference should not be a difference")
        }

        var moved = base
        moved.items[1].mm.y += 0.5
        let movedDiffs = Compare.differences(base, moved, tolerance: 0.01)
        if movedDiffs.count != 1 || movedDiffs.first?.identifier != "IN_INPUT" {
            failures.append("compare: expected one moved component, got \(movedDiffs.count)")
        }

        var changed = base
        changed.items[0].widget = "Trimpot"
        changed.items[2].role = .input
        let changedDiffs = Compare.differences(base, changed, tolerance: 0.01)
        if !changedDiffs.contains(where: { $0.kind == .widget }) {
            failures.append("compare: a changed widget type should be reported")
        }
        // Role changes matter most of all: an output silently read as an input
        // is the bug that shows up as a patch cable that will not connect.
        if !changedDiffs.contains(where: { $0.kind == .role }) {
            failures.append("compare: a changed role should be reported")
        }

        var dropped = base
        dropped.items.removeLast()
        let droppedDiffs = Compare.differences(base, dropped, tolerance: 0.01)
        if droppedDiffs.filter({ $0.kind == .missing }).count != 1 {
            failures.append("compare: a component missing from B should be reported once")
        }
        if Compare.differences(dropped, base, tolerance: 0.01).filter({ $0.kind == .added }).count != 1 {
            failures.append("compare: the same difference the other way round should read as added")
        }

        // A rename is one edit, and reporting it as a deletion plus an addition
        // buries it in a list of things that did not really change.
        var renamed = base
        renamed.items[0].identifier = "FREQ_PARAM"
        let renameDiffs = Compare.differences(base, renamed, tolerance: 0.01)
        if renameDiffs.count != 1 || renameDiffs.first?.kind != .renamed {
            failures.append("compare: a component at the same position under a new name is a rename, got "
                + "\(renameDiffs.map { "\($0.kind)" }.joined(separator: ", "))")
        }

        // Labels carry no identifier, so they match by their words — and a
        // panel with four jacks all labelled "CV" must not shuffle them.
        var left = Compare.Side(label: "A")
        left.labels = [("CV", CGPoint(x: 10, y: 20)), ("CV", CGPoint(x: 30, y: 20)),
                       ("GATE", CGPoint(x: 50, y: 20))]
        var right = left
        right.label = "B"
        right.labels = [("CV", CGPoint(x: 30, y: 20)), ("CV", CGPoint(x: 10, y: 20)),
                        ("GATE", CGPoint(x: 50, y: 20))]
        if !Compare.labelDifferences(left, right, tolerance: 0.01).isEmpty {
            failures.append("compare: identical labels in a different order are not a difference")
        }

        var missingLabel = left
        missingLabel.labels.removeLast()
        let labelDiffs = Compare.labelDifferences(left, missingLabel, tolerance: 0.01)
        if labelDiffs.count != 1 || labelDiffs.first?.kind != .missing {
            failures.append("compare: a dropped label should be reported once")
        }

        return failures
    }

    // MARK: - Label checks

    static func labelChecks() -> [String] {
        var failures: [String] = []

        var doc = PanelDocument()
        var named = ElementKind.jack.defaultElement(at: CGPoint(x: 40, y: 100))
        named.enumName = "CV_IN"
        let unnamed = ElementKind.jack.defaultElement(at: CGPoint(x: 80, y: 100))
        var existing = ElementKind.text.defaultElement(at: CGPoint(x: 0, y: 300))
        existing.params.text = "KEEP ME"
        doc.elements = [named, unnamed, existing]
        let ids: Set<UUID> = [named.id, unnamed.id, existing.id]

        // One label for the one named component. The unnamed jack is reported,
        // not labelled "Jack (3.5 mm)"; the text element in the selection is
        // not labelled at all.
        let first = doc.labelSelection(ids: ids, placement: .below, gap: 4, fontSize: 7,
                                       bold: true, uppercase: true, spaceUnderscores: true,
                                       colour: .hex("#E8E8F0"))
        if first.created != 1 { failures.append("label: expected 1 label, got \(first.created)") }
        if first.skipped != 1 { failures.append("label: the unnamed jack should be reported as skipped") }

        guard let made = doc.elements.first(where: { $0.labelOwner == named.id }) else {
            return failures + ["label: no label was attached to the named jack"]
        }
        if made.params.text != "CV IN" {
            failures.append("label: underscores should read as spaces, got \(made.params.text)")
        }
        if abs(made.center.x - named.center.x) > 0.01 {
            failures.append("label: a below label should be centred on its component")
        }
        if made.y < named.frame.maxY {
            failures.append("label: a below label should sit under its component")
        }
        if made.role != .decoration {
            failures.append("label: a label is artwork, never a component")
        }
        if doc.elements.contains(where: { $0.labelOwner == existing.id }) {
            failures.append("label: a text element in the selection should not be labelled")
        }

        // Re-running replaces rather than stacking. Getting the size wrong the
        // first time is the normal case, so this is the path that matters.
        let second = doc.labelSelection(ids: ids, placement: .above, gap: 6, fontSize: 9,
                                        bold: true, uppercase: true, spaceUnderscores: true,
                                        colour: .hex("#E8E8F0"))
        let labels = doc.elements.filter { $0.labelOwner != nil }
        if second.created != 1 || labels.count != 1 {
            failures.append("label: re-labelling should replace, found \(labels.count) labels")
        }
        if let above = labels.first, above.frame.maxY > named.y {
            failures.append("label: an above label should sit over its component")
        }
        if !doc.elements.contains(where: { $0.params.text == "KEEP ME" }) {
            failures.append("label: re-labelling removed a hand-made text element")
        }

        // A composed widget is labelled once, under the whole artwork — not
        // once per part, and not against the anchor's own frame.
        var wdoc = PanelDocument()
        let knob = ElementKind.knobLarge.defaultElement(at: CGPoint(x: 100, y: 100))
        var ring = ElementKind.ringSector.defaultElement(at: CGPoint(x: 88, y: 88))
        ring.w = 54; ring.h = 54
        wdoc.elements = [knob, ring]
        let wids: Set<UUID> = [knob.id, ring.id]
        if !wdoc.makeWidget(ids: wids, name: "LcarsKnob", role: .param) {
            failures.append("label: makeWidget fixture failed")
        }
        let anchor = wdoc.elements.first { $0.widgetSource == .custom }
        let wResult = wdoc.labelSelection(ids: wids, placement: .below, gap: 4, fontSize: 7,
                                          bold: true, uppercase: true, spaceUnderscores: true,
                                          colour: .hex("#E8E8F0"))
        if wResult.created != 1 {
            failures.append("label: a composed widget should take one label, got \(wResult.created)")
        }
        if let anchor, let wLabel = wdoc.elements.first(where: { $0.labelOwner == anchor.id }) {
            let bounds = wdoc.widgetBounds(of: anchor)
            if wLabel.y < bounds.maxY {
                failures.append("label: a widget's label should clear the whole artwork, not just the anchor")
            }
            if abs(wLabel.center.x - bounds.midX) > 0.01 {
                failures.append("label: a widget's label should be centred on the artwork")
            }
        } else {
            failures.append("label: the widget's label is not attached to its anchor")
        }

        // The frame is measured from the glyph run: a long label must not come
        // back the same width as a short one.
        var short = ElementKind.text.defaultElement(at: .zero)
        short.params.text = "IN"
        var long = short
        long.params.text = "CUTOFF FREQUENCY"
        if Renderer.textSize(for: long).width <= Renderer.textSize(for: short).width {
            failures.append("label: text size is not measured from the glyph run")
        }

        return failures
    }

    static func codegenChecks() -> [String] {
        var failures: [String] = []

        // Generated C++ must namespace the enum to the module, position by
        // centre, and convert px to the millimetres mm2px() expects.
        var rig = componentRig()
        rig.moduleSlug = "TestModule"
        let src = CodeGen.rackSource(rig)
        if !src.contains("enum ParamId {") { failures.append("codegen: no ParamId enum") }
        if !src.contains("CUTOFF_PARAM,") { failures.append("codegen: CUTOFF_PARAM missing from the enum") }
        if !src.contains("TestModule::CUTOFF_PARAM") { failures.append("codegen: enum not namespaced to the module") }
        if !src.contains("res/TestModule.svg") { failures.append("codegen: setPanel path wrong") }
        // The regenerable header: same positions as the flat form, wrapped so a
        // module source can include it without ever being rewritten.
        let header = CodeGen.panelHeader(rig)
        if !header.contains("#pragma once") || !header.contains("namespace TestModulePanel {") {
            failures.append("header: missing include guard or namespace")
        }
        if !header.contains("inline void addComponents(ModuleWidget* widget, Module* module) {") {
            failures.append("header: missing addComponents entry point")
        }
        if !header.contains("widget->addParam(createParamCentered<RoundLargeBlackKnob>(mm2px(Vec(15.240, 38.947))") {
            failures.append("header: component lines should be addressed to the widget, at the same position as the flat form")
        }
        if header.contains("\ncreateModel<") {
            failures.append("header: registration belongs in the module source, not the generated header")
        }

        // Rack's slug rule, checked here rather than at Rack's load time.
        if CodeGen.isValidSlug("Muse ND") || CodeGen.isValidSlug("") || CodeGen.isValidSlug("a/b") {
            failures.append("slug: spaces, slashes and empties are not valid Rack slugs")
        }
        if !CodeGen.isValidSlug("Muse-ND") || !CodeGen.isValidSlug("Muse_ND2") {
            failures.append("slug: letters, digits, - and _ are valid")
        }
        if CodeGen.slugSuggestion("Muse ND") != "Muse-ND" {
            failures.append("slug: suggestion for \"Muse ND\" should be \"Muse-ND\", got \(CodeGen.slugSuggestion("Muse ND"))")
        }
        var badSlug = componentRig()
        badSlug.moduleSlug = "Muse ND"
        if !CodeGen.warnings(badSlug).contains(where: { $0.contains("not a valid Rack slug") }) {
            failures.append("slug: an invalid module slug should warn")
        }

        if !src.contains("createModel<TestModule, TestModuleWidget>(\"TestModule\")") {
            failures.append("codegen: missing the createModel registration line")
        }
        if !src.contains("\"slug\": \"TestModule\"") {
            failures.append("codegen: missing the plugin.json module entry")
        }
        if !src.contains("addParam(createParamCentered<RoundLargeBlackKnob>(") {
            failures.append("codegen: param line missing, or not the Centered form")
        }
        // Knob at x=30 px, 30 px wide → centre 45 px → 45 * 25.4/75 = 15.240 mm.
        if !src.contains("mm2px(Vec(15.240, 38.947))") {
            failures.append("codegen: px→mm conversion wrong (expected 15.240, 38.947)")
        }

        // Components sharing a name must not emit duplicate enum entries. Seven
        // faders dropped on a panel are all called "Fader · Vertical".
        let dupA = ElementKind.faderVertical.defaultElement(at: CGPoint(x: 10, y: 200))
        let dupB = ElementKind.faderVertical.defaultElement(at: CGPoint(x: 40, y: 200))
        var dupDoc = PanelDocument()
        dupDoc.elements = [dupA, dupB]
        let dupSrc = CodeGen.rackSource(dupDoc)
        if dupSrc.components(separatedBy: "FADER_VERTICAL_PARAM,").count - 1 != 1 {
            failures.append("codegen: duplicate names produced duplicate enum entries")
        }
        if !dupSrc.contains("FADER_VERTICAL_2_PARAM,") {
            failures.append("codegen: second same-named component should be numbered _2")
        }

        // …but only inside one enum. Rack keeps ParamId and InputId apart, so a
        // knob and the CV input feeding it may both be called ANIMATE — which
        // is the normal way a module is named, not an accident. Numbering those
        // apart renamed five identifiers on the first real module tried.
        var sameName = PanelDocument()
        var knob = ElementKind.knobLarge.defaultElement(at: CGPoint(x: 10, y: 10))
        knob.role = .param
        knob.enumName = "ANIMATE"
        var jack = ElementKind.jack.defaultElement(at: CGPoint(x: 10, y: 60))
        jack.role = .input
        jack.enumName = "ANIMATE"
        var outJack = ElementKind.jack.defaultElement(at: CGPoint(x: 10, y: 110))
        outJack.role = .output
        outJack.enumName = "ANIMATE"
        sameName.elements = [knob, jack, outJack]
        let sameSrc = CodeGen.rackSource(sameName)
        for expected in ["ANIMATE_PARAM,", "ANIMATE_INPUT,", "ANIMATE_OUTPUT,"] where !sameSrc.contains(expected) {
            failures.append("codegen: \(expected) should survive — different enums do not clash")
        }
        if sameSrc.contains("ANIMATE_2") {
            failures.append("codegen: names in different enums were numbered apart")
        }
        if CodeGen.warnings(sameName).contains(where: { $0.contains("share the name") }) {
            failures.append("codegen: a name reused across enums is not a clash and must not warn")
        }

        // A document just written is current, whatever it was read from.
        var stamped = PanelDocument()
        stamped.schemaVersion = 0
        if let tmp = try? FileManager.default.url(for: .itemReplacementDirectory,
                                                  in: .userDomainMask,
                                                  appropriateFor: URL(fileURLWithPath: NSTemporaryDirectory()),
                                                  create: true).appendingPathComponent("stamp.panelgen") {
            do {
                try stamped.save(to: tmp)
                let back = try PanelDocument.load(from: tmp)
                if back.schemaVersion != PanelDocument.currentSchemaVersion {
                    failures.append("persistence: save should stamp the current schemaVersion, got \(back.schemaVersion)")
                }
                try? FileManager.default.removeItem(at: tmp)
            } catch {
                failures.append("persistence: schemaVersion stamp check failed: \(error)")
            }
        }

        // A custom widget generates its struct, its asset path and its call site.
        var custom = ElementKind.knobMedium.defaultElement(at: CGPoint(x: 60, y: 60))
        custom.widgetSource = .custom
        custom.customWidgetName = "LcarsKnob"
        custom.enumName = "RES"
        rig.elements.append(custom)
        let src2 = CodeGen.rackSource(rig)
        if !src2.contains("struct LcarsKnob : app::SvgKnob {") {
            failures.append("codegen: custom knob struct not generated")
        }
        // A custom knob must split into a static body and a rotating indicator,
        // the way Rack's own RoundKnob does — a single rotating SVG would spin
        // the knob body along with the pointer.
        if !src2.contains("bg->setSvg(") || !src2.contains("fb->addChildBelow(bg, tw);") {
            failures.append("codegen: custom knob is not the bg/fg RoundKnob shape")
        }
        if !src2.contains("res/components/lcars-knob-bg.svg")
            || !src2.contains("res/components/lcars-knob-fg.svg") {
            failures.append("codegen: custom knob asset paths missing or not kebab-case")
        }
        if !src2.contains("addParam(createParamCentered<LcarsKnob>(") {
            failures.append("codegen: custom widget class not used at the call site")
        }
        // Artwork keeps the viewBox in panel px but declares a physical size in
        // mm: rasterisers read the width attribute, and one in this toolchain
        // raises outright on a unitless value.
        let art = SVGExporter.componentSVG(custom, layer: .knobForeground)
        if !art.contains("viewBox=\"0 0 25.00 25.00\"") {
            failures.append("component art: viewBox must stay the element's px size (25×25)")
        }
        if !art.contains("width=\"8.47mm\"") {
            failures.append("component art: width should be declared in mm (8.47mm for 25 px)")
        }
        if !SVGExporter.documentSVG(rig).contains("mm\"") {
            failures.append("panel export: width/height should carry the mm unit by default")
        }

        return failures
    }

    /// A .panelgen exactly as the pre-button-group build wrote it: no
    /// schemaVersion, no params.segments / params.layout, no isHidden,
    /// no groupID. Embedded rather than kept as a file so the check cannot
    /// silently skip itself when a path is wrong.
    static let legacyDocumentJSON = #"""
    {
      "background" : { "a" : 1, "b" : 0.0784313725490196, "g" : 0.09019607843137255, "r" : 0.09019607843137255 },
      "elements" : [
        {
          "fill" : { "a" : 1, "b" : 0, "g" : 0.611764705882353, "r" : 1 },
          "h" : 30,
          "id" : "1E1B0C6E-0000-4000-8000-000000000001",
          "kind" : "knobLarge",
          "name" : "Knob · Large",
          "params" : {
            "armH" : 56, "armV" : 56, "bold" : true,
            "cornerBL" : 0, "cornerBR" : 0, "cornerTL" : 0, "cornerTR" : 0,
            "flipX" : false, "flipY" : false, "fontSize" : 12,
            "innerRadius" : 8, "pointerAngle" : 45,
            "startAngle" : -90, "sweepAngle" : 100,
            "text" : "LABEL", "thickness" : 16, "value" : 0.5
          },
          "rotation" : 0, "strokeWidth" : 1.5, "w" : 30, "x" : 30, "y" : 100
        },
        {
          "fill" : { "a" : 1, "b" : 0.9411764705882353, "g" : 0.9098039215686274, "r" : 0.9098039215686274 },
          "h" : 20,
          "id" : "1E1B0C6E-0000-4000-8000-000000000002",
          "kind" : "text",
          "name" : "Text Label",
          "params" : {
            "armH" : 56, "armV" : 56, "bold" : true,
            "cornerBL" : 0, "cornerBR" : 0, "cornerTL" : 0, "cornerTR" : 0,
            "flipX" : false, "flipY" : false, "fontSize" : 12,
            "innerRadius" : 8, "pointerAngle" : 45,
            "startAngle" : -90, "sweepAngle" : 100,
            "text" : "NX-1786", "thickness" : 16, "value" : 0.5
          },
          "rotation" : 0, "strokeWidth" : 1.5, "w" : 120, "x" : 20, "y" : 40
        }
      ],
      "format" : "3U",
      "name" : "Legacy Fixture",
      "widthHP" : 8
    }
    """#
}
