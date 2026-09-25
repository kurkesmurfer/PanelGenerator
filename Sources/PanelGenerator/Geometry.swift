import Foundation
import CoreGraphics

// MARK: - Panel metrics (VCV Rack SVG conventions)

enum PanelMetrics {
    static let pixelsPerHP: CGFloat = 15      // VCV Rack SVG convention
    static let height3U: CGFloat = 380        // 3U panel height in px
    static let height1U: CGFloat = 127        // common 1U tile height in px
    static let minPanelWidthHP = 2
    /// 84 HP is a full 19-inch rack row (426.7 mm), which is as wide as a
    /// single panel gets in practice.
    static let maxPanelWidthHP = 84

    /// Corner-screw inset from each edge and their side length, in px --
    /// shared with `PanelDocument.addCornerScrews` so there is one source
    /// of truth for where a screw actually sits. `CustomGrid` uses their
    /// combined reach to keep its row grid clear of them (and of the
    /// module name / brand mark that usually live in the same margin).
    static let screwInset: CGFloat = 7
    static let screwSide: CGFloat = 11

    static func height(for format: PanelFormat) -> CGFloat {
        switch format {
        case .u1: return height1U
        case .u3: return height3U
        }
    }

    /// Rack authors panel SVGs at 75 dpi, so panel pixels convert to the
    /// millimetres that `mm2px()` and MetaModule's `x_mm` both expect.
    static let mmPerPixel: CGFloat = 25.4 / 75

    static func mm(_ px: CGFloat) -> CGFloat { px * mmPerPixel }

    static func size(hp: Int, format: PanelFormat) -> CGSize {
        CGSize(width: CGFloat(max(hp, 1)) * pixelsPerHP,
               height: height(for: format))
    }
}

// MARK: - Geometry helpers

enum Geo {
    /// Half-HP snap grid keeps placements on the module grid.
    static var defaultSnap: CGFloat { PanelMetrics.pixelsPerHP / 2 }

    static func snap(_ v: CGFloat, to grid: CGFloat) -> CGFloat {
        grid <= 0 ? v : (v / grid).rounded() * grid
    }

    static func deg2rad(_ d: CGFloat) -> CGFloat { d * .pi / 180 }

    /// Rotate point p around c. Positive degrees appear clockwise in the
    /// y-down canvas coordinate space.
    static func rotate(_ p: CGPoint, around c: CGPoint, degrees d: CGFloat) -> CGPoint {
        let a = deg2rad(d)
        let s = sin(a), co = cos(a)
        let dx = p.x - c.x, dy = p.y - c.y
        return CGPoint(x: c.x + dx * co - dy * s,
                       y: c.y + dx * s + dy * co)
    }

    static func fmt(_ v: CGFloat) -> String {
        String(format: "%.2f", Double(v))
    }
}

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
enum SergeGrid {
    /// The 5 canonical row centre-lines for a 3U panel, in millimetres,
    /// top to bottom. These are fixed reference values, not `height3U / 5`.
    static let mainRowsMM: [CGFloat] = [27.2, 48.2, 69.2, 90.2, 111.2]

    /// 42 HP spans exactly 10 main column positions -> 63 px (21.34 mm) pitch.
    static let columnPitchPx: CGFloat = 42 * PanelMetrics.pixelsPerHP / 10

    static var mainRowsPx: [CGFloat] {
        mainRowsMM.map { $0 / PanelMetrics.mmPerPixel }
    }

