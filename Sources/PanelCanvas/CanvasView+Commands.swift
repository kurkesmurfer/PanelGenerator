import AppKit
import CoreGraphics
import PanelKit

// Canvas: selection, edit, naming, labelling, alignment and group commands.

extension CanvasView {

    // MARK: Selection & edit commands

    package func setSelection(_ ids: Set<UUID>) {
        selection = ids
        needsDisplay = true
        onSelectionChange?()
    }


    package func selectionAgrees<T: Equatable>(_ keyPath: KeyPath<PanelElement, T>) -> Bool {
        document.selectionAgrees(keyPath, ids: selection)
    }

    package var primaryElement: PanelElement? {
        guard selection.count == 1, let id = selection.first else { return nil }
        return document.elements.first { $0.id == id }
    }

    package func deleteSelection() {
        guard !selection.isEmpty else { return }
        apply(elements: document.elements.filter { !selection.contains($0.id) }, name: "Delete")
        setSelection([])
    }

    package func duplicateSelection() {
        guard !selection.isEmpty else { return }
        let copies = document.elements
            .filter { selection.contains($0.id) }
            .map { el -> PanelElement in
                var c = el
                c.id = UUID()
                c.x += Geo.defaultSnap * 2
                c.y += Geo.defaultSnap * 2
                return c
            }
        // Fresh group IDs: a duplicated group must not stay glued to the original.
        insert(withRemappedGroups(copies), name: "Duplicate")
    }

    /// Undoable wrapper around `PanelDocument.bindPrimitives()`.
    @discardableResult
    package func bindPrimitives() -> Int {
        var doc = document
        let bound = doc.bindPrimitives()
        guard bound > 0 else { return 0 }
        apply(elements: doc.elements, name: "Bind Primitives")
        return bound
    }

    package func selectAllElements() {
        // Templates stay out: Select All followed by a nudge must not drag the
        // thing you are tracing out from under your drawing.
        setSelection(Set(document.elements.filter { $0.isTemplate != true }.map(\.id)))
    }

    package func bringToFront() {
        guard !selection.isEmpty else { return }
        let front = document.elements.filter { selection.contains($0.id) }
        let rest = document.elements.filter { !selection.contains($0.id) }
        apply(elements: rest + front, name: "Reorder")
    }

    package func sendToBack() {
        guard !selection.isEmpty else { return }
        let picked = document.elements.filter { selection.contains($0.id) }
        let rest = document.elements.filter { !selection.contains($0.id) }
        apply(elements: picked + rest, name: "Reorder")
    }

    /// Align every selected element to the group bounding box (L/CX/R/T/CY/B).
    /// Align the selection. `to: "sel"` lines elements up with the selection's
    /// own bounding box (needs 2+ selected). `to: "panel"` aligns to the panel
    /// edges / center line and works with any selection size, even one element.
    /// Undoable wrapper around `PanelDocument.nameSequentially`.
    package func nameSelectionSequentially(prefix: String) {
        var doc = document
        doc.nameSequentially(ids: selection, prefix: prefix)
        guard doc.elements != document.elements else { return }
        apply(elements: doc.elements, name: "Name Components")
    }

    /// Undoable wrapper around `PanelDocument.labelSelection`.
    ///
    /// The new labels end up selected. That is the point of the command: the
    /// inspector's Size row then writes to all of them at once, so twenty-five
    /// labels are still one action if the size is wrong.
    @discardableResult
    package func labelSelection(placement: LabelPlacement,
                        gap: CGFloat,
                        fontSize: CGFloat,
                        bold: Bool,
                        uppercase: Bool,
                        spaceUnderscores: Bool,
                        colour: ColorSpec) -> (created: Int, skipped: Int) {
        let owners = selection
        var doc = document
        let result = doc.labelSelection(ids: owners, placement: placement, gap: gap,
                                        fontSize: fontSize, bold: bold, uppercase: uppercase,
                                        spaceUnderscores: spaceUnderscores, colour: colour)
        guard result.created > 0 else { return result }
        let made = Set(doc.elements.filter { el in
            el.kind == .text && (el.labelOwner.map(owners.contains) ?? false)
        }.map(\.id))
        apply(elements: doc.elements, name: "Label Selection")
        setSelection(made)
        return result
    }

    /// Undoable wrapper around `PanelDocument.setTemplate`.
    @discardableResult
    package func setTemplate(_ on: Bool, ids: Set<UUID>? = nil) -> Int {
        var doc = document
        let scope = ids ?? (selection.isEmpty ? Set(document.elements.map(\.id)) : selection)
        let changed = doc.setTemplate(on, ids: scope)
        guard changed > 0 else { return 0 }
        apply(elements: doc.elements, name: on ? "Make Template" : "Make Editable")
        return changed
    }

    /// Undoable wrapper around `PanelDocument.fitToPanel`.
    @discardableResult
    package func fitToPanel(_ mode: PanelDocument.FitMode, margin: CGFloat) -> Int {
        var doc = document
        let moved = doc.fitToPanel(mode, margin: margin)
        guard moved > 0 else { return 0 }
        apply(elements: doc.elements, name: "Fit to Panel")
        return moved
    }

    /// Undoable wrapper around `PanelDocument.nameFromLabels`.
    @discardableResult
    package func nameFromLabels(within limit: CGFloat) -> (named: Int, skipped: Int) {
        var doc = document
        let scope = selection.isEmpty ? Set(document.elements.map(\.id)) : selection
        let result = doc.nameFromLabels(ids: scope, within: limit)
        guard result.named > 0 else { return result }
        apply(elements: doc.elements, name: "Name from Labels")
        return result
    }

