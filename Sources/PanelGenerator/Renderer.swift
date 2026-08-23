import Foundation
import AppKit
import CoreGraphics

// MARK: - ShapePart
// One paintable piece of an element. Canvas, PNG and SVG exporters all consume
// exactly these, so what you see is what exports.

struct ShapePart {
    var path: CGPath
    var fill: ColorSpec?
    var stroke: ColorSpec?
    var lineWidth: CGFloat = 1
}

// MARK: - Renderer

enum Renderer {

    // MARK: Path builders

    static func ellipsePath(_ r: CGRect) -> CGPath {
        CGPath(ellipseIn: r, transform: nil)
    }

    static func roundedRectPath(_ f: CGRect,
                                tl: CGFloat, tr: CGFloat,
                                br: CGFloat, bl: CGFloat) -> CGPath {
        let maxR = min(f.width, f.height) / 2
        func cl(_ v: CGFloat) -> CGFloat { min(max(v, 0), maxR) }
        let TL = cl(tl), TR = cl(tr), BR = cl(br), BL = cl(bl)
        let p = CGMutablePath()
        p.move(to: CGPoint(x: f.minX + TL, y: f.minY))
        if TR > 0 {
            // addArc connects from the current point to the arc start automatically
            p.addArc(tangent1End: CGPoint(x: f.maxX, y: f.minY), tangent2End: CGPoint(x: f.maxX, y: f.minY + TR), radius: TR)
        } else {
            p.addLine(to: CGPoint(x: f.maxX, y: f.minY))
        }
        if BR > 0 {
            p.addArc(tangent1End: CGPoint(x: f.maxX, y: f.maxY), tangent2End: CGPoint(x: f.maxX - BR, y: f.maxY), radius: BR)
        } else {
            p.addLine(to: CGPoint(x: f.maxX, y: f.maxY))
        }
        if BL > 0 {
            p.addArc(tangent1End: CGPoint(x: f.minX, y: f.maxY), tangent2End: CGPoint(x: f.minX, y: f.maxY - BL), radius: BL)
        } else {
            p.addLine(to: CGPoint(x: f.minX, y: f.maxY))
        }
        if TL > 0 {
            p.addArc(tangent1End: CGPoint(x: f.minX, y: f.minY), tangent2End: CGPoint(x: f.minX + TL, y: f.minY), radius: TL)
        } else {
            p.addLine(to: CGPoint(x: f.minX, y: f.minY + TL))
        }
        p.closeSubpath()
        return p
    }

    /// LCARS elbow. Canonical orientation: corner at top-left, horizontal arm
    /// running right along the top, vertical arm running down the left side.
    /// Outer corner radius is derived as thickness + innerRadius (the classic
    /// Okudagram proportion). Flips mirror it into the other three corners.
    static func elbowPath(_ f: CGRect,
                          thickness t: CGFloat,
                          innerRi: CGFloat,
                          armH: CGFloat,
                          armV: CGFloat,
                          flipX: Bool,
                          flipY: Bool) -> CGPath {
        let th = max(2, t)
        let ri = max(0, min(innerRi, th))
        let ro = th + ri
        let W = max(armH + ro, ro * 2)
        let H = max(armV + ro, ro * 2)

        let p = CGMutablePath()
        p.move(to: CGPoint(x: W, y: 0))
        p.addLine(to: CGPoint(x: ro, y: 0))
        p.addArc(center: CGPoint(x: ro, y: ro), radius: ro,
                 startAngle: .pi * 1.5, endAngle: .pi, clockwise: true)   // 270°→180° (short way)
        p.addLine(to: CGPoint(x: 0, y: H))
        p.addLine(to: CGPoint(x: th, y: H))
        p.addLine(to: CGPoint(x: th, y: th + ri))
        p.addArc(center: CGPoint(x: th + ri, y: th + ri), radius: ri,
                 startAngle: .pi, endAngle: .pi * 1.5, clockwise: false)  // 180°→270° (short way)
        p.addLine(to: CGPoint(x: W, y: th))
        p.closeSubpath()

        let sx: CGFloat = (flipX ? -1 : 1) * f.width / W
        let sy: CGFloat = (flipY ? -1 : 1) * f.height / H
        var tr = CGAffineTransform(translationX: f.minX + (flipX ? f.width : 0),
                                   y: f.minY + (flipY ? f.height : 0))
        tr = tr.scaledBy(x: sx, y: sy)
        return p.copy(using: &tr) ?? p
    }

