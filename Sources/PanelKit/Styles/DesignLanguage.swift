import Foundation
import CoreGraphics

// MARK: - Design languages
//
// A design language is what one house style contributes to the editor: named
// colours for the swatch bank, entries for the palette, and the presets those
// entries apply on drop. The geometry every style shares (jacks, knobs, boxes,
// rings, text) stays in the model and the renderer; only what makes a panel
// read as Serge, LCARS or Kurkesmurfer lives under Styles/.
//
// Adding a language is one new file here and one line in `DesignLanguage.all`.

/// A named colour in the swatch bank.
package struct Swatch: Hashable {
    package let name: String
    package let color: ColorSpec

    package init(_ name: String, _ color: ColorSpec) {
        self.name = name
        self.color = color
    }
}

/// Swatches that belong together, e.g. the LCARS Okudagram set or Serge's
/// jack-ring colours.
package struct SwatchGroup {
    package let title: String
    package let swatches: [Swatch]
}

/// One palette cell: an element kind, and optionally a preset applied to the
/// element when it is dropped. The palette carries the preset on the
/// pasteboard as `kind#preset`, so preset ids must stay stable.
package struct PaletteEntry {
    package let kind: ElementKind
    package let preset: String?
    package let title: String

    package init(_ kind: ElementKind, _ preset: String? = nil, _ title: String) {
        self.kind = kind
        self.preset = preset
        self.title = title
    }
}

/// A titled palette section.
package struct PaletteSection {
    package let title: String
    package let entries: [PaletteEntry]
}

package struct DesignLanguage {
    package let id: String
    package let name: String
    package let swatchGroups: [SwatchGroup]
    package let paletteSections: [PaletteSection]
    /// Applies preset `id` to `element` if this language owns it and it fits
    /// the element's kind. Returns whether it did.
    package let applyPreset: (_ id: String, _ element: inout PanelElement) -> Bool
}

extension DesignLanguage {
    /// Every language, in palette order.
    package static let all: [DesignLanguage] = [
        Generic.language, Kurkesmurfer.language, Serge.language, LCARS.language,
    ]

    package static func named(_ id: String) -> DesignLanguage? {
        all.first { $0.id == id }
    }

    /// The inspector's swatch bank, in display order. Listed explicitly rather
    /// than derived from `all`: the light-panel paper colour leads the bank
    /// so a Serge light panel's background is one click away.
    package static let swatchBank: [SwatchGroup] = [
        Serge.paper, LCARS.okudagram, Serge.jackRings, Generic.leds,
    ]

    package static let allSwatches: [Swatch] = swatchBank.flatMap(\.swatches)

    /// Every language's palette sections, in order.
    package static var paletteSections: [PaletteSection] {
        all.flatMap(\.paletteSections)
    }

    /// Offers `id` to each language in turn; the first that owns it applies it.
    @discardableResult
    package static func applyPreset(_ id: String, to element: inout PanelElement) -> Bool {
        for language in all where language.applyPreset(id, &element) { return true }
        return false
    }
}

extension ColorSpec {
    /// A bank swatch by name, so defaults cite "Orange" rather than repeating
    /// "#FF9C00". An unknown name falls back to the first swatch rather than
    /// crashing.
    package static func swatch(_ name: String) -> ColorSpec {
        DesignLanguage.allSwatches.first { $0.name == name }?.color
            ?? DesignLanguage.allSwatches[0].color
    }
}
