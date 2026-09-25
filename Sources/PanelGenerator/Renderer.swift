import Foundation
import AppKit
import CoreGraphics
import CoreText

// MARK: - ShapePart
// One paintable piece of an element. Canvas, PNG and SVG exporters all consume
// exactly these, so what you see is what exports.

struct ShapePart {
    var path: CGPath
    var fill: ColorSpec?
    var stroke: ColorSpec?
    var lineWidth: CGFloat = 1
    /// Marks the parts of a knob that turn with the parameter. Rack's SvgKnob
    /// rotates one SVG over a static background, so the split has to be
    /// declared here rather than guessed from part ordering.
    var rotates: Bool = false
}

// MARK: - Renderer

enum Renderer {

    // MARK: Path builders

    static func ellipsePath(_ r: CGRect) -> CGPath {
        CGPath(ellipseIn: r, transform: nil)
    }

    /// A `.line` element's path: a straight or gently bowed run down the
    /// frame's vertical centre-line, top-mid to bottom-mid (rotate the
    /// element for a horizontal or diagonal run). `bow` offsets the curve's
    /// control point sideways from the straight midpoint -- 0 is dead
    /// straight; Serge's own hardware often bows this kind of connector
    /// slightly around whatever sits between a knob and its jack.
    static func linePath(_ f: CGRect, bow: CGFloat) -> CGPath {
        let top = CGPoint(x: f.midX, y: f.minY)
        let bottom = CGPoint(x: f.midX, y: f.maxY)
        let p = CGMutablePath()
        p.move(to: top)
        if bow == 0 {
            p.addLine(to: bottom)
        } else {
            p.addQuadCurve(to: bottom, control: CGPoint(x: f.midX + bow, y: f.midY))
        }
        return p
    }

    static func roundedRectPath(_ f: CGRect,
                                tl: CGFloat, tr: CGFloat,
                                br: CGFloat, bl: CGFloat) -> CGPath {
        let maxR = min(f.width, f.height) / 2
        func cl(_ v: CGFloat) -> CGFloat { min(max(v, 0), maxR) }
        let TL = cl(tl), TR = cl(tr), BR = cl(br), BL = cl(bl)
        let p = CGMutablePath()
        p.move(to: CGPoint(x: f.minX + TL, y: f.minY))
        if TR > 0 {
            // addArc connects from the current point to the arc start automatically
            p.addArc(tangent1End: CGPoint(x: f.maxX, y: f.minY), tangent2End: CGPoint(x: f.maxX, y: f.minY + TR), radius: TR)
        } else {
            p.addLine(to: CGPoint(x: f.maxX, y: f.minY))
        }
        if BR > 0 {
            p.addArc(tangent1End: CGPoint(x: f.maxX, y: f.maxY), tangent2End: CGPoint(x: f.maxX - BR, y: f.maxY), radius: BR)
        } else {
            p.addLine(to: CGPoint(x: f.maxX, y: f.maxY))
        }
        if BL > 0 {
            p.addArc(tangent1End: CGPoint(x: f.minX, y: f.maxY), tangent2End: CGPoint(x: f.minX, y: f.maxY - BL), radius: BL)
        } else {
            p.addLine(to: CGPoint(x: f.minX, y: f.maxY))
        }
        if TL > 0 {
            p.addArc(tangent1End: CGPoint(x: f.minX, y: f.minY), tangent2End: CGPoint(x: f.minX + TL, y: f.minY), radius: TL)
        } else {
            p.addLine(to: CGPoint(x: f.minX, y: f.minY + TL))
        }
        p.closeSubpath()
        return p
    }

    /// Closed path through `vertices`, rounding each corner i by `radii[i]`
    /// (0 = sharp). CGPath's tangent-arc constructor only needs the two
    /// edges meeting at a corner, so this works for concave (reentrant)
    /// corners exactly as well as convex ones -- unlike `roundedRectPath`,
    /// which only ever sees convex corners, this is the general case a
    /// notched box's reentrant corners need.
    static func roundedPolygonPath(_ vertices: [CGPoint], radii: [CGFloat]) -> CGPath {
        let n = vertices.count
        guard n >= 3, radii.count == n else {
            let p = CGMutablePath()
            if let first = vertices.first {
                p.move(to: first)
                for v in vertices.dropFirst() { p.addLine(to: v) }
                p.closeSubpath()
            }
            return p
        }
        func edgeLen(_ a: CGPoint, _ b: CGPoint) -> CGFloat { hypot(b.x - a.x, b.y - a.y) }
        func toward(_ a: CGPoint, _ b: CGPoint, _ d: CGFloat) -> CGPoint {
            let len = edgeLen(a, b)
            guard len > 0 else { return a }
            let t = min(max(d, 0), len) / len
            return CGPoint(x: a.x + (b.x - a.x) * t, y: a.y + (b.y - a.y) * t)
        }
        // Clamp each radius to at most half of either adjacent edge, so
        // neighbouring fillets never overlap or overshoot a short edge --
        // the same safety `roundedRectPath` gives a plain rect via `maxR`.
        var r = radii
        for i in 0..<n {
            let prev = vertices[(i - 1 + n) % n], cur = vertices[i], next = vertices[(i + 1) % n]
            let maxR = min(edgeLen(prev, cur), edgeLen(cur, next)) / 2
            r[i] = min(max(radii[i], 0), maxR)
        }
        let p = CGMutablePath()
        p.move(to: toward(vertices[0], vertices[1], r[0]))
        for i in 0..<n {
            let j = (i + 1) % n, k = (i + 2) % n
            let tangent2 = toward(vertices[j], vertices[k], r[j])
            p.addArc(tangent1End: vertices[j], tangent2End: tangent2, radius: r[j])
        }
        p.closeSubpath()
        return p
    }

