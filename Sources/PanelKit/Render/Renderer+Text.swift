import Foundation
import AppKit
import CoreGraphics
import CoreText

// Text as glyph outlines (nanosvg has no <text>).

extension Renderer {

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
    package static func textSize(for el: PanelElement) -> CGSize {
        guard let o = outline(for: el) else {
            return CGSize(width: max(8, el.params.fontSize * 2),
                          height: max(8, el.params.fontSize * 1.4))
        }
        return CGSize(width: max(8, o.advance + el.params.fontSize * 0.3),
                      height: max(8, o.capHeight * 1.5))
    }

    package static func textParts(for el: PanelElement) -> [ShapePart] {
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
}
