import Foundation
import CoreGraphics
import AppKit

// MARK: - Document

package struct PanelDocument: Codable, Hashable {
    /// On-disk shape version. Decoding is tolerant (a missing key falls back to
    /// the property default), so this is for diagnostics and future migrations,
    /// not for gating loads. 0 means "read from a file written before versioning
    /// existed"; `save` stamps the current version, so it never survives a
    /// round-trip.
    package static let currentSchemaVersion = 2
    package var schemaVersion: Int = PanelDocument.currentSchemaVersion

    /// An empty document with every setting at its default.
    package init() {}
    package var name: String = "Untitled"
    package var widthHP: Int = 8
    package var format: PanelFormat = .u3
    /// Divisions for `.customGrid` snap mode: an evenly-spaced N x M grid
    /// across the panel, for real modules whose actual layout doesn't
    /// follow Serge's standardised grid -- e.g. an imported panel that
    /// genuinely has 5 columns, not Serge's 4. Edited via View > Snap Step
    /// > Custom Grid..., which asks for both counts in a dialog.
    package var customGridColumns: Int = 4
    package var customGridRows: Int = 5
    /// Serge-style intermediate snap positions for the custom grid -- half
    /// rows and half-lane columns at the interior cell boundaries, on the
    /// diagonal cross between four main-grid points, exactly like
    /// `SergeGrid`'s own half-row/half-lane convention (reserved for LEDs/
    /// switches/jacks, never knobs, by Serge's own unenforced convention).
    package var customGridHalfPositions: Bool = false
    /// Finer, uncorrelated quarter-cell snap positions for the custom grid --
    /// two per cell per axis (at 1/4 and 3/4 of each column's width / row's
    /// height), available on any row or column regardless of main/half kind.
    /// Unlike `customGridHalfPositions`'s Serge-style diagonal correlation,
    /// this tier exists for layouts where two components flank a half
    /// position rather than share it -- e.g. a RISE/FALL knob pair's
    /// independent EXPO switches flanking the single half-lane column their
    /// shared CYCLE switch already occupies (the real GTO panel does this).
    package var customGridFinerPositions: Bool = false
    /// Extends `SergeGrid`'s half-row ladder by one further half-step (the
    /// same pitch as the existing interior half rows) beyond the topmost and
    /// bottommost main rows. Real Serge panels occasionally push a row of
    /// LEDs/jacks that far out -- e.g. the GTS's top LED row, which sits
    /// roughly a half-step above the standard grid's row 1 -- a position the
    /// interior half-row ladder alone can't reach. Opt-in because it's not
    /// part of Serge's own documented grid.
    package var sergeGridOuterHalfSteps: Bool = false
    // #1D1713 -- confirmed against the real SpaceTime (Kurkesmurfer) plugin's
    // own shipped panel SVGs (~/Development/SpaceTime/vcv/res/*.svg): every
    // one of them, without exception, paints its background rect exactly
    // this value. The old #17171E here was never checked against the real
    // product -- an invented placeholder that happened to look plausible.
    // Also, not coincidentally, the same dark background the Serge track
    // uses (Panel-language.md's own reference), so the two design languages
    // share one true background colour rather than two that merely look
    // similar.
    package var background: ColorSpec = .hex("#1D1713")
    /// Theme facility: a panel is theme-aware once this is set to something
    /// other than nil -- that's the "paper" colour for the light variant
    /// (`background` itself is always the dark/default paper, so an
    /// untouched document keeps rendering and emitting exactly as it always
    /// has). `inkDark`/`inkLight` are the matching pair of "ink" colours --
    /// what any element with `PanelElement.followsInk` set actually draws in,
    /// per active theme variant, instead of its own literal `fill`. Two
    /// roles only (ink/paper), not an open palette: the motivating case
    /// (Peet's hand-built GTS/GTS_Light pair) showed every themed difference
    /// between a dark and light panel was exactly these two things -- the
    /// backdrop and the label colour -- with every other element (jacks,
    /// knobs, LEDs) unchanged between variants.
    package var lightBackground: ColorSpec? = nil
    package var inkDark: ColorSpec = .hex("#E8E8F0")
    package var inkLight: ColorSpec = .black
    /// True once a document has an explicit light variant to emit/preview.
    package var isThemed: Bool { lightBackground != nil }
    /// The paper (background) or ink (label) colour to actually draw, for
    /// the given theme variant -- `dark` reproduces the document's own
    /// untouched values, so an unthemed document renders identically
    /// whichever variant is asked for.
    package func paper(for variant: ThemeVariant) -> ColorSpec {
        variant == .dark ? background : (lightBackground ?? background)
    }
    package func ink(for variant: ThemeVariant) -> ColorSpec {
        variant == .dark ? inkDark : inkLight
    }
    /// The colour an element actually draws in, for the given theme variant:
    /// its own literal `fill` unless it opted into following the panel's ink.
    package func resolvedFill(_ element: PanelElement, for variant: ThemeVariant) -> ColorSpec {
        if element.followsPaper { return paper(for: variant) }
        if element.followsInk { return ink(for: variant) }
        return element.fill
    }
    /// `element`, with `fill` substituted per `resolvedFill` when it follows
    /// the panel's paper or ink -- everything else about it (geometry,
    /// stroke, params) is untouched. The one place theme resolution actually
    /// happens; every renderer (canvas, SVG, PNG) calls this once per
    /// element rather than re-implementing the followsPaper/followsInk
    /// checks itself. `followsPaper` wins if an element somehow has both set
    /// -- not a combination the Inspector offers, but paper is the more
    /// specific "blend into the background" intent of the two.
    package func resolved(_ element: PanelElement, for variant: ThemeVariant) -> PanelElement {
        guard element.followsPaper || element.followsInk else { return element }
        var e = element
        e.fill = resolvedFill(element, for: variant)
        return e
    }
    /// Export labels as glyph outlines. Must stay on for VCV Rack: its SVG
    /// parser (nanosvg) has no text support and silently drops <text>. Turn it
    /// off only to hand editable text to Illustrator / Inkscape.
    package var textAsPaths: Bool = true
    /// Plugin and module slugs used by the generated widget code. Slugs are
    /// permanent once a patch has been saved with the module — treat them as
    /// immutable from first use.
    package var pluginSlug: String = "MyPlugin"
    package var moduleSlug: String = "MyModule"
    /// Namespace to wrap generated custom widgets in, e.g. `museui`. Empty
    /// puts them at file scope.
    package var widgetNamespace: String = ""
    package var svgUnits: SVGUnits = .millimetres
    package var elements: [PanelElement] = []

    /// Elements Rack / MetaModule will draw themselves, in stable top-left
    /// reading order so generated code and enums keep a sensible sequence.
    package var components: [PanelElement] {
        elements
            .filter { $0.role.isComponent && $0.isHidden != true && !isWidgetArtwork($0) }
            .sorted(by: PanelDocument.readingOrder)
    }

    /// Top row first, left to right within a row.
    ///
    /// The row tolerance matters: a row of jacks aligned by eye is not aligned
    /// to the micron, and exact equality on y would order a row by that noise
    /// instead of by position — scrambling the generated enum.
    package static func readingOrder(_ a: PanelElement, _ b: PanelElement) -> Bool {
        let rowHeight: CGFloat = 8
        let rowA = (a.center.y / rowHeight).rounded()
        let rowB = (b.center.y / rowHeight).rounded()
        return rowA == rowB ? a.center.x < b.center.x : rowA < rowB
    }

    /// Number these elements from one prefix, in reading order. Naming fifteen
    /// jacks one at a time is the tedium this removes; the identifiers are what
    /// make the generated enum readable as IN_1 rather than JACK_3_5_MM_7.
    package mutating func nameSequentially(ids: Set<UUID>, prefix: String) {
        let trimmed = prefix.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return }
        let ordered = elements.filter { ids.contains($0.id) }.sorted(by: PanelDocument.readingOrder)
        for (index, element) in ordered.enumerated() {
            guard let i = elements.firstIndex(where: { $0.id == element.id }) else { continue }
            elements[i].enumName = ordered.count == 1 ? trimmed : "\(trimmed)_\(index + 1)"
        }
    }

    /// The text a generated label should carry: the identifier you gave the
    /// element, not the kind it happens to be. An element still holding its
    /// default layer name gets no label — twenty jacks all reading
    /// "Jack (3.5 mm)" is worse than none, and the fix is to name them first.
    package func labelText(for el: PanelElement, uppercase: Bool, spaceUnderscores: Bool) -> String? {
        var raw = el.enumName.trimmingCharacters(in: .whitespaces)
        if raw.isEmpty && el.name != el.kind.displayName {
            raw = el.name.trimmingCharacters(in: .whitespaces)
        }
        guard !raw.isEmpty else { return nil }
        // Underscores are an identifier artefact: CUTOFF_FREQ is how the enum
        // must read, "CUTOFF FREQ" is how the panel must read.
        if spaceUnderscores { raw = raw.replacingOccurrences(of: "_", with: " ") }
        return uppercase ? raw.uppercased() : raw
    }

    /// Turn tracing template artwork into ordinary artwork, or back.
    ///
    /// A template is deliberately hard to touch — faint, unclickable, out of
    /// Select All — which is right while you are drawing over it and wrong the
    /// moment you decide to keep it. Without this the only way back is to
    /// import the file again and lose the work done since.
    @discardableResult
    package mutating func setTemplate(_ on: Bool, ids: Set<UUID>) -> Int {
        var changed = 0
        for i in elements.indices where ids.contains(elements[i].id) {
            let now = elements[i].isTemplate == true
            guard now != on else { continue }
            elements[i].isTemplate = on ? true : nil
            changed += 1
        }
        return changed
    }

    /// Elements that will not reach any export because they are templates.
    package var templateElements: [PanelElement] { elements.filter { $0.isTemplate == true } }

    package var pixelSize: CGSize { PanelMetrics.size(hp: widthHP, format: format) }
}

