import AppKit
import CoreGraphics
import PanelKit

// Canvas: drops from the palette. A plain drop inserts; a drop with ⌘ held
// onto an existing control replaces it in place (the whole selection, when
// the control is part of it).

extension CanvasView {

    // MARK: Drag & drop from palette

    package override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
        dragOperation(for: sender)
    }

    package override func draggingUpdated(_ sender: NSDraggingInfo) -> NSDragOperation {
        dragOperation(for: sender)
    }

    package override func draggingExited(_ sender: NSDraggingInfo?) {
        setDropReplaceTargets([])
    }

    package override func draggingEnded(_ sender: NSDraggingInfo) {
        setDropReplaceTargets([])
    }

    package override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        // "kind", "kind#preset" — a specific glyph, a ring knob, and so on —
        // or "stamp:<name>" for a saved fragment.
        guard let raw = sender.draggingPasteboard.string(forType: Paste.elementType) else { return false }
        let p0 = panelPoint(fromWindowLocation: sender.draggingLocation)
        if raw.hasPrefix(Paste.stampPrefix) {
            return insertStamp(named: String(raw.dropFirst(Paste.stampPrefix.count)), at: p0)
        }
        let parts = raw.split(separator: "#", maxSplits: 1).map(String.init)
        guard let kind = ElementKind(rawValue: parts[0]) else { return false }
        let preset = parts.count > 1 ? parts[1] : nil

        let targets = replaceTargets(for: sender)
        setDropReplaceTargets([])
        if !targets.isEmpty {
            replace(ids: targets, with: kind, preset: preset)
            return true
        }

        var el = kind.defaultElement(at: .zero)
        if let preset { el.applyPreset(preset) }
        el.frame.origin = snappedOrigin(forCenter: p0, size: CGSize(width: el.w, height: el.h))
        // Clamp inside the panel.
        el.frame.origin.x = max(0, min(el.frame.origin.x, document.pixelSize.width - el.w))
        el.frame.origin.y = max(0, min(el.frame.origin.y, document.pixelSize.height - el.h))
        insert([el], name: "Add \(kind.displayName)")
        return true
    }

    /// With ⌘ held over an element: that element, or the whole selection if
    /// the element is part of it. Stamps are multi-element and never replace.
    private func replaceTargets(for sender: NSDraggingInfo) -> Set<UUID> {
        guard NSEvent.modifierFlags.contains(.command),
              let raw = sender.draggingPasteboard.string(forType: Paste.elementType),
              !raw.hasPrefix(Paste.stampPrefix),
              let hit = element(at: panelPoint(fromWindowLocation: sender.draggingLocation))
        else { return [] }
        return selection.contains(hit.id) ? selection : [hit.id]
    }

    /// `.generic` while replacing, so the cursor loses its "+" badge.
    private func dragOperation(for sender: NSDraggingInfo) -> NSDragOperation {
        let targets = replaceTargets(for: sender)
        setDropReplaceTargets(targets)
        return targets.isEmpty ? .copy : .generic
    }

    private func setDropReplaceTargets(_ ids: Set<UUID>) {
        guard ids != dropReplaceTargets else { return }
        dropReplaceTargets = ids
        needsDisplay = true
    }
}