    /// A rounded rect with a rectangular tab added to the middle of one
    /// edge -- Serge's "sculpt this box around a neighbouring one" bracket
    /// shape (see GTO's mirrored channel brackets around its central
    /// SAMPLE/RUN zone). `edge` is 1/2/3/4 = top/right/bottom/left; `start`
    /// is measured from that edge's leading corner in the direction of
    /// travel (top/right/bottom/left each read left-to-right, top-to-
    /// bottom, right-to-left, bottom-to-top respectively, i.e. clockwise),
    /// `length` is the tab's span along the edge, `depth` how far it
    /// protrudes beyond the edge. `invert` flips the tab to cut INTO the
    /// box instead -- a recess for when the neighbour is the bigger shape
    /// and this box needs to make room for it, rather than reach out to
    /// wrap around it. Degenerates to a plain `roundedRectPath` equivalent
    /// when the edge is out of range or the tab has no size.
    static func notchedBoxPath(_ f: CGRect,
                               tl: CGFloat, tr: CGFloat, br: CGFloat, bl: CGFloat,
                               edge: Int, start: CGFloat, length: CGFloat, depth: CGFloat,
                               notchRadius: CGFloat, invert: Bool = false) -> CGPath {
        let TL = CGPoint(x: f.minX, y: f.minY)
        let TR = CGPoint(x: f.maxX, y: f.minY)
        let BR = CGPoint(x: f.maxX, y: f.maxY)
        let BL = CGPoint(x: f.minX, y: f.maxY)
        let nr = max(0, notchRadius)
        // A protrusion (invert == false) can reach out as far as asked --
        // it only ever adds area outside the box, so it can't self-
        // intersect. A recess (invert == true) removes area from INSIDE
        // the box, so it's capped short of the box's own opposite edge
        // (with a small margin) to keep the polygon simple.
        let crossDim: CGFloat = (edge == 1 || edge == 3) ? f.height : f.width
        let rawDepth = max(0, depth)
        let d = invert ? -min(rawDepth, max(0, crossDim - 2)) : rawDepth

        var vertices: [CGPoint] = [TL, TR, BR, BL]
        var radii: [CGFloat] = [tl, tr, br, bl]

        func clamped(_ edgeLength: CGFloat) -> (CGFloat, CGFloat) {
            let a = max(0, min(start, edgeLength))
            let len = max(0, min(length, edgeLength - a))
            return (a, len)
        }

        switch edge {
        case 1: // top: TL -> TR, left to right, tab points up (-y), or down
                 // into the box when inverted
            let (a, len) = clamped(f.width)
            if len > 0, d != 0 {
                let p1 = CGPoint(x: f.minX + a, y: f.minY)
                let p2 = CGPoint(x: f.minX + a, y: f.minY - d)
                let p3 = CGPoint(x: f.minX + a + len, y: f.minY - d)
                let p4 = CGPoint(x: f.minX + a + len, y: f.minY)
                vertices = [TL, p1, p2, p3, p4, TR, BR, BL]
                radii    = [tl, nr, nr, nr, nr, tr, br, bl]
            }
        case 2: // right: TR -> BR, top to bottom, tab points right (+x), or
                 // left into the box when inverted
            let (a, len) = clamped(f.height)
            if len > 0, d != 0 {
                let p1 = CGPoint(x: f.maxX, y: f.minY + a)
                let p2 = CGPoint(x: f.maxX + d, y: f.minY + a)
                let p3 = CGPoint(x: f.maxX + d, y: f.minY + a + len)
                let p4 = CGPoint(x: f.maxX, y: f.minY + a + len)
                vertices = [TL, TR, p1, p2, p3, p4, BR, BL]
                radii    = [tl, tr, nr, nr, nr, nr, br, bl]
            }
        case 3: // bottom: BR -> BL, right to left, tab points down (+y), or
                 // up into the box when inverted
            let (a, len) = clamped(f.width)
            if len > 0, d != 0 {
                let p1 = CGPoint(x: f.maxX - a, y: f.maxY)
                let p2 = CGPoint(x: f.maxX - a, y: f.maxY + d)
                let p3 = CGPoint(x: f.maxX - a - len, y: f.maxY + d)
                let p4 = CGPoint(x: f.maxX - a - len, y: f.maxY)
                vertices = [TL, TR, BR, p1, p2, p3, p4, BL]
                radii    = [tl, tr, br, nr, nr, nr, nr, bl]
            }
        case 4: // left: BL -> TL, bottom to top, tab points left (-x), or
                 // right into the box when inverted
            let (a, len) = clamped(f.height)
            if len > 0, d != 0 {
                let p1 = CGPoint(x: f.minX, y: f.maxY - a)
                let p2 = CGPoint(x: f.minX - d, y: f.maxY - a)
                let p3 = CGPoint(x: f.minX - d, y: f.maxY - a - len)
                let p4 = CGPoint(x: f.minX, y: f.maxY - a - len)
                vertices = [TL, TR, BR, BL, p1, p2, p3, p4]
                radii    = [tl, tr, br, bl, nr, nr, nr, nr]
            }
        default: break
        }

        return roundedPolygonPath(vertices, radii: radii)
    }

