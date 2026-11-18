import XCTest
import CoreGraphics
@testable import PanelKit

/// The Paperface language, and a reference build of Helios's OSCILLATOR
/// section in 3U. Set PG_PAPERFACE_DEMO to a path to have it saved there.
final class PaperfaceTests: XCTestCase {

    func testPresetsApply() {
        var jack = ElementKind.jack.defaultElement(at: .zero)
        jack.applyPreset("pfJackRed")
        XCTAssertEqual(jack.params.jackStyle, 1)
        XCTAssertEqual(PanelMetrics.mm(jack.w), 0.43 * Paperface.cellMM, accuracy: 0.01)

        var dome = ElementKind.path.defaultElement(at: .zero)
        dome.applyPreset("pfDome")
        XCTAssertNotNil(dome.pathData)
        XCTAssertFalse(Renderer.parts(for: dome).isEmpty, "dome path must parse")

        var glyph = ElementKind.symbol.defaultElement(at: .zero)
        glyph.applyPreset("pfSaw")
        XCTAssertEqual(glyph.params.symbol, "sawUp")
        XCTAssertEqual(glyph.fill, Paperface.ink)

        // A plain catalogue id still works on a symbol.
        glyph.applyPreset("noise")
        XCTAssertEqual(glyph.params.symbol, "noise")
    }

    func testEveryCellShapeParses() {
        for (id, d) in Paperface.shapes {
            XCTAssertNotNil(SVGPath.path(fromD: d), id)
        }
    }

    func testStylesRender() {
        var knob = ElementKind.knobMedium.defaultElement(at: .zero)
        knob.applyPreset("pfKnob")
        let parts = Renderer.parts(for: knob)
        XCTAssertEqual(parts.count, 2)
        XCTAssertTrue(parts.allSatisfy(\.rotates))
        var lamp = ElementKind.led.defaultElement(at: .zero)
        lamp.applyPreset("pfLamp")
        XCTAssertEqual(Renderer.parts(for: lamp).count, 4)
    }

    // MARK: - Helios OSCILLATOR, 8 HP

