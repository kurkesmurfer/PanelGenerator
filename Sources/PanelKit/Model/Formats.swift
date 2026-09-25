import Foundation
import CoreGraphics
import AppKit

// MARK: - Panel format

package enum PanelFormat: String, Codable, CaseIterable {
    case u1 = "1U"
    case u3 = "3U"
}

/// Which of a themed document's two colour pairs (`background`/
/// `lightBackground`, `inkDark`/`inkLight`) is currently in play -- for
/// on-canvas preview, SVG export, and `--emit`. `.dark` always resolves to
/// the document's own untouched `background`/`inkDark`/element `fill`
/// values, so nothing about an existing, non-themed document changes
/// unless something explicitly asks for `.light`.
package enum ThemeVariant: String, Codable, CaseIterable {
    case dark, light
}

// MARK: - Export units

/// Unit written into an exported SVG's `width`/`height`. The viewBox stays in
/// panel pixels either way, so no geometry is rescaled — only the declared
/// physical size of the canvas changes.
///
/// Millimetres are what Rack's own documentation, helper.py's `mm` branch and
/// every MetaModule rasteriser expect. A unitless pixel size is not merely
/// less idiomatic: a rasteriser that reads `width="…mm"` fails outright on it.
package enum SVGUnits: String, Codable, CaseIterable {
    case millimetres, pixels
    package var displayName: String { self == .millimetres ? "Millimetres" : "Pixels" }
}
