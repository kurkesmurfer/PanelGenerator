import Foundation
import CoreGraphics

/// Snapping to other elements — smart guides. The edges and centres of every
/// other visible element (and of the panel) are candidate lines; a dragged
/// selection, a resized edge or a pen point that comes within the threshold
/// of one locks to it, per axis, ahead of the grid.
package struct GuideSnap {
    /// Correction to apply on each axis, nil where nothing was in reach.
    package var dx: CGFloat?
    package var dy: CGFloat?
    /// The lines that caught, for drawing.
    package var xs: [CGFloat] = []
    package var ys: [CGFloat] = []

    package init() {}
}

extension PanelDocument {

    /// Candidate lines: left/centre/right and top/middle/bottom of every
    /// visible, non-template element not in `excluding`, plus the panel's
    /// edges and centre lines.
    package func guideLines(excluding: Set<UUID>) -> (xs: [CGFloat], ys: [CGFloat]) {
        let size = pixelSize
        var xs: [CGFloat] = [0, size.width / 2, size.width]
        var ys: [CGFloat] = [0, size.height / 2, size.height]
        for e in elements where !excluding.contains(e.id) && e.isHidden != true && e.isTemplate != true {
            let f = rotation(of: e)
            xs += [f.minX, f.midX, f.maxX]
            ys += [f.minY, f.midY, f.maxY]
        }
        return (xs, ys)
    }

    /// Axis-aligned bounds, honouring rotation.
    private func rotation(of e: PanelElement) -> CGRect {
        guard e.rotation != 0 else { return e.frame }
        let t = CGAffineTransform(translationX: e.center.x, y: e.center.y)
            .rotated(by: e.rotation * .pi / 180)
            .translatedBy(x: -e.center.x, y: -e.center.y)
        return e.frame.applying(t)
    }

    /// Best correction for points `probesX`/`probesY` (e.g. a rectangle's
    /// left, centre and right) against the candidate lines, within
    /// `threshold`. Ties go to the smallest correction.
    package static func guideSnap(probesX: [CGFloat], probesY: [CGFloat],
                                  lines: (xs: [CGFloat], ys: [CGFloat]), threshold: CGFloat) -> GuideSnap {
        func best(_ probes: [CGFloat], _ cands: [CGFloat]) -> (CGFloat, [CGFloat])? {
            var bestD: CGFloat?
            for p in probes {
                for c in cands where abs(c - p) <= threshold {
                    if bestD == nil || abs(c - p) < abs(bestD!) - 1e-9 { bestD = c - p }
                }
            }
            guard let d = bestD else { return nil }
            // Every line the corrected probes now sit on, so the drawing
            // shows "aligned with both of these".
            let hits = Set(cands.filter { c in probes.contains { abs(c - ($0 + d)) < 0.01 } }.map {
                ($0 * 100).rounded() / 100 })
            return (d, hits.sorted())
        }
        var g = GuideSnap()
        if let (d, xs) = best(probesX, lines.xs) { g.dx = d; g.xs = xs }
        if let (d, ys) = best(probesY, lines.ys) { g.dy = d; g.ys = ys }
        return g
    }

    /// A rectangle (the moving selection's bounds) against everything else.
    package func guideSnap(rect r: CGRect, excluding: Set<UUID>, threshold: CGFloat) -> GuideSnap {
        Self.guideSnap(probesX: [r.minX, r.midX, r.maxX], probesY: [r.minY, r.midY, r.maxY],
                       lines: guideLines(excluding: excluding), threshold: threshold)
    }

    /// A single point (a pen node, a dragged edge).
    package func guideSnap(point p: CGPoint, excluding: Set<UUID> = [], threshold: CGFloat) -> GuideSnap {
        Self.guideSnap(probesX: [p.x], probesY: [p.y], lines: guideLines(excluding: excluding), threshold: threshold)
    }
}
