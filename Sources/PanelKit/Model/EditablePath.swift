import Foundation
import CoreGraphics

// Freeform shapes as points and handles.
//
// A freeform shape is stored the way an imported path always has been: a
// `.path` element whose `pathData` is normalised into a 0…1 box, so its frame
// scales it like any other element. EditablePath is the editing view of that
// data — anchor points with optional Bézier handles, in panel coordinates —
// used by the pen tool, point editing and shape operations.

/// One anchor point. Handles are absolute positions; nil means the segment on
/// that side is straight at this end.
package struct PathNode: Hashable {
    package var point: CGPoint
    package var inHandle: CGPoint?
    package var outHandle: CGPoint?
    /// Smooth points keep their two handles in line when one is dragged.
    package var smooth: Bool

    package init(_ point: CGPoint, in inHandle: CGPoint? = nil, out outHandle: CGPoint? = nil, smooth: Bool = false) {
        self.point = point
        self.inHandle = inHandle
        self.outHandle = outHandle
        self.smooth = smooth
    }
}

package struct PathContour: Hashable {
    package var nodes: [PathNode]
    package var closed: Bool

    package init(nodes: [PathNode], closed: Bool) {
        self.nodes = nodes
        self.closed = closed
    }
}

package struct EditablePath: Hashable {
    package var contours: [PathContour]

    package init(contours: [PathContour]) { self.contours = contours }

    package var isEmpty: Bool { contours.allSatisfy { $0.nodes.isEmpty } }

    /// Any contour left open: drawn as a line, not a filled shape.
    package var hasOpenContour: Bool { contours.contains { !$0.closed && $0.nodes.count > 1 } }

    // MARK: To and from CGPath

    package var cgPath: CGPath {
        let p = CGMutablePath()
        for c in contours where !c.nodes.isEmpty {
            p.move(to: c.nodes[0].point)
            let count = c.nodes.count
            let segments = c.closed ? count : count - 1
            for i in 0..<segments {
                let a = c.nodes[i], b = c.nodes[(i + 1) % count]
                Self.addSegment(p, from: a, to: b)
            }
            if c.closed { p.closeSubpath() }
        }
        return p
    }

    private static func addSegment(_ p: CGMutablePath, from a: PathNode, to b: PathNode) {
        if a.outHandle == nil && b.inHandle == nil {
            p.addLine(to: b.point)
        } else {
            p.addCurve(to: b.point, control1: a.outHandle ?? a.point, control2: b.inHandle ?? b.point)
        }
    }

    /// Reads any CGPath. Quadratic segments become the equivalent cubic; a
    /// closing segment that lands on the start point is folded into it.
    package init(_ path: CGPath) {
        var contours: [PathContour] = []
        var nodes: [PathNode] = []
        var closed = false
        func flush() {
            if !nodes.isEmpty { contours.append(PathContour(nodes: nodes, closed: closed)) }
            nodes = []; closed = false
        }
        func near(_ a: CGPoint, _ b: CGPoint) -> Bool { abs(a.x - b.x) < 1e-6 && abs(a.y - b.y) < 1e-6 }
        path.applyWithBlock { e in
            let el = e.pointee
            switch el.type {
            case .moveToPoint:
                flush()
                nodes.append(PathNode(el.points[0]))
            case .addLineToPoint:
                nodes.append(PathNode(el.points[0]))
            case .addQuadCurveToPoint:
                guard let last = nodes.last?.point else { return }
                let c = el.points[0], end = el.points[1]
                let c1 = CGPoint(x: last.x + 2 / 3 * (c.x - last.x), y: last.y + 2 / 3 * (c.y - last.y))
                let c2 = CGPoint(x: end.x + 2 / 3 * (c.x - end.x), y: end.y + 2 / 3 * (c.y - end.y))
                nodes[nodes.count - 1].outHandle = c1
                nodes.append(PathNode(end, in: c2))
            case .addCurveToPoint:
                guard !nodes.isEmpty else { return }
                nodes[nodes.count - 1].outHandle = el.points[0]
                nodes.append(PathNode(el.points[2], in: el.points[1]))
            case .closeSubpath:
                closed = true
                if nodes.count > 1, near(nodes[0].point, nodes[nodes.count - 1].point) {
                    let last = nodes.removeLast()
                    nodes[0].inHandle = last.inHandle
                }
                flush()
            @unknown default:
                break
            }
        }
        flush()
        // A node whose handles are collinear through it reads as smooth.
        for ci in contours.indices {
            for ni in contours[ci].nodes.indices {
                let n = contours[ci].nodes[ni]
                if let a = n.inHandle, let b = n.outHandle {
                    let cross = (a.x - n.point.x) * (b.y - n.point.y) - (a.y - n.point.y) * (b.x - n.point.x)
                    let la = hypot(a.x - n.point.x, a.y - n.point.y), lb = hypot(b.x - n.point.x, b.y - n.point.y)
                    if la > 1e-6, lb > 1e-6, abs(cross) / (la * lb) < 1e-3 { contours[ci].nodes[ni].smooth = true }
                }
            }
        }
        self.contours = contours
    }

    package func transformed(_ t: CGAffineTransform) -> EditablePath {
        EditablePath(contours: contours.map { c in
            PathContour(nodes: c.nodes.map { n in
                PathNode(n.point.applying(t), in: n.inHandle?.applying(t),
                         out: n.outHandle?.applying(t), smooth: n.smooth)
            }, closed: c.closed)
        })
    }
}

