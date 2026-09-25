import AppKit
import UniformTypeIdentifiers
import PanelKit

// Window: stamps and help.

extension MainWindowController {

    // MARK: Stamps

    /// Save the selection to the palette.
    ///
    /// A house style is a handful of fragments repeated on every panel — a
    /// brand mark, a wordmark, a jack pair with its labels. They are the
    /// author's artwork, not the tool's, so the tool keeps them rather than
    /// shipping approximations of them.
    @objc func pgAddStamp(_ sender: Any?) {
        let selected = canvas.document.elements.filter { canvas.selection.contains($0.id) }
        guard !selected.isEmpty else { return }

        let alert = NSAlert()
        alert.messageText = "Add \(selected.count) element\(selected.count == 1 ? "" : "s") to the palette"
        alert.informativeText = """
        Saved fragments appear under Stamps and drop with fresh identity — no \
        component identifiers travel with them, so two panels never end up \
        sharing an enum name.
        """
        let field = NSTextField(frame: NSRect(x: 0, y: 0, width: 260, height: 24))
        field.stringValue = suggestedStampName(for: selected)
        field.placeholderString = "Name"
        alert.accessoryView = field
        alert.addButton(withTitle: "Save")
        alert.addButton(withTitle: "Cancel")
        alert.window.initialFirstResponder = field
        guard alert.runModal() == .alertFirstButtonReturn else { return }

        let name = field.stringValue.trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty else { return }

        // Overwriting silently would lose work that only exists here.
        if StampLibrary.stamp(named: StampLibrary.fileName(from: name)) != nil {
            let confirm = NSAlert()
            confirm.messageText = "“\(name)” is already in the palette."
            confirm.informativeText = "Replace it?"
            confirm.addButton(withTitle: "Replace")
            confirm.addButton(withTitle: "Cancel")
            guard confirm.runModal() == .alertFirstButtonReturn else { return }
        }

        do {
            let stamp = try StampLibrary.save(selected, as: name)
            palette.rebuild()
            if stamp.name != name {
                let note = NSAlert()
                note.messageText = "Saved as “\(stamp.name)”"
                note.informativeText = "The name is also a filename, so a few characters were replaced."
                note.runModal()
            }
        } catch {
            let fail = NSAlert(error: error)
            fail.runModal()
        }
    }

    /// Text elements name themselves; anything else falls back to its kind.
    private func suggestedStampName(for elements: [PanelElement]) -> String {
        if let text = elements.first(where: { $0.kind == .text }) {
            let s = text.params.text.trimmingCharacters(in: .whitespaces)
            if !s.isEmpty { return s }
        }
        if elements.count == 1 { return elements[0].kind.displayName }
        return "Stamp"
    }

    /// Reveal the stamp folder so a fragment can be renamed, deleted or handed
    /// to someone else — they are plain JSON files, and a palette you cannot
    /// prune fills up with mistakes.
    @objc func pgRevealStamps(_ sender: Any?) {
        let dir = StampLibrary.directory
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        NSWorkspace.shared.open(dir)
    }

    @objc func pgReloadStamps(_ sender: Any?) {
        palette.rebuild()
    }

    /// Open the workflow manual in the default browser.
    ///
    /// A separate window rather than a sheet: the manual is something you keep
    /// beside the app while you work, and the browser already does windows,
    /// search and printing better than a bundled viewer would.
    @objc func pgWorkflowManual(_ sender: Any?) {
        guard let url = Self.manualURL() else {
            let alert = NSAlert()
            alert.messageText = "The workflow manual is not installed."
            alert.informativeText = """
            Docs/Workflow.html is missing beside the app. It lives in the \
            PanelGenerator source tree; running “make app” copies it into the \
            bundle.
            """
            alert.runModal()
            return
        }
        NSWorkspace.shared.open(url)
    }

    /// Bundle first — that is the copy an installed app has — then the source
    /// tree relative to the executable, which is where it is during development.
    static func manualURL() -> URL? {
        if let inBundle = Bundle.main.url(forResource: "Workflow", withExtension: "html") {
            return inBundle
        }
        let exe = Bundle.main.executableURL?.resolvingSymlinksInPath()
            ?? URL(fileURLWithPath: CommandLine.arguments[0]).resolvingSymlinksInPath()
        var dir = exe.deletingLastPathComponent()
        for _ in 0..<6 {
            let candidate = dir.appendingPathComponent("Docs/Workflow.html")
            if FileManager.default.fileExists(atPath: candidate.path) { return candidate }
            let resources = dir.appendingPathComponent("Resources/Workflow.html")
            if FileManager.default.fileExists(atPath: resources.path) { return resources }
            dir = dir.deletingLastPathComponent()
        }
        return nil
    }

    @objc func pgHelp(_ sender: Any?) {
        let alert = NSAlert()
        alert.messageText = "PanelGenerator — Quick Start"
        alert.informativeText = """
        Drag primitives and shapes from the left repo onto the panel.
        Double-click a repo item to drop it in the centre.

        • Click to select · Shift-click to multi-select · drag empty space to marquee
        • Drag handles to resize — small elements show corner handles only
        • Blue ↻ badge above the selection: drag to rotate (⇧ snaps 15°)
        • Orange ⇄ / ⇅ badges: click, or drag across the shape, to mirror (elbows)
        • ⌫ or ⌦ deletes the selection · arrow keys nudge (⇧ = grid step)
        • ⌘D duplicate
        • Snap-to-grid aligns to the HP grid (⇧⌘G toggles)
        • The Fill control uses the native macOS colour picker; the swatch
          bank below it is a curated LCARS / TNG palette.
        • Elbows + Ring Sectors + per-corner-radius boxes are your friends:
          that's how you get the Next Generation look.
        • Name the controls, then Edit ▸ Label Selection… (⌘L) labels all of
          them at once. The new labels stay selected, so Size in the inspector
          re-sizes the whole set in one go.
        • {ka} {ru} {te} … inside a label's text places an alien glyph inline.
        • Select part of a panel and Edit ▸ Add Selection to Palette… saves it
          as a Stamp — a brand mark, a wordmark, a jack pair with its labels.
          Stamps drop with fresh identity, so no identifier travels with them.

        Help ▸ Workflow Manual opens the full workflow in your browser.

        File ▸ Import SVG (⌘I) reads an existing panel — as a faint tracing
        template you draw over, or as editable artwork.
        File ▸ Import Module Code (⌥⌘I) reads a ModuleWidget constructor and
        rebuilds its components, artwork included. See Docs/IMPORT.md.

        File ▸ Export SVG / PNG writes Rack-compatible artwork
        (1 HP = 15 px · 3U = 380 px · 1U = 127 px).
        """
        alert.runModal()
    }
}
