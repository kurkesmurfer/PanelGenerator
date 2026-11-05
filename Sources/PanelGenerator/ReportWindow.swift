import AppKit

/// A report you can work with: import and check results in a resizable
/// window whose text can be selected, edited, copied or saved, instead of an
/// alert that can only be read and dismissed.
///
/// The last report stays available from File ▸ Show Last Report.
final class ReportWindow: NSWindowController, NSWindowDelegate {

    private static var current: ReportWindow?
    private(set) static var last: (title: String, text: String, suggestedName: String)?

    private let textView: NSTextView
    private let suggestedName: String
    private var saveDirectory: URL?

    /// Shows `text` under `title`. `saveNear`, when given, is where Save…
    /// starts (e.g. beside the imported file).
    static func show(title: String, text: String, suggestedName: String, saveNear: URL? = nil,
                     over parent: NSWindow?) {
        last = (title, text, suggestedName)
        current?.close()
        let w = ReportWindow(title: title, text: text, suggestedName: suggestedName)
        w.saveDirectory = saveNear?.deletingLastPathComponent()
        current = w
        if let parent, let win = w.window {
            win.setFrameTopLeftPoint(NSPoint(x: parent.frame.midX - win.frame.width / 2,
                                             y: parent.frame.maxY - 80))
        }
        w.showWindow(nil)
        w.window?.makeKeyAndOrderFront(nil)
    }

    static func showLast(over parent: NSWindow?) {
        guard let l = last else {
            let alert = NSAlert()
            alert.messageText = "No report yet"
            alert.informativeText = "Import an SVG or module code, or run Check Panel, and its report will be here."
            alert.runModal()
            return
        }
        show(title: l.title, text: l.text, suggestedName: l.suggestedName, over: parent)
    }

    private init(title: String, text: String, suggestedName: String) {
        self.suggestedName = suggestedName
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 620, height: 420),
                              styleMask: [.titled, .closable, .resizable, .miniaturizable],
                              backing: .buffered, defer: false)
        window.title = title
        window.isReleasedWhenClosed = false
        window.minSize = NSSize(width: 380, height: 220)

        let scroll = NSScrollView()
        scroll.hasVerticalScroller = true
        scroll.borderType = .noBorder
        scroll.translatesAutoresizingMaskIntoConstraints = false
        textView = NSTextView()
        textView.isEditable = true
        textView.isSelectable = true
        textView.isRichText = false
        textView.allowsUndo = true
        textView.font = NSFont.monospacedSystemFont(ofSize: 12, weight: .regular)
        textView.textContainerInset = NSSize(width: 10, height: 10)
        textView.autoresizingMask = [.width]
        textView.isVerticallyResizable = true
        textView.textContainer?.widthTracksTextView = true
        textView.string = text
        scroll.documentView = textView

        super.init(window: window)
        window.delegate = self

        let copy = NSButton(title: "Copy All", target: self, action: #selector(copyAll))
        let save = NSButton(title: "Save…", target: self, action: #selector(save))
        let close = NSButton(title: "Close", target: self, action: #selector(closeReport))
        close.keyEquivalent = "\u{1B}"
        let hint = NSTextField(labelWithString: "Editable — add notes, then copy or save.")
        hint.textColor = .secondaryLabelColor
        hint.font = NSFont.systemFont(ofSize: 11)
        let buttons = NSStackView(views: [hint, NSView(), copy, save, close])
        buttons.orientation = .horizontal
        buttons.spacing = 8
        buttons.translatesAutoresizingMaskIntoConstraints = false

        let content = window.contentView!
        content.addSubview(scroll)
        content.addSubview(buttons)
        NSLayoutConstraint.activate([
            scroll.topAnchor.constraint(equalTo: content.topAnchor),
            scroll.leadingAnchor.constraint(equalTo: content.leadingAnchor),
            scroll.trailingAnchor.constraint(equalTo: content.trailingAnchor),
            scroll.bottomAnchor.constraint(equalTo: buttons.topAnchor, constant: -10),
            buttons.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 14),
            buttons.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -14),
            buttons.bottomAnchor.constraint(equalTo: content.bottomAnchor, constant: -12),
        ])
        window.center()
    }

    required init?(coder: NSCoder) { fatalError("not supported") }

    @objc private func copyAll() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(textView.string, forType: .string)
    }

    @objc private func save() {
        guard let window else { return }
        let panel = NSSavePanel()
        panel.nameFieldStringValue = suggestedName
        panel.allowedContentTypes = [.plainText]
        if let saveDirectory { panel.directoryURL = saveDirectory }
        panel.beginSheetModal(for: window) { [weak self] response in
            guard response == .OK, let url = panel.url, let self else { return }
            do {
                try self.textView.string.write(to: url, atomically: true, encoding: .utf8)
            } catch {
                NSAlert(error: error).runModal()
            }
        }
    }

    @objc private func closeReport() { close() }

    func windowWillClose(_ notification: Notification) {
        // Keep edits for Show Last Report.
        if let l = ReportWindow.last { ReportWindow.last = (l.title, textView.string, l.suggestedName) }
        if ReportWindow.current === self { ReportWindow.current = nil }
    }
}
