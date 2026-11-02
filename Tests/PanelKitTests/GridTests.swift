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