    /// Annulus arc (ring sector) inscribed in the frame — the big sweeping
    /// curved bands of the TNG aesthetic.
    static func ringSectorPath(_ f: CGRect,
                               thickness: CGFloat,
                               startDeg: CGFloat,
                               sweepDeg: CGFloat) -> CGPath {
        let c = CGPoint(x: f.midX, y: f.midY)
        let R = max(min(f.width, f.height) / 2, 1)
        let r = max(R - max(thickness, 1), 0.5)
        let a0 = Geo.deg2rad(startDeg)
        let a1 = Geo.deg2rad(startDeg + sweepDeg)
        let cw = sweepDeg < 0
        let p = CGMutablePath()
        p.move(to: CGPoint(x: c.x + R * cos(a0), y: c.y + R * sin(a0)))
        p.addArc(center: c, radius: R, startAngle: a0, endAngle: a1, clockwise: cw)
        p.addLine(to: CGPoint(x: c.x + r * cos(a1), y: c.y + r * sin(a1)))
        p.addArc(center: c, radius: r, startAngle: a1, endAngle: a0, clockwise: !cw)
        p.closeSubpath()
        return p
    }

    // MARK: Element → parts

    static func parts(for el: PanelElement) -> [ShapePart] {
        let f = el.frame
        let accent = el.fill
        let ink = ColorSpec.hex("#101216")
        let nearBlack = ColorSpec.hex("#050507")

        switch el.kind {

        case .jack:
            let ringW = max(1.4, f.width * 0.08)
            let face = f.insetBy(dx: f.width * 0.17, dy: f.height * 0.17)
            let holeR = f.width * 0.20
            let hole = CGRect(x: f.midX - holeR, y: f.midY - holeR, width: holeR * 2, height: holeR * 2)
            return [
                ShapePart(path: ellipsePath(f), fill: ink, stroke: accent, lineWidth: ringW),
                ShapePart(path: ellipsePath(face), fill: accent.darkened(0.62)),
                ShapePart(path: ellipsePath(hole), fill: nearBlack),
            ]

        case .knobLarge, .knobMedium, .knobSmall:
            let ringW = max(1.4, f.width * 0.07)
            let body = f.insetBy(dx: f.width * 0.15, dy: f.height * 0.15)
            let a = Geo.deg2rad(el.params.pointerAngle - 90)
            let r = body.width / 2
            let c = CGPoint(x: body.midX, y: body.midY)
            let p = CGMutablePath()
            p.move(to: CGPoint(x: c.x + cos(a) * r * 0.12, y: c.y + sin(a) * r * 0.12))
            p.addLine(to: CGPoint(x: c.x + cos(a) * r * 0.62, y: c.y + sin(a) * r * 0.62))
            let capR = body.width * 0.11
            let cap = CGRect(x: c.x - capR, y: c.y - capR, width: capR * 2, height: capR * 2)
            return [
                ShapePart(path: ellipsePath(f), fill: accent.darkened(0.75), stroke: accent, lineWidth: ringW),
                ShapePart(path: ellipsePath(body), fill: accent.darkened(0.42)),
                ShapePart(path: p, stroke: accent.lightened(0.55), lineWidth: max(1.4, f.width * 0.05)),
                ShapePart(path: ellipsePath(cap), fill: accent.lightened(0.30)),
            ]

        case .faderVertical:
            let trackW = min(7, f.width * 0.45)
            let track = CGRect(x: f.midX - trackW / 2, y: f.minY + f.height * 0.05,
                               width: trackW, height: f.height * 0.9)
            let hh = max(9, f.height * 0.14)
            let hy = f.maxY - hh - el.params.value * (f.height - hh)
            let handle = CGRect(x: f.minX + 1, y: hy, width: f.width - 2, height: hh)
            let groove = CGRect(x: handle.midX - handle.width * 0.32, y: handle.midY - 0.8,
                                width: handle.width * 0.64, height: 1.6)
            return [
                ShapePart(path: roundedRectPath(track, tl: trackW/2, tr: trackW/2, br: trackW/2, bl: trackW/2),
                          fill: ColorSpec.hex("#0B0C10"), stroke: ColorSpec.hex("#30333B"), lineWidth: 1),
                ShapePart(path: roundedRectPath(handle, tl: 2.5, tr: 2.5, br: 2.5, bl: 2.5),
                          fill: accent, stroke: ColorSpec.hex("#000000"), lineWidth: 1),
                ShapePart(path: roundedRectPath(groove, tl: 0.8, tr: 0.8, br: 0.8, bl: 0.8),
                          fill: ColorSpec.hex("#111318")),
            ]

        case .faderHorizontal:
            let trackH = min(7, f.height * 0.45)
            let track = CGRect(x: f.minX + f.width * 0.05, y: f.midY - trackH / 2,
                               width: f.width * 0.9, height: trackH)
            let hw = max(9, f.width * 0.14)
            let hx = f.minX + el.params.value * (f.width - hw)
            let handle = CGRect(x: hx, y: f.minY + 1, width: hw, height: f.height - 2)
            let groove = CGRect(x: handle.midX - 0.8, y: handle.midY - handle.height * 0.32,
                                width: 1.6, height: handle.height * 0.64)
            return [
                ShapePart(path: roundedRectPath(track, tl: trackH/2, tr: trackH/2, br: trackH/2, bl: trackH/2),
                          fill: ColorSpec.hex("#0B0C10"), stroke: ColorSpec.hex("#30333B"), lineWidth: 1),
                ShapePart(path: roundedRectPath(handle, tl: 2.5, tr: 2.5, br: 2.5, bl: 2.5),
                          fill: accent, stroke: ColorSpec.hex("#000000"), lineWidth: 1),
                ShapePart(path: roundedRectPath(groove, tl: 0.8, tr: 0.8, br: 0.8, bl: 0.8),
                          fill: ColorSpec.hex("#111318")),
            ]

        case .pushButton:
            let cap = f.insetBy(dx: f.width * 0.18, dy: f.height * 0.18)
            var ps: [ShapePart] = [
                ShapePart(path: roundedRectPath(f, tl: 2, tr: 2, br: 2, bl: 2),
                          fill: el.fill.darkened(0.6), stroke: ColorSpec.hex("#0B0C10")),
                ShapePart(path: roundedRectPath(cap, tl: 1.5, tr: 1.5, br: 1.5, bl: 1.5), fill: el.fill),
                ShapePart(path: roundedRectPath(
                    CGRect(x: cap.minX + cap.width * 0.2, y: cap.minY + cap.height * 0.14,
                           width: cap.width * 0.6, height: cap.height * 0.3),
                    tl: 1, tr: 1, br: 1, bl: 1), fill: el.fill.lightened(0.35)),
            ]
            _ = ps
            return ps
        case .buttonGroup:
            let n = max(2, min(12, Int(el.params.segments.rounded())))
            // Radius hugs the frame so the selection outline matches the art.
            let r: CGFloat
            switch Int(el.params.layout) {
            case 1:   r = min(f.height / 2 - 1.5, f.width / CGFloat(2 * n) - 1)      // row
            case 2,3: r = min(f.width, f.height) * 0.16 + 2.5                        // cross / ring
            default:  r = min(f.width / 2 - 1.5, f.height / CGFloat(2 * n) - 1.5)    // column
            }
            let c = CGPoint(x: f.midX, y: f.midY)
            let positions: [CGPoint]
            switch Int(el.params.layout) {
            case 1:
                positions = (0..<n).map { CGPoint(x: f.minX + f.width * CGFloat($0) / CGFloat(n - 1), y: c.y) }
            case 2:
                positions = [CGPoint(x: c.x, y: f.minY + r + 2), CGPoint(x: c.x, y: f.maxY - r - 2),
                             CGPoint(x: f.minX + r + 2, y: c.y), CGPoint(x: f.maxX - r - 2, y: c.y)]
            case 3:
                positions = (0..<n).map { i in
                    let a = CGFloat(i) / CGFloat(n) * 2 * .pi - .pi / 2
                    let rad = min(f.width, f.height) / 2 - r - 2
                    return CGPoint(x: c.x + rad * cos(a), y: c.y + rad * sin(a))
                }
            default:
                positions = (0..<n).map { CGPoint(x: c.x, y: f.minY + f.height * CGFloat($0) / CGFloat(n - 1)) }
            }
            var gs: [ShapePart] = []
            for p in positions {
                let outer = CGRect(x: p.x - r, y: p.y - r, width: r * 2, height: r * 2)
                let capR = r * 0.74
                let cap = CGRect(x: p.x - capR, y: p.y - capR, width: capR * 2, height: capR * 2)
                let glint = CGRect(x: p.x - r * 0.34, y: p.y - r * 0.5, width: r * 0.68, height: r * 0.52)
                gs.append(ShapePart(path: CGPath(ellipseIn: outer, transform: nil),
                                    fill: el.fill.darkened(0.55), stroke: ColorSpec.hex("#0B0C10")))
                gs.append(ShapePart(path: CGPath(ellipseIn: cap, transform: nil), fill: el.fill))
                gs.append(ShapePart(path: CGPath(ellipseIn: glint, transform: nil),
                                    fill: el.fill.lightened(0.35)))
            }
            return gs
        case .led:
            let haloW = max(1.2, f.width * 0.11)
            let core = f.insetBy(dx: f.width * 0.28, dy: f.height * 0.28)
            let glintR = max(f.width * 0.10, 0.8)
            let glint = CGRect(x: f.minX + f.width * 0.30 - glintR, y: f.minY + f.height * 0.30 - glintR,
                               width: glintR * 2, height: glintR * 2)
            var halo = accent; halo.a = 0.45
            return [
                ShapePart(path: ellipsePath(f), fill: nil, stroke: halo, lineWidth: haloW),
                ShapePart(path: ellipsePath(core), fill: accent),
                ShapePart(path: ellipsePath(glint), fill: ColorSpec(r: 1, g: 1, b: 1, a: 0.85)),
            ]

        case .screw:
            let slot = CGMutablePath()
            slot.move(to: CGPoint(x: f.minX + f.width * 0.26, y: f.minY + f.height * 0.26))
            slot.addLine(to: CGPoint(x: f.maxX - f.width * 0.26, y: f.maxY - f.height * 0.26))
            return [
                ShapePart(path: ellipsePath(f), fill: accent,
                          stroke: ColorSpec.hex("#4A4F58"), lineWidth: 1),
                ShapePart(path: slot, stroke: ColorSpec.hex("#33373E"),
                          lineWidth: max(1.3, f.width * 0.10)),
            ]

        case .box:
            return [ShapePart(
                path: roundedRectPath(f,
                                      tl: el.params.cornerTL, tr: el.params.cornerTR,
                                      br: el.params.cornerBR, bl: el.params.cornerBL),
                fill: accent, stroke: el.stroke, lineWidth: el.strokeWidth)]

        case .ellipse:
            return [ShapePart(path: ellipsePath(f), fill: accent,
                              stroke: el.stroke, lineWidth: el.strokeWidth)]

        case .triangle:
            let p = CGMutablePath()
            p.move(to: CGPoint(x: f.midX, y: f.minY))
            p.addLine(to: CGPoint(x: f.maxX, y: f.maxY))
            p.addLine(to: CGPoint(x: f.minX, y: f.maxY))
            p.closeSubpath()
            return [ShapePart(path: p, fill: accent, stroke: el.stroke, lineWidth: el.strokeWidth)]

        case .elbow:
            return [ShapePart(
                path: elbowPath(f,
                                thickness: el.params.thickness,
                                innerRi: el.params.innerRadius,
                                armH: el.params.armH,
                                armV: el.params.armV,
                                flipX: el.params.flipX,
                                flipY: el.params.flipY),
                fill: accent, stroke: el.stroke, lineWidth: el.strokeWidth)]

        case .ringSector:
            return [ShapePart(
                path: ringSectorPath(f,
                                     thickness: el.params.thickness,
                                     startDeg: el.params.startAngle,
                                     sweepDeg: el.params.sweepAngle),
                fill: accent, stroke: el.stroke, lineWidth: el.strokeWidth)]

        case .text:
            return []   // drawn separately (vector text in canvas/PNG, <text> in SVG)
        }
    }

