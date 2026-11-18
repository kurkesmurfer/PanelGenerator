import Foundation
import CoreGraphics

// MARK: - Paperface snap grid

/// The Paperface grid's settings, stored per document when they differ from
/// the measured defaults. Every value is optional so a document only records
/// what was changed, and documents that never touch the grid stay unchanged.
package struct PaperfaceGridSpec: Codable, Hashable {
    /// First main row line, mm from the top.
    package var rowOriginMM: CGFloat?
    /// Main row pitch, mm. Fractional pitches are the point: 57.6 px is
    /// 19.507 mm, which no pixel grid can hit.
    package var rowPitchMM: CGFloat?
    package var rowCount: Int?
    /// Column pitch in whole HP.
    package var columnHP: Int?
    /// Quarter positions between main and half, on both axes.
    package var quarters: Bool?

    package init(rowOriginMM: CGFloat? = nil, rowPitchMM: CGFloat? = nil, rowCount: Int? = nil,
                 columnHP: Int? = nil, quarters: Bool? = nil) {
        self.rowOriginMM = rowOriginMM; self.rowPitchMM = rowPitchMM; self.rowCount = rowCount
        self.columnHP = columnHP; self.quarters = quarters
    }

    package var isDefault: Bool {
        rowOriginMM == nil && rowPitchMM == nil && rowCount == nil && columnHP == nil && quarters != true
    }
}

