import Foundation
import CoreGraphics

// MARK: - Paperface snap grid

/// The Paperface 50 grid in 3U: six evenly spaced object rows, the
/// "phase-shifted" half rows between them (Serge's half-step trick, used on
/// the Paperface panels for the third 1V/O jack, the slopes' START jacks and
/// the like), and columns at a whole number of HP so a module of n columns is
/// exactly n × pitch wide.
///
/// Rows are measured on the Paperface50 reference renders: object centres at
/// 144.6, 323.5, 502.7, 681.9, 861.0, 1041.7 px of 1198, i.e. a 179.5 px
/// (25.4 mm × 1.06) pitch, scaled to 128.5 mm → 15.5 mm + 19.25 mm steps.
///
/// Columns: the original pitch is 171 px, a hair narrower than the rows. In
/// 3U that is 18.4 mm, which no whole HP matches; 4 HP (20.32 mm) is the
/// nearest that keeps cells near-square (5 % wider than tall), and is the
/// default. The pitch is per document (`paperfaceColumnHP`), 2–6 HP, for
/// narrower or wider layouts. Half columns sit halfway between, so with the
/// default every even HP is reachable.
package enum PaperfaceGrid {
    package static let firstRowMM: CGFloat = 15.5
    package static let rowPitchMM: CGFloat = 19.25
    package static let rowCount = 6
    package static let defaultColumnHP = 4
    package static let columnHPRange = 2...6

    package static var mainRowsMM: [CGFloat] {
        (0..<rowCount).map { firstRowMM + rowPitchMM * CGFloat($0) }
    }

    package static func columnHP(for doc: PanelDocument) -> Int {
        min(max(doc.paperfaceColumnHP ?? defaultColumnHP, columnHPRange.lowerBound), columnHPRange.upperBound)
    }

    package static func columnPitchPx(for doc: PanelDocument) -> CGFloat {
        CGFloat(columnHP(for: doc)) * PanelMetrics.pixelsPerHP
    }

    /// Main rows, half rows (interior, plus one half step beyond each end
    /// when `sergeGridOuterHalfSteps` is on — the same per-document switch
    /// Serge's grid uses), main and half columns.
    package static func lines(for doc: PanelDocument) -> SergeGrid.Lines {
        var l = SergeGrid.Lines()
        let toPx: (CGFloat) -> CGFloat = { $0 / PanelMetrics.mmPerPixel }
        if doc.format == .u3 {
            let rows = mainRowsMM.map(toPx)
            l.mainRows = rows
            var half = (0..<rows.count - 1).map { (rows[$0] + rows[$0 + 1]) / 2 }
            if doc.sergeGridOuterHalfSteps {
                let step = toPx(rowPitchMM) / 2
                half = [rows[0] - step] + half + [rows[rows.count - 1] + step]
            }
            l.halfRows = half
        }

        // Columns: as many whole pitches as fit, centred. On a panel that is
        // a whole number of pitches wide (the intended case) that puts the
        // first column half a pitch in, on the HP raster.
        let width = PanelMetrics.size(hp: doc.widthHP, format: doc.format).width
        let pitch = columnPitchPx(for: doc)
        let n = max(1, Int((width / pitch).rounded(.down)))
        let left = (width - pitch * CGFloat(n - 1)) / 2
        l.mainCols = (0..<n).map { left + pitch * CGFloat($0) }
        l.halfCols = n > 1 ? (1..<n).map { left + pitch * (CGFloat($0) - 0.5) } : []
        return l
    }

    /// A document built in the Paperface language: its face colour, a
    /// column pitch of its own, or Paperface cell shapes.
    package static func isPaperface(_ doc: PanelDocument) -> Bool {
        doc.paperfaceColumnHP != nil || doc.background == Paperface.face
            || doc.elements.contains { $0.kind == .path && Paperface.shapes.values.contains($0.pathData ?? "") }
    }

    private static func nearest(_ v: CGFloat, in values: [CGFloat]) -> CGFloat {
        values.min(by: { abs($0 - v) < abs($1 - v) }) ?? v
    }

    /// Nearest row of either tier, then nearest column of either tier — a
    /// half column is offered on a main row too, as on Serge's grid, because
    /// the panels put lamps and small jacks there.
    package static func snapCenter(_ p: CGPoint, in doc: PanelDocument) -> CGPoint {
        let l = lines(for: doc)
        let cols = l.mainCols + l.halfCols
        let x = cols.isEmpty ? p.x : nearest(p.x, in: cols)
        let rows = l.mainRows + l.halfRows
        let y = rows.isEmpty ? p.y : nearest(p.y, in: rows)
        return CGPoint(x: x, y: y)
    }
}
