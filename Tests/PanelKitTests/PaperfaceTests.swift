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
        let k: CGFloat = 128.5 / 1198                 // mm per source px
        let left: CGFloat = 96, width: CGFloat = 342
        let marginMM = (8 * 5.08 - width * k) / 2
        func mm(_ x: CGFloat, _ y: CGFloat) -> CGPoint {
            CGPoint(x: (x - left) * k + marginMM, y: y * k)
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
