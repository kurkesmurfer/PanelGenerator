import Foundation
import CoreGraphics

// Shape operations: combining shapes, converting to editable freeform shapes,
// and turning a stroke into a filled outline. All geometry comes from the
// renderer, so what is combined is exactly what is drawn.

package enum ShapeOperation: String, CaseIterable {
    case combine, subtract, intersect, exclude

    package var displayName: String {
        switch self {
        case .combine:   return "Combine"
        case .subtract:  return "Subtract Front from Back"
        case .intersect: return "Intersect"
        case .exclude:   return "Exclude Overlap"
        }
    }
}

package enum ShapeOperationError: LocalizedError {
    case needsTwo, empty, nothingToConvert, noStroke

    package var errorDescription: String? {
        switch self {
        case .needsTwo:         return "Select two or more shapes to combine."
        case .empty:            return "The result would be empty — the shapes do not overlap that way."
        case .nothingToConvert: return "Nothing in the selection can become a freeform shape. Jacks, knobs, faders "
                                     + "and other controls are drawn by Rack and stay as they are."
        case .noStroke:         return "None of the selected shapes has a stroke to outline."
        }
    }
}

extension PanelElement {

    /// Kinds whose drawing is artwork that can become a freeform shape.
    package var isConvertibleToPath: Bool {
        switch kind {
        case .box, .ellipse, .triangle, .line, .elbow, .swirl, .ringSector, .symbol, .path, .text:
            return true
        default:
            return false
        }
    }

    /// What the element draws, as one path in panel coordinates with its
    /// rotation applied. Filled parts are united; a part that is only stroked
    /// (a line) contributes its stroke's outline when `outlineStrokes` is set,
    /// otherwise its centre line.
    package func renderedGeometry(outlineStrokes: Bool) -> CGPath {
        let parts = kind == .path ? Renderer.importedParts(for: self) : Renderer.parts(for: self)
        var result: CGPath? = nil
        let lines = CGMutablePath()
        for part in parts {
            let filled = (part.fill?.a ?? 0) > 0.001
            if filled {
                result = result.map { $0.union(part.path) } ?? part.path
            } else if part.stroke != nil {
                if outlineStrokes {
                    let o = part.path.copy(strokingWithWidth: part.lineWidth, lineCap: .butt,
                                           lineJoin: .miter, miterLimit: 10)
                    result = result.map { $0.union(o) } ?? o
                } else {
                    lines.addPath(part.path)
                }
            }
        }
        var geometry: CGPath = result ?? lines
        if result != nil, !lines.isEmpty {
            let m = CGMutablePath(); m.addPath(geometry); m.addPath(lines); geometry = m
        }
        guard rotation != 0 else { return geometry }
        var t = CGAffineTransform(translationX: center.x, y: center.y)
            .rotated(by: Geo.deg2rad(rotation))
            .translatedBy(x: -center.x, y: -center.y)
        return geometry.copy(using: &t) ?? geometry
    }

    /// The paint a converted shape keeps: a filled shape keeps its fill and
    /// stroke; a stroke-only one (a line) keeps its stroke and stays unfilled.
    fileprivate var convertedAppearance: (fill: ColorSpec, stroke: ColorSpec?, width: CGFloat) {
        let parts = kind == .path ? Renderer.importedParts(for: self) : Renderer.parts(for: self)
        let firstFilled = parts.first { ($0.fill?.a ?? 0) > 0.001 }
        let firstStroked = parts.first { $0.stroke != nil }
        return (firstFilled?.fill ?? ColorSpec(r: 0, g: 0, b: 0, a: 0),
                firstStroked?.stroke,
                firstStroked?.lineWidth ?? strokeWidth)
    }
}

extension PanelDocument {

