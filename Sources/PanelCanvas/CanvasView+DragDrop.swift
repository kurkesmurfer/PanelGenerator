import AppKit
import CoreGraphics
import PanelKit

// Canvas: drops from the palette.

extension CanvasView {

    // MARK: Drag & drop from palette

    package override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation { .copy }
    package override func draggingUpdated(_ sender: NSDraggingInfo) -> NSDragOperation { .copy }

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

        var el = kind.defaultElement(at: .zero)
        if parts.count > 1 { el.applyPreset(parts[1]) }
        let p = p0
        el.frame.origin = snappedOrigin(forCenter: p, size: CGSize(width: el.w, height: el.h))
        // Clamp inside the panel.
        el.frame.origin.x = max(0, min(el.frame.origin.x, document.pixelSize.width - el.w))
        el.frame.origin.y = max(0, min(el.frame.origin.y, document.pixelSize.height - el.h))
        insert([el], name: "Add \(kind.displayName)")
        return true
    }
}
