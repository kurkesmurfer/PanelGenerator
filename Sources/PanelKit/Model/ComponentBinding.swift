import Foundation
import CoreGraphics
import AppKit

// MARK: - Component binding

/// What an element becomes in the generated widget code. `.decoration` is
/// artwork — it stays in the exported panel. Everything else is a live
/// component: Rack and MetaModule draw those themselves, so they are excluded
/// from the panel artwork and exported as positions instead.
package enum ComponentRole: String, Codable, CaseIterable {
    case decoration, param, input, output, light, custom

    package var displayName: String {
        switch self {
        case .decoration: return "Decoration (artwork)"
        case .param:      return "Param"
        case .input:      return "Input"
        case .output:     return "Output"
        case .light:      return "Light"
        case .custom:     return "Custom widget"
        }
    }

    /// Fill colour Rack's `helper.py` classifies a components-layer shape by.
    package var helperFill: String? {
        switch self {
        case .decoration: return nil
        case .param:      return "#ff0000"
        case .input:      return "#00ff00"
        case .output:     return "#0000ff"
        case .light:      return "#ff00ff"
        case .custom:     return "#ffff00"
        }
    }

    /// Suffix `helper.py` appends to the identifier it reads from `data-name`.
    package var enumSuffix: String {
        switch self {
        case .param:  return "_PARAM"
        case .input:  return "_INPUT"
        case .output: return "_OUTPUT"
        case .light:  return "_LIGHT"
        default:      return ""
        }
    }

    package var isComponent: Bool { self != .decoration }

    /// One-letter badge for the layer list. The colours are helper.py's own
    /// classification colours, so what you see in the list is what lands in the
    /// components layer.
    package var badge: String {
        switch self {
        case .decoration: return ""
        case .param:      return "P"
        case .input:      return "I"
        case .output:     return "O"
        case .light:      return "L"
        case .custom:     return "C"
        }
    }
}

/// Where a component's artwork comes from.
package enum WidgetSource: String, Codable, CaseIterable {
    /// A Rack ComponentLibrary type. Its size is fixed by Rack's own SVG, so
    /// the on-canvas element is a placement guide only — resizing it here
    /// changes nothing in Rack.
    case stock
    /// PanelGenerator's own artwork, exported as res/components/<name>.svg.
    /// `setSvg()` takes the widget's size from that file, so resizing here is
    /// the way you resize the control.
    case custom

    package var displayName: String { self == .stock ? "Rack default" : "Custom (own art)" }
}

// MARK: - Label placement

/// Where "Label Selection…" puts a generated label relative to its component.
package enum LabelPlacement: String, Codable, CaseIterable {
    case above, below, left, right
    package var displayName: String { rawValue.capitalized }
}
