import AppKit
import PanelKit
import PanelCanvas

final class AppDelegate: NSObject, NSApplicationDelegate {
    var windowController: MainWindowController!

    func applicationDidFinishLaunching(_ notification: Notification) {
        // The whole chrome is dark; force dark appearance so native controls
        // (labels, fields, checkboxes, sliders) stay legible on it.
        NSApp.appearance = NSAppearance(named: .darkAqua)
        // Before the palette is built, or the shipped stamps would not appear
        // until the next launch.
        StampLibrary.installSeeds()
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
        file.addItem(item("Import SVG…", #selector(MainWindowController.pgImportSVG(_:)), key: "i", target: wc))
        let moduleImport = item("Import Module Code…", #selector(MainWindowController.pgImportModuleCode(_:)), key: "i", target: wc)
        moduleImport.keyEquivalentModifierMask = [.command, .option]
        file.addItem(moduleImport)
        file.addItem(.separator())
        file.addItem(item("Export SVG…", #selector(MainWindowController.pgExportSVG(_:)), key: "e", target: wc))
        file.addItem(item("Export PNG…", #selector(MainWindowController.pgExportPNG(_:)), key: "E", target: wc))
        let codeItem = item("Export Widget Code…", #selector(MainWindowController.pgExportCode(_:)), key: "e", target: wc)
        codeItem.keyEquivalentModifierMask = [.command, .option]
        file.addItem(codeItem)
        file.addItem(item("Check Panel for Issues…", #selector(MainWindowController.pgCheckPanel(_:)), target: wc))
        fileItem.submenu = file

        // Edit
        let editItem = NSMenuItem()
        main.addItem(editItem)
        let edit = NSMenu(title: "Edit")
        edit.addItem(item("Undo", #selector(MainWindowController.pgUndo(_:)), key: "z", target: wc))
        edit.addItem(item("Redo", #selector(MainWindowController.pgRedo(_:)), key: "Z", target: wc))
        edit.addItem(.separator())
        edit.addItem(item("Cut", #selector(MainWindowController.cut(_:)), key: "x"))
        edit.addItem(item("Copy", #selector(MainWindowController.copy(_:)), key: "c"))
        edit.addItem(item("Paste", #selector(MainWindowController.paste(_:)), key: "v"))
        edit.addItem(.separator())
        edit.addItem(item("Duplicate", #selector(MainWindowController.pgDuplicate(_:)), key: "d", target: wc))
        // Plain Backspace (no ⌘) deletes the selection. Safe with an empty
        // modifier mask because it is nil-targeted (see delete(_:) below): a
        // real text edit in progress resolves to the field editor's own
        // delete(_:) first and never reaches this one.
        let deleteItem = item("Delete", #selector(MainWindowController.delete(_:)), key: "\u{7F}")
        deleteItem.keyEquivalentModifierMask = []
        edit.addItem(deleteItem)
        edit.addItem(.separator())
        edit.addItem(item("Select All", #selector(MainWindowController.pgSelectAll(_:)), key: "a", target: wc))
        edit.addItem(item("Deselect All", #selector(MainWindowController.pgDeselectAll(_:)), key: "A", target: wc))
        edit.addItem(.separator())
        edit.addItem(item("Bring to Front", #selector(MainWindowController.pgFront(_:)), target: wc))
        edit.addItem(item("Send to Back", #selector(MainWindowController.pgBack(_:)), target: wc))
        edit.addItem(.separator())
        edit.addItem(item("Insert Corner Screws", #selector(MainWindowController.pgScrews(_:)), target: wc))
        edit.addItem(item("Bind Primitives as Components", #selector(MainWindowController.pgBindPrimitives(_:)), target: wc))
        edit.addItem(item("Make Widget from Selection…", #selector(MainWindowController.pgMakeWidget(_:)), target: wc))
        edit.addItem(item("Label Selection…", #selector(MainWindowController.pgLabelSelection(_:)), key: "l", target: wc))
        edit.addItem(item("Name from Labels", #selector(MainWindowController.pgNameFromLabels(_:)), key: "L", target: wc))
        edit.addItem(item("Adopt Identifiers…", #selector(MainWindowController.pgAdoptIdentifiers(_:)), target: wc))
        edit.addItem(item("Fit to Panel…", #selector(MainWindowController.pgFitToPanel(_:)), target: wc))
        edit.addItem(.separator())
        edit.addItem(item("Add Selection to Palette…", #selector(MainWindowController.pgAddStamp(_:)), target: wc))
        edit.addItem(item("Reload Palette Stamps", #selector(MainWindowController.pgReloadStamps(_:)), target: wc))
        edit.addItem(item("Reveal Palette Stamps in Finder", #selector(MainWindowController.pgRevealStamps(_:)), target: wc))
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

        let stepItem = NSMenuItem(title: "Snap Step", action: nil, keyEquivalent: "")
        let stepMenu = NSMenu(title: "Snap Step")
        // Serge's non-uniform row/column grid is the default snap mode; it
        // covers placement and movement, so it's listed above the uniform
        // steps that still govern resize handles and arrow-key nudging.
        stepMenu.addItem(item("Serge Grid", #selector(MainWindowController.pgSetSergeGrid(_:)), target: wc))
        // Per-document setting, independent of which mode is active: one
        // further half-step row beyond the top/bottom of Serge's standard
        // 5-row grid, for real panels that push a row of LEDs/jacks that
        // far out (e.g. the GTS's top LED row).
        stepMenu.addItem(item("Serge Grid: Outer Half-Step",
                              #selector(MainWindowController.pgToggleSergeOuterHalfStep(_:)), target: wc))
        // A plain, editable N x M grid for panels whose real layout doesn't
        // follow Serge's standardised one -- always opens a dialog asking
        // for column/row counts, since that's a per-panel choice.
        stepMenu.addItem(item("Custom Grid…", #selector(MainWindowController.pgSetCustomGrid(_:)), target: wc))
        stepMenu.addItem(.separator())
        // 15 px is 1 HP. Tags carry the step in hundredths of a pixel.
        let steps: [(String, CGFloat)] = [
            ("1 px — 0.34 mm", 1),
            ("⅛ HP — 0.64 mm", 15.0 / 8),
            ("¼ HP — 1.27 mm", 15.0 / 4),
            ("½ HP — 2.54 mm", 15.0 / 2),
            ("1 HP — 5.08 mm", 15),
        ]
        for (title, value) in steps {
            let mi = item(title, #selector(MainWindowController.pgSetSnapStep(_:)), target: wc)
            mi.tag = Int((value * 100).rounded())
            stepMenu.addItem(mi)
        }
        stepItem.submenu = stepMenu
        view.addItem(stepItem)

        // Theme facility: preview which of a themed document's two colour
        // variants the canvas draws. Editing-only (never saved) and inert
        // on a document that hasn't opted into theming -- see
        // PanelDocument.isThemed / InspectorView's "Theme" section.
        let themeItem = NSMenuItem(title: "Theme", action: nil, keyEquivalent: "")
        let themeMenu = NSMenu(title: "Theme")
        let dark = item("Preview: Dark", #selector(MainWindowController.pgSetThemePreview(_:)), target: wc)
        dark.tag = 0
        let light = item("Preview: Light", #selector(MainWindowController.pgSetThemePreview(_:)), target: wc)
        light.tag = 1
        themeMenu.addItem(dark)
        themeMenu.addItem(light)
        themeItem.submenu = themeMenu
        view.addItem(themeItem)
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
        help.addItem(item("Workflow Manual", #selector(MainWindowController.pgWorkflowManual(_:)), key: "?", target: wc))
        help.addItem(item("Keyboard Shortcuts & Tips", #selector(MainWindowController.pgHelp(_:)), target: wc))
        helpItem.submenu = help

        return main
    }
}
