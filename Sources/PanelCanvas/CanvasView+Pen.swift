import AppKit
import CoreGraphics
import PanelKit

// Canvas: the pen tool.
//
// Click to place a corner point; press and drag to pull out a curve handle
// (a smooth point). Click the first point to close the shape, or press Return
// (or double-click) to finish it as an open line. ⌫ removes the last point,
// Esc finishes what is there and leaves the tool. Points snap to the active
// grid; ⇧ constrains to 45°, ⌥ turns snapping off while held.

struct PenSession {
    var nodes: [PathNode] = []
    /// The last node's handle is being dragged out.
    var draggingHandle = false
    /// Where the pointer is, for the rubber band to the next point.
    var hover: CGPoint?
}

extension CanvasView {

    package var isPenActive: Bool { pen != nil }

    package func beginPen() {
        endPointEdit()
        setSelection([])
        pen = PenSession()
        window?.makeFirstResponder(self)
        window?.invalidateCursorRects(for: self)
        NSCursor.crosshair.set()
        needsDisplay = true
        onToolChange?()
    }

    /// Commits a shape in progress (if it has two or more points) and leaves
    /// the pen.
    package func endPen() {
        guard pen != nil else { return }
        commitPen(closed: false)
        pen = nil
        NSCursor.arrow.set()
        needsDisplay = true
        onToolChange?()
    }

    package func togglePen() { isPenActive ? endPen() : beginPen() }

    // MARK: Events (called from the main mouse and key handlers)

    /// Where a click lands: snapped, and constrained with ⇧.
    private func penPoint(_ raw: CGPoint, flags: NSEvent.ModifierFlags) -> CGPoint {
        var p = raw
        if flags.contains(.shift), let last = pen?.nodes.last?.point {
            let dx = p.x - last.x, dy = p.y - last.y
            let angle = (atan2(dy, dx) / (.pi / 4)).rounded() * (.pi / 4)
            let len = hypot(dx, dy)
            p = CGPoint(x: last.x + cos(angle) * len, y: last.y + sin(angle) * len)
        } else if !flags.contains(.option) {
            // A point near another element's edge or centre takes that line
            // (per axis); the grid decides the other axis.
            let g = snapToElements ? document.guideSnap(point: raw, threshold: guideThreshold) : GuideSnap()
            if snapEnabled { p = snappedCenter(p) }
            if let d = g.dx { p.x = raw.x + d }
            if let d = g.dy { p.y = raw.y + d }
            activeGuides = (g.dx != nil || g.dy != nil) ? g : nil
        }
        return p
    }

    private var closeRadius: CGFloat { 6 / zoom }

    func penMouseDown(_ event: NSEvent) {
        guard var s = pen else { return }
        let raw = panelPoint(from: event)
        if event.clickCount >= 2 {
            // The first click of the double already placed a point there.
            commitPen(closed: false)
            return
        }
        if s.nodes.count >= 2, let first = s.nodes.first,
           hypot(raw.x - first.point.x, raw.y - first.point.y) <= closeRadius {
            commitPen(closed: true)
            return
        }
        let p = penPoint(raw, flags: event.modifierFlags)
        s.nodes.append(PathNode(p))
        s.draggingHandle = true
        s.hover = p
        pen = s
        needsDisplay = true
    }

    func penMouseDragged(_ event: NSEvent) {
        guard var s = pen, s.draggingHandle, let last = s.nodes.last else { return }
        var h = panelPoint(from: event)
        if event.modifierFlags.contains(.shift) {
            let dx = h.x - last.point.x, dy = h.y - last.point.y
            let angle = (atan2(dy, dx) / (.pi / 4)).rounded() * (.pi / 4)
            let len = hypot(dx, dy)
            h = CGPoint(x: last.point.x + cos(angle) * len, y: last.point.y + sin(angle) * len)
        }
        let i = s.nodes.count - 1
        if hypot(h.x - last.point.x, h.y - last.point.y) < 2 / zoom {
            s.nodes[i].outHandle = nil
            s.nodes[i].inHandle = nil
            s.nodes[i].smooth = false
        } else {
            s.nodes[i].outHandle = h
            s.nodes[i].inHandle = CGPoint(x: 2 * last.point.x - h.x, y: 2 * last.point.y - h.y)
            s.nodes[i].smooth = true
        }
        s.hover = h
        pen = s
        needsDisplay = true
    }

    func penMouseUp(_ event: NSEvent) {
        pen?.draggingHandle = false
        needsDisplay = true
    }

    package override func mouseMoved(with event: NSEvent) {
        guard pen != nil else { super.mouseMoved(with: event); return }
        pen?.hover = penPoint(panelPoint(from: event), flags: event.modifierFlags)
        needsDisplay = true
    }

    package override func cursorUpdate(with event: NSEvent) {
        if pen != nil || pointEdit != nil { NSCursor.crosshair.set() } else { super.cursorUpdate(with: event) }
    }

    /// Return, Enter, ⌫ and Esc mean something else while drawing; they are
    /// taken here, ahead of the menu's own key equivalents (⌫ is Delete).
    func penKey(_ event: NSEvent) -> Bool {
        guard pen != nil else { return false }
        switch event.keyCode {
        case 36, 76:                       // Return, Enter
            if (pen?.nodes.count ?? 0) >= 2 { commitPen(closed: false) } else { endPen() }
            return true
        case 51, 117:                      // ⌫, ⌦
            if pen?.nodes.isEmpty == false { pen?.nodes.removeLast(); needsDisplay = true }
            return true
        case 53:                           // Esc
            endPen()
            return true
        default:
            return false
        }
    }

