import Foundation
import AppKit
import CoreGraphics
import CoreText

// LCARS geometry: the elbow and the swirl built from two of its corners.

extension Renderer {

    // MARK: LCARS elbow and swirl

    /// LCARS elbow. Canonical orientation: corner at top-left, horizontal arm
    /// running right along the top, vertical arm running down the left side.
    /// Outer corner radius is derived as thickness + innerRadius (the classic
    /// Okudagram proportion). Flips mirror it into the other three corners.
    package static func elbowPath(_ f: CGRect,
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
    package static func swirlPath(_ f: CGRect,
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
}
