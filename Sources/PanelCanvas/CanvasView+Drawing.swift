import AppKit
import CoreGraphics
import PanelKit

// Canvas: drawing the panel, grids and overlays.

extension CanvasView {

    // MARK: Drawing

    package override func draw(_ dirtyRect: NSRect) {
        guard let ctx = NSGraphicsContext.current?.cgContext else { return }

        // Workspace backdrop
        ctx.setFillColor(ColorSpec.hex("#26262E").nsColor.cgColor)
        ctx.fill(bounds)

        ctx.saveGState()
        let origin = contentOrigin
        ctx.translateBy(x: origin.x, y: origin.y)
        ctx.scaleBy(x: zoom, y: zoom)

        // Panel shadow
        let panelRect = CGRect(origin: .zero, size: document.pixelSize)
        ctx.setShadow(offset: CGSize(width: 0, height: -3 / zoom), blur: 10 / zoom,
                      color: NSColor.black.withAlphaComponent(0.55).cgColor)
        ctx.setFillColor(document.paper(for: themePreview).nsColor.cgColor)
        ctx.fill(panelRect.insetBy(dx: -1, dy: -1).offsetBy(dx: 0, dy: 0))
        ctx.setShadow(offset: .zero, blur: 0, color: nil)

        Renderer.drawBackground(document, in: ctx, variant: themePreview)
        drawGrid(in: ctx)
        if snapEnabled && snapMode == .sergeGrid { drawSergeGrid(in: ctx) }
        if snapEnabled && snapMode == .customGrid { drawCustomGrid(in: ctx) }

        for el in document.elements where el.isHidden != true {
            // A tracing template is drawn faintly and behind your own work in
            // spirit — it is reference, not artwork. It is still visible enough
            // to trace, and the layer list is where you select or delete it.
            if el.isTemplate == true {
                ctx.saveGState()
                ctx.setAlpha(0.35)
                Renderer.draw(el, in: ctx, doc: document, variant: themePreview)
                ctx.restoreGState()
            } else {
                Renderer.draw(el, in: ctx, doc: document, variant: themePreview)
            }
        }

        drawSelectionOverlay(in: ctx)
        drawMarqueeOverlay(in: ctx)

        ctx.restoreGState()
    }

    private func drawGrid(in ctx: CGContext) {
        let size = document.pixelSize
        let minor = PanelMetrics.pixelsPerHP
        ctx.saveGState()
        ctx.clip(to: CGRect(origin: .zero, size: size))

        func lines(step: CGFloat, alpha: CGFloat) {
            ctx.setStrokeColor(NSColor.white.withAlphaComponent(alpha).cgColor)
            ctx.setLineWidth(1 / zoom)
            var x: CGFloat = step
            while x < size.width - 0.01 {
                ctx.move(to: CGPoint(x: x, y: 0)); ctx.addLine(to: CGPoint(x: x, y: size.height))
                x += step
            }
            var y: CGFloat = step
            while y < size.height - 0.01 {
                ctx.move(to: CGPoint(x: 0, y: y)); ctx.addLine(to: CGPoint(x: size.width, y: y))
                y += step
            }
            ctx.strokePath()
        }
        lines(step: minor, alpha: 0.05)
        lines(step: minor * 4, alpha: 0.09)
        ctx.restoreGState()
    }

