import XCTest
import CoreGraphics
@testable import PanelKit

/// Regression cases for Import SVG, each the shape of a real file that used
/// to come in wrong. A 6 HP, 3U panel in millimetres unless a test says
/// otherwise.
final class SVGImportTests: XCTestCase {

    private func svg(_ body: String, head: String = ##"width="30.48mm" height="128.5mm" viewBox="0 0 30.48 128.5""##) -> Data {
        Data(##"<svg xmlns="http://www.w3.org/2000/svg" xmlns:xlink="http://www.w3.org/1999/xlink" "##
             .appending(head).appending(">").appending(body).appending("</svg>").utf8)
    }

    private func load(_ data: Data, file: StaticString = #filePath, line: UInt = #line) -> SVGImport.Outcome? {
        do { return try SVGImport.outcome(from: data) } catch {
            XCTFail("import failed: \(error.localizedDescription)", file: file, line: line)
            return nil
        }
    }

    private let mm = 75.0 / 25.4 as CGFloat

    func testCSSClassesStyleShapes() {
        // Illustrator's default export: everything styled by class.
        let o = load(svg(##"""
            <style>.st0{fill:#FF9C00;} .st1{fill:none;stroke:#99CCFF;stroke-width:0.5} rect.big{fill:#123456}</style>
            <circle class="st0" cx="10" cy="20" r="3"/>
            <path class="st1" d="M2 30 L20 30"/>
            <rect class="big st0" x="2" y="40" width="5" height="5"/>
            """##))
        let fills = o?.elements.map { $0.fill.hexString.uppercased() } ?? []
        XCTAssertTrue(fills.contains("#FF9C00"), "class fill")
        XCTAssertEqual(o?.elements.first { $0.kind == .path }?.stroke?.hexString.uppercased(), "#99CCFF")
        XCTAssertTrue(fills.contains("#123456"), "tag.class beats .class by specificity")
    }

    func testStyleAttributeBeatsCSSBeatsPresentationAttribute() {
        let o = load(svg(##"<style>.a{fill:#00FF00}</style><circle class="a" fill="#FF0000" style="fill:#0000FF" cx="5" cy="5" r="2"/><circle class="a" fill="#FF0000" cx="15" cy="5" r="2"/>"##))
        let fills = o?.elements.map { $0.fill.hexString.uppercased() }
        XCTAssertEqual(fills, ["#0000FF", "#00FF00"])
    }

    func testHiddenLayersStayOut() {
        let o = load(svg(##"""
            <g style="display:none"><circle cx="5" cy="5" r="2" fill="red"/></g>
            <circle cx="5" cy="15" r="2" fill="blue" visibility="hidden"/>
            <circle cx="5" cy="25" r="2" fill="lime"/>
            """##))
        XCTAssertEqual(o?.elements.count, 1)
        XCTAssertTrue(o?.warnings.contains { $0.contains("hidden") } ?? false)
    }

    func testHiddenComponentsLayerIsStillRead() {
        // helper.py's components layer is usually hidden: it is data.
        let o = load(svg(##"<g id="components" style="display:none"><circle cx="6" cy="100" r="2" fill="#00ff00" data-name="CV_IN"/></g>"##))
        XCTAssertEqual(o?.elements.first?.role, .input)
        XCTAssertEqual(o?.elements.first?.enumName, "CV_IN")
    }

    func testUseAndSymbolAreResolved() {
        let o = load(svg(##"""
            <defs><circle id="dot" r="1" fill="#FF0000"/>
            <symbol id="sq" viewBox="0 0 10 10"><rect width="10" height="10" fill="#00FF00"/></symbol></defs>
            <use href="#dot" x="5" y="5"/><use xlink:href="#dot" x="10" y="5"/>
            <use href="#sq" x="2" y="50" width="5" height="5"/>
            """##))
        let red = o?.elements.filter { $0.fill.hexString.uppercased() == "#FF0000" } ?? []
        XCTAssertEqual(red.count, 2)
        XCTAssertEqual(red.map { $0.center.x / mm }.sorted().first ?? 0, 5, accuracy: 0.01)
        let square = o?.elements.first { $0.fill.hexString.uppercased() == "#00FF00" }
        XCTAssertEqual((square?.w ?? 0) / mm, 5, accuracy: 0.01, "symbol viewBox scaled to the use size")
    }

    func testClipPathIntersectsGeometry() {
        let o = load(svg(##"""
            <defs><clipPath id="c"><rect x="0" y="0" width="10" height="10"/></clipPath></defs>
            <g clip-path="url(#c)"><rect x="5" y="5" width="20" height="20" fill="#FF0000"/>
            <rect x="50" y="50" width="5" height="5" fill="#0000FF"/></g>
            """##))
        XCTAssertEqual(o?.elements.count, 1, "the fully clipped shape is left out")
        guard let el = o?.elements.first else { return }
        XCTAssertEqual(el.w / mm, 5, accuracy: 0.01)
        XCTAssertEqual(el.h / mm, 5, accuracy: 0.01)
    }

    func testGradientBecomesItsAverageColour() {
        let o = load(svg(##"""
            <defs><linearGradient id="g"><stop offset="0" stop-color="#000000"/><stop offset="1" style="stop-color:#FFFFFF"/></linearGradient>
            <linearGradient id="h" xlink:href="#g"/></defs>
            <rect x="2" y="2" width="5" height="5" fill="url(#h)"/>
            """##))
        let c = o?.elements.first?.fill
        XCTAssertEqual(c?.r ?? 0, 0.5, accuracy: 0.01)
    }

    func testEvenOddKeepsItsHole() throws {
        // A ring drawn as two same-direction circles relies on evenodd.
        let ring = "M10 5 A5 5 0 1 1 0 5 A5 5 0 1 1 10 5 Z M7 5 A2 2 0 1 1 3 5 A2 2 0 1 1 7 5 Z"
        let o = try XCTUnwrap(load(svg(##"<path fill-rule="evenodd" fill="#FFFFFF" d="\##(ring)" transform="translate(5 5)"/>"##)))
        let el = try XCTUnwrap(o.elements.first)
        let path = try XCTUnwrap(Renderer.importedParts(for: el).first?.path)
        let centre = CGPoint(x: el.frame.midX, y: el.frame.midY)
        XCTAssertFalse(path.contains(centre, using: .winding), "the hole survives a non-zero fill")
        XCTAssertTrue(path.contains(CGPoint(x: el.frame.minX + 1, y: el.frame.midY), using: .winding))
    }

    func testColourForms() {
        XCTAssertEqual(SVGColour.parse("darkgray")?.hexString.uppercased(), "#A9A9A9")
        XCTAssertEqual(SVGColour.parse("#FF000080")?.a ?? 0, 128.0 / 255, accuracy: 0.001)
        XCTAssertEqual(SVGColour.parse("#f00a")?.a ?? 0, 170.0 / 255, accuracy: 0.001)
        XCTAssertEqual(SVGColour.parse("rgb(100%, 0%, 0%)")?.r ?? 0, 1, accuracy: 0.001)
        XCTAssertEqual(SVGColour.parse("rgb(255 0 0 / 50%)")?.a ?? 0, 0.5, accuracy: 0.001)
        XCTAssertEqual(SVGColour.parse("hsl(120, 100%, 50%)")?.hexString.uppercased(), "#00FF00")
        XCTAssertNil(SVGColour.parse("nonsense"))
    }

    func testUnknownColourIsDrawnNotDropped() {
        let o = load(svg(##"<circle cx="5" cy="5" r="2" fill="ultraviolet"/>"##))
        XCTAssertEqual(o?.elements.first?.fill, .black)
        XCTAssertTrue(o?.warnings.contains { $0.contains("ultraviolet") } ?? false)
    }

    func testOpacityMultipliesDownTheTree() {
        let o = load(svg(##"<g opacity="0.5"><circle cx="5" cy="5" r="2" fill="#FF0000" fill-opacity="0.5"/></g>"##))
        XCTAssertEqual(o?.elements.first?.fill.a ?? 0, 0.25, accuracy: 0.001)
    }

    func testCurrentColor() {
        let o = load(svg(##"<g color="#336699"><circle cx="5" cy="5" r="2" fill="currentColor"/></g>"##))
        XCTAssertEqual(o?.elements.first?.fill.hexString.uppercased(), "#336699")
    }

    func testIllustratorPointFileIsScaledByItsHeight() {
        // 6 HP x 3U in points, no width attribute: 1:1 would be 4% small.
        let o = load(svg(##"<rect x="0" y="0" width="86.4" height="364.25" fill="#202020"/><circle cx="43.2" cy="100" r="5" fill="#FFFFFF"/>"##,
                         head: ##"viewBox="0 0 86.4 364.25""##))
        XCTAssertEqual(o?.widthHP, 6)
        XCTAssertEqual(o?.format, .u3)
        XCTAssertEqual(o?.elements.first?.center.x ?? 0, 45, accuracy: 0.1)
    }

    func testKnobArtIsNotMistakenForAStrip() {
        // ~1U-tall in mm, but not a whole number of HP wide: leave the scale alone.
        let o = load(svg(##"<circle cx="20" cy="20" r="19" fill="#333333"/>"##, head: ##"viewBox="0 0 39.65 39.65""##))
        XCTAssertEqual(o?.elements.first?.w ?? 0, 38, accuracy: 0.1)
    }

    func testWidthAndHeightWithoutViewBox() {
        let o = load(svg(##"<circle cx="57.6" cy="57.6" r="10" fill="#FFFFFF"/>"##, head: ##"width="30.48mm" height="128.5mm""##))
        XCTAssertEqual(o?.widthHP, 6)
        // 57.6 CSS px = 15.24 mm
        XCTAssertEqual((o?.elements.first?.center.x ?? 0) / mm, 15.24, accuracy: 0.01)
    }

    func testMalformedPathDrawsUpToTheError() {
        let o = load(svg(##"<path fill="#FFFFFF" d="M2 2 L10 2 L10 10 Z L oops"/>"##))
        XCTAssertEqual(o?.elements.count, 1)
    }

    func testHTMLEntitiesAndEmptyFile() {
        XCTAssertNotNil(load(svg(##"<text x="2" y="10" font-size="3" fill="#FFFFFF">A&nbsp;B</text>"##)))
        XCTAssertThrowsError(try SVGImport.outcome(from: Data())) { error in
            XCTAssertTrue(error.localizedDescription.contains("empty"))
        }
    }

    func testInkscapeTextPositionedOnTspan() {
        let o = load(svg(##"<text font-size="3" fill="#FFFFFF"><tspan x="10" y="60">PITCH</tspan></text>"##))
        let label = o?.elements.first
        XCTAssertEqual(label?.params.text, "PITCH")
        XCTAssertGreaterThan(label?.x ?? 0, 5 * mm)
    }
}