    /// Positions measured on Paperface50-Helios.png (2914 × 1198), in source
    /// pixels, mapped uniformly to 3U: the section's left grid line lands at
    /// the panel's left margin.
    static func oscillator() -> PanelDocument {
        var doc = PanelDocument()
        doc.name = "Helios OSC"
        doc.widthHP = 8
        doc.format = .u3
        doc.background = Paperface.face
        // On the Paperface grid: a source column (171 px) becomes one 4 HP
        // column, so the section's two columns fill 8 HP edge to edge; a
        // source row (179.5 px from 144.6) becomes one 19.25 mm grid row.
        let left: CGFloat = 96
        let kx = CGFloat(PaperfaceGrid.defaultColumnHP) * 5.08 / 171
        let ky = PaperfaceGrid.rowPitchMM / 179.5
        func mm(_ x: CGFloat, _ y: CGFloat) -> CGPoint {
            CGPoint(x: (x - left) * kx, y: PaperfaceGrid.firstRowMM + (y - 144.6) * ky)
        }
        func px(_ p: CGPoint) -> CGPoint { CGPoint(x: p.x / PanelMetrics.mmPerPixel, y: p.y / PanelMetrics.mmPerPixel) }

        func add(_ kind: ElementKind, _ preset: String?, centre x: CGFloat, _ y: CGFloat,
                 role: ComponentRole? = nil, _ edit: (inout PanelElement) -> Void = { _ in }) {
            var e = kind.defaultElement(at: .zero)
            if let preset { e.applyPreset(preset) }
            if let role { e.role = role }
            edit(&e)
            let c = px(mm(x, y))
            e.x = c.x - e.w / 2; e.y = c.y - e.h / 2
            doc.elements.append(e)
        }
        /// A cell shape filling the source rectangle x0…x1 × y0…y1.
        func shape(_ preset: String, _ x0: CGFloat, _ y0: CGFloat, _ x1: CGFloat, _ y1: CGFloat,
                   d: String? = nil) {
            var e = ElementKind.path.defaultElement(at: .zero)
            e.applyPreset(preset)
            if let d { e.pathData = d }
            let a = px(mm(x0, y0)), b = px(mm(x1, y1))
            e.x = a.x; e.y = a.y; e.w = b.x - a.x; e.h = b.y - a.y
            doc.elements.append(e)
        }
        func line(_ x0: CGFloat, _ y0: CGFloat, _ x1: CGFloat, _ y1: CGFloat) {
            shape("pfCell", min(x0, x1), min(y0, y1), max(x0, x1) + 0.001, max(y0, y1) + 0.001,
                  d: x0 == x1 ? "M0.5 0V1" : "M0 0.5H1")
        }
        func text(_ s: String, _ x: CGFloat, _ y: CGFloat, title: Bool = false) {
            add(.text, title ? "pfTitle" : "pfLabel", centre: x, y) { e in
                e.params.text = s
                let size = Renderer.textSize(for: e)
                e.w = size.width; e.h = size.height
            }
        }

        // Source coordinates: crop origin (90, 70) added to what was read off
        // the crop, so these are the original image's pixels.
        let X: (CGFloat) -> CGFloat = { $0 + 90 }, Y: (CGFloat) -> CGFloat = { $0 + 70 }
        let c0 = X(6), c1 = X(170), c2 = X(340)

        text("OSCILLATOR", X(172), 48, title: true)

        // Cells
        shape("pfCell", c0, Y(12), c1, Y(343))
        shape("pfCell", c1, Y(12), c2, Y(343))
        shape("pfCell", c0, Y(343), c2, Y(522))
        shape("pfCell", c0, Y(522), c2, Y(835))

        // Row 1: shaped / sine outputs, wave-shape attenuator
        add(.jack, "pfJackBlack", centre: X(84), Y(73), role: .output)
        line(X(84), Y(128), X(84), Y(200))
        add(.jack, "pfJackWhite", centre: X(84), Y(254), role: .output)
        add(.symbol, "pfSine", centre: X(84), Y(318))
        shape("pfDome", c1, Y(10), c2, Y(118))
        add(.knobMedium, "pfKnob", centre: X(255), Y(70), role: .param)
        shape("pfScale", c1, Y(118), c2, Y(133), d: "M0 0H1V1H0Z")
        text("−", X(190), Y(150)); text("+", X(320), Y(150))
        text("WAVE", X(255), Y(162)); text("SHAPE", X(255), Y(188))
        add(.jack, "pfJackWhite", centre: X(255), Y(254), role: .input)

        // Row 2: saw out, normalled to the black jack
        add(.jack, "pfJackWhite", centre: X(84), Y(433), role: .output)
        line(X(135), Y(433), X(205), Y(433))
        add(.symbol, "pfSaw", centre: X(170), Y(403))
        add(.jack, "pfJackBlack", centre: X(255), Y(433), role: .output)

        // Row 3: three 1 V/oct inputs, two attenuated
        line(X(170), Y(522), X(170), Y(610))
        add(.jack, "pfJackWhite", centre: X(84), Y(612), role: .input)
        add(.jack, "pfJackWhite", centre: X(255), Y(612), role: .input)
        text("1V/O", X(170), Y(643))
        add(.jack, "pfJackWhite", centre: X(170), Y(705), role: .input)
        shape("pfDome", c0, Y(728), c1, Y(835))
        shape("pfDome", c1, Y(728), c2, Y(835))
        add(.knobMedium, "pfKnob", centre: X(84), Y(793), role: .param)
        add(.knobMedium, "pfKnob", centre: X(255), Y(793), role: .param)

        // Row 4: sync (fed through an attenuverter scale) and frequency
        shape("pfScale", c0, Y(853), c1, Y(883))
        shape("pfScale", c1, Y(853), c2, Y(883))
        shape("pfFunnel", c0, Y(883), c1, Y(973))
        add(.jack, "pfJackPurple", centre: X(84), Y(973), role: .input)
        text("SYNC", X(84), Y(1040))
        shape("pfRoof", c1, Y(885), c2, Y(1010), d: "M0 1V0.44L0.5 0L1 0.44V1Z")
        add(.knobMedium, "pfKnob", centre: X(255), Y(975), role: .param)
        shape("pfLabelStrip", c1, Y(1023), c2, Y(1057))
        text("FREQ", X(255), Y(1040))

        add(.screw, "pfScrew", centre: X(30), 1170)
        add(.screw, "pfScrew", centre: X(312), 30)
        return doc
    }

