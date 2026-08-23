import Foundation
import CoreGraphics

/// Converts a CGPath into an SVG `d` attribute string. This is the bridge that
/// lets the single shared renderer feed the SVG exporter.
enum PathSVG {

    static func d(_ path: CGPath) -> String {
        var out = ""
        func n(_ v: CGFloat) -> String { Geo.fmt(v) }

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