    /// Adds the shape in progress to the document and starts a fresh one —
    /// the pen stays active, like every drawing tool's pen.
    func commitPen(closed: Bool) {
        guard var s = pen else { return }
        var nodes = s.nodes
        // A double-click or a closing click can leave a duplicate last point.
        while nodes.count >= 2, let a = nodes.last, let b = nodes.dropLast().last,
              hypot(a.point.x - b.point.x, a.point.y - b.point.y) < 0.01 {
            nodes.removeLast()
        }
        s.nodes = []
        s.draggingHandle = false
        pen = s
        needsDisplay = true
        guard nodes.count >= 2 else { return }
        let path = EditablePath(contours: [PathContour(nodes: nodes, closed: closed && nodes.count >= 3)])
        let el = PanelElement.freeform(path, ink: document.ink(for: themePreview))
        insert([el], name: closed ? "Draw Shape" : "Draw Line")
        setSelection([el.id])
    }

    // MARK: Drawing

    func drawPenOverlay(in ctx: CGContext) {
        guard let s = pen else { return }
        ctx.saveGState()
        let accent = NSColor.systemTeal.cgColor
        if !s.nodes.isEmpty {
            let path = EditablePath(contours: [PathContour(nodes: s.nodes, closed: false)]).cgPath
            ctx.addPath(path)
            ctx.setStrokeColor(accent)
            ctx.setLineWidth(1.5 / zoom)
            ctx.strokePath()
            // Rubber band to where the next point would go.
            if let h = s.hover, !s.draggingHandle, let last = s.nodes.last {
                let band = CGMutablePath()
                band.move(to: last.point)
                if let out = last.outHandle {
                    band.addCurve(to: h, control1: out, control2: h)
                } else {
                    band.addLine(to: h)
                }
                ctx.addPath(band)
                ctx.setLineDash(phase: 0, lengths: [3 / zoom, 3 / zoom])
                ctx.setLineWidth(1 / zoom)
                ctx.strokePath()
                ctx.setLineDash(phase: 0, lengths: [])
            }
        }
        drawNodes(s.nodes, highlightFirst: s.nodes.count >= 2 && s.hover.map { h in
            hypot(h.x - s.nodes[0].point.x, h.y - s.nodes[0].point.y) <= closeRadius
        } ?? false, in: ctx, selected: [])
        ctx.restoreGState()
    }

    /// Anchor points as squares, handles as small circles on lines.
    func drawNodes(_ nodes: [PathNode], highlightFirst: Bool, in ctx: CGContext, selected: Set<Int>) {
        let r = 3.5 / zoom
        ctx.setLineWidth(1 / zoom)
        for (i, n) in nodes.enumerated() {
            for h in [n.inHandle, n.outHandle].compactMap({ $0 }) {
                ctx.setStrokeColor(NSColor.systemTeal.withAlphaComponent(0.8).cgColor)
                ctx.move(to: n.point); ctx.addLine(to: h); ctx.strokePath()
                ctx.setFillColor(NSColor.white.cgColor)
                ctx.fillEllipse(in: CGRect(x: h.x - r * 0.8, y: h.y - r * 0.8, width: r * 1.6, height: r * 1.6))
                ctx.setStrokeColor(NSColor.systemTeal.cgColor)
                ctx.strokeEllipse(in: CGRect(x: h.x - r * 0.8, y: h.y - r * 0.8, width: r * 1.6, height: r * 1.6))
            }
            let big = (i == 0 && highlightFirst) ? r * 1.8 : r
            let box = CGRect(x: n.point.x - big, y: n.point.y - big, width: big * 2, height: big * 2)
            ctx.setFillColor(selected.contains(i) ? NSColor.systemTeal.cgColor : NSColor.white.cgColor)
            ctx.fill(box)
            ctx.setStrokeColor(NSColor.black.cgColor)
            ctx.stroke(box)
        }
    }

    /// A one-line reminder of the keys, in the canvas's top-left corner.
    func drawToolHint() {
        let text: String
        if pen != nil {
            text = "Pen — click: corner · drag: curve · click first point: close · Return: finish line · ⌫: undo point · Esc: done"
        } else if pointEdit != nil {
            text = "Edit points — drag points or handles · click a segment: add · ⌫: delete · double-click a point: corner/smooth · Esc: done"
        } else {
            return
        }
        let attrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 11, weight: .medium),
            .foregroundColor: NSColor.white,
        ]
        let size = (text as NSString).size(withAttributes: attrs)
        let origin = CGPoint(x: visibleRect.minX + 10, y: visibleRect.minY + 10)
        let box = CGRect(x: origin.x - 6, y: origin.y - 3, width: size.width + 12, height: size.height + 6)
        NSColor.black.withAlphaComponent(0.7).setFill()
        NSBezierPath(roundedRect: box, xRadius: 5, yRadius: 5).fill()
        (text as NSString).draw(at: origin, withAttributes: attrs)
    }
}

extension CanvasView {
    /// Edit ▸ Delete (plain ⌫) is nil-targeted and reaches the canvas first:
    /// while drawing or editing points it removes points, not elements.
    @objc package func delete(_ sender: Any?) {
        if pen != nil {
            if pen?.nodes.isEmpty == false { pen?.nodes.removeLast(); needsDisplay = true }
        } else if var s = pointEdit {
            deleteSelectedPoints(&s)
        } else {
            deleteSelection()
        }
    }
}
