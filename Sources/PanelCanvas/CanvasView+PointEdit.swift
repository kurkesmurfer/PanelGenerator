import AppKit
import CoreGraphics
import PanelKit

// Canvas: editing the points of one freeform shape.
//
// Double-click a freeform shape (or use Edit ▸ Edit Points) to start. Drag a
// point to move it with its handles, or a handle to reshape the curve (a
// smooth point keeps its handles in line). Click on the outline to add a
// point there, ⌫ deletes the selected points, double-click a point to switch
// it between corner and smooth. ⇧-click adds to the point selection. Esc, or a
// click away from the shape, finishes.

struct PointEditSession {
    var elementID: UUID
    /// The shape in the element's own unrotated space (panel coordinates).
    var path: EditablePath
    /// The rotation pivot `path` is expressed against: the element's frame
    /// centre when the session (or the last gesture) started.
    var pivot: CGPoint
    var selected: Set<NodeRef> = []
    var drag: Drag? = nil

    struct NodeRef: Hashable { var contour: Int; var node: Int }
    enum Drag {
        case nodes(start: CGPoint, original: EditablePath)
        case handle(NodeRef, isOut: Bool)
    }
}

extension CanvasView {

    package var isEditingPoints: Bool { pointEdit != nil }

    /// Starts point editing on `id`, which must be a freeform shape. Any other
    /// kind is first offered for conversion by the caller.
    @discardableResult
    package func beginPointEdit(_ id: UUID? = nil) -> Bool {
        let target = id ?? (selection.count == 1 ? selection.first : nil)
        guard let target, let el = document.elements.first(where: { $0.id == target }),
              let path = el.editablePath else { return false }
        if pen != nil { endPen() }
        pointEdit = PointEditSession(elementID: target, path: path, pivot: el.center)
        setSelection([target])
        window?.makeFirstResponder(self)
        NSCursor.crosshair.set()
        needsDisplay = true
        onToolChange?()
        return true
    }

    package func endPointEdit() {
        guard pointEdit != nil else { return }
        pointEdit = nil
        NSCursor.arrow.set()
        needsDisplay = true
        onToolChange?()
    }

    private var editedElement: PanelElement? {
        guard let s = pointEdit else { return nil }
        return document.elements.first { $0.id == s.elementID }
    }

    /// Panel point → the element's unrotated space.
    private func editLocal(_ p: CGPoint) -> CGPoint {
        guard let el = editedElement, let s = pointEdit else { return p }
        return toLocal(p, rotation: el.rotation, center: s.pivot)
    }

    /// Re-reads the shape from the element after a change has been written,
    /// so the session's coordinates match the refitted frame again.
    private func resyncPointEdit() {
        guard let el = editedElement, let fresh = el.editablePath else { return }
        pointEdit?.path = fresh
        pointEdit?.pivot = el.center
    }

    // MARK: Hit testing

    private var hitRadius: CGFloat { 5 / zoom }

    private func hitHandle(_ p: CGPoint, in s: PointEditSession) -> (PointEditSession.NodeRef, Bool)? {
        for (ci, c) in s.path.contours.enumerated() {
            for (ni, n) in c.nodes.enumerated() {
                if let h = n.outHandle, hypot(h.x - p.x, h.y - p.y) <= hitRadius { return (.init(contour: ci, node: ni), true) }
                if let h = n.inHandle, hypot(h.x - p.x, h.y - p.y) <= hitRadius { return (.init(contour: ci, node: ni), false) }
            }
        }
        return nil
    }

    private func hitNode(_ p: CGPoint, in s: PointEditSession) -> PointEditSession.NodeRef? {
        for (ci, c) in s.path.contours.enumerated() {
            for (ni, n) in c.nodes.enumerated() where hypot(n.point.x - p.x, n.point.y - p.y) <= hitRadius {
                return .init(contour: ci, node: ni)
            }
        }
        return nil
    }