    /// LCARS elbow. Canonical orientation: corner at top-left, horizontal arm
    /// running right along the top, vertical arm running down the left side.
    /// Outer corner radius is derived as thickness + innerRadius (the classic
    /// Okudagram proportion). Flips mirror it into the other three corners.
    static func elbowPath(_ f: CGRect,
                          thickness t: CGFloat,
                          thicknessV tv: CGFloat,
                          innerRi: CGFloat,
                          armH: CGFloat,
                          armV: CGFloat,
                          flipX: Bool,
                          flipY: Bool) -> CGPath {
        // thH/thV independent so the vertical arm can be much wider than
        // the horizontal one. Both fillets stay circular regardless: the
        // outer arc is centered at (ro, ro) -- unrelated to either arm's
        // width, just tangent to the two outer edges -- and the inner arc
        // is centered at (thV + ri, thH + ri), tangent to the two inner
        // edges (x = thV, y = thH). ro is keyed to the THICKER arm so the
        // outer fillet is always at least as large as either arm and the
        // shape never self-intersects.
        let thH = max(2, t)
        let thV = max(2, tv)
        let ri = max(0, min(innerRi, min(thH, thV)))
        let ro = max(thH, thV) + ri
        // armH/armV are total reach INCLUDING the corner bulge (not the
        // straight run beyond it) -- so reach and thickness stop competing
        // for the same scale budget: growing the reach no longer shrinks
        // the rendered thickness the way the old `armH + ro` formula did.
        let W = max(armH, ro)
        let H = max(armV, ro)

        let p = CGMutablePath()
        p.move(to: CGPoint(x: W, y: 0))
        p.addLine(to: CGPoint(x: ro, y: 0))
        p.addArc(center: CGPoint(x: ro, y: ro), radius: ro,
                 startAngle: .pi * 1.5, endAngle: .pi, clockwise: true)   // 270°→180° (short way)
        p.addLine(to: CGPoint(x: 0, y: H))
        p.addLine(to: CGPoint(x: thV, y: H))
        p.addLine(to: CGPoint(x: thV, y: thH + ri))
        p.addArc(center: CGPoint(x: thV + ri, y: thH + ri), radius: ri,
                 startAngle: .pi, endAngle: .pi * 1.5, clockwise: false)  // 180°→270° (short way)
        p.addLine(to: CGPoint(x: W, y: thH))
        p.closeSubpath()

        let sx: CGFloat = (flipX ? -1 : 1) * f.width / W
        let sy: CGFloat = (flipY ? -1 : 1) * f.height / H
        var tr = CGAffineTransform(translationX: f.minX + (flipX ? f.width : 0),
                                   y: f.minY + (flipY ? f.height : 0))
        tr = tr.scaledBy(x: sx, y: sy)
        return p.copy(using: &tr) ?? p
    }

    /// LCARS swirl (double elbow). Built from two elbow corners of the SAME
    /// sense (not mirrored) plus a straight spine between them -- so, unlike
    /// a corner used twice symmetrically (which produces a hook with both
    /// arms on the same side), the two arms end up on opposite sides: the
    /// bottom arm's free end is the shape's leftmost point, the top arm's
    /// free end is its rightmost. Composed from `elbowPath` rather than
    /// hand-derived, so the cove stays identical through both bends -- the
    /// second piece is simply offset horizontally so its tail lands exactly
    /// on the first piece's tail, which is what lets a plain vertical spine
    /// bridge two corners that would otherwise want to be on opposite sides.
    /// Canonical orientation (no flips): comes from the left at the bottom,
    /// goes to the right at the top -- flipX/flipY mirror it as usual.
    static func swirlPath(_ f: CGRect,
                          thickness t: CGFloat,
                          thicknessV tv: CGFloat,
                          innerRi: CGFloat,
                          armH: CGFloat,
                          armH2: CGFloat,
                          armV: CGFloat,
                          flipX: Bool,
                          flipY: Bool) -> CGPath {
        let thH = max(2, t)
        let thV = max(2, tv)
        let ri = max(0, min(innerRi, min(thH, thV)))
        let ro = max(thH, thV) + ri
        // Independent per-piece widths -- unequal armH/armH2 is what shifts
        // the knee (the spine) off-centre rather than leaving it wherever a
        // single shared arm length would put it.
        let armWBottom = max(armH, ro)
        let armWTop = max(armH2, ro)
        let stubH = ro * 2
        // The seam between the two corner pieces -- and the connecting
        // spine below -- is `thV` wide (the vertical-arm thickness), not
        // `thH`: the spine IS the vertical run, continued straight through.
        let W = armWBottom + armWTop - thV

        let p = CGMutablePath()
        // Bottom piece: corner at bottom-right, arm along the bottom
        // pointing left. Its free end (local x = 0) is the shape's leftmost
        // point -- "comes from the left".
        p.addPath(elbowPath(CGRect(x: 0, y: stubH + armV, width: armWBottom, height: stubH),
                            thickness: t, thicknessV: tv, innerRi: innerRi, armH: armH, armV: stubH,
                            flipX: true, flipY: true))
        // Top piece: corner at top-left, arm along the top pointing right.
        // Offset by (armWBottom - thV) so its tail lands exactly on the
        // bottom piece's tail; its free end is the shape's rightmost point
        // -- "goes to the right".
        p.addPath(elbowPath(CGRect(x: armWBottom - thV, y: 0, width: armWTop, height: stubH),
                            thickness: t, thicknessV: tv, innerRi: innerRi, armH: armH2, armV: stubH,
                            flipX: false, flipY: false))
        p.addRect(CGRect(x: armWBottom - thV, y: stubH, width: thV, height: armV))

        let H = stubH * 2 + armV
        let sx: CGFloat = (flipX ? -1 : 1) * f.width / W
        let sy: CGFloat = (flipY ? -1 : 1) * f.height / H
        var tr = CGAffineTransform(translationX: f.minX + (flipX ? f.width : 0),
                                   y: f.minY + (flipY ? f.height : 0))
        tr = tr.scaledBy(x: sx, y: sy)
        return p.copy(using: &tr) ?? p
    }

