import Foundation
import CoreGraphics
import AppKit

// Whole-selection edits: uniform views, colours, alignment, bulk binding.

extension PanelDocument {

    /// The element whose values stand in for a homogeneous multi-selection.
    ///
    /// nil unless every selected element is the same kind — and, for symbols,
    /// the same symbol — because otherwise the inspector's rows would not mean
    /// the same thing for every element it is about to write to. Returns in
    /// document order, so the stand-in does not change between rebuilds.
    package func uniformSelection(ids: Set<UUID>) -> PanelElement? {
        let selected = elements.filter { ids.contains($0.id) }
        guard selected.count > 1, let first = selected.first else { return nil }
        guard selected.allSatisfy({ $0.kind == first.kind }) else { return nil }
        if first.kind == .symbol {
            guard selected.allSatisfy({ $0.params.symbol == first.params.symbol }) else { return nil }
        }
        return first
    }

    /// Whether every selected element already agrees on a value. The inspector
    /// marks the ones that do not, so a slider showing a single number never
    /// implies the rest match it.
    package func selectionAgrees<T: Equatable>(_ keyPath: KeyPath<PanelElement, T>, ids: Set<UUID>) -> Bool {
        let selected = elements.filter { ids.contains($0.id) }
        guard let first = selected.first else { return true }
        return selected.allSatisfy { $0[keyPath: keyPath] == first[keyPath: keyPath] }
    }

    /// Distinct colours across `ids`, most-used first, each with the elements
    /// carrying it.
    ///
    /// Ordering is stable — count, then the colour itself — because the
    /// inspector rebuilds constantly and a well that jumps position between
    /// rebuilds is worse than no well at all.
    package func colourGroups(ids: Set<UUID>, strokes: Bool) -> [(colour: ColorSpec, ids: [UUID])] {
        var buckets: [ColorSpec: [UUID]] = [:]
        for el in elements where ids.contains(el.id) {
            guard let colour = strokes ? el.stroke : el.fill else { continue }
            buckets[colour, default: []].append(el.id)
        }
        func key(_ c: ColorSpec) -> String { "\(c.hexString)-\(c.a)" }
        return buckets
            .map { (colour: $0.key, ids: $0.value) }
            .sorted {
                $0.ids.count != $1.ids.count
                    ? $0.ids.count > $1.ids.count
                    : key($0.colour) < key($1.colour)
            }
    }

    /// Recolour exactly these elements. Addressed by id rather than by
    /// matching the old colour: a colour well fires continuously while the
    /// picker is open, and after the first change the old colour no longer
    /// matches anything.
    package mutating func setColour(_ colour: ColorSpec, ids: [UUID], strokes: Bool) {
        let wanted = Set(ids)
        for i in elements.indices where wanted.contains(elements[i].id) {
            if strokes { elements[i].stroke = colour } else { elements[i].fill = colour }
        }
    }

    /// Align the given elements, either to their own collective bounds or to
    /// the panel.
    ///
    /// Y grows downward here, so "top" is the smallest y: aligning to top puts
    /// every selected element at the topmost edge *present in the selection*.
    /// The panel's own top edge is a different operation and has to be asked
    /// for — conflating the two is the whole reason this takes a flag.
    package mutating func align(_ mode: String, ids: Set<UUID>, toPanel: Bool) {
        let bounds: CGRect
        if toPanel {
            guard !ids.isEmpty else { return }
            bounds = CGRect(origin: .zero, size: pixelSize)
        } else {
            let sel = elements.filter { ids.contains($0.id) }
            guard let first = sel.first, sel.count > 1 else { return }
            var b = first.frame
            for el in sel.dropFirst() { b = b.union(el.frame) }
            bounds = b
        }
        for i in elements.indices where ids.contains(elements[i].id) {
            switch mode {
            case "L":  elements[i].x = bounds.minX
            case "R":  elements[i].x = bounds.maxX - elements[i].w
            case "CX": elements[i].x = bounds.midX - elements[i].w / 2
            case "T":  elements[i].y = bounds.minY
            case "B":  elements[i].y = bounds.maxY - elements[i].h
            case "CY": elements[i].y = bounds.midY - elements[i].h / 2
            default: break
            }
        }
    }

    /// Give every still-unbound primitive the role its kind implies, returning
    /// how many changed.
    ///
    /// A panel made before component binding existed opens with everything as
    /// decoration — correct, because it keeps old exports byte-identical, but
    /// it means one trip through the inspector per control. This is the escape
    /// hatch. Only elements still sitting at `.decoration` whose kind actually
    /// implies a component are touched, so a role set by hand is never
    /// overwritten, and shapes, text and screws stay as artwork.
    @discardableResult
    package mutating func bindPrimitives() -> Int {
        var bound = 0
        for i in elements.indices {
            let kind = elements[i].kind
            guard elements[i].role == .decoration, kind.defaultRole != .decoration else { continue }
            elements[i].role = kind.defaultRole
            if elements[i].stockWidget.isEmpty { elements[i].stockWidget = kind.defaultStockWidget }
            bound += 1
        }
        return bound
    }

    package mutating func addCornerScrews() {
        let inset = PanelMetrics.screwInset, side = PanelMetrics.screwSide
        let sz = pixelSize
        let origins = [
            CGPoint(x: inset, y: inset),
            CGPoint(x: sz.width - inset - side, y: inset),
            CGPoint(x: inset, y: sz.height - inset - side),
            CGPoint(x: sz.width - inset - side, y: sz.height - inset - side),
        ]
        for o in origins where !elements.contains(where: { $0.kind == .screw && $0.frame.intersects(CGRect(origin: o, size: CGSize(side, side))) }) {
            elements.append(ElementKind.screw.defaultElement(at: o))
        }
    }
}
