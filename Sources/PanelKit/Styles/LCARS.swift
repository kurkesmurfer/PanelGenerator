import Foundation
import CoreGraphics

/// Star Trek: TNG LCARS: solid filled curves (elbows, swirls, sweeping ring
/// sectors) in the Okudagram colours. The elbow and swirl geometry is in
/// LCARS+Paths.swift.
package enum LCARS {

    /// The classic Okudagram colours.
    package static let okudagram = SwatchGroup(title: "LCARS", swatches: [
        Swatch("Orange",     .hex("#FF9C00")),
        Swatch("Amber",      .hex("#FFAA33")),
        Swatch("Gold",       .hex("#FFCC66")),
        Swatch("Peach",      .hex("#FFCC99")),
        Swatch("Apricot",    .hex("#FF9966")),
        Swatch("Salmon",     .hex("#CC8F99")),
        Swatch("Cardassian", .hex("#CC6666")),
        Swatch("Alert Red",  .hex("#DD4444")),
        Swatch("Lavender",   .hex("#CC99CC")),
        Swatch("Periwinkle", .hex("#9999CC")),
        Swatch("Sky",        .hex("#99CCFF")),
        Swatch("Steel",      .hex("#6688AA")),
        // A bright accent, not a background: see Serge "Serge Light BG".
        Swatch("Vanilla",    .hex("#FFFF99")),
        Swatch("Ink",        .hex("#101018")),
    ])

    package static let palette: [PaletteSection] = [
        PaletteSection(title: "LCARS", entries: [
            PaletteEntry(.elbow, nil, "Elbow"),
            PaletteEntry(.swirl, nil, "Swirl"),
        ]),
    ]

    package static let language = DesignLanguage(
        id: "lcars", name: "LCARS",
        swatchGroups: [okudagram],
        paletteSections: palette,
        applyPreset: { _, _ in false })
}
