import Foundation
import CoreGraphics

// Picking and filtering: which element a click means, and narrowing or
// widening a selection by role, kind, name and style.

extension PanelElement {

    /// Outline-only: a shape whose fill is (near) transparent and which draws
    /// a stroke — a Paperface cell, dome or diamond, a line, a delineation
    /// box. Its interior is not part of it for clicking.
    package var isOutlineOnly: Bool {
        switch kind.category {
        case .shape: return (fill.a < 0.05 && (stroke?.a ?? 0) > 0.05) || kind == .line
        default: return false
        }
    }

    /// Hit test in panel space. Outline-only shapes respond within
    /// `tolerance` of their drawn line; everything else on its frame.
    package func hit(_ p: CGPoint, tolerance: CGFloat) -> Bool {
        guard isHidden != true, isTemplate != true else { return false }
        let local = Geo.rotate(p, around: center, degrees: -rotation)
        guard frame.insetBy(dx: -tolerance, dy: -tolerance).contains(local) else { return false }
        guard isOutlineOnly else { return frame.contains(local) }
        for part in Renderer.parts(for: self) {
            let width = max(part.lineWidth, 0.5) + tolerance * 2
            if part.path.copy(strokingWithWidth: width, lineCap: .round, lineJoin: .round, miterLimit: 4)
                .contains(local) { return true }
            if let f = part.fill, f.a > 0.05, part.path.contains(local) { return true }
        }
        return false
    }

    /// Pick priority: controls first, then text and glyphs, then filled
    /// shapes, then outlines — so a jack inside a cell is clicked as the
    /// jack whatever their stacking order.
    package var pickPriority: Int {
        if role.isComponent { return 0 }
        switch kind {
        case .text, .symbol: return 1
        default: return isOutlineOnly ? 3 : 2
        }
    }
}

extension PanelDocument {

    /// Everything under `p`, in the order a click should consider it:
    /// by pick priority, topmost first within the same priority.
    package func hitStack(at p: CGPoint, tolerance: CGFloat) -> [PanelElement] {
        let hits = elements.enumerated().filter { $0.element.hit(p, tolerance: tolerance) }
        return hits.sorted {
            $0.element.pickPriority != $1.element.pickPriority
                ? $0.element.pickPriority < $1.element.pickPriority
                : $0.offset > $1.offset
        }.map(\.element)
    }

    // MARK: - Filters

    package enum SelectionFilter: String, CaseIterable {
        case controls, decoration, labels

        package func accepts(_ e: PanelElement) -> Bool {
            switch self {
            case .controls:   return e.role.isComponent
            case .labels:     return e.kind == .text
            case .decoration: return !e.role.isComponent && e.kind != .text
            }
        }
    }

    package func narrow(_ ids: Set<UUID>, to filter: SelectionFilter) -> Set<UUID> {
        Set(elements.filter { ids.contains($0.id) && filter.accepts($0) }.map(\.id))
    }

    package enum Sameness: String, CaseIterable {
        case kind, name, style
    }

    /// Every selectable element matching any of `ids` on `what`. Style is
    /// kind + fill + stroke + line width: "all the grey outlines like this".
    package func selectSame(as ids: Set<UUID>, by what: Sameness) -> Set<UUID> {
        let refs = elements.filter { ids.contains($0.id) }
        guard !refs.isEmpty else { return ids }
        func matches(_ e: PanelElement, _ r: PanelElement) -> Bool {
            switch what {
            case .kind:  return e.kind == r.kind
            case .name:  return e.name == r.name
            case .style: return e.kind == r.kind && e.fill == r.fill && e.stroke == r.stroke
                && abs(e.strokeWidth - r.strokeWidth) < 0.001
            }
        }
        return Set(elements.filter { e in e.isTemplate != true && refs.contains { matches(e, $0) } }.map(\.id))
    }

    /// The Select… dialog: all conditions must hold; nil/empty ones are
    /// ignored. Name matches as a case-insensitive substring.
    package func select(kinds: Set<ElementKind>? = nil, filter: SelectionFilter? = nil,
                        nameContains: String = "", within scope: Set<UUID>? = nil) -> Set<UUID> {
        let needle = nameContains.trimmingCharacters(in: .whitespaces).lowercased()
        return Set(elements.filter { e in
            e.isTemplate != true && e.isHidden != true
                && (scope.map { $0.contains(e.id) } ?? true)
                && (kinds.map { $0.isEmpty || $0.contains(e.kind) } ?? true)
                && (filter.map { $0.accepts(e) } ?? true)
                && (needle.isEmpty || e.name.lowercased().contains(needle)
                    || (e.kind == .text && e.params.text.lowercased().contains(needle)))
        }.map(\.id))
    }
}
