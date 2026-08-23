import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate {
    var windowController: MainWindowController!

    func applicationDidFinishLaunching(_ notification: Notification) {
        // The whole chrome is dark; force dark appearance so native controls
        // (labels, fields, checkboxes, sliders) stay legible on it.
        NSApp.appearance = NSAppearance(named: .darkAqua)
        windowController = MainWindowController()
        windowController.showWindow(nil)
        windowController.window?.makeKeyAndOrderFront(nil)
        NSApp.mainMenu = MenuBuilder.build(with: windowController)
        NSApp.activate(ignoringOtherApps: true)
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        true
    }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        windowController.confirmDiscardIfNeeded() ? .terminateNow : .terminateCancel
    }
}

// MARK: - Menu bar

enum MenuBuilder {

    static func item(_ title: String,
                     _ action: Selector?,
                     key: String = "",
                     target: AnyObject? = nil) -> NSMenuItem {
        let mi = NSMenuItem(title: title, action: action, keyEquivalent: key)
        if let t = target { mi.target = t }
        return mi
    }

    static func build(with wc: MainWindowController) -> NSMenu {
        let main = NSMenu()

        // App menu
        let appItem = NSMenuItem()
        main.addItem(appItem)
        let appMenu = NSMenu(title: "PanelGenerator")
        appMenu.addItem(item("About PanelGenerator", #selector(NSApplication.orderFrontStandardAboutPanel(_:))))
        appMenu.addItem(.separator())
        appMenu.addItem(item("Hide PanelGenerator", #selector(NSApplication.hide(_:)), key: "h"))
        appMenu.addItem(.separator())
        appMenu.addItem(item("Quit PanelGenerator", #selector(NSApplication.terminate(_:)), key: "q"))
        appItem.submenu = appMenu

        // File
        let fileItem = NSMenuItem()
        main.addItem(fileItem)
        let file = NSMenu(title: "File")
        file.addItem(item("New Panel", #selector(MainWindowController.pgNew(_:)), key: "n", target: wc))
        file.addItem(item("Open…", #selector(MainWindowController.pgOpen(_:)), key: "o", target: wc))
        file.addItem(item("Save", #selector(MainWindowController.pgSave(_:)), key: "s", target: wc))
        file.addItem(item("Save As…", #selector(MainWindowController.pgSaveAs(_:)), key: "S", target: wc))
        file.addItem(.separator())
        file.addItem(item("Export SVG…", #selector(MainWindowController.pgExportSVG(_:)), key: "e", target: wc))
        file.addItem(item("Export PNG…", #selector(MainWindowController.pgExportPNG(_:)), key: "E", target: wc))
        fileItem.submenu = file

        // Edit
        let editItem = NSMenuItem()
        main.addItem(editItem)
        let edit = NSMenu(title: "Edit")
        edit.addItem(item("Undo", #selector(MainWindowController.pgUndo(_:)), key: "z", target: wc))
        edit.addItem(item("Redo", #selector(MainWindowController.pgRedo(_:)), key: "Z", target: wc))
        edit.addItem(.separator())
        edit.addItem(item("Duplicate", #selector(MainWindowController.pgDuplicate(_:)), key: "d", target: wc))
        // Plain Backspace (no ⌘) deletes the selection. The empty modifier mask
        // is safe because validateMenuItem gates the item to canvas focus.
        let deleteItem = item("Delete", #selector(MainWindowController.pgDelete(_:)), key: "\u{7F}", target: wc)
        deleteItem.keyEquivalentModifierMask = []
        edit.addItem(deleteItem)
        edit.addItem(.separator())
        edit.addItem(item("Select All", #selector(MainWindowController.pgSelectAll(_:)), key: "a", target: wc))
        edit.addItem(.separator())
        edit.addItem(item("Bring to Front", #selector(MainWindowController.pgFront(_:)), target: wc))
        edit.addItem(item("Send to Back", #selector(MainWindowController.pgBack(_:)), target: wc))
        edit.addItem(.separator())
        edit.addItem(item("Insert Corner Screws", #selector(MainWindowController.pgScrews(_:)), target: wc))
        editItem.submenu = edit

        // View
        let viewItem = NSMenuItem()
        main.addItem(viewItem)
        let view = NSMenu(title: "View")
        view.addItem(item("Zoom In", #selector(MainWindowController.pgZoomIn(_:)), key: "=", target: wc))
        view.addItem(item("Zoom Out", #selector(MainWindowController.pgZoomOut(_:)), key: "-", target: wc))
        view.addItem(item("Actual Size", #selector(MainWindowController.pgZoomActual(_:)), key: "0", target: wc))
        view.addItem(item("Fit in Window", #selector(MainWindowController.pgZoomFit(_:)), key: "9", target: wc))
        view.addItem(.separator())
        let snap = item("Snap to Grid", #selector(MainWindowController.pgToggleSnap(_:)), key: "G", target: wc)
        snap.state = wc.canvas.snapEnabled ? .on : .off
        view.addItem(snap)
        viewItem.submenu = view

        // Window
        let winItem = NSMenuItem()
        main.addItem(winItem)
        let win = NSMenu(title: "Window")
        win.addItem(item("Minimize", #selector(NSWindow.performMiniaturize(_:)), key: "m"))
        win.addItem(item("Zoom", #selector(NSWindow.performZoom(_:))))
        winItem.submenu = win

        // Help
        let helpItem = NSMenuItem()
        main.addItem(helpItem)
        let help = NSMenu(title: "Help")
        help.addItem(item("Keyboard Shortcuts & Tips", #selector(MainWindowController.pgHelp(_:)), target: wc))
        helpItem.submenu = help

        return main
    }
}
