import Foundation
import CoreGraphics
import AppKit

// MARK: - Element parameters (flat & robust for JSON round-trips)

package struct ElementParams: Codable, Hashable {
    // Box per-corner radii
    package var cornerTL: CGFloat = 0
    package var cornerTR: CGFloat = 0
    package var cornerBR: CGFloat = 0
    package var cornerBL: CGFloat = 0
    /// Box notch: a rectangular tab added to the middle of one edge, for
    /// "sculpting" a box's outline around a neighbouring one -- e.g. Serge's
    /// GTO channel brackets, which step out around a central zone while
    /// every corner, including the two new reentrant ones, stays rounded.
    /// 0 = no notch (a plain rounded rect); 1/2/3/4 = top/right/bottom/left.
    package var notchEdge: CGFloat = 0
    /// Distance from that edge's start corner to the tab, in the direction
    /// of travel (top: left-to-right, right: top-to-bottom, bottom:
    /// right-to-left, left: bottom-to-top) -- so `start`/`length` read the
    /// same way regardless of which edge is chosen.
    package var notchStart: CGFloat = 0
    /// How far the tab spans along the edge.
    package var notchLength: CGFloat = 0
    /// How far the tab protrudes beyond the edge.
    package var notchDepth: CGFloat = 0
    /// Fillet radius at the tab's 4 new corners (both the two convex ones at
    /// its far end and the two concave ones where it meets the base edge).
    package var notchRadius: CGFloat = 4
    /// false (default): the notch is a tab that protrudes OUT beyond the
    /// edge, reaching toward a smaller neighbour (Serge's GTO brackets).
    /// true: the notch cuts IN instead, biting a rectangular recess out of
    /// this box so a bigger neighbour can overlap into what would
    /// otherwise be this box's own territory -- the same "sculpt around a
    /// neighbour" idea, the other direction round.
    package var notchInvert: Bool = false
    /// Sideways offset of a `.line` element's curve control point from its
    /// straight midpoint -- 0 is a plain straight line; Serge's own hardware
    /// often bows this kind of connector slightly around whatever sits
    /// between the knob and its jack.
    package var lineBow: CGFloat = 0
    // Elbow / Swirl
    package var thickness: CGFloat = 16   // horizontal-arm thickness
    /// Vertical-arm thickness, independent of `thickness` so the vertical
    /// run can be much wider (or narrower) than the horizontal one while
    /// both the outer and inner corner fillets stay perfectly circular --
    /// the fillet radii are keyed off `min`/`max` of the two thicknesses
    /// rather than assuming they match. Falls back to `thickness` when
    /// decoding older documents that predate this field, so old shapes
    /// keep rendering with symmetric arms exactly as before.
    package var thicknessV: CGFloat = 16
    package var innerRadius: CGFloat = 8
    package var armH: CGFloat = 56       // elbow's only arm; swirl's bottom arm
    package var armV: CGFloat = 56
    /// Swirl's top arm. Independent of `armH` so the knee (the spine) can
    /// sit off-centre -- equal values keep it where `armH` alone would put
    /// it. Unused by `.elbow`.
    package var armH2: CGFloat = 56
    package var flipX: Bool = false
    package var flipY: Bool = false
    // Ring sector
    package var startAngle: CGFloat = -90
    package var sweepAngle: CGFloat = 100
    // Knobs
    package var pointerAngle: CGFloat = 45       // degrees, 0 = pointing up
    /// 0 pointer only, 1 position ring only, 2 both. A plain knob is what Rack
    /// draws, so it stays the default and the ring is a separate palette entry
    /// rather than a changed meaning for an existing one.
    package var knobStyle: CGFloat = 0
    /// Total sweep of the open ring, degrees. 298.8 is Rack's own ±0.83·π.
    package var arcSpan: CGFloat = 298.8
    /// Ring thickness as a fraction of the knob's diameter.
    package var arcWidth: CGFloat = 0.10
    // Faders
    package var value: CGFloat = 0.5             // 0..1
    // Button groups
    package var segments: CGFloat = 4            // buttons in the group (2…12)
    package var layout: CGFloat = 0              // 0 column, 1 row, 2 cross, 3 circular
    // Text
    package var text: String = "LABEL"
    package var fontSize: CGFloat = 12
    package var bold: Bool = true
    // Symbols. `weight` is a fraction of the symbol's short side, so a glyph
    // keeps its proportions at any size. The four slots are generic: what each
    // means is declared by the symbol's SymbolSpec, which is what lets the
    // catalogue grow without touching the model.
    package var symbol: String = "sine"
    package var weight: CGFloat = 0.16
    package var symbolA: CGFloat = 0.5
    package var symbolB: CGFloat = 0.5
    package var symbolC: CGFloat = 0.5
    package var symbolD: CGFloat = 0.5
}

// MARK: - Tolerant decoding (see Decoding.swift)
//
// Kept beside the type: the synthesised CodingKeys are only visible in the
// file that declares it.

extension ElementParams {
    package init(from decoder: Decoder) throws {
        self.init()
        let c = try decoder.container(keyedBy: CodingKeys.self)
        cornerTL     = try c.decodeOr(.cornerTL, cornerTL)
        cornerTR     = try c.decodeOr(.cornerTR, cornerTR)
        cornerBR     = try c.decodeOr(.cornerBR, cornerBR)
        cornerBL     = try c.decodeOr(.cornerBL, cornerBL)
        notchEdge    = try c.decodeOr(.notchEdge, notchEdge)
        notchStart   = try c.decodeOr(.notchStart, notchStart)
        notchLength  = try c.decodeOr(.notchLength, notchLength)
        notchDepth   = try c.decodeOr(.notchDepth, notchDepth)
        notchRadius  = try c.decodeOr(.notchRadius, notchRadius)
        notchInvert  = try c.decodeOr(.notchInvert, notchInvert)
        lineBow      = try c.decodeOr(.lineBow, lineBow)
        thickness    = try c.decodeOr(.thickness, thickness)
        thicknessV   = try c.decodeOr(.thicknessV, thickness)
        innerRadius  = try c.decodeOr(.innerRadius, innerRadius)
        armH         = try c.decodeOr(.armH, armH)
        armV         = try c.decodeOr(.armV, armV)
        armH2        = try c.decodeOr(.armH2, armH2)
        flipX        = try c.decodeOr(.flipX, flipX)
        flipY        = try c.decodeOr(.flipY, flipY)
        startAngle   = try c.decodeOr(.startAngle, startAngle)
        sweepAngle   = try c.decodeOr(.sweepAngle, sweepAngle)
        pointerAngle = try c.decodeOr(.pointerAngle, pointerAngle)
        knobStyle    = try c.decodeOr(.knobStyle, knobStyle)
        arcSpan      = try c.decodeOr(.arcSpan, arcSpan)
        arcWidth     = try c.decodeOr(.arcWidth, arcWidth)
        value        = try c.decodeOr(.value, value)
        segments     = try c.decodeOr(.segments, segments)
        layout       = try c.decodeOr(.layout, layout)
        text         = try c.decodeOr(.text, text)
        fontSize     = try c.decodeOr(.fontSize, fontSize)
        bold         = try c.decodeOr(.bold, bold)
        symbol       = try c.decodeOr(.symbol, symbol)
        weight       = try c.decodeOr(.weight, weight)
        symbolA      = try c.decodeOr(.symbolA, symbolA)
        symbolB      = try c.decodeOr(.symbolB, symbolB)
        symbolC      = try c.decodeOr(.symbolC, symbolC)
        symbolD      = try c.decodeOr(.symbolD, symbolD)
    }
}
