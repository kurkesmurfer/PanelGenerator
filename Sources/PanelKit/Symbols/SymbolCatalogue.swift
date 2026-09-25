import Foundation
import CoreGraphics

// MARK: - Symbol design language
//
// See Docs/SYMBOLS.md for the rules. In short:
//
//  * Every symbol is authored as a *centreline* in a unit box, 0…1 on both
//    axes, y downward — the same orientation as the panel.
//  * The centreline is stroked into a filled outline at the element's weight.
//    Nothing in the family is a hairline: LCARS is solid shape, and a stroke
//    thin enough to look right on screen disappears entirely at MetaModule's
//    240 px faceplate.
//  * Weight is a fraction of the symbol's short side, so a glyph looks the
//    same at 12 px and at 120 px. That is what makes the set scalable rather
//    than merely resizable.
//  * The content box is inset by half the weight, so the outline — round caps
//    included — can never spill outside the element's frame.

package enum SymbolCategory: String, Codable, CaseIterable {
    case signal, function, filter, mark, glyph

    package var displayName: String {
        switch self {
        case .signal:   return "Signal"
        case .function: return "Function"
        case .filter:   return "Filter"
        case .mark:     return "Mark"
        case .glyph:    return "Glyph"
        }
    }
}

/// Everything a symbol's geometry is allowed to depend on.
package struct SymbolContext {
    /// The inset unit box the centreline is drawn in.
    package let box: CGRect
    /// Four normalised parameters, 0…1. Meaning is per symbol.
    package let p: [CGFloat]

    package func at(_ t: CGFloat, _ v: CGFloat) -> CGPoint {
        CGPoint(x: box.minX + t * box.width, y: box.minY + v * box.height)
    }
}

package struct SymbolSpec {
    package let id: String
    package let name: String
    package let category: SymbolCategory
    /// Waveforms stretch to whatever frame you give them; marks whose meaning
    /// depends on their proportions are drawn in the largest centred square.
    package let preservesAspect: Bool
    /// Labels for the four parameter slots. nil means the symbol ignores it.
    package let parameters: [String?]
    package let defaults: [CGFloat]
    package let centreline: (SymbolContext) -> CGPath
}

// MARK: - Catalogue

package enum SymbolCatalogue {

    /// Weight as a fraction of the short side. Clamped so the inset rule below
    /// always has room to work.
    package static let defaultWeight: CGFloat = 0.16
    package static let minWeight: CGFloat = 0.04
    package static let maxWeight: CGFloat = 0.28
    /// Never let a ribbon collapse below this in panel pixels — 1.2 px is
    /// roughly 0.4 mm, which is about the finest a panel is worth printing.
    package static let minWeightPixels: CGFloat = 1.2

    package static let all: [SymbolSpec] = signals + functions + filters + marks + glyphs

    package static func spec(_ id: String) -> SymbolSpec {
        all.first { $0.id == id } ?? all[0]
    }

    package static func specs(in category: SymbolCategory) -> [SymbolSpec] {
        all.filter { $0.category == category }
    }

    /// The finished, fillable outline for an element, in panel coordinates.
    package static func path(for el: PanelElement) -> CGPath {
        let spec = spec(el.params.symbol)
        let f = el.frame

        // Where the unit box lands inside the element.
        var target = CGRect(origin: .zero, size: f.size)
        if spec.preservesAspect {
            let side = min(f.width, f.height)
            target = CGRect(x: (f.width - side) / 2, y: (f.height - side) / 2,
                            width: side, height: side)
        }
        guard target.width > 0, target.height > 0 else { return CGMutablePath() }

        let weight = min(max(el.params.weight, minWeight), maxWeight)
        // Inset by half the weight so the stroked outline, round caps and all,
        // stays inside the frame whatever the weight.
        let inset = weight / 2
        let box = CGRect(x: inset, y: inset, width: 1 - inset * 2, height: 1 - inset * 2)

        let context = SymbolContext(box: box, p: [
            el.params.symbolA, el.params.symbolB, el.params.symbolC, el.params.symbolD,
        ])
        let unit = spec.centreline(context)

        var transform = CGAffineTransform(translationX: f.minX + target.minX,
                                          y: f.minY + target.minY)
            .scaledBy(x: target.width, y: target.height)
        guard let placed = unit.copy(using: &transform) else { return unit }

        let px = max(minWeightPixels, weight * min(target.width, target.height))
        return placed.copy(strokingWithWidth: px, lineCap: .round, lineJoin: .round, miterLimit: 4)
    }
}