    /// Combines the shapes in `ids` into one freeform shape. The result takes
    /// the place, identity (so labels still point at it) and appearance of the
    /// back-most shape; the others are removed. Subtract removes everything in
    /// front from the back-most.
    package mutating func combine(ids: Set<UUID>, _ op: ShapeOperation) throws -> UUID {
        let picked = elements.filter { ids.contains($0.id) && $0.isConvertibleToPath }
        guard picked.count >= 2, let back = picked.first else { throw ShapeOperationError.needsTwo }
        let paths = picked.map { $0.renderedGeometry(outlineStrokes: true) }
        var result: CGPath
        switch op {
        case .combine:
            result = paths.dropFirst().reduce(paths[0]) { $0.union($1) }
        case .subtract:
            let front = paths.dropFirst().dropFirst().reduce(paths[1]) { $0.union($1) }
            result = paths[0].subtracting(front)
        case .intersect:
            result = paths.dropFirst().reduce(paths[0]) { $0.intersection($1) }
        case .exclude:
            result = paths.dropFirst().reduce(paths[0]) { $0.symmetricDifference($1) }
        }
        guard !result.isEmpty, !result.boundingBoxOfPath.isEmpty else { throw ShapeOperationError.empty }

        let look = back.convertedAppearance
        var el = back
        el.kind = .path
        el.params = ElementParams()
        el.rotation = 0
        el.setPath(result)
        el.fill = look.fill.a > 0.001 ? look.fill : (look.stroke ?? .swatch("Orange"))
        el.stroke = look.fill.a > 0.001 ? look.stroke : nil
        el.strokeWidth = look.width
        if el.name == back.kind.displayName { el.name = "Shape" }

        let others = Set(picked.dropFirst().map(\.id))
        elements = elements.compactMap { e in
            if e.id == back.id { return el }
            return others.contains(e.id) ? nil : e
        }
        return back.id
    }

    /// Turns each convertible element into a freeform shape that draws the
    /// same, keeping its id, place in the layer order and paint. Returns how
    /// many were converted.
    @discardableResult
    package mutating func convertToPath(ids: Set<UUID>) throws -> Int {
        var n = 0
        for i in elements.indices where ids.contains(elements[i].id) {
            let old = elements[i]
            guard old.isConvertibleToPath, old.kind != .path || old.rotation != 0 else { continue }
            let geometry = old.renderedGeometry(outlineStrokes: false)
            guard !geometry.isEmpty else { continue }
            let look = old.convertedAppearance
            var el = old
            el.kind = .path
            el.params = ElementParams()
            el.rotation = 0
            el.setPath(geometry)
            el.fill = look.fill
            el.stroke = look.stroke
            el.strokeWidth = look.width
            if el.name == old.kind.displayName { el.name = "Shape" }
            elements[i] = el
            n += 1
        }
        guard n > 0 else { throw ShapeOperationError.nothingToConvert }
        return n
    }

    /// Replaces each stroked shape's stroke with a filled outline of it. A
    /// shape that is also filled keeps its fill, and the outline is added as a
    /// new shape just above it. Returns the ids of the outlines.
    @discardableResult
    package mutating func outlineStroke(ids: Set<UUID>) throws -> [UUID] {
        var made: [UUID] = []
        var out: [PanelElement] = []
        for old in elements {
            guard ids.contains(old.id), old.isConvertibleToPath, let stroke = old.stroke, old.strokeWidth > 0
            else { out.append(old); continue }
            var line = old
            line.fill = ColorSpec(r: 0, g: 0, b: 0, a: 0)
            let outline = line.renderedGeometry(outlineStrokes: true)
            guard !outline.isEmpty else { out.append(old); continue }
            var shape = old
            shape.kind = .path
            shape.params = ElementParams()
            shape.rotation = 0
            shape.setPath(outline)
            shape.fill = stroke
            shape.stroke = nil
            // Filled as drawn, not as stored: a line ignores its fill colour.
            let drawsFill = (old.kind == .path ? Renderer.importedParts(for: old) : Renderer.parts(for: old))
                .contains { ($0.fill?.a ?? 0) > 0.001 }
            if drawsFill {
                var kept = old
                kept.stroke = nil
                out.append(kept)
                shape.id = UUID()
                shape.role = .decoration
                shape.enumName = ""
                shape.labelOwner = nil
                shape.name = "Outline of \(old.name)"
            } else if shape.name == old.kind.displayName {
                shape.name = "Shape"
            }
            out.append(shape)
            made.append(shape.id)
        }
        guard !made.isEmpty else { throw ShapeOperationError.noStroke }
        elements = out
        return made
    }
}
