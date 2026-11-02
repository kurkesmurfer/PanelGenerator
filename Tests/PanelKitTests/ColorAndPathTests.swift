import XCTest
import CoreGraphics
@testable import PanelKit

final class ColorSpecTests: XCTestCase {
    func testHexRoundTrip() {
        for hex in ["#000000", "#FFFFFF", "#FF9C00", "#1D1713", "#99CCFF"] {
            XCTAssertEqual(ColorSpec.hex(hex).hexString.uppercased(), hex)
        }
    }
}

final class PathTests: XCTestCase {
    /// PathSVG.d and SVGPath.path(fromD:) are inverses up to rounding.
    func testSVGPathDataRoundTripsBounds() {
        let frames = [CGRect(x: 10, y: 20, width: 60, height: 30),
                      CGRect(x: 0, y: 0, width: 17, height: 64)]
        for f in frames {
            let paths = [Renderer.ellipsePath(f), Renderer.ringSectorPath(f, thickness: 6, startDeg: 200, sweepDeg: 140)]
            for p in paths {
                guard let back = SVGPath.path(fromD: PathSVG.d(p, decimals: 4)) else { return XCTFail("unparsable d") }
                let a = p.boundingBoxOfPath, b = back.boundingBoxOfPath
                XCTAssertEqual(a.minX, b.minX, accuracy: 1e-3); XCTAssertEqual(a.maxX, b.maxX, accuracy: 1e-3)
                XCTAssertEqual(a.minY, b.minY, accuracy: 1e-3); XCTAssertEqual(a.maxY, b.maxY, accuracy: 1e-3)
            }
        }
    }

    func testEllipseFillsItsFrame() {
        let f = CGRect(x: 5, y: 7, width: 40, height: 22)
        let b = Renderer.ellipsePath(f).boundingBoxOfPath
        XCTAssertEqual(b.width, f.width, accuracy: 1e-6)
        XCTAssertEqual(b.height, f.height, accuracy: 1e-6)
    }
}