// MARK: - Tolerant decoding (see Decoding.swift)
//
// Kept beside the type: the synthesised CodingKeys are only visible in the
// file that declares it.

extension PanelDocument {
    /// Pre-v2 documents stored armH/armH2/armV as the straight arm run
    /// BEYOND the corner (`W = armH + ro`); v2 reinterprets them as the
    /// total reach INCLUDING the corner (`W = max(armH, ro)`), so that
    /// growing the reach no longer eats into the rendered thickness. This
    /// recomputes every pre-v2 elbow/swirl element's stored values so it
    /// keeps rendering exactly as it did before the change.
    package static func migrateReachSemantics(_ elements: inout [PanelElement]) {
        for i in elements.indices {
            switch elements[i].kind {
            case .elbow, .swirl:
                let p = elements[i].params
                let thH = max(2, p.thickness)
                let thV = max(2, p.thicknessV)
                let ri = max(0, min(p.innerRadius, min(thH, thV)))
                let ro = max(thH, thV) + ri
                func oldReach(_ v: CGFloat) -> CGFloat { max(v + ro, ro * 2) }
                elements[i].params.armH = oldReach(p.armH)
                if elements[i].kind == .elbow {
                    elements[i].params.armV = oldReach(p.armV)
                } else {
                    elements[i].params.armH2 = oldReach(p.armH2)
                }
            default:
                break
            }
        }
    }
}
extension PanelDocument {
    package init(from decoder: Decoder) throws {
        self.init()
        let c = try decoder.container(keyedBy: CodingKeys.self)
        // Explicit 0, not the current default: no key means the file predates
        // versioning, which is worth being able to tell apart from a v1 file.
        schemaVersion = try c.decodeOr(.schemaVersion, 0)
        name          = try c.decodeOr(.name, name)
        widthHP       = try c.decodeOr(.widthHP, widthHP)
        format        = try c.decodeOr(.format, format)
        customGridColumns = try c.decodeOr(.customGridColumns, customGridColumns)
        customGridRows    = try c.decodeOr(.customGridRows, customGridRows)
        customGridHalfPositions = try c.decodeOr(.customGridHalfPositions, customGridHalfPositions)
        customGridFinerPositions = try c.decodeOr(.customGridFinerPositions, customGridFinerPositions)
        sergeGridOuterHalfSteps  = try c.decodeOr(.sergeGridOuterHalfSteps, sergeGridOuterHalfSteps)
        background    = try c.decodeOr(.background, background)
        lightBackground = try c.decodeIfPresent(ColorSpec.self, forKey: .lightBackground)
        inkDark       = try c.decodeOr(.inkDark, inkDark)
        inkLight      = try c.decodeOr(.inkLight, inkLight)
        textAsPaths   = try c.decodeOr(.textAsPaths, textAsPaths)
        pluginSlug    = try c.decodeOr(.pluginSlug, pluginSlug)
        moduleSlug      = try c.decodeOr(.moduleSlug, moduleSlug)
        widgetNamespace = try c.decodeOr(.widgetNamespace, widgetNamespace)
        svgUnits        = try c.decodeOr(.svgUnits, svgUnits)
        // Strict: one undecodable element must not silently yield a blank panel.
        elements      = try c.decodeIfPresent([PanelElement].self, forKey: .elements) ?? []
        if schemaVersion < 2 {
            PanelDocument.migrateReachSemantics(&elements)
        }
    }
}