    /// Annulus arc (ring sector) inscribed in the frame — the big sweeping
    /// curved bands of the TNG aesthetic.
    static func ringSectorPath(_ f: CGRect,
                               thickness: CGFloat,
                               startDeg: CGFloat,
                               sweepDeg: CGFloat) -> CGPath {
        let c = CGPoint(x: f.midX, y: f.midY)
        let R = max(min(f.width, f.height) / 2, 1)
        let r = max(R - max(thickness, 1), 0.5)
        let a0 = Geo.deg2rad(startDeg)
        let a1 = Geo.deg2rad(startDeg + sweepDeg)
        let cw = sweepDeg < 0
        let p = CGMutablePath()
        p.move(to: CGPoint(x: c.x + R * cos(a0), y: c.y + R * sin(a0)))
        p.addArc(center: c, radius: R, startAngle: a0, endAngle: a1, clockwise: cw)
        p.addLine(to: CGPoint(x: c.x + r * cos(a1), y: c.y + r * sin(a1)))
        p.addArc(center: c, radius: r, startAngle: a1, endAngle: a0, clockwise: !cw)
        p.closeSubpath()
        return p
    }

    // MARK: Element → parts

    static func parts(for el: PanelElement) -> [ShapePart] {
        let f = el.frame
        let accent = el.fill
        let ink = ColorSpec.hex("#101216")
        let nearBlack = ColorSpec.hex("#050507")

        switch el.kind {

        case .jack:
            let ringW = max(1.4, f.width * 0.08)
            let face = f.insetBy(dx: f.width * 0.17, dy: f.height * 0.17)
            let holeR = f.width * 0.20
            let hole = CGRect(x: f.midX - holeR, y: f.midY - holeR, width: holeR * 2, height: holeR * 2)
            return [
                ShapePart(path: ellipsePath(f), fill: ink, stroke: accent, lineWidth: ringW),
                ShapePart(path: ellipsePath(face), fill: accent.darkened(0.62)),
                ShapePart(path: ellipsePath(hole), fill: nearBlack),
            ]

        case .knobLarge, .knobMedium, .knobSmall:
            var out: [ShapePart] = []

            // Position ring. The track is an open circle with its gap at the
            // bottom — the same ring-sector geometry the shape palette already
            // provides — and the value is a second sector drawn over it from
            // the track's start to the pointer.
            let style = Int(el.params.knobStyle.rounded())
            let showArc = style >= 1
            let showPointer = style != 1
            var seat = f
            if showArc {
                let track = max(1.5, el.params.arcWidth * min(f.width, f.height))
                let gap = max(1.0, f.width * 0.05)
                let span = min(max(el.params.arcSpan, 20), 350)
                let start = -90 - span / 2

                // Fold the stored angle into ±180 so 300° reads as −60° rather
                // than running off the end of the track.
                var rel = el.params.pointerAngle.truncatingRemainder(dividingBy: 360)
                if rel > 180 { rel -= 360 }
                if rel < -180 { rel += 360 }
                let sweep = min(max(rel + span / 2, 0), span)

                out.append(ShapePart(
                    path: ringSectorPath(f, thickness: track, startDeg: start, sweepDeg: span),
                    fill: accent.darkened(0.74)))
                if sweep > 0.5 {
                    out.append(ShapePart(
                        path: ringSectorPath(f, thickness: track, startDeg: start, sweepDeg: sweep),
                        fill: accent))
                }
                seat = f.insetBy(dx: track + gap, dy: track + gap)
            }

            let ringW = max(1.4, seat.width * 0.07)
            let body = seat.insetBy(dx: seat.width * 0.15, dy: seat.height * 0.15)
            let a = Geo.deg2rad(el.params.pointerAngle - 90)
            let r = body.width / 2
            let c = CGPoint(x: body.midX, y: body.midY)
            let p = CGMutablePath()
            p.move(to: CGPoint(x: c.x + cos(a) * r * 0.12, y: c.y + sin(a) * r * 0.12))
            p.addLine(to: CGPoint(x: c.x + cos(a) * r * 0.62, y: c.y + sin(a) * r * 0.62))
            let capR = body.width * 0.11
            let cap = CGRect(x: c.x - capR, y: c.y - capR, width: capR * 2, height: capR * 2)

            out.append(ShapePart(path: ellipsePath(seat), fill: accent.darkened(0.75),
                                 stroke: accent, lineWidth: ringW))
            out.append(ShapePart(path: ellipsePath(body), fill: accent.darkened(0.42)))
            if showPointer {
                out.append(ShapePart(path: p, stroke: accent.lightened(0.55),
                                     lineWidth: max(1.4, seat.width * 0.05), rotates: true))
            }
            out.append(ShapePart(path: ellipsePath(cap), fill: accent.lightened(0.30), rotates: true))
            return out

        case .faderVertical:
            let trackW = min(7, f.width * 0.45)
            let track = CGRect(x: f.midX - trackW / 2, y: f.minY + f.height * 0.05,
                               width: trackW, height: f.height * 0.9)
            let hh = max(9, f.height * 0.14)
            let hy = f.maxY - hh - el.params.value * (f.height - hh)
            let handle = CGRect(x: f.minX + 1, y: hy, width: f.width - 2, height: hh)
            let groove = CGRect(x: handle.midX - handle.width * 0.32, y: handle.midY - 0.8,
                                width: handle.width * 0.64, height: 1.6)
            return [
                ShapePart(path: roundedRectPath(track, tl: trackW/2, tr: trackW/2, br: trackW/2, bl: trackW/2),
                          fill: ColorSpec.hex("#0B0C10"), stroke: ColorSpec.hex("#30333B"), lineWidth: 1),
                ShapePart(path: roundedRectPath(handle, tl: 2.5, tr: 2.5, br: 2.5, bl: 2.5),
                          fill: accent, stroke: ColorSpec.hex("#000000"), lineWidth: 1),
                ShapePart(path: roundedRectPath(groove, tl: 0.8, tr: 0.8, br: 0.8, bl: 0.8),
                          fill: ColorSpec.hex("#111318")),
            ]

        case .faderHorizontal:
            let trackH = min(7, f.height * 0.45)
            let track = CGRect(x: f.minX + f.width * 0.05, y: f.midY - trackH / 2,
                               width: f.width * 0.9, height: trackH)
            let hw = max(9, f.width * 0.14)
            let hx = f.minX + el.params.value * (f.width - hw)
            let handle = CGRect(x: hx, y: f.minY + 1, width: hw, height: f.height - 2)
            let groove = CGRect(x: handle.midX - 0.8, y: handle.midY - handle.height * 0.32,
                                width: 1.6, height: handle.height * 0.64)
            return [
                ShapePart(path: roundedRectPath(track, tl: trackH/2, tr: trackH/2, br: trackH/2, bl: trackH/2),
                          fill: ColorSpec.hex("#0B0C10"), stroke: ColorSpec.hex("#30333B"), lineWidth: 1),
                ShapePart(path: roundedRectPath(handle, tl: 2.5, tr: 2.5, br: 2.5, bl: 2.5),
                          fill: accent, stroke: ColorSpec.hex("#000000"), lineWidth: 1),
                ShapePart(path: roundedRectPath(groove, tl: 0.8, tr: 0.8, br: 0.8, bl: 0.8),
                          fill: ColorSpec.hex("#111318")),
            ]

        case .pushButton:
            // Value drives the pressed state, the same way it selects a button
            // group's position: a button exports as two frames and Rack swaps
            // them, so the artwork has to be able to draw both.
            let down = el.params.value >= 0.5
            let cap = f.insetBy(dx: f.width * (down ? 0.24 : 0.18),
                                dy: f.height * (down ? 0.24 : 0.18))
            var ps: [ShapePart] = [
                ShapePart(path: roundedRectPath(f, tl: 2, tr: 2, br: 2, bl: 2),
                          fill: el.fill.darkened(0.6), stroke: ColorSpec.hex("#0B0C10")),
                ShapePart(path: roundedRectPath(cap, tl: 1.5, tr: 1.5, br: 1.5, bl: 1.5),
                          fill: down ? el.fill.lightened(0.18) : el.fill),
            ]
            if !down {
                // The glint is what a raised cap looks like; a pressed one has
                // no highlight to catch.
                ps.append(ShapePart(path: roundedRectPath(
                    CGRect(x: cap.minX + cap.width * 0.2, y: cap.minY + cap.height * 0.14,
                           width: cap.width * 0.6, height: cap.height * 0.3),
                    tl: 1, tr: 1, br: 1, bl: 1), fill: el.fill.lightened(0.35)))
            }
            return ps
        case .buttonGroup:
            let n = max(2, min(12, Int(el.params.segments.rounded())))
            // Radius and end-cap insets hug the frame, so the art stays inside
            // the selection outline. Note: the cross layout is always 4 caps.
            let r: CGFloat
            switch Int(el.params.layout) {
            case 1:   r = min(f.height / 2 - 1.5, f.width / CGFloat(2 * n) - 1)      // row
            case 2,3: r = min(f.width, f.height) * 0.16 + 2.5                        // cross / ring
            default:  r = min(f.width / 2 - 1.5, f.height / CGFloat(2 * n) - 1.5)    // column
            }
            let c = CGPoint(x: f.midX, y: f.midY)
            let positions: [CGPoint]
            switch Int(el.params.layout) {
            case 1:
                let span = max(f.width - r * 2, 0)
                positions = (0..<n).map {
                    CGPoint(x: f.minX + r + span * CGFloat($0) / CGFloat(n - 1), y: c.y)
                }
            case 2:
                positions = [CGPoint(x: c.x, y: f.minY + r + 2), CGPoint(x: c.x, y: f.maxY - r - 2),
                             CGPoint(x: f.minX + r + 2, y: c.y), CGPoint(x: f.maxX - r - 2, y: c.y)]
            case 3:
                positions = (0..<n).map { i in
                    let a = CGFloat(i) / CGFloat(n) * 2 * .pi - .pi / 2
                    let rad = min(f.width, f.height) / 2 - r - 2
                    return CGPoint(x: c.x + rad * cos(a), y: c.y + rad * sin(a))
                }
            default:
                let span = max(f.height - r * 2, 0)
                positions = (0..<n).map {
                    CGPoint(x: c.x, y: f.minY + r + span * CGFloat($0) / CGFloat(n - 1))
                }
            }
            // Which position is on. A switch is exported as one SVG per
            // position — Rack's SvgSwitch picks the frame by parameter value —
            // so the artwork has to be able to draw any of them, and Value is
            // what selects it here and in the inspector.
            let selected = Int((el.params.value * CGFloat(n - 1)).rounded())

            var gs: [ShapePart] = []
            for (index, p) in positions.enumerated() {
                let on = index == selected
                let outer = CGRect(x: p.x - r, y: p.y - r, width: r * 2, height: r * 2)
                let capR = r * 0.74
                let cap = CGRect(x: p.x - capR, y: p.y - capR, width: capR * 2, height: capR * 2)
                let glint = CGRect(x: p.x - r * 0.34, y: p.y - r * 0.5, width: r * 0.68, height: r * 0.52)
                gs.append(ShapePart(path: CGPath(ellipseIn: outer, transform: nil),
                                    fill: el.fill.darkened(0.55), stroke: ColorSpec.hex("#0B0C10")))
                gs.append(ShapePart(path: CGPath(ellipseIn: cap, transform: nil),
                                    fill: on ? el.fill : el.fill.darkened(0.42)))
                if on {
                    gs.append(ShapePart(path: CGPath(ellipseIn: glint, transform: nil),
                                        fill: el.fill.lightened(0.35)))
                }
            }
            return gs
        case .led:
            // Dome-shaped lens: a dark bezel (shares the jack body's
            // "ink" tone) holds a lens that fills most of the frame,
            // with an offset highlight/shadow pair faking curvature --
            // this renderer has no gradient primitive, so "dome" is
            // three flat circles, not a radial fill.
            var halo = accent; halo.a = 0.35
            let haloW = max(1.0, f.width * 0.06)
            let bezel = f.insetBy(dx: f.width * 0.06, dy: f.height * 0.06)
            let lens = f.insetBy(dx: f.width * 0.16, dy: f.height * 0.16)
            let lensR = lens.width / 2
            let hlOffset = lensR * 0.32
            let highlightR = lensR * 0.5
            let highlight = CGRect(x: lens.midX - hlOffset - highlightR, y: lens.midY - hlOffset - highlightR,
                                   width: highlightR * 2, height: highlightR * 2)
            let shadowR = lensR * 0.85
            let shadowOffset = hlOffset * 0.6
            let shadow = CGRect(x: lens.midX + shadowOffset - shadowR, y: lens.midY + shadowOffset - shadowR,
                                width: shadowR * 2, height: shadowR * 2)
            return [
                ShapePart(path: ellipsePath(f), fill: nil, stroke: halo, lineWidth: haloW),
                ShapePart(path: ellipsePath(bezel), fill: nearBlack),
                ShapePart(path: ellipsePath(lens), fill: accent),
                ShapePart(path: ellipsePath(shadow), fill: accent.darkened(0.28)),
                ShapePart(path: ellipsePath(highlight), fill: accent.lightened(0.55)),
            ]

        case .screw:
            let slot = CGMutablePath()
            slot.move(to: CGPoint(x: f.minX + f.width * 0.26, y: f.minY + f.height * 0.26))
            slot.addLine(to: CGPoint(x: f.maxX - f.width * 0.26, y: f.maxY - f.height * 0.26))
            return [
                ShapePart(path: ellipsePath(f), fill: accent,
                          stroke: ColorSpec.hex("#4A4F58"), lineWidth: 1),
                ShapePart(path: slot, stroke: ColorSpec.hex("#33373E"),
                          lineWidth: max(1.3, f.width * 0.10)),
            ]

        case .box:
            let notchEdge = Int(el.params.notchEdge.rounded())
            let boxPath: CGPath
            if notchEdge >= 1, notchEdge <= 4, el.params.notchLength > 0, el.params.notchDepth > 0 {
                boxPath = notchedBoxPath(f,
                                         tl: el.params.cornerTL, tr: el.params.cornerTR,
                                         br: el.params.cornerBR, bl: el.params.cornerBL,
                                         edge: notchEdge, start: el.params.notchStart,
                                         length: el.params.notchLength, depth: el.params.notchDepth,
                                         notchRadius: el.params.notchRadius, invert: el.params.notchInvert)
            } else {
                boxPath = roundedRectPath(f,
                                          tl: el.params.cornerTL, tr: el.params.cornerTR,
                                          br: el.params.cornerBR, bl: el.params.cornerBL)
            }
            return [ShapePart(path: boxPath, fill: accent, stroke: el.stroke, lineWidth: el.strokeWidth)]

        case .ellipse:
            return [ShapePart(path: ellipsePath(f), fill: accent,
                              stroke: el.stroke, lineWidth: el.strokeWidth)]

        case .triangle:
            let p = CGMutablePath()
            p.move(to: CGPoint(x: f.midX, y: f.minY))
            p.addLine(to: CGPoint(x: f.maxX, y: f.maxY))
            p.addLine(to: CGPoint(x: f.minX, y: f.maxY))
            p.closeSubpath()
            return [ShapePart(path: p, fill: accent, stroke: el.stroke, lineWidth: el.strokeWidth)]

        case .line:
            // Stroke only -- a line has no area, so fill never applies here
            // regardless of what the element's own fill colour happens to be.
            return [ShapePart(path: linePath(f, bow: el.params.lineBow),
                              fill: nil, stroke: el.stroke, lineWidth: max(0.25, el.strokeWidth))]

        case .elbow:
            return [ShapePart(
                path: elbowPath(f,
                                thickness: el.params.thickness,
                                thicknessV: el.params.thicknessV,
                                innerRi: el.params.innerRadius,
                                armH: el.params.armH,
                                armV: el.params.armV,
                                flipX: el.params.flipX,
                                flipY: el.params.flipY),
                fill: accent, stroke: el.stroke, lineWidth: el.strokeWidth)]

        case .swirl:
            return [ShapePart(
                path: swirlPath(f,
                                thickness: el.params.thickness,
                                thicknessV: el.params.thicknessV,
                                innerRi: el.params.innerRadius,
                                armH: el.params.armH,
                                armH2: el.params.armH2,
                                armV: el.params.armV,
                                flipX: el.params.flipX,
                                flipY: el.params.flipY),
                fill: accent, stroke: el.stroke, lineWidth: el.strokeWidth)]

        case .ringSector:
            return [ShapePart(
                path: ringSectorPath(f,
                                     thickness: el.params.thickness,
                                     startDeg: el.params.startAngle,
                                     sweepDeg: el.params.sweepAngle),
                fill: accent, stroke: el.stroke, lineWidth: el.strokeWidth)]

        case .symbol:
            return [ShapePart(path: SymbolCatalogue.path(for: el), fill: accent,
                              stroke: el.stroke, lineWidth: el.strokeWidth)]

        case .path:
            return importedParts(for: el)

        case .text:
            return textParts(for: el)
        }
    }