    /// The segment nearest `p` within reach, and where along it (0…1).
    private func hitSegment(_ p: CGPoint, in s: PointEditSession) -> (contour: Int, after: Int, t: CGFloat)? {
        var best: (Int, Int, CGFloat, CGFloat)? = nil
        for (ci, c) in s.path.contours.enumerated() {
            let n = c.nodes.count
            guard n >= 2 else { continue }
            for i in 0..<(c.closed ? n : n - 1) {
                let a = c.nodes[i], b = c.nodes[(i + 1) % n]
                let p0 = a.point, p1 = a.outHandle ?? a.point, p2 = b.inHandle ?? b.point, p3 = b.point
                for k in 0...48 {
                    let t = CGFloat(k) / 48
                    let q = Self.cubic(p0, p1, p2, p3, t)
                    let d = hypot(q.x - p.x, q.y - p.y)
                    if d <= hitRadius, d < (best?.3 ?? .infinity) { best = (ci, i, t, d) }
                }
            }
        }
        return best.map { ($0.0, $0.1, $0.2) }
    }

    static func cubic(_ p0: CGPoint, _ p1: CGPoint, _ p2: CGPoint, _ p3: CGPoint, _ t: CGFloat) -> CGPoint {
        let u = 1 - t
        let a = u * u * u, b = 3 * u * u * t, c = 3 * u * t * t, d = t * t * t
        return CGPoint(x: a * p0.x + b * p1.x + c * p2.x + d * p3.x,
                       y: a * p0.y + b * p1.y + c * p2.y + d * p3.y)
    }

    // MARK: Events

    func pointEditMouseDown(_ event: NSEvent) {
        guard var s = pointEdit, let el = editedElement else { return }
        let p = editLocal(panelPoint(from: event))
        let adding = event.modifierFlags.contains(.shift)

        if let (ref, isOut) = hitHandle(p, in: s) {
            s.drag = .handle(ref, isOut: isOut)
            beginGestureUndo("Edit Points")
        } else if let ref = hitNode(p, in: s) {
            if event.clickCount >= 2 {
                toggleSmooth(ref, in: &s)
                pointEdit = s
                commitPointEdit(name: "Corner / Smooth Point")
                return
            }
            if adding {
                if s.selected.contains(ref) { s.selected.remove(ref) } else { s.selected.insert(ref) }
            } else if !s.selected.contains(ref) {
                s.selected = [ref]
            }
            s.drag = .nodes(start: p, original: s.path)
            beginGestureUndo("Edit Points")
        } else if let hit = hitSegment(p, in: s) {
            insertNode(contour: hit.contour, after: hit.after, t: hit.t, in: &s)
            pointEdit = s
            commitPointEdit(name: "Add Point")
            return
        } else {
            // A click away from the shape finishes; on it, just clears the
            // point selection.
            let local = el.frame.insetBy(dx: -8 / zoom, dy: -8 / zoom)
            if local.contains(p) {
                s.selected = []
            } else {
                endPointEdit()
                return
            }
        }
        pointEdit = s
        needsDisplay = true
    }