/// The Paperface 50 grid in 3U: evenly spaced main rows, the phase-shifted
/// half rows between them (Serge's half-step trick, used on the Paperface
/// panels for the third 1V/O jack, the slopes' START jacks and the like),
/// optional quarter positions, and columns a whole number of HP apart so a
/// module of n columns is exactly n × pitch wide.
///
/// Defaults are measured on the Paperface50 reference renders: object
/// centres at 144.6, 323.5, 502.7, 681.9, 861.0, 1041.7 px of 1198 — a
/// 179.5 px pitch, scaled to 128.5 mm: 15.5 mm + 19.25 mm steps, six rows.
/// Cell outlines fall on the half rows. A document can instead put the main
/// rows on the cell lines (e.g. origin 22 px, pitch 57.6 px, seven lines);
/// the object centres are then the half rows.
///
/// Columns: the original pitch (18.4 mm in 3U) matches no whole HP; 4 HP
/// (20.32 mm) is the nearest that keeps cells near-square, and the default.
package enum PaperfaceGrid {
    package static let firstRowMM: CGFloat = 15.5
    package static let rowPitchMM: CGFloat = 19.25
    package static let rowCount = 6
    package static let defaultColumnHP = 4
    package static let columnHPRange = 2...6

    package struct Resolved {
        package var originMM: CGFloat
        package var pitchMM: CGFloat
        package var rows: Int
        package var columnHP: Int
        package var quarters: Bool
    }

    package static func resolved(_ doc: PanelDocument) -> Resolved {
        let s = doc.paperfaceGrid
        return Resolved(originMM: s?.rowOriginMM ?? firstRowMM,
                        pitchMM: max(1, s?.rowPitchMM ?? rowPitchMM),
                        rows: min(max(s?.rowCount ?? rowCount, 1), 24),
                        columnHP: min(max(s?.columnHP ?? defaultColumnHP, columnHPRange.lowerBound),
                                      columnHPRange.upperBound),
                        quarters: s?.quarters ?? false)
    }

    package static var mainRowsMM: [CGFloat] {
        (0..<rowCount).map { firstRowMM + rowPitchMM * CGFloat($0) }
    }

    package static func columnHP(for doc: PanelDocument) -> Int { resolved(doc).columnHP }

    package static func columnPitchPx(for doc: PanelDocument) -> CGFloat {
        CGFloat(columnHP(for: doc)) * PanelMetrics.pixelsPerHP
    }

    /// Main and half rows and columns; quarter positions, when on, are
    /// returned as extra half rows/columns (they snap the same way and draw
    /// as the small dots).
    package static func lines(for doc: PanelDocument) -> SergeGrid.Lines {
        let r = resolved(doc)
        var l = SergeGrid.Lines()
        let toPx: (CGFloat) -> CGFloat = { $0 / PanelMetrics.mmPerPixel }
        if doc.format == .u3 {
            let rows = (0..<r.rows).map { toPx(r.originMM + r.pitchMM * CGFloat($0)) }
            l.mainRows = rows
            var half = rows.count > 1 ? (0..<rows.count - 1).map { (rows[$0] + rows[$0 + 1]) / 2 } : []
            let step = toPx(r.pitchMM) / 2
            if doc.sergeGridOuterHalfSteps, let first = rows.first, let last = rows.last {
                half = [first - step] + half + [last + step]
            }
            if r.quarters {
                half += (rows + half).flatMap { [$0 - step / 2, $0 + step / 2] }
            }
            l.halfRows = Array(Set(half.map { ($0 * 1000).rounded() / 1000 })).sorted()
        }

        // Columns: as many whole pitches as fit, centred. On a panel that is
        // a whole number of pitches wide that puts the first column half a
        // pitch in, on the HP raster.
        let width = PanelMetrics.size(hp: doc.widthHP, format: doc.format).width
        let pitch = CGFloat(r.columnHP) * PanelMetrics.pixelsPerHP
        let n = max(1, Int((width / pitch).rounded(.down)))
        let left = (width - pitch * CGFloat(n - 1)) / 2
        l.mainCols = (0..<n).map { left + pitch * CGFloat($0) }
        var halfCols = n > 1 ? (1..<n).map { left + pitch * (CGFloat($0) - 0.5) } : []
        if r.quarters {
            halfCols += (l.mainCols + halfCols).flatMap { [$0 - pitch / 4, $0 + pitch / 4] }
                .filter { $0 > 0 && $0 < width }
        }
        l.halfCols = halfCols.sorted()
        return l
    }

    // MARK: - Frame

    /// The artwork's bounds, mm: the top line (first row's centre − 6.9, the
    /// title strip above it), the bottom line (last row + half a row), and
    /// for a six-row panel the double line between two three-row sections.
    /// Measured on Paris Flash: 8.61, 63.6 / 66.19, 121.07 mm.
    package struct Frame {
        package var topMM: CGFloat
        package var bottomMM: CGFloat
        package var sectionMM: [(bottom: CGFloat, top: CGFloat)]
        /// Lines a cell's top may sit on, and lines its bottom may sit on.
        package var tops: [CGFloat] { [topMM] + sectionMM.map(\.top) }
        package var bottoms: [CGFloat] { sectionMM.map(\.bottom) + [bottomMM] }
        package var all: [CGFloat] { tops + bottoms }
    }

    package static func frame(for doc: PanelDocument) -> Frame? {
        guard doc.format == .u3 else { return nil }
        let r = resolved(doc)
        let rows = (0..<r.rows).map { r.originMM + r.pitchMM * CGFloat($0) }
        guard let first = rows.first, let last = rows.last else { return nil }
        var sections: [(CGFloat, CGFloat)] = []
        if rows.count == 6 {
            sections = [(rows[2] + r.pitchMM / 2, rows[3] + Paperface.firstRowTopMM)]
        }
        return Frame(topMM: first + Paperface.firstRowTopMM, bottomMM: last + r.pitchMM / 2,
                     sectionMM: sections)
    }

    /// Paperface cell shapes (not glyphs) on the panel.
    static func isCellShape(_ e: PanelElement) -> Bool {
        e.kind == .path && Paperface.shapes.values.contains(e.pathData ?? "") && !e.role.isComponent
    }

    /// Snaps the cell shapes in `ids` (or all) onto the frame: a top within
    /// `reachMM` of a top line moves onto it, likewise a bottom. Returns how
    /// many edges moved.
    @discardableResult
    package static func fitToFrame(_ doc: inout PanelDocument, ids: Set<UUID>? = nil, reachMM: CGFloat = 3) -> Int {
        guard let f = frame(for: doc) else { return 0 }
        let px: (CGFloat) -> CGFloat = { $0 / PanelMetrics.mmPerPixel }
        var moved = 0
        for i in doc.elements.indices where isCellShape(doc.elements[i]) && (ids?.contains(doc.elements[i].id) ?? true) {
            var e = doc.elements[i]
            let top = PanelMetrics.mm(e.y), bottom = PanelMetrics.mm(e.y + e.h)
            if let t = f.tops.min(by: { abs($0 - top) < abs($1 - top) }), abs(t - top) <= reachMM, abs(t - top) > 0.001 {
                let b = e.y + e.h; e.y = px(t); e.h = b - e.y; moved += 1
            }
            if let b = f.bottoms.min(by: { abs($0 - bottom) < abs($1 - bottom) }), abs(b - bottom) <= reachMM,
               abs(b - bottom) > 0.001 {
                e.h = px(b) - e.y; moved += 1
            }
            doc.elements[i] = e
        }
        return moved
    }

    /// Cell shapes reaching outside the frame, for the export report.
    package static func frameWarnings(_ doc: PanelDocument) -> [String] {
        guard isPaperface(doc), let f = frame(for: doc) else { return [] }
        let out = doc.elements.filter { e in
            isCellShape(e) && e.isHidden != true
                && (PanelMetrics.mm(e.y) < f.topMM - 0.05 || PanelMetrics.mm(e.y + e.h) > f.bottomMM + 0.05)
        }
        guard !out.isEmpty else { return [] }
        return ["\(out.count) Paperface cell shape\(out.count == 1 ? "" : "s") reach outside the frame "
            + String(format: "(%.2f–%.2f mm): ", Double(f.topMM), Double(f.bottomMM))
            + out.prefix(4).map(\.name).joined(separator: ", ")
            + ". Edit ▸ Fit Artwork to Frame snaps edges within 3 mm onto it."]
    }

    /// A document built in the Paperface language: its face colour, grid
    /// settings of its own, or Paperface cell shapes.
    package static func isPaperface(_ doc: PanelDocument) -> Bool {
        doc.paperfaceGrid != nil || doc.background == Paperface.face
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