    func testOscillatorDemo() throws {
        let doc = Self.oscillator()
        XCTAssertEqual(doc.elements.filter { $0.role == .param }.count, 4)
        XCTAssertEqual(doc.elements.filter { $0.kind == .jack }.count, 9)
        if let out = ProcessInfo.processInfo.environment["PG_PAPERFACE_DEMO"] {
            try doc.save(to: URL(fileURLWithPath: out))
        }
    }
}

final class SelectionAndLabelTests: XCTestCase {

    private func doc() -> (PanelDocument, jack: UUID, knob: UUID, cell: UUID, label: UUID) {
        var d = PanelDocument()
        var cell = ElementKind.path.defaultElement(at: CGPoint(x: 0, y: 0)); cell.applyPreset("pfCell")
        cell.w = 60; cell.h = 60
        var jack = ElementKind.jack.defaultElement(at: .zero); jack.applyPreset("pfJackWhite")
        jack.x = 30 - jack.w / 2; jack.y = 30 - jack.h / 2
        var knob = ElementKind.knobMedium.defaultElement(at: .zero); knob.applyPreset("pfKnob")
        knob.x = 90 - knob.w / 2; knob.y = 30 - knob.h / 2
        var label = ElementKind.text.defaultElement(at: .zero); label.applyPreset("pfLabel")
        label.params.text = "IN"; label.x = 25; label.y = 50
        // Cell on top of the jack: the stacking that used to swallow clicks.
        d.elements = [jack, knob, cell, label]
        return (d, jack.id, knob.id, cell.id, label.id)
    }

    func testClickInsideAnOutlinePicksTheControl() {
        let (d, jack, _, cell, _) = doc()
        XCTAssertEqual(d.hitStack(at: CGPoint(x: 30, y: 30), tolerance: 2).first?.id, jack)
        // Empty interior of the cell is not the cell…
        XCTAssertTrue(d.hitStack(at: CGPoint(x: 12, y: 45), tolerance: 2).isEmpty)
        // …its line is.
        XCTAssertEqual(d.hitStack(at: CGPoint(x: 0.5, y: 45), tolerance: 2).first?.id, cell)
    }

    func testNarrowAndSelectSame() {
        let (d, jack, knob, cell, label) = doc()
        let all: Set<UUID> = [jack, knob, cell, label]
        XCTAssertEqual(d.narrow(all, to: .controls), [jack, knob])
        XCTAssertEqual(d.narrow(all, to: .decoration), [cell])
        XCTAssertEqual(d.narrow(all, to: .labels), [label])
        XCTAssertEqual(d.selectSame(as: [cell], by: .name), [cell])
        XCTAssertEqual(d.select(filter: .controls, nameContains: "knob"), [knob])
    }

    func testLabelsSnapFromTheCentre() {
        var (d, jack, knob, _, label) = doc()
        XCTAssertEqual(d.attachLabels([label]), 1)
        let l = d.elements.first { $0.id == label }!
        XCTAssertEqual(l.labelOwner, jack)
        let j = d.elements.first { $0.id == jack }!
        XCTAssertEqual(PanelMetrics.mm(l.center.y - j.center.y), LabelGridSpec.defaultOffsetMM, accuracy: 1e-6)
        XCTAssertEqual(l.center.x, j.center.x, accuracy: 1e-6)
        // A label under the (bigger) knob lands on the same line.
        var k2 = l; k2.id = UUID(); k2.labelOwner = knob; k2.x += 60; k2.y += 2
        d.elements.append(k2)
        d.snapLabels([k2.id])
        XCTAssertEqual(d.elements.last!.center.y, l.center.y, accuracy: 1e-6)
        XCTAssertEqual(d.labelsFollowing([jack]), [label])
    }
}