    func pointEditMouseDragged(_ event: NSEvent) {
        guard var s = pointEdit, let drag = s.drag else { return }
        var p = editLocal(panelPoint(from: event))
        switch drag {
        case .nodes(let start, let original):
            if snapEnabled, !event.modifierFlags.contains(.option), s.selected.count == 1,
               let only = s.selected.first {
                // A single point snaps itself; a group moves by the snapped delta of its first.
                let origin = original.contours[only.contour].nodes[only.node].point
                let target = snappedCenter(CGPoint(x: origin.x + p.x - start.x, y: origin.y + p.y - start.y))
                p = CGPoint(x: start.x + target.x - origin.x, y: start.y + target.y - origin.y)
            }
            let dx = p.x - start.x, dy = p.y - start.y
            var path = original
            for ref in s.selected {
                var n = path.contours[ref.contour].nodes[ref.node]
                n.point.x += dx; n.point.y += dy
                n.inHandle = n.inHandle.map { CGPoint(x: $0.x + dx, y: $0.y + dy) }
                n.outHandle = n.outHandle.map { CGPoint(x: $0.x + dx, y: $0.y + dy) }
                path.contours[ref.contour].nodes[ref.node] = n
            }
            s.path = path
        case .handle(let ref, let isOut):
            var n = s.path.contours[ref.contour].nodes[ref.node]
            if isOut { n.outHandle = p } else { n.inHandle = p }
            // A smooth point keeps the opposite handle on the same line, at
            // its own length; ⌥ breaks it into a corner.
            if event.modifierFlags.contains(.option) {
                n.smooth = false
            } else if n.smooth, let other = isOut ? n.inHandle : n.outHandle {
                let len = hypot(other.x - n.point.x, other.y - n.point.y)
                let dx = p.x - n.point.x, dy = p.y - n.point.y
                let d = max(hypot(dx, dy), 1e-6)
                let mirrored = CGPoint(x: n.point.x - dx / d * len, y: n.point.y - dy / d * len)
                if isOut { n.inHandle = mirrored } else { n.outHandle = mirrored }
            }
            s.path.contours[ref.contour].nodes[ref.node] = n
        }
        pointEdit = s
        applyPointEdit()
    }

    func pointEditMouseUp(_ event: NSEvent) {
        guard pointEdit?.drag != nil else { return }
        pointEdit?.drag = nil
        endGesture()
        resyncPointEdit()
        needsDisplay = true
    }

    /// ⌫, Esc while editing points.
    func pointEditKey(_ event: NSEvent) -> Bool {
        guard var s = pointEdit else { return false }
        switch event.keyCode {
        case 53, 36, 76:                   // Esc, Return, Enter
            endPointEdit()
            return true
        case 51, 117:                      // ⌫, ⌦
            deleteSelectedPoints(&s)
            return true
        default:
            return false
        }
    }

    func deleteSelectedPoints(_ s: inout PointEditSession) {
        guard !s.selected.isEmpty else { return }
        var path = s.path
        for ref in s.selected.sorted(by: { ($0.contour, $0.node) > ($1.contour, $1.node) }) {
            path.contours[ref.contour].nodes.remove(at: ref.node)
        }
        path.contours.removeAll { $0.nodes.count < 2 }
        for i in path.contours.indices where path.contours[i].nodes.count < 3 { path.contours[i].closed = false }
        s.selected = []
        if path.isEmpty {
            let id = s.elementID
            endPointEdit()
            apply(elements: document.elements.filter { $0.id != id }, name: "Delete Points")
            setSelection([])
            return
        }
        s.path = path
        pointEdit = s
        commitPointEdit(name: "Delete Points")
    }

    private func toggleSmooth(_ ref: PointEditSession.NodeRef, in s: inout PointEditSession) {
        let c = s.path.contours[ref.contour]
        var n = c.nodes[ref.node]
        if n.smooth || n.inHandle != nil || n.outHandle != nil {
            n.inHandle = nil; n.outHandle = nil; n.smooth = false
        } else {
            let count = c.nodes.count
            let prev = (ref.node > 0 || c.closed) ? c.nodes[(ref.node - 1 + count) % count].point : n.point
            let next = (ref.node < count - 1 || c.closed) ? c.nodes[(ref.node + 1) % count].point : n.point
            var tx = next.x - prev.x, ty = next.y - prev.y
            let tl = max(hypot(tx, ty), 1e-6)
            tx /= tl; ty /= tl
            let lin = hypot(n.point.x - prev.x, n.point.y - prev.y) / 3
            let lout = hypot(next.x - n.point.x, next.y - n.point.y) / 3
            n.inHandle = CGPoint(x: n.point.x - tx * lin, y: n.point.y - ty * lin)
            n.outHandle = CGPoint(x: n.point.x + tx * lout, y: n.point.y + ty * lout)
            n.smooth = true
        }
        s.path.contours[ref.contour].nodes[ref.node] = n
    }

