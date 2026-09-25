import Foundation
import CoreGraphics

// MARK: - Panel metrics (VCV Rack SVG conventions)

package enum PanelMetrics {
    package static let pixelsPerHP: CGFloat = 15      // VCV Rack SVG convention
    package static let height3U: CGFloat = 380        // 3U panel height in px
    package static let height1U: CGFloat = 127        // common 1U tile height in px
    package static let minPanelWidthHP = 2
    /// 84 HP is a full 19-inch rack row (426.7 mm), which is as wide as a
    /// single panel gets in practice.
    package static let maxPanelWidthHP = 84

    /// Corner-screw inset from each edge and their side length, in px --
    /// shared with `PanelDocument.addCornerScrews` so there is one source
    /// of truth for where a screw actually sits. `CustomGrid` uses their
    /// combined reach to keep its row grid clear of them (and of the
    /// module name / brand mark that usually live in the same margin).
    package static let screwInset: CGFloat = 7
    package static let screwSide: CGFloat = 11

    package static func height(for format: PanelFormat) -> CGFloat {
        switch format {
        case .u1: return height1U
        case .u3: return height3U
        }
    }

    /// Rack authors panel SVGs at 75 dpi, so panel pixels convert to the
    /// millimetres that `mm2px()` and MetaModule's `x_mm` both expect.
    package static let mmPerPixel: CGFloat = 25.4 / 75

    package static func mm(_ px: CGFloat) -> CGFloat { px * mmPerPixel }

    package static func size(hp: Int, format: PanelFormat) -> CGSize {
        CGSize(width: CGFloat(max(hp, 1)) * pixelsPerHP,
               height: height(for: format))
    }
}

// MARK: - Geometry helpers

package enum Geo {
    /// Half-HP snap grid keeps placements on the module grid.
    package static var defaultSnap: CGFloat { PanelMetrics.pixelsPerHP / 2 }

    package static func snap(_ v: CGFloat, to grid: CGFloat) -> CGFloat {
        grid <= 0 ? v : (v / grid).rounded() * grid
    }

    package static func deg2rad(_ d: CGFloat) -> CGFloat { d * .pi / 180 }

    /// Rotate point p around c. Positive degrees appear clockwise in the
    /// y-down canvas coordinate space.
    package static func rotate(_ p: CGPoint, around c: CGPoint, degrees d: CGFloat) -> CGPoint {
        let a = deg2rad(d)
        let s = sin(a), co = cos(a)
        let dx = p.x - c.x, dy = p.y - c.y
        return CGPoint(x: c.x + dx * co - dy * s,
                       y: c.y + dx * s + dy * co)
    }

    package static func fmt(_ v: CGFloat) -> String {
        String(format: "%.2f", Double(v))
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
package enum CustomGrid {
    /// Rows keep clear of the corner screws by default: a screw's far edge
    /// sits `screwInset + screwSide` in from the panel edge, and a module's
    /// name (top) and brand mark (bottom) typically live in that same
    /// margin, so the row grid is confined to the band between them --
    /// "bottom of [top] screw" for the top bound, "top of [bottom] screw"
    /// for the bottom bound. Columns are unrestricted; nothing about a
    /// panel's left/right edges asks for the same treatment.
    package static var rowMargin: CGFloat { PanelMetrics.screwInset + PanelMetrics.screwSide }

    package struct Lines {
        package var mainCols: [CGFloat] = []
        package var mainRows: [CGFloat] = []
        /// Serge-style intermediate positions (`PanelDocument.
        /// customGridHalfPositions`): half-lane columns sit at the interior
        /// cell boundaries, half rows at the interior row boundaries --
        /// exactly `SergeGrid`'s own half-row/half-lane convention, just
        /// generalised to whatever N x M the document is set to, rather
        /// than Serge's fixed 5 x 10. Empty when the checkbox is off.
        package var halfCols: [CGFloat] = []
        package var halfRows: [CGFloat] = []
        /// Finer, uncorrelated quarter-cell positions (`PanelDocument.
        /// customGridFinerPositions`): two per cell per axis, at 1/4 and 3/4
        /// of each column's width / row's height. Unlike the half tier,
        /// these aren't tied to a particular row/column kind -- they're
        /// candidates on every row and column alike. Empty when the
        /// checkbox is off.
        package var quarterCols: [CGFloat] = []
        package var quarterRows: [CGFloat] = []
    }

    /// Column/row centre-lines. Columns divide the full panel width evenly;
    /// rows divide only the band between the corner screws (see
    /// `rowMargin`), so the outer rows land well clear of a module's name
    /// and brand mark instead of the panel's bare edges.
    package static func lines(for doc: PanelDocument) -> Lines {
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
    package static func snapCenter(_ p: CGPoint, in doc: PanelDocument) -> CGPoint {
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

extension CGSize {
    package init(_ w: CGFloat, _ h: CGFloat) { self.init(width: w, height: h) }
}