    /// Half rows sit at the arithmetic midpoint between each pair of
    /// consecutive main rows. Serge inserts these one at a time, top to
    /// bottom, as density requires; PanelGenerator offers all four as snap
    /// targets at once rather than tracking a density heuristic.
    static var halfRowsPx: [CGFloat] {
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
    static func halfRowsPx(includingOuter: Bool) -> [CGFloat] {
        let interior = halfRowsPx
        guard includingOuter, let first = mainRowsPx.first, let last = mainRowsPx.last else {
            return interior
        }
        let step = halfStepPx
        guard step > 0 else { return interior }
        return [first - step] + interior + [last + step]
    }

    struct Lines {
        var mainRows: [CGFloat] = []
        var halfRows: [CGFloat] = []
        var mainCols: [CGFloat] = []
        var halfCols: [CGFloat] = []
    }

    /// Builds the grid line set for a document. Rows only apply to 3U
    /// panels (Serge's row grid is a 3U convention); columns are derived
    /// from panel width and offered for any format.
    static func lines(for doc: PanelDocument) -> Lines {
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
    static func snapCenter(_ p: CGPoint, in doc: PanelDocument) -> CGPoint {
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

// MARK: - Custom (plain N x M) snap grid

/// A simple, editable snap grid: divides the panel evenly into `columns`
/// columns and `rows` rows (from `PanelDocument.customGridColumns/Rows`),
/// unlike `SergeGrid`'s fixed, correlated row/column layout. For real
/// modules whose actual component layout doesn't follow Serge's
/// standardised grid -- e.g. an imported panel that genuinely has 5
/// columns, not Serge's 4 -- set the divisions to match via View > Snap
/// Step > Custom Grid..., which asks for both counts in a dialog.
enum CustomGrid {
    /// Rows keep clear of the corner screws by default: a screw's far edge
    /// sits `screwInset + screwSide` in from the panel edge, and a module's
    /// name (top) and brand mark (bottom) typically live in that same
    /// margin, so the row grid is confined to the band between them --
    /// "bottom of [top] screw" for the top bound, "top of [bottom] screw"
    /// for the bottom bound. Columns are unrestricted; nothing about a
    /// panel's left/right edges asks for the same treatment.
    static var rowMargin: CGFloat { PanelMetrics.screwInset + PanelMetrics.screwSide }

    struct Lines {
        var mainCols: [CGFloat] = []
        var mainRows: [CGFloat] = []
        /// Serge-style intermediate positions (`PanelDocument.
        /// customGridHalfPositions`): half-lane columns sit at the interior
        /// cell boundaries, half rows at the interior row boundaries --
        /// exactly `SergeGrid`'s own half-row/half-lane convention, just
        /// generalised to whatever N x M the document is set to, rather
        /// than Serge's fixed 5 x 10. Empty when the checkbox is off.
        var halfCols: [CGFloat] = []
        var halfRows: [CGFloat] = []
        /// Finer, uncorrelated quarter-cell positions (`PanelDocument.
        /// customGridFinerPositions`): two per cell per axis, at 1/4 and 3/4
        /// of each column's width / row's height. Unlike the half tier,
        /// these aren't tied to a particular row/column kind -- they're
        /// candidates on every row and column alike. Empty when the
        /// checkbox is off.
        var quarterCols: [CGFloat] = []
        var quarterRows: [CGFloat] = []
    }

    /// Column/row centre-lines. Columns divide the full panel width evenly;
    /// rows divide only the band between the corner screws (see
    /// `rowMargin`), so the outer rows land well clear of a module's name
    /// and brand mark instead of the panel's bare edges.
    static func lines(for doc: PanelDocument) -> Lines {
        let size = doc.pixelSize
        let n = max(1, doc.customGridColumns)
        let m = max(1, doc.customGridRows)
        var l = Lines()

        let colW = size.width / CGFloat(n)
        l.mainCols = (0..<n).map { colW * (CGFloat($0) + 0.5) }

        let margin = rowMargin
        let hasRoom = size.height - margin * 2 > 0
        let top = hasRoom ? margin : 0
        let usable = hasRoom ? size.height - margin * 2 : size.height
        let rowH = usable / CGFloat(m)
        l.mainRows = (0..<m).map { top + rowH * (CGFloat($0) + 0.5) }

        if doc.customGridHalfPositions {
            if n > 1 { l.halfCols = (1..<n).map { colW * CGFloat($0) } }
            if m > 1 { l.halfRows = (1..<m).map { top + rowH * CGFloat($0) } }
        }
        if doc.customGridFinerPositions {
            l.quarterCols = (0..<n).flatMap { k -> [CGFloat] in
                let kf = CGFloat(k)
                let a: CGFloat = colW * (kf + 0.25)
                let b: CGFloat = colW * (kf + 0.75)
                return [a, b]
            }
            l.quarterRows = (0..<m).flatMap { k -> [CGFloat] in
                let kf = CGFloat(k)
                let a: CGFloat = top + rowH * (kf + 0.25)
                let b: CGFloat = top + rowH * (kf + 0.75)
                return [a, b]
            }
        }
        return l
    }

    private static func nearest(_ v: CGFloat, in values: [CGFloat]) -> CGFloat {
        values.min(by: { abs($0 - v) < abs($1 - v) }) ?? v
    }

    /// Snaps a *centre* point to the grid. With Serge-style half positions
    /// off, the two axes are independent (nearest column, nearest row).
    /// With them on, it's correlated exactly like `SergeGrid`: nearest row
    /// first (main or half, whichever is closer), then columns of the
    /// matching kind -- main columns on a main row, half-lane columns on a
    /// half row.
    static func snapCenter(_ p: CGPoint, in doc: PanelDocument) -> CGPoint {
        let l = lines(for: doc)
        guard doc.customGridHalfPositions else {
            let xs = l.mainCols + l.quarterCols
            let ys = l.mainRows + l.quarterRows
            let sx = xs.isEmpty ? p.x : nearest(p.x, in: xs)
            let sy = ys.isEmpty ? p.y : nearest(p.y, in: ys)
            return CGPoint(x: sx, y: sy)
        }
        // Quarter positions are uncorrelated: available as extra column
        // candidates on every row, whatever kind that row is.
        let mainCandidateCols = l.mainCols + l.quarterCols
        let halfCandidateCols = (l.halfCols.isEmpty ? l.mainCols : l.halfCols) + l.quarterCols
        var rows: [(y: CGFloat, cols: [CGFloat])] = []
        rows += l.mainRows.map { ($0, mainCandidateCols) }
        rows += l.halfRows.map { ($0, halfCandidateCols) }
        rows += l.quarterRows.map { ($0, mainCandidateCols) }
        guard let closest = rows.min(by: { abs($0.y - p.y) < abs($1.y - p.y) }) else {
            let sx = l.mainCols.isEmpty ? p.x : nearest(p.x, in: l.mainCols)
            return CGPoint(x: sx, y: p.y)
        }
        let sx = closest.cols.isEmpty ? p.x : nearest(p.x, in: closest.cols)
        return CGPoint(x: sx, y: closest.y)
    }
}
