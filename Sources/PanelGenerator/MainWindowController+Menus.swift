import AppKit
import UniformTypeIdentifiers
import PanelKit

// Window: menu validation.

extension MainWindowController {

    // MARK: Menu validation

    /// Cut/Copy/Paste/Delete: a disabled menu item that still *claims* a key
    /// equivalent doesn't let the keystroke fall through to whatever has
    /// focus -- AppKit treats the key as consumed and just beeps. So an
    /// `isEditingText` guard here (an earlier version of this fix) was the
    /// wrong shape: it correctly detected real text editing, but disabling
    /// these items while a field editor was focused made the *beep* follow
    /// the text cursor instead of curing it -- confirmed live: opening the
    /// Edit menu by hand re-validates and reads enabled, yet the raw key
    /// still beeped, because the disabled-item interception happens before
    /// that revalidation is ever consulted for a real keystroke.
    ///
    /// The actual fix is standard Cocoa, not a focus check: these four menu
    /// items are wired with a *nil* target (AppDelegate.swift) and this
    /// controller's methods use the exact selector names AppKit's own
    /// NSText/NSTextView editing already implements (copy(_:), cut(_:),
    /// paste(_:), delete(_:)) instead of the pg-prefixed names every other
    /// custom action uses. A nil-targeted action is resolved fresh against
    /// the current first responder chain on every keystroke: while a field
    /// editor is first responder, AppKit finds *its* copy(_:) before ever
    /// reaching this controller (a window's windowController sits later in
    /// the chain, after its view hierarchy), so plain text editing keeps
    /// working automatically, validated by NSTextView's own
    /// enabled-when-something's-selected logic -- nothing here needs to
    /// know editing is happening at all. Once nothing text-related is
    /// first responder, resolution falls through to these methods and
    /// validateMenuItem below, exactly as for every other canvas-selection
    /// action in this switch.
    func validateMenuItem(_ menuItem: NSMenuItem) -> Bool {
        switch menuItem.action {
        case #selector(pgToggleSnap(_:)):
            menuItem.state = canvas.snapEnabled ? .on : .off
        case #selector(pgSetSnapStep(_:)):
            menuItem.state = (canvas.snapMode == .uniform
                              && Int((canvas.snapStep * 100).rounded()) == menuItem.tag) ? .on : .off
        case #selector(pgSetSergeGrid(_:)):
            menuItem.state = canvas.snapMode == .sergeGrid ? .on : .off
        case #selector(pgToggleSergeOuterHalfStep(_:)):
            menuItem.state = canvas.document.sergeGridOuterHalfSteps ? .on : .off
        case #selector(pgSetCustomGrid(_:)):
            menuItem.state = canvas.snapMode == .customGrid ? .on : .off
        case #selector(pgSetThemePreview(_:)):
            let wantsLight = menuItem.tag == 1
            menuItem.state = (canvas.themePreview == .light) == wantsLight ? .on : .off
        case #selector(pgDeselectAll(_:)):
            return !canvas.selection.isEmpty
        case #selector(pgUndo(_:)):
            return canvas.edits.canUndo
        case #selector(pgRedo(_:)):
            return canvas.edits.canRedo
        case #selector(delete(_:)):
            return !canvas.selection.isEmpty
        case #selector(copy(_:)), #selector(cut(_:)):
            return !canvas.selection.isEmpty
        case #selector(paste(_:)):
            return canvas.canPaste
        case #selector(pgDuplicate(_:)), #selector(pgFront(_:)), #selector(pgBack(_:)),
             #selector(pgMakeWidget(_:)), #selector(pgLabelSelection(_:)),
             #selector(pgAddStamp(_:)):
            return !canvas.selection.isEmpty
        default:
            break
        }
        return true
    }
}
