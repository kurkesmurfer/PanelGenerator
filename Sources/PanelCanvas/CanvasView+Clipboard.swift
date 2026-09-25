import AppKit
import CoreGraphics
import PanelKit

// Canvas: copy / paste and stamp drops.

extension CanvasView {

    // MARK: Copy / paste


    var clipboardElements: [PanelElement] {
        get {
            guard let data = NSPasteboard.general.data(forType: Self.pasteType),
                  let els = try? JSONDecoder().decode([PanelElement].self, from: data) else { return [] }
            return els
        }
        set {
            guard let data = try? JSONEncoder().encode(newValue) else { return }
            let pb = NSPasteboard.general
            pb.clearContents()
            pb.setData(data, forType: Self.pasteType)
        }
    }


    package func copySelection() {
        let els = document.elements.filter { selection.contains($0.id) }
        guard !els.isEmpty else { return }
        clipboardElements = els
    }

    package func cutSelection() {
        copySelection()
        deleteSelection()
    }

    package func paste() {
        let els = clipboardElements
        guard !els.isEmpty else { return }
        var pasted: [PanelElement] = []
        for var e in els {
            e.id = UUID()
            e.x += PanelMetrics.pixelsPerHP
            e.y += PanelMetrics.pixelsPerHP
            pasted.append(e)
        }
        // Fresh group IDs here too, or pasting a group would select/move the
        // originals along with the paste.
        let remapped = withRemappedGroups(pasted)
        insert(remapped, name: "Paste")
        setSelection(Set(remapped.map(\.id)))
    }

    package func insertAtCenter(_ kind: ElementKind, preset: String? = nil) {
        var el = kind.defaultElement(at: .zero)
        if let preset { el.applyPreset(preset) }
        let panelCenter = CGPoint(x: document.pixelSize.width / 2, y: document.pixelSize.height / 2)
        el.frame.origin = snappedOrigin(forCenter: panelCenter, size: CGSize(width: el.w, height: el.h))
        el.frame.origin.x = max(0, min(el.frame.origin.x, document.pixelSize.width - el.w))
        el.frame.origin.y = max(0, min(el.frame.origin.y, document.pixelSize.height - el.h))
        insert([el], name: "Add \(kind.displayName)")
    }

    // MARK: Stamps

    /// Drop a saved fragment centred on `point`, nudged back inside the panel
    /// if it would hang over an edge. Returns false only if the stamp is gone
    /// from disk since the palette was built.
    @discardableResult
    func insertStamp(named name: String, at point: CGPoint) -> Bool {
        guard let stamp = StampLibrary.stamp(named: name)?.resolved else { return false }
        let snapped = snappedCenter(point)
        var els = StampLibrary.instance(of: stamp, at: snapped)
        guard !els.isEmpty else { return false }

        // Shift the whole fragment as one, so a stamp never loses its internal
        // spacing to a clamp.
        var box = els[0].frame
        for el in els.dropFirst() { box = box.union(el.frame) }
        var dx: CGFloat = 0, dy: CGFloat = 0
        if box.maxX > document.pixelSize.width { dx = document.pixelSize.width - box.maxX }
        if box.minX + dx < 0 { dx = -box.minX }
        if box.maxY > document.pixelSize.height { dy = document.pixelSize.height - box.maxY }
        if box.minY + dy < 0 { dy = -box.minY }
        if dx != 0 || dy != 0 {
            for i in els.indices { els[i].x += dx; els[i].y += dy }
        }

        insert(els, name: "Add \(stamp.name)")
        return true
    }

    @discardableResult
    package func insertStampAtCenter(named name: String) -> Bool {
        insertStamp(named: name,
                    at: CGPoint(x: document.pixelSize.width / 2,
                                y: document.pixelSize.height / 2))
    }
}