// MARK: - Freeform elements

extension PanelElement {

    /// The shape of a `.path` element in panel coordinates, unrotated (the
    /// frame's own space). nil for any other kind.
    package var editablePath: EditablePath? {
        guard kind == .path, let d = pathData, let unit = SVGPath.path(fromD: d) ?? SVGPath.partialPath(fromD: d)
        else { return nil }
        let t = CGAffineTransform(scaleX: max(w, 0.01), y: max(h, 0.01))
            .concatenating(CGAffineTransform(translationX: x, y: y))
        return EditablePath(unit).transformed(t)
    }

    /// Replaces a `.path` element's geometry, refitting its frame to the
    /// shape's bounds so selection, handles and alignment keep working.
    package mutating func setPath(_ path: EditablePath) {
        setPath(path.cgPath)
    }

    package mutating func setPath(_ path: CGPath) {
        let (frame, data) = PanelElement.normalised(path)
        self.frame = frame
        pathData = data
    }

    /// A path re-expressed in a 0…1 box, and the box. A perfectly horizontal
    /// or vertical path has a zero-size box, which would divide by zero and
    /// make the element unselectable, so each side is at least half a pixel.
    package static func normalised(_ path: CGPath) -> (frame: CGRect, data: String) {
        let box = path.boundingBoxOfPath
        let w = max(box.width, 0.5), h = max(box.height, 0.5)
        let frame = CGRect(x: box.minX, y: box.minY, width: w, height: h)
        var t = CGAffineTransform(translationX: -box.minX, y: -box.minY)
            .concatenating(CGAffineTransform(scaleX: 1 / w, y: 1 / h))
        guard let unit = path.copy(using: &t) else { return (frame, "") }
        return (frame, PathSVG.d(unit, decimals: 6))
    }

    /// A new freeform element drawn with the pen. Closed shapes are filled;
    /// open ones are lines, stroked in the panel's ink.
    package static func freeform(_ path: EditablePath, ink: ColorSpec) -> PanelElement {
        var e = ElementKind.path.defaultElement(at: .zero)
        e.setPath(path)
        if path.hasOpenContour {
            e.fill = ColorSpec(r: 0, g: 0, b: 0, a: 0)
            e.stroke = ink
            e.strokeWidth = 1.5
        } else {
            e.fill = .swatch("Orange")
            e.stroke = nil
        }
        e.name = path.hasOpenContour ? "Line" : "Shape"
        return e
    }
}
