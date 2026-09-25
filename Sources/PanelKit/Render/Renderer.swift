import Foundation
import AppKit
import CoreGraphics
import CoreText

// MARK: - ShapePart
// One paintable piece of an element. Canvas, PNG and SVG exporters all consume
// exactly these, so what you see is what exports.

package struct ShapePart {
    package var path: CGPath
    package var fill: ColorSpec?
    package var stroke: ColorSpec?
    package var lineWidth: CGFloat = 1
    /// Marks the parts of a knob that turn with the parameter. Rack's SvgKnob
    /// rotates one SVG over a static background, so the split has to be
    /// declared here rather than guessed from part ordering.
    package var rotates: Bool = false
}

// MARK: - Renderer

package enum Renderer {

    // MARK: Drawing

    package static func drawBackground(_ doc: PanelDocument, in ctx: CGContext, variant: ThemeVariant = .dark) {
        ctx.setFillColor(doc.paper(for: variant).nsColor.cgColor)
        ctx.fill(CGRect(origin: .zero, size: doc.pixelSize))
    }

    package static func applyRotation(_ el: PanelElement, _ ctx: CGContext) {
        guard el.rotation != 0 else { return }
        let c = el.center
        ctx.translateBy(x: c.x, y: c.y)
        ctx.rotate(by: Geo.deg2rad(el.rotation))
        ctx.translateBy(x: -c.x, y: -c.y)
    }

    /// `doc`/`variant` are only consulted for an element with `followsInk`
    /// set -- everything else draws in its own literal `fill`, exactly as
    /// before this parameter existed. Passing no `doc` (every call site that
    /// predates theming) is therefore a no-op: `followsInk` elements simply
    /// keep whatever colour their `fill` already holds.
    package static func draw(_ el: PanelElement, in ctx: CGContext, doc: PanelDocument? = nil, variant: ThemeVariant = .dark) {
        ctx.saveGState()
        applyRotation(el, ctx)
        let el = doc?.resolved(el, for: variant) ?? el
        // No special case for text any more — it is outlines like everything else.
        for part in parts(for: el) {
            if let fl = part.fill {
                ctx.saveGState()
                ctx.addPath(part.path)
                ctx.setFillColor(fl.nsColor.cgColor)
                ctx.fillPath()
                ctx.restoreGState()
            }
            if let st = part.stroke {
                ctx.saveGState()
                ctx.addPath(part.path)
                ctx.setStrokeColor(st.nsColor.cgColor)
                ctx.setLineWidth(part.lineWidth)
                ctx.strokePath()
                ctx.restoreGState()
            }
        }
        ctx.restoreGState()
    }
}