    /// Splits the segment after `after` at `t` (de Casteljau), keeping the
    /// curve's shape exactly.
    private func insertNode(contour ci: Int, after i: Int, t: CGFloat, in s: inout PointEditSession) {
        var c = s.path.contours[ci]
        let n = c.nodes.count
        let j = (i + 1) % n
        let a = c.nodes[i], b = c.nodes[j]
        func lerp(_ p: CGPoint, _ q: CGPoint) -> CGPoint { CGPoint(x: p.x + (q.x - p.x) * t, y: p.y + (q.y - p.y) * t) }
        if a.outHandle == nil && b.inHandle == nil {
            c.nodes.insert(PathNode(lerp(a.point, b.point)), at: i + 1)
        } else {
            let p0 = a.point, p1 = a.outHandle ?? a.point, p2 = b.inHandle ?? b.point, p3 = b.point
            let q0 = lerp(p0, p1), q1 = lerp(p1, p2), q2 = lerp(p2, p3)
            let r0 = lerp(q0, q1), r1 = lerp(q1, q2)
            let m = lerp(r0, r1)
            c.nodes[i].outHandle = q0
            c.nodes[j].inHandle = q2
            c.nodes.insert(PathNode(m, in: r0, out: r1, smooth: true), at: i + 1)
        }
        s.path.contours[ci] = c
        s.selected = [.init(contour: ci, node: i + 1)]
    }

    /// Writes the session's path into the element during a drag (the
    /// gesture's undo is already registered).
    private func applyPointEdit() {
        guard let s = pointEdit else { return }
        var els = document.elements
        guard let i = els.firstIndex(where: { $0.id == s.elementID }) else { return }
        els[i] = Self.reshaped(els[i], to: s.path, pivot: s.pivot)
        document.elements = els
        needsDisplay = true
        notifyChange()
    }

    /// One undoable change outside a drag.
    private func commitPointEdit(name: String) {
        guard let s = pointEdit else { return }
        var els = document.elements
        guard let i = els.firstIndex(where: { $0.id == s.elementID }) else { return }
        els[i] = Self.reshaped(els[i], to: s.path, pivot: s.pivot)
        apply(elements: els, name: name)
        resyncPointEdit()
        needsDisplay = true
    }

    /// `el` with a new shape, given in the unrotated space about `pivot`.
    /// The frame is refitted to the shape; a rotated element's frame is then
    /// shifted so that rotating about its new centre leaves every point where
    /// rotating about the old pivot put it: d = R(v) − v, v = new centre − pivot.
    static func reshaped(_ el: PanelElement, to path: EditablePath, pivot: CGPoint) -> PanelElement {
        var e = el
        e.setPath(path)
        if el.rotation != 0 {
            let c = e.center
            let turned = Geo.rotate(c, around: pivot, degrees: el.rotation)
            e.x += turned.x - c.x
            e.y += turned.y - c.y
        }
        return e
    }

    // MARK: Drawing

    func drawPointEditOverlay(in ctx: CGContext) {
        guard let s = pointEdit, let el = editedElement else { return }
        ctx.saveGState()
        if el.rotation != 0 {
            ctx.translateBy(x: s.pivot.x, y: s.pivot.y)
            ctx.rotate(by: Geo.deg2rad(el.rotation))
            ctx.translateBy(x: -s.pivot.x, y: -s.pivot.y)
        }
        ctx.addPath(s.path.cgPath)
        ctx.setStrokeColor(NSColor.systemTeal.cgColor)
        ctx.setLineWidth(1 / zoom)
        ctx.strokePath()
        for (ci, c) in s.path.contours.enumerated() {
            let sel = Set(s.selected.filter { $0.contour == ci }.map(\.node))
            drawNodes(c.nodes, highlightFirst: false, in: ctx, selected: sel)
        }
        ctx.restoreGState()
    }
}