    // MARK: Imported paths

    /// Parsed `d` strings, keyed by the string itself. An imported panel is a
    /// few hundred paths and the canvas redraws on every mouse move; re-parsing
    /// all of them per frame is the difference between usable and not.
    private static var importCache: [String: CGPath] = [:]

    /// An imported path, scaled from its unit box into the element's frame.
    /// That is what makes dragging a corner resize the artwork rather than
    /// crop it.
    static func importedParts(for el: PanelElement) -> [ShapePart] {
        guard let d = el.pathData, !d.isEmpty else { return [] }
        let unit: CGPath
        if let hit = importCache[d] {
            unit = hit
        } else {
            guard let parsed = SVGPath.path(fromD: d) else { return [] }
            if importCache.count > 2048 { importCache.removeAll() }
            importCache[d] = parsed
            unit = parsed
        }
        let f = el.frame
        var t = CGAffineTransform(scaleX: max(f.width, 0.01), y: max(f.height, 0.01))
            .concatenating(CGAffineTransform(translationX: f.minX, y: f.minY))
        guard let placed = unit.copy(using: &t) else { return [] }
        return [ShapePart(path: placed, fill: el.fill,
                          stroke: el.stroke, lineWidth: el.strokeWidth)]
    }

    /// Splits a knob's parts into the static body and the part Rack rotates,
    /// mirroring `RoundKnob`: a background `SvgWidget` added below the
    /// TransformWidget, with only the foreground turning.
    ///
    /// Split on each part's own `rotates` flag rather than on part ordering,
    /// so a knob can gain or lose pieces — a position ring, no pointer —
    /// without the export quietly rotating the wrong thing.
    ///
    /// The value arc deliberately lands in the background: Rack turns one SVG
    /// over a static one, and an arc that *grows* cannot be produced by
    /// rotation. CodeGen warns when a custom knob relies on it.
    static func knobLayers(_ parts: [ShapePart]) -> (bg: [ShapePart], fg: [ShapePart])? {
        let fg = parts.filter { $0.rotates }
        guard !fg.isEmpty else { return nil }
        return (parts.filter { !$0.rotates }, fg)
    }

