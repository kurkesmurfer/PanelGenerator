import AppKit
import UniformTypeIdentifiers
import PanelKit
import PanelCanvas

// Window: new, open, save.

extension MainWindowController {

    // MARK: Document lifecycle

    @objc func pgNew(_ sender: Any?) {
        guard confirmDiscardIfNeeded() else { return }
        loadIntoCanvas(PanelDocument(), url: nil)
    }

    @objc func pgOpen(_ sender: Any?) {
        guard confirmDiscardIfNeeded() else { return }
        let panel = NSOpenPanel()
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.allowedContentTypes = [UTType(filenameExtension: PanelDocument.fileExtension) ?? .json]
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            loadIntoCanvas(try PanelDocument.load(from: url), url: url)
        } catch {
            showError("Could not open panel", error)
        }
    }

    @objc func pgSave(_ sender: Any?) {
        if let url = fileURL {
            save(to: url)
        } else {
            pgSaveAs(sender)
        }
    }

    @objc func pgSaveAs(_ sender: Any?) {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [UTType(filenameExtension: PanelDocument.fileExtension) ?? .json]
        panel.nameFieldStringValue = sanitizedFileName + "." + PanelDocument.fileExtension
        guard panel.runModal() == .OK, let url = panel.url else { return }
        save(to: url)
    }

    func save(to url: URL) {
        do {
            try canvas.document.save(to: url)
            fileURL = url
            isDirty = false
            updateTitle()
        } catch {
            showError("Could not save panel", error)
        }
    }

    var sanitizedFileName: String {
        let bad = CharacterSet(charactersIn: "/:\\?%*|\"<>")
        return documentName.components(separatedBy: bad).joined(separator: "-")
    }
}