    /// Visual guide for the active Serge grid: main row/main column
    /// intersections as solid dots (knob positions), every other
    /// combination -- main row x half-lane column, half row x main
    /// column, half row x half-lane column -- as smaller, dimmer dots (the
    /// LED/switch/jack positions, including the "parallel slot" a
    /// half-lane column offers on a main row -- confirmed against the real
    /// GTS panel, where status LEDs sit at half-lane column x's but at the
    /// full height of the main row 1 jacks either side of them).
    private func drawSergeGrid(in ctx: CGContext) {
        let l = SergeGrid.lines(for: document)
        guard !l.mainRows.isEmpty || !l.halfRows.isEmpty else { return }
        ctx.saveGState()
        ctx.clip(to: CGRect(origin: .zero, size: document.pixelSize))

        func dots(rows: [CGFloat], cols: [CGFloat], radius: CGFloat, alpha: CGFloat) {
            guard !rows.isEmpty, !cols.isEmpty else { return }
            ctx.setFillColor(NSColor.white.withAlphaComponent(alpha).cgColor)
            for y in rows {
                for x in cols {
                    ctx.fillEllipse(in: CGRect(x: x - radius, y: y - radius,
                                               width: radius * 2, height: radius * 2))
                }
            }
        }
        dots(rows: l.mainRows, cols: l.mainCols, radius: 2.2 / zoom, alpha: 0.35)
        dots(rows: l.mainRows, cols: l.halfCols, radius: 1.5 / zoom, alpha: 0.22)
        dots(rows: l.halfRows, cols: l.mainCols, radius: 1.5 / zoom, alpha: 0.22)
        dots(rows: l.halfRows, cols: l.halfCols, radius: 1.5 / zoom, alpha: 0.22)
        ctx.restoreGState()
    }

    /// Visual guide for the active custom grid: a dot at every column x row
    /// intersection of the panel's own configured N x M divisions, plus (if
    /// Serge-style half positions are on) dimmer dots at the half-row/
    /// half-lane crossings -- same two-tier treatment as `drawSergeGrid`.
    private func drawCustomGrid(in ctx: CGContext) {
        let l = CustomGrid.lines(for: document)
        guard !l.mainCols.isEmpty, !l.mainRows.isEmpty else { return }
        ctx.saveGState()
        ctx.clip(to: CGRect(origin: .zero, size: document.pixelSize))

        func dots(rows: [CGFloat], cols: [CGFloat], radius: CGFloat, alpha: CGFloat) {
            guard !rows.isEmpty, !cols.isEmpty else { return }
            ctx.setFillColor(NSColor.white.withAlphaComponent(alpha).cgColor)
            for y in rows {
                for x in cols {
                    ctx.fillEllipse(in: CGRect(x: x - radius, y: y - radius,
                                               width: radius * 2, height: radius * 2))
                }
            }
        }
        dots(rows: l.mainRows, cols: l.mainCols, radius: 2.2 / zoom, alpha: 0.35)
        dots(rows: l.halfRows, cols: l.halfCols, radius: 1.5 / zoom, alpha: 0.22)
        // Quarter tier is uncorrelated (available on every row/column), so
        // draw it as its own faint overlay rather than a diagonal subset.
        let allRows = l.mainRows + l.halfRows + l.quarterRows
        let allCols = l.mainCols + l.halfCols
        dots(rows: allRows, cols: l.quarterCols, radius: 1.1 / zoom, alpha: 0.14)
        dots(rows: l.quarterRows, cols: allCols, radius: 1.1 / zoom, alpha: 0.14)
        ctx.restoreGState()
    }

    func transformedPath(for el: PanelElement) -> CGPath {
        guard el.rotation != 0 else { return CGPath(rect: el.frame, transform: nil) }
        var t = CGAffineTransform(translationX: el.center.x, y: el.center.y)
        t = t.rotated(by: Geo.deg2rad(el.rotation))
        t = t.translatedBy(x: -el.center.x, y: -el.center.y)
        return CGPath(rect: el.frame, transform: &t)
    }

