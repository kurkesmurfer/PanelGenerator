import Foundation
import CoreGraphics

/// Converts a CGPath into an SVG `d` attribute string. This is the bridge that
/// lets the single shared renderer feed the SVG exporter.
package enum PathSVG {

    /// `decimals` is two for export, where the unit is a panel pixel and
    /// hundredths are far below what any rasteriser resolves. It has to be
    /// much finer for a path stored normalised into a 0…1 box: at two decimals
    /// a unit path quantises to one part in a hundred, which on a 90 px panel
    /// is a visible staircase.
    package static func d(_ path: CGPath, decimals: Int = 2) -> String {
        var out = ""
        let format = "%.\(decimals)f"
        func n(_ v: CGFloat) -> String {
            var s = String(format: format, Double(v))
            // Trailing zeros are noise in a stored path, and a stored path is
            // written once per import but read on every redraw.
            if s.contains(".") {
                while s.hasSuffix("0") { s.removeLast() }
                if s.hasSuffix(".") { s.removeLast() }
            }
            return s == "-0" ? "0" : s
        }

        path.applyWithBlock { elementPointer in
            let el = elementPointer.pointee
            switch el.type {
            case .moveToPoint:
                out += "M \(n(el.points[0].x)) \(n(el.points[0].y)) "
            case .addLineToPoint:
                out += "L \(n(el.points[0].x)) \(n(el.points[0].y)) "
            case .addQuadCurveToPoint:
                out += "Q \(n(el.points[0].x)) \(n(el.points[0].y)) \(n(el.points[1].x)) \(n(el.points[1].y)) "
            case .addCurveToPoint:
                out += "C \(n(el.points[0].x)) \(n(el.points[0].y)) \(n(el.points[1].x)) \(n(el.points[1].y)) \(n(el.points[2].x)) \(n(el.points[2].y)) "
            case .closeSubpath:
                out += "Z "
            @unknown default:
                break
            }
        }
        return out.trimmingCharacters(in: .whitespaces)
    }
}