final class GuideTests: XCTestCase {
    func testSelectionLocksToAnotherElementsEdgeAndCentre() {
        var d = PanelDocument()
        var a = ElementKind.box.defaultElement(at: CGPoint(x: 20, y: 40)); a.w = 30; a.h = 20
        var b = ElementKind.box.defaultElement(at: CGPoint(x: 70, y: 41.5)); b.w = 10; b.h = 10
        d.elements = [a, b]
        // b's top 41.5 is 1.5 from a's top 40: caught. Its centre x (75) is
        // nowhere near a line on x… except none, so x is free.
        let g = d.guideSnap(rect: b.frame, excluding: [b.id], threshold: 3)
        XCTAssertEqual(g.dy ?? 99, -1.5, accuracy: 1e-9)
        XCTAssertEqual(g.ys, [40, 50])   // top on a's top, bottom on a's centre
        XCTAssertNil(g.dx)
        _ = a
    }

    func testPointPrefersTheNearestLine() {
        var d = PanelDocument()
        var a = ElementKind.box.defaultElement(at: CGPoint(x: 20, y: 40)); a.w = 30; a.h = 20
        d.elements = [a]
        let g = d.guideSnap(point: CGPoint(x: 34, y: 61), threshold: 3)
        XCTAssertEqual(g.dx ?? 99, 1, accuracy: 1e-9)    // centre line x = 35
        XCTAssertEqual(g.dy ?? 99, -1, accuracy: 1e-9)   // bottom y = 60
        _ = a
    }
}

final class PaperfaceRowTests: XCTestCase {
    /// Three rows of row units make one section, ending on the half row.
    func testRowUnitsEndOnTheHalfRow() {
        for (name, build) in Paperface.units {
            let els = build()
            let c = els.first { $0.role.isComponent }!
            let bottom = els.map(\.frame.maxY).max()!
            XCTAssertLessThanOrEqual(PanelMetrics.mm(bottom - c.center.y), 9.626, name)
            XCTAssertEqual(PanelMetrics.mm(c.center.y - els.map(\.frame.minY).min()!), name.hasPrefix("Attenuator") ? 7.0 : 9.625,
                           accuracy: 0.01, name)
        }
    }

    /// Writes the row units as seed stamps when PG_PAPERFACE_STAMPS names a
    /// directory (the repo's Stamps/Paperface).
    func testWriteRowUnitStamps() throws {
        guard let dir = ProcessInfo.processInfo.environment["PG_PAPERFACE_STAMPS"] else { return }
        StampLibrary.directoryOverride = URL(fileURLWithPath: dir)
        defer { StampLibrary.directoryOverride = nil }
        for (name, build) in Paperface.units { try StampLibrary.save(build(), as: name) }
    }
}

final class FlipTests: XCTestCase {
    func testFlipMirrorsPositionsAndDecorationOnly() {
        var d = PanelDocument()
        var saw = ElementKind.symbol.defaultElement(at: CGPoint(x: 10, y: 10)); saw.applyPreset("pfSaw")
        var jack = ElementKind.jack.defaultElement(at: CGPoint(x: 50, y: 10)); jack.applyPreset("pfJackWhite")
        var label = ElementKind.text.defaultElement(at: CGPoint(x: 50, y: 40)); label.applyPreset("pfLabel")
        d.elements = [saw, jack, label]
        let box = d.elements.dropFirst().reduce(d.elements[0].frame) { $0.union($1.frame) }
        d.flip(Set(d.elements.map(\.id)), .horizontal)
        let s = d.elements[0], j = d.elements[1], t = d.elements[2]
        XCTAssertTrue(s.params.flipX)                    // the saw's drawing mirrors
        XCTAssertEqual(j.params.jackStyle, 1)            // the jack's does not
        XCTAssertFalse(t.params.flipX)                   // text stays readable
        XCTAssertEqual(s.frame.maxX, box.maxX, accuracy: 1e-9)   // positions mirror
        XCTAssertEqual(j.frame.minX, box.minX, accuracy: 1e-9)
        // The mirrored saw's outline is the original's reflected.
        let a = Renderer.parts(for: saw)[0].path.boundingBox
        let b = Renderer.parts(for: s)[0].path.boundingBox
        XCTAssertEqual(a.width, b.width, accuracy: 1e-6)
    }
}

