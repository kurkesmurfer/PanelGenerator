import Foundation
import CoreGraphics

// MARK: - Serge-style non-uniform snap grid

/// Serge modules place components on a fixed, non-uniform grid: 5 main
/// rows across a 3U panel at fixed mm positions (not evenly derived from
/// panel height), plus up to 4 "half rows" inserted between consecutive
/// main rows as component density demands. A half row carries "half-lane"
/// columns offset by half the main column pitch, so a half-row position
/// sits on the diagonal cross between the four surrounding main-grid
/// points. By Serge convention these in-between spots are reserved for
/// LEDs/switches (and jacks under pressure) -- never knobs; PanelGenerator
/// doesn't enforce that rule, it only offers the positions.
///
/// Row values and the 42 HP / 10-column pitch come from the Serge panel
/// style guide (~/Development/Serge/docs/Panel-language.md), cross-checked
/// against DUSG-spec.md's "five canonical lanes" and a real built module's
/// coordinates.
package enum SergeGrid {
    /// The 5 canonical row centre-lines for a 3U panel, in millimetres,
    /// top to bottom. These are fixed reference values, not `height3U / 5`.
    package static let mainRowsMM: [CGFloat] = [27.2, 48.2, 69.2, 90.2, 111.2]

    /// 42 HP spans exactly 10 main column positions -> 63 px (21.34 mm) pitch.
    package static let columnPitchPx: CGFloat = 42 * PanelMetrics.pixelsPerHP / 10

    package static var mainRowsPx: [CGFloat] {
        mainRowsMM.map { $0 / PanelMetrics.mmPerPixel }
    }

    /// Half rows sit at the arithmetic midpoint between each pair of
    /// consecutive main rows. Serge inserts these one at a time, top to
    /// bottom, as density requires; PanelGenerator offers all four as snap
    /// targets at once rather than tracking a density heuristic.
    package static var halfRowsPx: [CGFloat] {
        let rows = mainRowsPx
        guard rows.count > 1 else { return [] }
        return (0..<rows.count - 1).map { (rows[$0] + rows[$0 + 1]) / 2 }
    }

    /// Row-to-row half-step spacing (10.5 mm on Serge's grid), derived from
    /// the main row pitch rather than hard-coded.
    private static var halfStepPx: CGFloat {
        let rows = mainRowsPx
        guard rows.count > 1 else { return 0 }
        return (rows[1] - rows[0]) / 2
    }

    /// The interior half rows, plus -- when `includingOuter` is set from
    /// `PanelDocument.sergeGridOuterHalfSteps` -- one further row at the same
    /// half-step pitch beyond the topmost and bottommost main rows.
    package static func halfRowsPx(includingOuter: Bool) -> [CGFloat] {
        let interior = halfRowsPx
        guard includingOuter, let first = mainRowsPx.first, let last = mainRowsPx.last else {
            return interior
        }
        let step = halfStepPx
        guard step > 0 else { return interior }
        return [first - step] + interior + [last + step]
    }

    package struct Lines {
        package var mainRows: [CGFloat] = []
        package var halfRows: [CGFloat] = []
        package var mainCols: [CGFloat] = []
        package var halfCols: [CGFloat] = []
    }

    /// Builds the grid line set for a document. Rows only apply to 3U
    /// panels (Serge's row grid is a 3U convention); columns are derived
    /// from panel width and offered for any format.
    package static func lines(for doc: PanelDocument) -> Lines {
        var l = Lines()
        if doc.format == .u3 {
            l.mainRows = mainRowsPx
            l.halfRows = halfRowsPx(includingOuter: doc.sergeGridOuterHalfSteps)
        }
        let width = PanelMetrics.size(hp: doc.widthHP, format: doc.format).width
        let pitch = columnPitchPx
        guard pitch > 0 else { return l }

        // Main columns: however many of the canonical pitch positions fit
        // the panel width, then recentred as one block so the margin is
        // equal on both edges -- a 42 HP panel already comes out this way
        // with zero remainder (630 px = exactly 10 x 63 px), but a narrower
        // panel used to keep a fixed half-pitch margin on the left and
        // whatever was left over on the right, which could be far smaller
        // (confirmed against real use: 24 HP came out 10.67 mm left vs.
        // 4.57 mm right -- an 18 px skew, not the "evenly balanced" look
        // Custom Grid already gives). Column *count* is unchanged from
        // before (still "however many fit at this pitch"); only where that
        // block sits within the width changed. The n points span
        // (n-1) x pitch centre-to-centre (n=1 spans zero), not n x pitch --
        // an off-by-one caught in verification against the 24 HP case
        // below before this shipped.
        var n = 0
        var probe = pitch / 2
        while probe < width { n += 1; probe += pitch }
        let span = pitch * CGFloat(max(n - 1, 0))
        let leftMargin = max(0, (width - span) / 2)
        l.mainCols = (0..<n).map { leftMargin + pitch * CGFloat($0) }

        // Half-lane columns sit at the boundaries between main columns
        // (the midpoint between each consecutive pair); only meaningful on
        // half rows. Derived from the same recentred main columns, so they
        // stay exactly on those boundaries by construction.
        l.halfCols = n > 1 ? (1..<n).map { leftMargin + pitch * (CGFloat($0) - 0.5) } : []

        return l
    }

    private static func nearest(_ v: CGFloat, in values: [CGFloat]) -> CGFloat {
        values.min(by: { abs($0 - v) < abs($1 - v) }) ?? v
    }

    /// Snaps a *centre* point to the correlated Serge grid: nearest row
    /// first (main or half row, whichever is closer), then the nearest
    /// column from *either* column tier -- main columns and half-lane
    /// columns are both offered on every row, not just half rows.
    ///
    /// This was originally row-gated (main columns only on a main row,
    /// half-lane columns only on a half row), which matched the drawn
    /// overlay but not the real hardware: on the actual GTS panel, the
    /// status LEDs sit at half-lane column positions *on main row 1*, at
    /// the same height as the END/OUT jacks flanking them -- not on a row
    /// of their own. Confirmed against the reference photo and against
    /// Peet's report that the LED's correct position "does not snap":
    /// with the old gating, a main row simply never offered a half-lane
    /// column as a candidate, so that exact spot was unreachable and the
    /// LED had to sit on the outer half-step row instead (visually one row
    /// too high). Falls back to plain column-pitch snapping when the
    /// document has no rows to offer (non-3U formats).
    package static func snapCenter(_ p: CGPoint, in doc: PanelDocument) -> CGPoint {
        let l = lines(for: doc)
        let rows = l.mainRows + l.halfRows
        guard let closestY = rows.min(by: { abs($0 - p.y) < abs($1 - p.y) }) else {
            let sx = l.mainCols.isEmpty ? p.x : nearest(p.x, in: l.mainCols)
            return CGPoint(x: sx, y: p.y)
        }
        let cols = l.mainCols + l.halfCols
        let sx = cols.isEmpty ? p.x : nearest(p.x, in: cols)
        return CGPoint(x: sx, y: closestY)
    }
}
