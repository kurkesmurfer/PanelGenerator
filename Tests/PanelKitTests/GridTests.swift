import XCTest
import CoreGraphics
@testable import PanelKit

final class SergeGridTests: XCTestCase {
    private func doc(hp: Int, format: PanelFormat = .u3) -> PanelDocument {
        var d = PanelDocument()
        d.widthHP = hp
        d.format = format
        return d
    }

    func testFortyTwoHPHasTenColumnsAtCanonicalPitch() {
        let l = SergeGrid.lines(for: doc(hp: 42))
        XCTAssertEqual(l.mainCols.count, 10)
        XCTAssertEqual(SergeGrid.columnPitchPx, 63, accuracy: 1e-9)
        for (a, b) in zip(l.mainCols, l.mainCols.dropFirst()) {
            XCTAssertEqual(b - a, 63, accuracy: 1e-9)
        }
        XCTAssertEqual(l.mainCols.first!, 31.5, accuracy: 1e-9)
    }

    /// The recentring fix: a panel narrower than 42 HP keeps equal margins.
    /// Before it, 24 HP came out 10.67 mm left vs 4.57 mm right.
    func testNarrowPanelIsRecentred() {
        for hp in [8, 12, 16, 24, 30] {
            let width = PanelMetrics.size(hp: hp, format: .u3).width
            let cols = SergeGrid.lines(for: doc(hp: hp)).mainCols
            guard let first = cols.first, let last = cols.last else { return XCTFail("no columns at \(hp) HP") }
            XCTAssertEqual(first, width - last, accuracy: 1e-9, "\(hp) HP margins differ")
        }
    }

    /// n columns span (n-1) pitches, not n — the off-by-one caught by hand.
    func testSpanIsNMinusOnePitches() {
        let cols = SergeGrid.lines(for: doc(hp: 24)).mainCols
        XCTAssertEqual(cols.last! - cols.first!, SergeGrid.columnPitchPx * CGFloat(cols.count - 1), accuracy: 1e-9)
    }

    func testHalfColumnsSitBetweenMainColumns() {
        let l = SergeGrid.lines(for: doc(hp: 42))
        XCTAssertEqual(l.halfCols.count, l.mainCols.count - 1)
        for (i, h) in l.halfCols.enumerated() {
            XCTAssertEqual(h, (l.mainCols[i] + l.mainCols[i + 1]) / 2, accuracy: 1e-9)
        }
    }

    func testRowsAreTheFixedMillimetreValues() {
        let rows = SergeGrid.lines(for: doc(hp: 42)).mainRows
        XCTAssertEqual(rows.count, 5)
        for (px, mm) in zip(rows, SergeGrid.mainRowsMM) {
            XCTAssertEqual(PanelMetrics.mm(px), mm, accuracy: 1e-9)
        }
    }

    func testOuterHalfStepsAddOneRowEachEnd() {
        XCTAssertEqual(SergeGrid.halfRowsPx(includingOuter: false).count, 4)
        XCTAssertEqual(SergeGrid.halfRowsPx(includingOuter: true).count, 6)
    }

    /// Documents current behaviour: 1U has no Serge rows (see issue #7).
    func testOneUHasNoRows() {
        let l = SergeGrid.lines(for: doc(hp: 42, format: .u1))
        XCTAssertTrue(l.mainRows.isEmpty)
        XCTAssertTrue(l.halfRows.isEmpty)
    }
}

final class CustomGridTests: XCTestCase {
    func testColumnAndRowCountsFollowTheDocument() {
        var d = PanelDocument()
        d.widthHP = 20
        d.customGridColumns = 5
        d.customGridRows = 4
        let l = CustomGrid.lines(for: d)
        XCTAssertEqual(l.mainCols.count, 5)
        XCTAssertEqual(l.mainRows.count, 4)
    }

    func testRowsStayClearOfTheScrews() {
        var d = PanelDocument()
        d.customGridRows = 6
        let h = d.pixelSize.height
        for y in CustomGrid.lines(for: d).mainRows {
            XCTAssertGreaterThanOrEqual(y, CustomGrid.rowMargin - 1e-9)
            XCTAssertLessThanOrEqual(y, h - CustomGrid.rowMargin + 1e-9)
        }
    }
}