final class PaperfaceGlyphTests: XCTestCase {
    func testGlyphsParseAndApply() {
        for (id, g) in Paperface.glyphs {
            var e = ElementKind.path.defaultElement(at: .zero)
            e.applyPreset(id)
            XCTAssertEqual(e.pathData, g.d, id)
            XCTAssertFalse(Renderer.parts(for: e).isEmpty, id)
            XCTAssertEqual(e.stroke, g.helios ? Paperface.line : Paperface.ink, id)
        }
    }

    /// A sheet of every glyph, large, for comparing with the renders.
    /// PG_PAPERFACE_GLYPHS=<path> saves it.
    func testGlyphSheet() throws {
        guard let out = ProcessInfo.processInfo.environment["PG_PAPERFACE_GLYPHS"] else { return }
        var doc = PanelDocument()
        doc.widthHP = 8; doc.format = .u3; doc.background = Paperface.face; doc.name = "Glyphs"
        let ids = ["pfgSine", "pfgSaw", "pfgSquare", "pfgRise", "pfgFall", "pfgPulse", "pfgNotch", "pfgAD"]
        for (i, id) in ids.enumerated() {
            var e = ElementKind.path.defaultElement(at: .zero)
            e.applyPreset(id)
            let cx = (i % 2 == 0 ? 10.16 : 30.48) / PanelMetrics.mmPerPixel
            let cy = (15.5 + 19.25 * CGFloat(i / 2)) / PanelMetrics.mmPerPixel
            e.x = cx - e.w / 2; e.y = cy - e.h / 2
            doc.elements.append(e)
        }
        try doc.save(to: URL(fileURLWithPath: out))
    }
}

final class LightMatchTests: XCTestCase {
    func testDefaultLEDFollowsColourAndSize() {
        var small = ElementKind.led.defaultElement(at: .zero); small.applyPreset("pfLampSmall")
        XCTAssertEqual(small.widgetClass, "MediumLight<YellowLight>")
        var large = ElementKind.led.defaultElement(at: .zero); large.applyPreset("pfLamp")
        XCTAssertEqual(large.widgetClass, "LargeLight<YellowLight>")
        var tiny = ElementKind.led.defaultElement(at: .zero)
        tiny.w = 2.2 / PanelMetrics.mmPerPixel; tiny.h = tiny.w; tiny.fill = .hex("#ECE500")
        XCTAssertEqual(tiny.widgetClass, "SmallLight<YellowLight>")
        // A chosen type is kept.
        tiny.stockWidget = "SmallLight<GreenLight>"
        XCTAssertEqual(tiny.widgetClass, "SmallLight<GreenLight>")
        // The untouched default red LED still comes out as before.
        XCTAssertEqual(ElementKind.led.defaultElement(at: .zero).widgetClass, "MediumLight<RedLight>")
    }
}

final class TitleFrameToggleTests: XCTestCase {
    func testPaperfaceTitleSitsOnItsLine() {
        var d = PanelDocument(); d.widthHP = 8; d.background = Paperface.face; d.title = "Dual Gates"
        let t = d.titleElements()
        XCTAssertEqual(t.count, 1)
        XCTAssertEqual(t[0].params.text, "DUAL GATES")
        XCTAssertEqual(PanelMetrics.mm(t[0].center.y), 4.9, accuracy: 0.01)
        XCTAssertEqual(t[0].center.x, d.pixelSize.width / 2, accuracy: 0.01)
        // Same height whatever the width.
        d.widthHP = 16
        XCTAssertEqual(PanelMetrics.mm(d.titleElements()[0].center.y), 4.9, accuracy: 0.01)
    }

    func testMakeModuleTitleTakesTheLabel() {
        var d = PanelDocument(); d.background = Paperface.face
        var l = ElementKind.text.defaultElement(at: CGPoint(x: 30, y: 8)); l.params.text = "SSG"
        var j = ElementKind.jack.defaultElement(at: CGPoint(x: 30, y: 60))
        d.elements = [l, j]
        XCTAssertEqual(d.makeModuleTitle(from: [l.id, j.id]), "SSG")
        XCTAssertEqual(d.elements.map(\.id), [j.id])   // the label goes, the jack stays
        _ = j
    }