    // MARK: Text → outlines
    //
    // Labels become real glyph outlines rather than an SVG <text> element:
    // VCV Rack renders panels through nanosvg, which has no text support and
    // drops <text> silently — every label would vanish on load. Outlines also
    // put text on the same ShapePart path as everything else, so canvas, PNG
    // and SVG stay identical by construction instead of by coincidence.

    private struct TextKey: Hashable {
        let text: String
        let size: CGFloat
        let bold: Bool
    }

    /// Glyph outlines laid out with the baseline at the origin, already
    /// mirrored into the panel's y-down space.
    private struct TextOutline {
        let path: CGPath
        let advance: CGFloat
        let capHeight: CGFloat
    }

    /// Keyed on text/size/weight only — never on the frame — so dragging a
    /// label does not grow the cache. Main-thread only, like the rest of the
    /// drawing code.
    private static var outlineCache: [TextKey: TextOutline] = [:]

    /// Size a text element's own drawing wants: the advance of the laid-out
    /// line by its cap height, padded so the frame stays grabbable. Needed when
    /// a label is created in code and has no frame to inherit — the glyph run,
    /// not the string length, is what decides the width.
    static func textSize(for el: PanelElement) -> CGSize {
        guard let o = outline(for: el) else {
            return CGSize(width: max(8, el.params.fontSize * 2),
                          height: max(8, el.params.fontSize * 1.4))
        }
        return CGSize(width: max(8, o.advance + el.params.fontSize * 0.3),
                      height: max(8, o.capHeight * 1.5))
    }