final class PaperfaceGridTests: XCTestCase {
    private func doc(hp: Int, pitch: Int? = nil, outer: Bool = false) -> PanelDocument {
        var d = PanelDocument()
        d.widthHP = hp
        d.format = .u3
        if let pitch { d.paperfaceGrid = PaperfaceGridSpec(columnHP: pitch) }
        d.sergeGridOuterHalfSteps = outer
        return d
    }
    private func mm(_ v: [CGFloat]) -> [CGFloat] { v.map { (PanelMetrics.mm($0) * 100).rounded() / 100 } }

    func testSixRowsAndHalfRows() {
        let l = PaperfaceGrid.lines(for: doc(hp: 8))
        XCTAssertEqual(mm(l.mainRows), [15.5, 34.75, 54, 73.25, 92.5, 111.75])
        XCTAssertEqual(l.halfRows.count, 5)
        XCTAssertEqual(PanelMetrics.mm(l.halfRows[0]), 25.125, accuracy: 0.001)
        let outer = PaperfaceGrid.lines(for: doc(hp: 8, outer: true))
        XCTAssertEqual(outer.halfRows.count, 7)
        XCTAssertEqual(PanelMetrics.mm(outer.halfRows.last!), 121.375, accuracy: 0.001)
    }

    func testColumnsSitOnTheHPRaster() {
        // Default 4 HP: an 8 HP module holds exactly two columns.
        let l = PaperfaceGrid.lines(for: doc(hp: 8))
        XCTAssertEqual(mm(l.mainCols), [10.16, 30.48])
        XCTAssertEqual(mm(l.halfCols), [20.32])
        // 3 HP pitch on a 12 HP panel: four columns, 15.24 mm apart.
        let t = PaperfaceGrid.lines(for: doc(hp: 12, pitch: 3))
        XCTAssertEqual(mm(t.mainCols), [7.62, 22.86, 38.1, 53.34])
        // Out-of-range pitch is clamped rather than producing nonsense.
        XCTAssertEqual(PaperfaceGrid.columnHP(for: doc(hp: 8, pitch: 40)), 6)
    }

    /// The co-session's cell-line grid: origin 22 px, pitch 57.6 px, seven
    /// lines — fractional pixels, so only reachable with a real pitch.
    func testCellLineGridWithFractionalPitch() {
        var d = doc(hp: 12)
        d.paperfaceGrid = PaperfaceGridSpec(rowOriginMM: 22 * PanelMetrics.mmPerPixel,
                                            rowPitchMM: 57.6 * PanelMetrics.mmPerPixel, rowCount: 7, quarters: true)
        let l = PaperfaceGrid.lines(for: d)
        XCTAssertEqual(l.mainRows.count, 7)
        XCTAssertEqual(l.mainRows[0], 22, accuracy: 1e-6)
        XCTAssertEqual(l.mainRows[6], 22 + 6 * 57.6, accuracy: 1e-6)
        XCTAssertTrue(l.halfRows.contains { abs($0 - 50.8) < 1e-3 })   // centre of the first cell
        XCTAssertTrue(l.halfRows.contains { abs($0 - 36.4) < 1e-3 })   // quarter
        let s = PaperfaceGrid.snapCenter(CGPoint(x: 31, y: 252), in: d)
        XCTAssertEqual(s.y, 252.4, accuracy: 1e-3)                    // 22 + 4 × 57.6
        XCTAssertEqual(s.x, 30, accuracy: 1e-6)
    }

    func testSnapReachesHalfPositions() {
        let d = doc(hp: 8)
        // Between rows 3 and 4, halfway across: the half row and half column.
        let p = CGPoint(x: 20.0 / PanelMetrics.mmPerPixel, y: 63.0 / PanelMetrics.mmPerPixel)
        let s = PaperfaceGrid.snapCenter(p, in: d)
        XCTAssertEqual(PanelMetrics.mm(s.x), 20.32, accuracy: 0.001)
        XCTAssertEqual(PanelMetrics.mm(s.y), 63.625, accuracy: 0.001)
    }
}
