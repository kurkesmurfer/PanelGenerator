import XCTest
import CoreGraphics
@testable import PanelKit
@testable import PanelCanvas

final class EditablePathTests: XCTestCase {
    private func box(_ p: CGPath) -> CGRect { p.boundingBoxOfPath }

    func testRoundTripKeepsGeometry() {
        let src = CGMutablePath()
        src.move(to: CGPoint(x: 10, y: 10))
        src.addLine(to: CGPoint(x: 50, y: 10))
        src.addCurve(to: CGPoint(x: 50, y: 50), control1: CGPoint(x: 70, y: 20), control2: CGPoint(x: 70, y: 40))
        src.addQuadCurve(to: CGPoint(x: 10, y: 50), control: CGPoint(x: 30, y: 70))
        src.closeSubpath()
        let e = EditablePath(src)
        XCTAssertEqual(e.contours.count, 1)
        XCTAssertTrue(e.contours[0].closed)
        XCTAssertEqual(e.contours[0].nodes.count, 4, "closing segment folded into the start point")
        let back = e.cgPath
        XCTAssertEqual(box(back).minX, box(src).minX, accuracy: 1e-6)
        XCTAssertEqual(box(back).maxX, box(src).maxX, accuracy: 1e-6)
        XCTAssertEqual(box(back).maxY, box(src).maxY, accuracy: 1e-6, "quadratic converted exactly to cubic")
    }

    func testCollinearHandlesReadAsSmooth() {
        let p = CGMutablePath()
        p.move(to: CGPoint(x: 0, y: 0))
        p.addCurve(to: CGPoint(x: 10, y: 0), control1: CGPoint(x: 0, y: 5), control2: CGPoint(x: 5, y: 5))
        p.addCurve(to: CGPoint(x: 20, y: 0), control1: CGPoint(x: 15, y: -5), control2: CGPoint(x: 20, y: 5))
        XCTAssertTrue(EditablePath(p).contours[0].nodes[1].smooth)
    }

    func testFreeformElementRoundTrip() throws {
        let path = EditablePath(contours: [PathContour(nodes: [
            PathNode(CGPoint(x: 20, y: 30)), PathNode(CGPoint(x: 80, y: 30)),
            PathNode(CGPoint(x: 50, y: 90), in: CGPoint(x: 70, y: 90), out: CGPoint(x: 30, y: 90), smooth: true),
        ], closed: true)])
        let el = PanelElement.freeform(path, ink: .white)
        XCTAssertEqual(el.kind, .path)
        XCTAssertEqual(el.frame.minX, 20, accuracy: 1e-4)
        XCTAssertNil(el.stroke, "a closed shape is filled")
        let back = try XCTUnwrap(el.editablePath)
        XCTAssertEqual(back.contours[0].nodes.count, 3)
        XCTAssertEqual(back.contours[0].nodes[2].point.x, 50, accuracy: 1e-3)
        XCTAssertEqual(back.contours[0].nodes[2].outHandle?.x ?? 0, 30, accuracy: 1e-3)

        let line = PanelElement.freeform(EditablePath(contours: [PathContour(nodes: [
            PathNode(CGPoint(x: 0, y: 0)), PathNode(CGPoint(x: 10, y: 10))], closed: false)]), ink: .white)
        XCTAssertEqual(line.stroke, .white, "an open line is stroked in the ink")
        XCTAssertEqual(line.fill.a, 0)
    }

    /// Editing a rotated shape must not make it jump: the frame is shifted so
    /// rotating about its new centre puts every point where it was.
    func testReshapingARotatedShapeKeepsItInPlace() throws {
        var el = PanelElement.freeform(EditablePath(contours: [PathContour(nodes: [
            PathNode(CGPoint(x: 0, y: 0)), PathNode(CGPoint(x: 40, y: 0)), PathNode(CGPoint(x: 40, y: 20))],
            closed: true)]), ink: .white)
        el.rotation = 30
        let pivot = el.center
        var path = try XCTUnwrap(el.editablePath)
        path.contours[0].nodes[2].point = CGPoint(x: 60, y: 50)   // grow the shape
        let moved = CanvasView.reshaped(el, to: path, pivot: pivot)
        let fresh = try XCTUnwrap(moved.editablePath)
        for (a, b) in zip(path.contours[0].nodes, fresh.contours[0].nodes) {
            let before = Geo.rotate(a.point, around: pivot, degrees: 30)
            let after = Geo.rotate(b.point, around: moved.center, degrees: 30)
            XCTAssertEqual(before.x, after.x, accuracy: 1e-3)
            XCTAssertEqual(before.y, after.y, accuracy: 1e-3)
        }
    }
}

