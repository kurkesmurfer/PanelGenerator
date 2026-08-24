import Foundation
import CoreGraphics

// MARK: - Panel metrics (VCV Rack SVG conventions)

enum PanelMetrics {
    static let pixelsPerHP: CGFloat = 15      // VCV Rack SVG convention
    static let height3U: CGFloat = 380        // 3U panel height in px
    static let height1U: CGFloat = 127        // common 1U tile height in px
    static let minPanelWidthHP = 2
    static let maxPanelWidthHP = 48

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