    func testFrameAndFit() {
        var d = PanelDocument(); d.background = Paperface.face
        let f = PaperfaceGrid.frame(for: d)!
        XCTAssertEqual(f.topMM, 8.6, accuracy: 0.001)
        XCTAssertEqual(f.bottomMM, 121.375, accuracy: 0.001)
        XCTAssertEqual(f.sectionMM[0].bottom, 63.625, accuracy: 0.001)
        XCTAssertEqual(f.sectionMM[0].top, 66.35, accuracy: 0.001)
        var cell = ElementKind.path.defaultElement(at: .zero); cell.applyPreset("pfCell")
        cell.y = 7.0 / PanelMetrics.mmPerPixel; cell.h = (65.0 - 7.0) / PanelMetrics.mmPerPixel
        d.elements = [cell]
        XCTAssertFalse(PaperfaceGrid.frameWarnings(d).isEmpty)
        XCTAssertEqual(PaperfaceGrid.fitToFrame(&d), 2)
        XCTAssertEqual(PanelMetrics.mm(d.elements[0].y), 8.6, accuracy: 0.001)
        XCTAssertEqual(PanelMetrics.mm(d.elements[0].y + d.elements[0].h), 63.625, accuracy: 0.001)
        XCTAssertTrue(PaperfaceGrid.frameWarnings(d).isEmpty)
    }

    func testToggleIsACustomSwitchWithAFramePerPosition() {
        var t = ElementKind.buttonGroup.defaultElement(at: .zero); t.applyPreset("pfToggle3")
        XCTAssertEqual(t.widgetClass, "PaperfaceToggle3")
        let files = CodeGen.componentFiles(for: t)
        XCTAssertEqual(files.count, 3)
        // Up, end-on, down: three different drawings.
        var drawings: [CGRect] = []
        for v in [0, 0.5, 1] as [CGFloat] {
            t.params.value = v
            drawings.append(Renderer.parts(for: t).last!.path.boundingBox)
        }
        XCTAssertLessThan(drawings[0].midY, drawings[1].midY)
        XCTAssertLessThan(drawings[1].midY, drawings[2].midY)
    }
}

final class PaperfaceButtonTests: XCTestCase {
    func testButtonIsACustomMomentaryWithTwoFrames() throws {
        var b = ElementKind.pushButton.defaultElement(at: .zero); b.applyPreset("pfButton")
        XCTAssertEqual(b.widgetClass, "PaperfacePushButton")
        XCTAssertEqual(b.w * PanelMetrics.mmPerPixel, 9.2, accuracy: 0.01)
        XCTAssertEqual(CodeGen.componentFiles(for: b).count, 2)
        let up = Renderer.parts(for: b)
        b.params.value = 1
        let down = Renderer.parts(for: b)
        XCTAssertEqual(up.count, 3)
        XCTAssertLessThan(down.last!.path.boundingBox.width, up.last!.path.boundingBox.width)
        if let dir = ProcessInfo.processInfo.environment["PG_TITLE_SHEET"] {
            var doc = PanelDocument(); doc.widthHP = 4; doc.background = Paperface.face
            for (i, v) in ([0, 1] as [CGFloat]).enumerated() {
                var e = ElementKind.pushButton.defaultElement(at: .zero); e.applyPreset("pfButton")
                e.params.value = v
                e.x = 10.16 / PanelMetrics.mmPerPixel - e.w / 2
                e.y = (20 + 20 * CGFloat(i)) / PanelMetrics.mmPerPixel - e.h / 2
                doc.elements.append(e)
            }
            try doc.save(to: URL(fileURLWithPath: dir + "/pf-button.panelgen"))
        }
    }
}

