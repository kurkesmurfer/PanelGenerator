import Foundation
import AppKit
import CoreGraphics
import CoreText

// MARK: - ShapePart
// One paintable piece of an element. Canvas, PNG and SVG exporters all consume
// exactly these, so what you see is what exports.

struct ShapePart {
    var path: CGPath
    var fill: ColorSpec?
    var stroke: ColorSpec?
    var lineWidth: CGFloat = 1
    /// Marks the parts of a knob that turn with the parameter. Rack's SvgKnob
    /// rotates one SVG over a static background, so the split has to be
    /// declared here rather than guessed from part ordering.
    var rotates: Bool = false
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
            let cap = f.insetBy(dx: f.width * 0.18, dy: f.height * 0.18)
            let ps: [ShapePart] = [
                ShapePart(path: roundedRectPath(f, tl: 2, tr: 2, br: 2, bl: 2),
                          fill: el.fill.darkened(0.6), stroke: ColorSpec.hex("#0B0C10")),
                ShapePart(path: roundedRectPath(cap, tl: 1.5, tr: 1.5, br: 1.5, bl: 1.5), fill: el.fill),
                ShapePart(path: roundedRectPath(
                    CGRect(x: cap.minX + cap.width * 0.2, y: cap.minY + cap.height * 0.14,
                           width: cap.width * 0.6, height: cap.height * 0.3),
                    tl: 1, tr: 1, br: 1, bl: 1), fill: el.fill.lightened(0.35)),
            ]
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
    static func importedParts(for el: PanelElement) -> [ShapePart] {
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
    static func knobLayers(_ parts: [ShapePart]) -> (bg: [ShapePart], fg: [ShapePart])? {
        let fg = parts.filter { $0.rotates }
        guard !fg.isEmpty else { return nil }
        return (parts.filter { !$0.rotates }, fg)
    }

    // MARK: Text → outlines
    //
    // Labels become real glyph outlines rather than an SVG <text> element:
    // VCV Rack renders panels through nanosvg, which has no text support and
    // drops <text> silently — every label would vanish on load. Outlines also
    // put text on the same ShapePart path as everything else, so canvas, PNG
    // and SVG stay identical by construction instead of by coincidence.

    private struct TextKey: Hashable {
        let text: String
        let size: CGFloat
        let bold: Bool
    }

    /// Glyph outlines laid out with the baseline at the origin, already
    /// mirrored into the panel's y-down space.
    private struct TextOutline {
        let path: CGPath
        let advance: CGFloat
        let capHeight: CGFloat
    }

    /// Keyed on text/size/weight only — never on the frame — so dragging a
    /// label does not grow the cache. Main-thread only, like the rest of the
    /// drawing code.
    private static var outlineCache: [TextKey: TextOutline] = [:]

    /// Size a text element's own drawing wants: the advance of the laid-out
    /// line by its cap height, padded so the frame stays grabbable. Needed when
    /// a label is created in code and has no frame to inherit — the glyph run,
    /// not the string length, is what decides the width.
    static func textSize(for el: PanelElement) -> CGSize {
        guard let o = outline(for: el) else {
            return CGSize(width: max(8, el.params.fontSize * 2),
                          height: max(8, el.params.fontSize * 1.4))
        }
        return CGSize(width: max(8, o.advance + el.params.fontSize * 0.3),
                      height: max(8, o.capHeight * 1.5))
    }

    static func textParts(for el: PanelElement) -> [ShapePart] {
        guard let o = outline(for: el) else { return [] }
        // Centre the cap-height box in the frame: visually centred for the
        // all-caps labels these panels are actually made of.
        var t = CGAffineTransform(translationX: el.frame.midX - o.advance / 2,
                                  y: el.frame.midY + o.capHeight / 2)
        guard let placed = o.path.copy(using: &t) else { return [] }
        return [ShapePart(path: placed, fill: el.fill)]
    }

    /// A text element is a sequence of literal runs and glyph tokens. `{ka}`
    /// anywhere in the string places the Ka glyph inline, sized to cap height
    /// so it sits on the baseline with the Latin characters around it.
    private enum TextSegment {
        case literal(String)
        case glyph(String)      // a SymbolCatalogue id in the .glyph category
    }

    private static func segments(of text: String) -> [TextSegment] {
        var out: [TextSegment] = []
        var literal = ""
        var i = text.startIndex

        while i < text.endIndex {
            if text[i] == "{", let close = text[i...].firstIndex(of: "}") {
                let name = String(text[text.index(after: i)..<close]).lowercased()
                if let spec = SymbolCatalogue.all.first(where: {
                    $0.category == .glyph && $0.id.lowercased() == "glyph" + name
                }) {
                    if !literal.isEmpty { out.append(.literal(literal)); literal = "" }
                    out.append(.glyph(spec.id))
                    i = text.index(after: close)
                    continue
                }
                // Not a glyph name — leave the brace alone rather than eating it.
            }
            literal.append(text[i])
            i = text.index(after: i)
        }
        if !literal.isEmpty { out.append(.literal(literal)) }
        return out
    }

    /// One glyph as a filled ribbon in a `side` × `side` box, top-left at the
    /// origin. Same construction as a Symbol element, so a glyph typed into a
    /// label and one dropped from the palette are the same shape.
    private static func glyphOutline(_ id: String, side: CGFloat) -> CGPath? {
        guard side > 1 else { return nil }
        let weight = SymbolCatalogue.defaultWeight
        let inset = weight / 2
        let box = CGRect(x: inset, y: inset, width: 1 - inset * 2, height: 1 - inset * 2)
        let spec = SymbolCatalogue.spec(id)
        let unit = spec.centreline(SymbolContext(box: box, p: spec.defaults))

        var scale = CGAffineTransform(scaleX: side, y: side)
        guard let scaled = unit.copy(using: &scale) else { return nil }
        let px = max(SymbolCatalogue.minWeightPixels, weight * side)
        return scaled.copy(strokingWithWidth: px, lineCap: .round, lineJoin: .round, miterLimit: 4)
    }

    /// Outlines for one literal run, baseline at the origin, y-down.
    private static func literalOutline(_ text: String, font nsFont: NSFont) -> (CGPath, CGFloat) {
        let ctFont = nsFont as CTFont
        let line = CTLineCreateWithAttributedString(
            NSAttributedString(string: text, attributes: [.font: nsFont]))
        let advance = CGFloat(CTLineGetTypographicBounds(line, nil, nil, nil))

        let out = CGMutablePath()
        for run in (CTLineGetGlyphRuns(line) as? [CTRun] ?? []) {
            // A run can carry a substituted font (accents, symbols); fall back
            // to ours rather than dropping the glyph.
            let attrs = CTRunGetAttributes(run) as NSDictionary
            let runFont = (attrs[kCTFontAttributeName as String] as? NSFont)
                .map { $0 as CTFont } ?? ctFont

            let n = CTRunGetGlyphCount(run)
            guard n > 0 else { continue }
            var glyphs = [CGGlyph](repeating: 0, count: n)
            var pos = [CGPoint](repeating: .zero, count: n)
            CTRunGetGlyphs(run, CFRangeMake(0, n), &glyphs)
            CTRunGetPositions(run, CFRangeMake(0, n), &pos)

            for i in 0..<n {
                guard let g = CTFontCreatePathForGlyph(runFont, glyphs[i], nil) else { continue }
                // Glyph outlines are y-up with the origin on the baseline; the
                // panel is y-down, so mirror each glyph as it is placed.
                var t = CGAffineTransform(translationX: pos[i].x, y: -pos[i].y)
                t = t.scaledBy(x: 1, y: -1)
                out.addPath(g, transform: t)
            }
        }
        return (out, advance)
    }

    private static func outline(for el: PanelElement) -> TextOutline? {
        let key = TextKey(text: el.params.text,
                          size: max(4, el.params.fontSize),
                          bold: el.params.bold)
        guard !key.text.isEmpty else { return nil }
        if let hit = outlineCache[key] { return hit }

        let nsFont = NSFont.systemFont(ofSize: key.size, weight: key.bold ? .semibold : .regular)
        let capHeight = CTFontGetCapHeight(nsFont as CTFont)

        let out = CGMutablePath()
        var x: CGFloat = 0
        for segment in segments(of: key.text) {
            switch segment {
            case .literal(let run):
                let (path, advance) = literalOutline(run, font: nsFont)
                var t = CGAffineTransform(translationX: x, y: 0)
                if let placed = path.copy(using: &t) { out.addPath(placed) }
                x += advance

            case .glyph(let id):
                // Square, cap height, sitting on the baseline: y = -capHeight is
                // the top of the box in the panel's y-down space.
                if let g = glyphOutline(id, side: capHeight) {
                    var t = CGAffineTransform(translationX: x, y: -capHeight)
                    if let placed = g.copy(using: &t) { out.addPath(placed) }
                }
                x += capHeight * 1.14   // the glyph plus a little tracking
            }
        }

        let result = TextOutline(path: out, advance: x, capHeight: capHeight)
        if outlineCache.count > 512 { outlineCache.removeAll() }
        outlineCache[key] = result
        return result
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