    private func drawSelectionOverlay(in ctx: CGContext) {
        // Multi-selection: group bounds + corner handles + rotate badge.
        if selection.count > 1, let b = selectionBounds {
            ctx.setStrokeColor(ColorSpec.hex("#4FC3F7").nsColor.cgColor)
            ctx.setLineWidth(1 / zoom)
            ctx.stroke(b)
            for (dir, r) in activeHandles(for: b)
            where dir == .nw || dir == .ne || dir == .sw || dir == .se {
                ctx.setFillColor(NSColor.white.cgColor)
                let hr = r.insetBy(dx: -handleSize / 2, dy: -handleSize / 2)
                ctx.fill(hr)
                ctx.setStrokeColor(NSColor.black.cgColor)
                ctx.stroke(hr)
            }
            drawOverlayBadge(ctx, at: CGPoint(x: b.midX, y: b.minY - overlayHandleOffset),
                             glyph: "↻", color: ColorSpec.hex("#4FC3F7"))
        }
        let ids = selection
        guard !ids.isEmpty else { return }

        for el in document.elements where el.isHidden != true && ids.contains(el.id) {
            ctx.saveGState()
            ctx.addPath(transformedPath(for: el))
            ctx.setStrokeColor(ColorSpec.hex("#4FC3F7").nsColor.cgColor)
            ctx.setLineWidth(1.2 / zoom)
            ctx.setLineDash(phase: 0, lengths: [4 / zoom, 3 / zoom])
            ctx.strokePath()
            ctx.restoreGState()
        }

        // Resize handles, single-selection. Drawn at the frame's own
        // (unrotated) corners, then rotated onto the screen around the
        // element's centre so they still land on the visible, tilted
        // bounding box -- resizing along a rotated element's own axes only
        // reads correctly if its handles are where the element visibly is.
        if let p = primaryElement {
            let hs = handleSize
            for (_, r) in activeHandles(for: p.frame) {
                let mid = CGPoint(x: r.midX, y: r.midY)
                let c = p.rotation == 0 ? mid : Geo.rotate(mid, around: p.center, degrees: p.rotation)
                let hr = CGRect(x: c.x - hs / 2, y: c.y - hs / 2, width: hs, height: hs)
                ctx.setFillColor(NSColor.white.cgColor)
                ctx.fill(hr)
                ctx.setStrokeColor(NSColor.black.cgColor)
                ctx.setLineWidth(1 / zoom)
                ctx.stroke(hr)
            }
        }

        // Rotation + mirror badges (single selection).
        if let p = primaryElement {
            if let rp = rotateHandlePoint {
                ctx.setStrokeColor(ColorSpec.hex("#4FC3F7").nsColor.cgColor)
                ctx.setLineWidth(1.2 / zoom)
                ctx.move(to: CGPoint(x: p.frame.midX, y: p.frame.minY))
                ctx.addLine(to: rp)
                ctx.strokePath()
                drawOverlayBadge(ctx, at: rp, glyph: "↻", color: ColorSpec.hex("#4FC3F7"))
            }
            if let m = mirrorHandlePoints {
                drawOverlayBadge(ctx, at: m.x, glyph: "⇄", color: ColorSpec.hex("#FFB74D"))
                drawOverlayBadge(ctx, at: m.y, glyph: "⇅", color: ColorSpec.hex("#FFB74D"))
            }
        }
    }

    private func drawOverlayBadge(_ ctx: CGContext, at c: CGPoint, glyph: String, color: ColorSpec) {
        let r = badgeRect(at: c)
        ctx.setFillColor(color.nsColor.cgColor)
        ctx.fillEllipse(in: r)
        ctx.setStrokeColor(NSColor.black.withAlphaComponent(0.75).cgColor)
        ctx.setLineWidth(1 / zoom)
        ctx.strokeEllipse(in: r)
        let attrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.boldSystemFont(ofSize: 8), .foregroundColor: NSColor.black]
        let size = (glyph as NSString).size(withAttributes: attrs)
        (glyph as NSString).draw(at: CGPoint(x: c.x - size.width / 2, y: c.y - size.height / 2),
                                 withAttributes: attrs)
    }

    private func drawMarqueeOverlay(in ctx: CGContext) {
        guard let m = marqueeRect else { return }
        ctx.setFillColor(NSColor.white.withAlphaComponent(0.08).cgColor)
        ctx.fill(m)
        ctx.setStrokeColor(NSColor.white.withAlphaComponent(0.7).cgColor)
        ctx.setLineWidth(1 / zoom)
        ctx.setLineDash(phase: 0, lengths: [3 / zoom, 3 / zoom])
        ctx.stroke(m)
    }
}