    /// Undoable wrapper around `PanelDocument.adoptIdentifiers`.
    @discardableResult
    package func adoptIdentifiers(from source: PanelDocument, within limit: CGFloat)
    -> (adopted: [PanelDocument.Adoption], unmatched: [String]) {
        var doc = document
        let scope = selection.isEmpty ? Set(document.elements.map(\.id)) : selection
        let result = doc.adoptIdentifiers(from: source, ids: scope, within: limit)
        guard !result.adopted.isEmpty else { return result }
        apply(elements: doc.elements, name: "Adopt Identifiers")
        return result
    }

    /// Undoable wrapper around `PanelDocument.makeWidget`.
    @discardableResult
    package func makeWidget(name: String, role: ComponentRole) -> Bool {
        var doc = document
        guard doc.makeWidget(ids: selection, name: name, role: role) else { return false }
        apply(elements: doc.elements, name: "Make Widget")
        return true
    }

    /// Undoable wrapper around `PanelDocument.setColour`.
    package func setColour(_ colour: ColorSpec, ids: [UUID], strokes: Bool, name: String) {
        var doc = document
        doc.setColour(colour, ids: ids, strokes: strokes)
        guard doc.elements != document.elements else { return }
        apply(elements: doc.elements, name: name)
    }

    /// Undoable wrapper around `PanelDocument.align`.
    package func alignSelection(_ mode: String, to target: String = "sel") {
        let toPanel = target == "panel"
        var doc = document
        doc.align(mode, ids: selection, toPanel: toPanel)
        guard doc.elements != document.elements else { return }   // no empty undo steps
        apply(elements: doc.elements, name: toPanel ? "Align to Panel" : "Align")
    }

    /// Evenly distribute 3+ selected elements along an axis (first/last stay
    /// put either way). Two different notions of "evenly", picked via `by`:
    ///
    /// - `"gap"` (default): equal edge-to-edge spacing. Right when the
    ///   selection's own widths/heights should read as evenly separated --
    ///   e.g. a row of labels or icons where whitespace is what the eye
    ///   tracks.
    /// - `"center"`: equal centre-to-centre spacing, ignoring each
    ///   element's own size. Right when the selection's *positions* should
    ///   divide the span evenly regardless of what's sitting at each one --
    ///   e.g. two switches of one size splitting the run between two knobs
    ///   of a different size into thirds, which is a position statement
    ///   ("these four sit at 0, 1/3, 2/3, 1 of the span"), not a
    ///   whitespace statement. `"gap"` cannot express that when the
    ///   elements involved aren't all the same size, since equal edge gaps
    ///   and equal centre spacing only coincide when they are.
    package func distributeSelection(_ axis: String, by mode: String = "gap") {
        let idxs = document.elements.indices.filter { selection.contains(document.elements[$0].id) }
        guard idxs.count > 2 else { return }
        var els = document.elements
        let sorted = idxs.sorted {
            axis == "X" ? els[$0].frame.minX < els[$1].frame.minX
                        : els[$0].frame.minY < els[$1].frame.minY
        }
        if mode == "center" {
            let firstCenter = axis == "X" ? els[sorted.first!].center.x : els[sorted.first!].center.y
            let lastCenter  = axis == "X" ? els[sorted.last!].center.x  : els[sorted.last!].center.y
            let step = (lastCenter - firstCenter) / CGFloat(sorted.count - 1)
            for (n, i) in sorted.enumerated() {
                let c = firstCenter + step * CGFloat(n)
                if axis == "X" { els[i].x = c - els[i].w / 2 }
                else { els[i].y = c - els[i].h / 2 }
            }
            apply(elements: els, name: "Distribute")
            return
        }
        let first = els[sorted.first!], last = els[sorted.last!]
        let span = axis == "X" ? last.frame.maxX - first.frame.minX
                               : last.frame.maxY - first.frame.minY
        let total = sorted.reduce(CGFloat(0)) {
            axis == "X" ? $0 + els[$1].w : $0 + els[$1].h
        }
        let gap = (span - total) / CGFloat(sorted.count - 1)
        var cursor = axis == "X" ? first.frame.minX : first.frame.minY
        for i in sorted {
            if axis == "X" { els[i].x = cursor; cursor += els[i].w + gap }
            else { els[i].y = cursor; cursor += els[i].h + gap }
        }
        apply(elements: els, name: "Distribute")
    }

    // MARK: Groups

    /// Assign a shared group ID to the selection; clicking any member then selects all.
    package func groupSelection() {
        guard selection.count > 1 else { return }
        let gid = UUID()
        var els = document.elements
        for i in els.indices where selection.contains(els[i].id) { els[i].groupID = gid }
        apply(elements: els, name: "Group")
    }

    package func ungroupSelection() {
        var els = document.elements
        var hit = false
        for i in els.indices where selection.contains(els[i].id) {
            if els[i].groupID != nil { els[i].groupID = nil; hit = true }
        }
        guard hit else { return }
        apply(elements: els, name: "Ungroup")
    }

    /// (internal: the layer list expands row clicks to whole groups too)
    package func groupMembers(_ id: UUID) -> Set<UUID> {
        guard let el = document.elements.first(where: { $0.id == id }),
              let gid = el.groupID else { return [id] }
        return Set(document.elements.filter { $0.groupID == gid }.map(\.id))
    }

    /// Fresh group IDs for copied elements so duplicates and pastes never share
    /// membership with the elements they were copied from. Members of the same
    /// source group stay grouped together under one new ID.
    func withRemappedGroups(_ els: [PanelElement]) -> [PanelElement] {
        var map: [UUID: UUID] = [:]
        return els.map { el in
            var e = el
            if let g = el.groupID {
                if map[g] == nil { map[g] = UUID() }
                e.groupID = map[g]
            }
            return e
        }
    }
}