    static func textParts(for el: PanelElement) -> [ShapePart] {
        guard let o = outline(for: el) else { return [] }
        // Centre the cap-height box in the frame: visually centred for the
        // all-caps labels these panels are actually made of.
        var t = CGAffineTransform(translationX: el.frame.midX - o.advance / 2,
                                  y: el.frame.midY + o.capHeight / 2)
        guard let placed = o.path.copy(using: &t) else { return [] }
        return [ShapePart(path: placed, fill: el.fill)]
    }

    /// A text element is a sequence of literal runs and glyph tokens. `{ka}`
    /// anywhere in the string places the Ka glyph inline, sized to cap height
    /// so it sits on the baseline with the Latin characters around it.
    private enum TextSegment {
        case literal(String)
        case glyph(String)      // a SymbolCatalogue id in the .glyph category
    }

    private static func segments(of text: String) -> [TextSegment] {
        var out: [TextSegment] = []
        var literal = ""
        var i = text.startIndex

        while i < text.endIndex {
            if text[i] == "{", let close = text[i...].firstIndex(of: "}") {
                let name = String(text[text.index(after: i)..<close]).lowercased()
                if let spec = SymbolCatalogue.all.first(where: {
                    $0.category == .glyph && $0.id.lowercased() == "glyph" + name
                }) {
                    if !literal.isEmpty { out.append(.literal(literal)); literal = "" }
                    out.append(.glyph(spec.id))
                    i = text.index(after: close)
                    continue
                }
                // Not a glyph name — leave the brace alone rather than eating it.
            }
            literal.append(text[i])
            i = text.index(after: i)
        }
        if !literal.isEmpty { out.append(.literal(literal)) }
        return out
    }

    /// One glyph as a filled ribbon in a `side` × `side` box, top-left at the
    /// origin. Same construction as a Symbol element, so a glyph typed into a
    /// label and one dropped from the palette are the same shape.
    private static func glyphOutline(_ id: String, side: CGFloat) -> CGPath? {
        guard side > 1 else { return nil }
        let weight = SymbolCatalogue.defaultWeight
        let inset = weight / 2
        let box = CGRect(x: inset, y: inset, width: 1 - inset * 2, height: 1 - inset * 2)
        let spec = SymbolCatalogue.spec(id)
        let unit = spec.centreline(SymbolContext(box: box, p: spec.defaults))

        var scale = CGAffineTransform(scaleX: side, y: side)
        guard let scaled = unit.copy(using: &scale) else { return nil }
        let px = max(SymbolCatalogue.minWeightPixels, weight * side)
        return scaled.copy(strokingWithWidth: px, lineCap: .round, lineJoin: .round, miterLimit: 4)
    }