    // MARK: Drawing

    static func drawBackground(_ doc: PanelDocument, in ctx: CGContext) {
        ctx.setFillColor(doc.background.nsColor.cgColor)
        ctx.fill(CGRect(origin: .zero, size: doc.pixelSize))
    }

    static func applyRotation(_ el: PanelElement, _ ctx: CGContext) {
        guard el.rotation != 0 else { return }
        let c = el.center
        ctx.translateBy(x: c.x, y: c.y)
        ctx.rotate(by: Geo.deg2rad(el.rotation))
        ctx.translateBy(x: -c.x, y: -c.y)
    }

    static func draw(_ el: PanelElement, in ctx: CGContext) {
        ctx.saveGState()
        applyRotation(el, ctx)
        if el.kind == .text {
            drawText(el, in: ctx)
        } else {
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
        }
        ctx.restoreGState()
    }

    static func drawText(_ el: PanelElement, in ctx: CGContext) {
        let font = NSFont.systemFont(ofSize: max(4, el.params.fontSize),
                                     weight: el.params.bold ? .semibold : .regular)
        let attrs: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: el.fill.nsColor,
        ]
        let str = NSString(string: el.params.text)
        let size = str.size(withAttributes: attrs)
        let pt = NSPoint(x: el.frame.midX - size.width / 2,
                         y: el.frame.midY - size.height / 2)
        str.draw(at: pt, withAttributes: attrs)
    }
}
