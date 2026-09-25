import AppKit
import CoreGraphics
import PanelKit

// Canvas: resize, rotate and mirror handles.

extension CanvasView {

    // MARK: Handles

    enum HandleDir: String { case nw, n, ne, e, se, s, sw, w }


    private func handleRects(for f: CGRect) -> [(HandleDir, CGRect)] {
        let hs = handleSize
        let pts: [(HandleDir, CGPoint)] = [
            (.nw, CGPoint(x: f.minX, y: f.minY)), (.n, CGPoint(x: f.midX, y: f.minY)),
            (.ne, CGPoint(x: f.maxX, y: f.minY)), (.e, CGPoint(x: f.maxX, y: f.midY)),
            (.se, CGPoint(x: f.maxX, y: f.maxY)), (.s, CGPoint(x: f.midX, y: f.maxY)),
            (.sw, CGPoint(x: f.minX, y: f.maxY)), (.w, CGPoint(x: f.minX, y: f.midY)),
        ]
        return pts.map { ($0.0, CGRect(x: $0.1.x - hs / 2, y: $0.1.y - hs / 2, width: hs, height: hs)) }
    }

    /// Handles that are actually usable for this frame. Edge-mid handles need
    /// perpendicular room — otherwise they carpet small elements (sliders!)
    /// and every grab turns into a resize instead of a move.
    func activeHandles(for f: CGRect) -> [(HandleDir, CGRect)] {
        let hs = handleSize
        return handleRects(for: f).filter { (dir, _) in
            switch dir {
            case .nw, .ne, .se, .sw: return f.width >= hs * 2 || f.height >= hs * 2
            case .e, .w:             return f.height >= hs * 4
            case .n, .s:             return f.width  >= hs * 4
            }
        }
    }

    func handle(at p: CGPoint) -> HandleDir? {
        guard let prim = primaryElement else { return nil }
        let local = toLocal(p, rotation: prim.rotation, center: prim.center)
        for (dir, r) in activeHandles(for: prim.frame) where r.contains(local) {
            return dir
        }
        return nil
    }

    /// Un-rotate a screen/panel point into an element's own local (unrotated)
    /// space -- the space its `frame` (x/y/w/h) is defined in. `rotation` is
    /// applied only at draw time (see `transformedPath`/`Renderer.applyRotation`),
    /// so hit-testing and resize math against the frame need the inverse of
    /// that same transform first.
    func toLocal(_ p: CGPoint, rotation: CGFloat, center: CGPoint) -> CGPoint {
        rotation == 0 ? p : Geo.rotate(p, around: center, degrees: -rotation)
    }

    // MARK: Rotation & mirror overlay handles


    var rotateHandlePoint: CGPoint? {
        guard let f = primaryElement?.frame else { return nil }
        return CGPoint(x: f.midX, y: f.minY - overlayHandleOffset)
    }

    /// Mirror handles only for kinds whose renderer honours flipX / flipY
    /// (elbow, swirl).
    var mirrorHandlePoints: (x: CGPoint, y: CGPoint)? {
        guard let el = primaryElement, el.kind == .elbow || el.kind == .swirl else { return nil }
        let f = el.frame
        return (CGPoint(x: f.minX - overlayHandleOffset, y: f.midY),
                CGPoint(x: f.midX, y: f.maxY + overlayHandleOffset))
    }

    func badgeRect(at c: CGPoint) -> CGRect {
        CGRect(x: c.x - overlayHandleSize / 2, y: c.y - overlayHandleSize / 2,
               width: overlayHandleSize, height: overlayHandleSize)
    }

    func overlayHandle(at p: CGPoint) -> OverlayHandle? {
        guard primaryElement != nil else { return nil }
        if let rp = rotateHandlePoint, badgeRect(at: rp).contains(p) { return .rotate }
        if let m = mirrorHandlePoints {
            if badgeRect(at: m.x).contains(p) { return .mirrorX }
            if badgeRect(at: m.y).contains(p) { return .mirrorY }
        }
        return nil
    }
}
