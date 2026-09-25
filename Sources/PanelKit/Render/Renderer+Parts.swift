import Foundation
import AppKit
import CoreGraphics
import CoreText

// Element → ShapeParts: the single source of truth for canvas, PNG and SVG.

extension Renderer {

    // MARK: Element → parts

    package static func parts(for el: PanelElement) -> [ShapePart] {
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
            var out: [ShapePart] = []

            // Position ring. The track is an open circle with its gap at the
            // bottom — the same ring-sector geometry the shape palette already
            // provides — and the value is a second sector drawn over it from
            // the track's start to the pointer.
            let style = Int(el.params.knobStyle.rounded())
            let showArc = style >= 1
            let showPointer = style != 1
            var seat = f
            if showArc {
                let track = max(1.5, el.params.arcWidth * min(f.width, f.height))
                let gap = max(1.0, f.width * 0.05)
                let span = min(max(el.params.arcSpan, 20), 350)
                let start = -90 - span / 2

                // Fold the stored angle into ±180 so 300° reads as −60° rather
                // than running off the end of the track.
                var rel = el.params.pointerAngle.truncatingRemainder(dividingBy: 360)
                if rel > 180 { rel -= 360 }
                if rel < -180 { rel += 360 }
                let sweep = min(max(rel + span / 2, 0), span)

                out.append(ShapePart(
                    path: ringSectorPath(f, thickness: track, startDeg: start, sweepDeg: span),
                    fill: accent.darkened(0.74)))
                if sweep > 0.5 {
                    out.append(ShapePart(
                        path: ringSectorPath(f, thickness: track, startDeg: start, sweepDeg: sweep),
                        fill: accent))
                }
                seat = f.insetBy(dx: track + gap, dy: track + gap)
            }

            let ringW = max(1.4, seat.width * 0.07)
            let body = seat.insetBy(dx: seat.width * 0.15, dy: seat.height * 0.15)
            let a = Geo.deg2rad(el.params.pointerAngle - 90)
            let r = body.width / 2
            let c = CGPoint(x: body.midX, y: body.midY)
            let p = CGMutablePath()
            p.move(to: CGPoint(x: c.x + cos(a) * r * 0.12, y: c.y + sin(a) * r * 0.12))
            p.addLine(to: CGPoint(x: c.x + cos(a) * r * 0.62, y: c.y + sin(a) * r * 0.62))
            let capR = body.width * 0.11
            let cap = CGRect(x: c.x - capR, y: c.y - capR, width: capR * 2, height: capR * 2)

            out.append(ShapePart(path: ellipsePath(seat), fill: accent.darkened(0.75),
                                 stroke: accent, lineWidth: ringW))
            out.append(ShapePart(path: ellipsePath(body), fill: accent.darkened(0.42)))
            if showPointer {
                out.append(ShapePart(path: p, stroke: accent.lightened(0.55),
                                     lineWidth: max(1.4, seat.width * 0.05), rotates: true))
            }
            out.append(ShapePart(path: ellipsePath(cap), fill: accent.lightened(0.30), rotates: true))
            return out

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
            // Value drives the pressed state, the same way it selects a button
            // group's position: a button exports as two frames and Rack swaps
            // them, so the artwork has to be able to draw both.
            let down = el.params.value >= 0.5
            let cap = f.insetBy(dx: f.width * (down ? 0.24 : 0.18),
                                dy: f.height * (down ? 0.24 : 0.18))
            var ps: [ShapePart] = [
                ShapePart(path: roundedRectPath(f, tl: 2, tr: 2, br: 2, bl: 2),
                          fill: el.fill.darkened(0.6), stroke: ColorSpec.hex("#0B0C10")),
                ShapePart(path: roundedRectPath(cap, tl: 1.5, tr: 1.5, br: 1.5, bl: 1.5),
                          fill: down ? el.fill.lightened(0.18) : el.fill),
            ]
            if !down {
                // The glint is what a raised cap looks like; a pressed one has
                // no highlight to catch.
                ps.append(ShapePart(path: roundedRectPath(
                    CGRect(x: cap.minX + cap.width * 0.2, y: cap.minY + cap.height * 0.14,
                           width: cap.width * 0.6, height: cap.height * 0.3),
                    tl: 1, tr: 1, br: 1, bl: 1), fill: el.fill.lightened(0.35)))
            }
            return ps
        case .buttonGroup:
            let n = max(2, min(12, Int(el.params.segments.rounded())))
            // Radius and end-cap insets hug the frame, so the art stays inside
            // the selection outline. Note: the cross layout is always 4 caps.
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
                let span = max(f.width - r * 2, 0)
                positions = (0..<n).map {
                    CGPoint(x: f.minX + r + span * CGFloat($0) / CGFloat(n - 1), y: c.y)
                }
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
                let span = max(f.height - r * 2, 0)
                positions = (0..<n).map {
                    CGPoint(x: c.x, y: f.minY + r + span * CGFloat($0) / CGFloat(n - 1))
                }
            }
            // Which position is on. A switch is exported as one SVG per
            // position — Rack's SvgSwitch picks the frame by parameter value —
            // so the artwork has to be able to draw any of them, and Value is
            // what selects it here and in the inspector.
            let selected = Int((el.params.value * CGFloat(n - 1)).rounded())