    /// Outlines for one literal run, baseline at the origin, y-down.
    private static func literalOutline(_ text: String, font nsFont: NSFont) -> (CGPath, CGFloat) {
        let ctFont = nsFont as CTFont
        let line = CTLineCreateWithAttributedString(
            NSAttributedString(string: text, attributes: [.font: nsFont]))
        let advance = CGFloat(CTLineGetTypographicBounds(line, nil, nil, nil))

        let out = CGMutablePath()
        for run in (CTLineGetGlyphRuns(line) as? [CTRun] ?? []) {
            // A run can carry a substituted font (accents, symbols); fall back
            // to ours rather than dropping the glyph.
            let attrs = CTRunGetAttributes(run) as NSDictionary
            let runFont = (attrs[kCTFontAttributeName as String] as? NSFont)
                .map { $0 as CTFont } ?? ctFont

            let n = CTRunGetGlyphCount(run)
            guard n > 0 else { continue }
            var glyphs = [CGGlyph](repeating: 0, count: n)
            var pos = [CGPoint](repeating: .zero, count: n)
            CTRunGetGlyphs(run, CFRangeMake(0, n), &glyphs)
            CTRunGetPositions(run, CFRangeMake(0, n), &pos)

            for i in 0..<n {
                guard let g = CTFontCreatePathForGlyph(runFont, glyphs[i], nil) else { continue }
                // Glyph outlines are y-up with the origin on the baseline; the
                // panel is y-down, so mirror each glyph as it is placed.
                var t = CGAffineTransform(translationX: pos[i].x, y: -pos[i].y)
                t = t.scaledBy(x: 1, y: -1)
                out.addPath(g, transform: t)
            }
        }
        return (out, advance)
    }

    private static func outline(for el: PanelElement) -> TextOutline? {
        let key = TextKey(text: el.params.text,
                          size: max(4, el.params.fontSize),
                          bold: el.params.bold)
        guard !key.text.isEmpty else { return nil }
        if let hit = outlineCache[key] { return hit }

        let nsFont = NSFont.systemFont(ofSize: key.size, weight: key.bold ? .semibold : .regular)
        let capHeight = CTFontGetCapHeight(nsFont as CTFont)

        let out = CGMutablePath()
        var x: CGFloat = 0
        for segment in segments(of: key.text) {
            switch segment {
            case .literal(let run):
                let (path, advance) = literalOutline(run, font: nsFont)
                var t = CGAffineTransform(translationX: x, y: 0)
                if let placed = path.copy(using: &t) { out.addPath(placed) }
                x += advance

            case .glyph(let id):
                // Square, cap height, sitting on the baseline: y = -capHeight is
                // the top of the box in the panel's y-down space.
                if let g = glyphOutline(id, side: capHeight) {
                    var t = CGAffineTransform(translationX: x, y: -capHeight)
                    if let placed = g.copy(using: &t) { out.addPath(placed) }
                }
                x += capHeight * 1.14   // the glyph plus a little tracking
            }
        }

        let result = TextOutline(path: out, advance: x, capHeight: capHeight)
        if outlineCache.count > 512 { outlineCache.removeAll() }
        outlineCache[key] = result
        return result
    }

    // MARK: Drawing

    static func drawBackground(_ doc: PanelDocument, in ctx: CGContext, variant: ThemeVariant = .dark) {
        ctx.setFillColor(doc.paper(for: variant).nsColor.cgColor)
        ctx.fill(CGRect(origin: .zero, size: doc.pixelSize))
    }

    static func applyRotation(_ el: PanelElement, _ ctx: CGContext) {
        guard el.rotation != 0 else { return }
        let c = el.center
        ctx.translateBy(x: c.x, y: c.y)
        ctx.rotate(by: Geo.deg2rad(el.rotation))
        ctx.translateBy(x: -c.x, y: -c.y)
    }

    /// `doc`/`variant` are only consulted for an element with `followsInk`
    /// set -- everything else draws in its own literal `fill`, exactly as
    /// before this parameter existed. Passing no `doc` (every call site that
    /// predates theming) is therefore a no-op: `followsInk` elements simply
    /// keep whatever colour their `fill` already holds.
    static func draw(_ el: PanelElement, in ctx: CGContext, doc: PanelDocument? = nil, variant: ThemeVariant = .dark) {
        ctx.saveGState()
        applyRotation(el, ctx)
        let el = doc?.resolved(el, for: variant) ?? el
        // No special case for text any more — it is outlines like everything else.
        for part in parts(for: el) {
            if let fl = part.fill {
                ctx.saveGState()
                ctx.addPath(part.path)
                ctx.setFillColor(fl.nsColor.cgColor)
                ctx.fillPath()
                ctx.restoreGState()
            }
            if let st = part.stroke {
                ctx.saveGState()
                ctx.addPath(part.path)
                ctx.setStrokeColor(st.nsColor.cgColor)
                ctx.setLineWidth(part.lineWidth)
                ctx.strokePath()
                ctx.restoreGState()
            }
        }
        ctx.restoreGState()
    }
}

// MARK: - Stamps that need measuring

extension StampLibrary.Stamp {
    /// A text element saved with a zero-size frame means "measure me here".
    ///
    /// A stamp that ships with the app cannot know the text metrics of the
    /// machine it will be drawn on — the same string is a different width in a
    /// different system font — so the wordmark is stored as text plus a size
    /// and given its box on arrival. Nothing the person saves themselves is
    /// affected: `save` always records a real frame.
    var resolved: StampLibrary.Stamp {
        guard elements.contains(where: { $0.kind == .text && ($0.w <= 0 || $0.h <= 0) }) else {
            return self
        }
        var out = self
        for i in out.elements.indices where out.elements[i].kind == .text {
            guard out.elements[i].w <= 0 || out.elements[i].h <= 0 else { continue }
            let size = Renderer.textSize(for: out.elements[i])
            out.elements[i].w = size.width
            out.elements[i].h = size.height
        }
        return out
    }
}
