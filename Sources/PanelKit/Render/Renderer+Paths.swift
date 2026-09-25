import Foundation
import AppKit
import CoreGraphics
import CoreText

// Parametric path builders shared by every design language.

extension Renderer {

    // MARK: Path builders

    package static func ellipsePath(_ r: CGRect) -> CGPath {
        CGPath(ellipseIn: r, transform: nil)
    }

    /// A `.line` element's path: a straight or gently bowed run down the
    /// frame's vertical centre-line, top-mid to bottom-mid (rotate the
    /// element for a horizontal or diagonal run). `bow` offsets the curve's
    /// control point sideways from the straight midpoint -- 0 is dead
    /// straight; Serge's own hardware often bows this kind of connector
    /// slightly around whatever sits between a knob and its jack.
    package static func linePath(_ f: CGRect, bow: CGFloat) -> CGPath {
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

    package static func roundedRectPath(_ f: CGRect,
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
    package static func roundedPolygonPath(_ vertices: [CGPoint], radii: [CGFloat]) -> CGPath {
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
    package static func notchedBoxPath(_ f: CGRect,
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


    /// Annulus arc (ring sector) inscribed in the frame — the big sweeping
    /// curved bands of the TNG aesthetic.
    package static func ringSectorPath(_ f: CGRect,
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
}