            var gs: [ShapePart] = []
            for (index, p) in positions.enumerated() {
                let on = index == selected
                let outer = CGRect(x: p.x - r, y: p.y - r, width: r * 2, height: r * 2)
                let capR = r * 0.74
                let cap = CGRect(x: p.x - capR, y: p.y - capR, width: capR * 2, height: capR * 2)
                let glint = CGRect(x: p.x - r * 0.34, y: p.y - r * 0.5, width: r * 0.68, height: r * 0.52)
                gs.append(ShapePart(path: CGPath(ellipseIn: outer, transform: nil),
                                    fill: el.fill.darkened(0.55), stroke: ColorSpec.hex("#0B0C10")))
                gs.append(ShapePart(path: CGPath(ellipseIn: cap, transform: nil),
                                    fill: on ? el.fill : el.fill.darkened(0.42)))
                if on {
                    gs.append(ShapePart(path: CGPath(ellipseIn: glint, transform: nil),
                                        fill: el.fill.lightened(0.35)))
                }
            }
            return gs
        case .led:
            // Dome-shaped lens: a dark bezel (shares the jack body's
            // "ink" tone) holds a lens that fills most of the frame,
            // with an offset highlight/shadow pair faking curvature --
            // this renderer has no gradient primitive, so "dome" is
            // three flat circles, not a radial fill.
            var halo = accent; halo.a = 0.35
            let haloW = max(1.0, f.width * 0.06)
            let bezel = f.insetBy(dx: f.width * 0.06, dy: f.height * 0.06)
            let lens = f.insetBy(dx: f.width * 0.16, dy: f.height * 0.16)
            let lensR = lens.width / 2
            let hlOffset = lensR * 0.32
            let highlightR = lensR * 0.5
            let highlight = CGRect(x: lens.midX - hlOffset - highlightR, y: lens.midY - hlOffset - highlightR,
                                   width: highlightR * 2, height: highlightR * 2)
            let shadowR = lensR * 0.85
            let shadowOffset = hlOffset * 0.6
            let shadow = CGRect(x: lens.midX + shadowOffset - shadowR, y: lens.midY + shadowOffset - shadowR,
                                width: shadowR * 2, height: shadowR * 2)
            return [
                ShapePart(path: ellipsePath(f), fill: nil, stroke: halo, lineWidth: haloW),
                ShapePart(path: ellipsePath(bezel), fill: nearBlack),
                ShapePart(path: ellipsePath(lens), fill: accent),
                ShapePart(path: ellipsePath(shadow), fill: accent.darkened(0.28)),
                ShapePart(path: ellipsePath(highlight), fill: accent.lightened(0.55)),
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
            let notchEdge = Int(el.params.notchEdge.rounded())
            let boxPath: CGPath
            if notchEdge >= 1, notchEdge <= 4, el.params.notchLength > 0, el.params.notchDepth > 0 {
                boxPath = notchedBoxPath(f,
                                         tl: el.params.cornerTL, tr: el.params.cornerTR,
                                         br: el.params.cornerBR, bl: el.params.cornerBL,
                                         edge: notchEdge, start: el.params.notchStart,
                                         length: el.params.notchLength, depth: el.params.notchDepth,
                                         notchRadius: el.params.notchRadius, invert: el.params.notchInvert)
            } else {
                boxPath = roundedRectPath(f,
                                          tl: el.params.cornerTL, tr: el.params.cornerTR,
                                          br: el.params.cornerBR, bl: el.params.cornerBL)
            }
            return [ShapePart(path: boxPath, fill: accent, stroke: el.stroke, lineWidth: el.strokeWidth)]

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

        case .line:
            // Stroke only -- a line has no area, so fill never applies here
            // regardless of what the element's own fill colour happens to be.
            return [ShapePart(path: linePath(f, bow: el.params.lineBow),
                              fill: nil, stroke: el.stroke, lineWidth: max(0.25, el.strokeWidth))]

        case .elbow:
            return [ShapePart(
                path: elbowPath(f,
                                thickness: el.params.thickness,
                                thicknessV: el.params.thicknessV,
                                innerRi: el.params.innerRadius,
                                armH: el.params.armH,
                                armV: el.params.armV,
                                flipX: el.params.flipX,
                                flipY: el.params.flipY),
                fill: accent, stroke: el.stroke, lineWidth: el.strokeWidth)]

        case .swirl:
            return [ShapePart(
                path: swirlPath(f,
                                thickness: el.params.thickness,
                                thicknessV: el.params.thicknessV,
                                innerRi: el.params.innerRadius,
                                armH: el.params.armH,
                                armH2: el.params.armH2,
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

        case .symbol:
            return [ShapePart(path: SymbolCatalogue.path(for: el), fill: accent,
                              stroke: el.stroke, lineWidth: el.strokeWidth)]

        case .path:
            return importedParts(for: el)

        case .text:
            return textParts(for: el)
        }
    }

    // MARK: Imported paths

    /// Parsed `d` strings, keyed by the string itself. An imported panel is a
    /// few hundred paths and the canvas redraws on every mouse move; re-parsing
    /// all of them per frame is the difference between usable and not.
    private static var importCache: [String: CGPath] = [:]

    /// An imported path, scaled from its unit box into the element's frame.
    /// That is what makes dragging a corner resize the artwork rather than
    /// crop it.
    package static func importedParts(for el: PanelElement) -> [ShapePart] {
        guard let d = el.pathData, !d.isEmpty else { return [] }
        let unit: CGPath
        if let hit = importCache[d] {
            unit = hit
        } else {
            guard let parsed = SVGPath.path(fromD: d) else { return [] }
            if importCache.count > 2048 { importCache.removeAll() }
            importCache[d] = parsed
            unit = parsed
        }
        let f = el.frame
        var t = CGAffineTransform(scaleX: max(f.width, 0.01), y: max(f.height, 0.01))
            .concatenating(CGAffineTransform(translationX: f.minX, y: f.minY))
        guard let placed = unit.copy(using: &t) else { return [] }
        return [ShapePart(path: placed, fill: el.fill,
                          stroke: el.stroke, lineWidth: el.strokeWidth)]
    }

    /// Splits a knob's parts into the static body and the part Rack rotates,
    /// mirroring `RoundKnob`: a background `SvgWidget` added below the
    /// TransformWidget, with only the foreground turning.
    ///
    /// Split on each part's own `rotates` flag rather than on part ordering,
    /// so a knob can gain or lose pieces — a position ring, no pointer —
    /// without the export quietly rotating the wrong thing.
    ///
    /// The value arc deliberately lands in the background: Rack turns one SVG
    /// over a static one, and an arc that *grows* cannot be produced by
    /// rotation. CodeGen warns when a custom knob relies on it.
    package static func knobLayers(_ parts: [ShapePart]) -> (bg: [ShapePart], fg: [ShapePart])? {
        let fg = parts.filter { $0.rotates }
        guard !fg.isEmpty else { return nil }
        return (parts.filter { !$0.rotates }, fg)
    }
}