final class ShapeOperationTests: XCTestCase {
    private func box(_ x: CGFloat, _ y: CGFloat, _ w: CGFloat, _ h: CGFloat, _ hex: String) -> PanelElement {
        var e = ElementKind.box.defaultElement(at: .zero)
        e.frame = CGRect(x: x, y: y, width: w, height: h)
        e.setCornerRadii(0)
        e.fill = .hex(hex)
        e.stroke = nil
        return e
    }

    private func doc(_ els: [PanelElement]) -> PanelDocument {
        var d = PanelDocument()
        d.elements = els
        return d
    }

    func testCombineKeepsBackShapeIdentityAndPaint() throws {
        let a = box(10, 10, 40, 40, "#FF0000"), b = box(30, 30, 40, 40, "#00FF00")
        var d = doc([a, b])
        let id = try d.combine(ids: [a.id, b.id], .combine)
        XCTAssertEqual(id, a.id)
        XCTAssertEqual(d.elements.count, 1)
        let r = d.elements[0]
        XCTAssertEqual(r.kind, .path)
        XCTAssertEqual(r.fill.hexString.uppercased(), "#FF0000")
        XCTAssertEqual(r.frame.minX, 10, accuracy: 1e-3)
        XCTAssertEqual(r.frame.maxX, 70, accuracy: 1e-3)
    }

    func testSubtractIntersectExclude() throws {
        let a = box(10, 10, 40, 40, "#FF0000"), b = box(30, 10, 40, 40, "#00FF00")
        var s = doc([a, b]); _ = try s.combine(ids: [a.id, b.id], .subtract)
        XCTAssertEqual(s.elements[0].frame.maxX, 30, accuracy: 1e-3)
        var i = doc([a, b]); _ = try i.combine(ids: [a.id, b.id], .intersect)
        XCTAssertEqual(i.elements[0].frame.minX, 30, accuracy: 1e-3)
        XCTAssertEqual(i.elements[0].frame.maxX, 50, accuracy: 1e-3)
        var x = doc([a, b]); _ = try x.combine(ids: [a.id, b.id], .exclude)
        let p = try XCTUnwrap(Renderer.importedParts(for: x.elements[0]).first?.path)
        XCTAssertFalse(p.contains(CGPoint(x: 40, y: 30), using: .winding), "the overlap is cut out")
        XCTAssertTrue(p.contains(CGPoint(x: 20, y: 30), using: .winding))
    }

    func testDisjointIntersectionIsRefused() {
        let a = box(0, 0, 10, 10, "#FF0000"), b = box(50, 50, 10, 10, "#00FF00")
        var d = doc([a, b])
        XCTAssertThrowsError(try d.combine(ids: [a.id, b.id], .intersect))
        XCTAssertEqual(d.elements.count, 2, "nothing changes on refusal")
    }

    func testConvertToPathKeepsLookAndPlace() throws {
        var round = box(10, 20, 40, 30, "#336699")
        round.setCornerRadii(6)
        round.rotation = 90
        var jack = ElementKind.jack.defaultElement(at: .zero)
        jack.x = 100
        var d = doc([round, jack])
        XCTAssertEqual(try d.convertToPath(ids: [round.id, jack.id]), 1, "controls are left alone")
        let r = d.elements[0]
        XCTAssertEqual(r.id, round.id)
        XCTAssertEqual(r.kind, .path)
        XCTAssertEqual(r.rotation, 0, "rotation is applied into the geometry")
        XCTAssertEqual(r.frame.width, 30, accuracy: 1e-3)
        XCTAssertEqual(r.frame.height, 40, accuracy: 1e-3)
        XCTAssertEqual(r.fill.hexString.uppercased(), "#336699")
        XCTAssertEqual(d.elements[1].kind, .jack)

        var onlyJack = doc([jack])
        XCTAssertThrowsError(try onlyJack.convertToPath(ids: [jack.id]))
    }

    func testOutlineStroke() throws {
        var line = ElementKind.line.defaultElement(at: .zero)
        line.stroke = .hex("#FFFFFF")
        line.strokeWidth = 4
        var d = doc([line])
        let made = try d.outlineStroke(ids: [line.id])
        XCTAssertEqual(made, [line.id])
        XCTAssertEqual(d.elements[0].fill.hexString.uppercased(), "#FFFFFF")
        XCTAssertNil(d.elements[0].stroke)

        var framed = box(10, 10, 40, 40, "#FF0000")
        framed.stroke = .hex("#000000"); framed.strokeWidth = 2
        var f = doc([framed])
        _ = try f.outlineStroke(ids: [framed.id])
        XCTAssertEqual(f.elements.count, 2, "fill kept, outline added above")
        XCTAssertNil(f.elements[0].stroke)
        XCTAssertEqual(f.elements[1].frame.minX, 9, accuracy: 0.01)
    }
}