final class TitleToggleSheet: XCTestCase {
    /// PG_TITLE_SHEET=<dir> writes two demo documents: a Paperface panel
    /// with a title, the frame-fitted cells and the toggle in its three
    /// positions, and a Kurkesmurfer panel with the logo lockup.
    func testSheets() throws {
        guard let dir = ProcessInfo.processInfo.environment["PG_TITLE_SHEET"] else { return }
        var pf = PanelDocument(); pf.widthHP = 8; pf.background = Paperface.face; pf.title = "Dual Gates"
        let px: (CGFloat) -> CGFloat = { $0 / PanelMetrics.mmPerPixel }
        for (i, v) in ([0, 0.5, 1] as [CGFloat]).enumerated() {
            var t = ElementKind.buttonGroup.defaultElement(at: .zero); t.applyPreset("pfToggle3")
            t.params.value = v
            t.x = px(20.32) - t.w / 2; t.y = px(15.5 + 19.25 * CGFloat(i)) - t.h / 2
            pf.elements.append(t)
        }
        var cell = ElementKind.path.defaultElement(at: .zero); cell.applyPreset("pfCell")
        cell.x = 0; cell.w = px(40.64); cell.y = px(8.6); cell.h = px(63.625 - 8.6)
        pf.elements.insert(cell, at: 0)
        try pf.save(to: URL(fileURLWithPath: dir + "/pf-title.panelgen"))
        var km = PanelDocument(); km.widthHP = 10; km.designLanguage = "kurkesmurfer"; km.title = "Head"
        try km.save(to: URL(fileURLWithPath: dir + "/km-title.panelgen"))
    }
}

final class CompareAliasTests: XCTestCase {
    func testWidgetLibraryAliasesResolve() {
        let lib = """
        using namespace rack;
        using LargeLightYellowLight = rack::componentlibrary::LargeLight<YellowLight>;   // LargeLight<YellowLight>
        using PJ301MPort = rack::componentlibrary::PJ301MPort;
        """
        let aliases = Compare.widgetAliases(in: [lib])
        XCTAssertNil(aliases["namespace"])
        XCTAssertEqual(Compare.canonicalWidget(Compare.resolve("LargeLightYellowLight", aliases)),
                       Compare.canonicalWidget("LargeLight<YellowLight>"))
        XCTAssertEqual(Compare.canonicalWidget(Compare.resolve("PJ301MPort", aliases)), "PJ301MPort")
        // Without the library, the canonical shape still meets.
        XCTAssertEqual(Compare.canonicalWidget("MediumLightYellowLight"),
                       Compare.canonicalWidget("rack::componentlibrary::MediumLight<YellowLight>"))
        XCTAssertNotEqual(Compare.canonicalWidget("MediumLight<RedLight>"),
                          Compare.canonicalWidget("MediumLight<YellowLight>"))
    }
}

final class FileCaseTests: XCTestCase {
    /// On the default macOS volume a save under a recapitalised name must
    /// take the new spelling, not keep the old directory entry.
    func testSaveTakesTheNewCapitalisation() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("pg-case-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        var doc = PanelDocument(); doc.moduleSlug = "Oscplus"
        try doc.save(to: dir.appendingPathComponent("Oscplus.panelgen"))
        doc.moduleSlug = "OscPlus"
        try doc.save(to: dir.appendingPathComponent("OscPlus.panelgen"))
        let names = try FileManager.default.contentsOfDirectory(atPath: dir.path)
        XCTAssertEqual(names, ["OscPlus.panelgen"])
        XCTAssertEqual(try PanelDocument.load(from: dir.appendingPathComponent("OscPlus.panelgen")).moduleSlug, "OscPlus")
    }
}

final class PanelHeightTests: XCTestCase {
    /// A 3U panel in millimetres is 128.5 mm tall, scaled uniformly.
    func testThreeUPanelIs128_5mm() {
        var doc = PanelDocument(); doc.widthHP = 12; doc.svgUnits = .millimetres
        let svg = SVGExporter.documentSVG(doc)
        XCTAssertTrue(svg.contains(#"width="60.96mm" height="128.5mm""#), String(svg.prefix(300)))
        let m = svg.range(of: #"viewBox="0 0 180(\.00)? ([0-9.]+)""#, options: .regularExpression)
        XCTAssertNotNil(m)
        let vb = String(svg[m!]).split(separator: " ").last!.dropLast()
        let vh = Double(vb)!
        XCTAssertEqual(180 / 60.96, vh / 128.5, accuracy: 0.0005)   // same scale both ways
        XCTAssertTrue(SVGExporter.componentsSVG(doc).contains(#"height="128.5mm""#))
    }
}
