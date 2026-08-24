import Foundation

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

            let failures = persistenceChecks() + exportChecks()

            print(failures.isEmpty ? "SELFTEST OK" : "SELFTEST FAILED")
            print("  elements : \(doc.elements.count)")
            print("  panel    : \(doc.widthHP)HP \(doc.format.rawValue) (\(Int(doc.pixelSize.width))×\(Int(doc.pixelSize.height)) px)")
            print("  svg      : \(svgURL.path) (\(svg.utf8.count) bytes)")
            print("  png      : \(pngURL.path) (\(png.count) bytes)")
            if failures.isEmpty {
                print("  persist  : round-trip · legacy decode · unknown-kind guard OK")
                print("  export   : text outlines · binding · components layer · codegen OK")
                print("  bulk     : bind primitives · hand-set roles preserved OK")
                print("  align    : selection bounds vs panel bounds OK")
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

    static func exportChecks() -> [String] {
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

        // A label on its own must produce real geometry, not an empty group.
        var probe = PanelDocument()
        var label = ElementKind.text.defaultElement(at: CGPoint(x: 10, y: 10))
        label.params.text = "PG"
        probe.elements = [label]
        if !SVGExporter.documentSVG(probe).contains("<path") {
            failures.append("text export: a text element produced no outline path")
        }


        // Components must not be painted into the panel: Rack and MetaModule
        // draw them on top, so the artwork would show through from underneath.
        var rig = PanelDocument()
        var deco = ElementKind.box.defaultElement(at: CGPoint(x: 10, y: 10))
        deco.fill = .hex("#123456")
        var knob = ElementKind.knobLarge.defaultElement(at: CGPoint(x: 30, y: 100))
        knob.fill = .hex("#ABCDEF")
        knob.enumName = "CUTOFF"
        rig.elements = [deco, knob]

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

        // Generated C++ must namespace the enum to the module, position by
        // centre, and convert px to the millimetres mm2px() expects.
        rig.moduleSlug = "TestModule"
        let src = CodeGen.rackSource(rig)
        if !src.contains("enum ParamId {") { failures.append("codegen: no ParamId enum") }
        if !src.contains("CUTOFF_PARAM,") { failures.append("codegen: CUTOFF_PARAM missing from the enum") }
        if !src.contains("TestModule::CUTOFF_PARAM") { failures.append("codegen: enum not namespaced to the module") }
        if !src.contains("res/TestModule.svg") { failures.append("codegen: setPanel path wrong") }
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
