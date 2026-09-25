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

enum SymbolCategory: String, Codable, CaseIterable {
    case signal, function, filter, mark, glyph

    var displayName: String {
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
struct SymbolContext {
    /// The inset unit box the centreline is drawn in.
    let box: CGRect
    /// Four normalised parameters, 0…1. Meaning is per symbol.
    let p: [CGFloat]

    func at(_ t: CGFloat, _ v: CGFloat) -> CGPoint {
        CGPoint(x: box.minX + t * box.width, y: box.minY + v * box.height)
    }
}

struct SymbolSpec {
    let id: String
    let name: String
    let category: SymbolCategory
    /// Waveforms stretch to whatever frame you give them; marks whose meaning
    /// depends on their proportions are drawn in the largest centred square.
    let preservesAspect: Bool
    /// Labels for the four parameter slots. nil means the symbol ignores it.
    let parameters: [String?]
    let defaults: [CGFloat]
    let centreline: (SymbolContext) -> CGPath
}

// MARK: - Geometry helpers

private func poly(_ c: SymbolContext, _ pts: [(CGFloat, CGFloat)]) -> CGPath {
    let path = CGMutablePath()
    for (i, q) in pts.enumerated() {
        let point = c.at(q.0, q.1)
        if i == 0 { path.move(to: point) } else { path.addLine(to: point) }
    }
    return path
}

private func sampled(_ c: SymbolContext, _ count: Int = 40, _ f: (CGFloat) -> CGFloat) -> CGPath {
    let path = CGMutablePath()
    for i in 0...count {
        let t = CGFloat(i) / CGFloat(count)
        let point = c.at(t, f(t))
        if i == 0 { path.move(to: point) } else { path.addLine(to: point) }
    }
    return path
}

/// Deterministic jitter. Not random: a symbol has to look the same every time
/// it is drawn, exported and re-opened.
private let noiseTable: [CGFloat] = [
    0.52, 0.14, 0.83, 0.31, 0.67, 0.05, 0.94, 0.42, 0.23, 0.78,
    0.11, 0.60, 0.36, 0.88, 0.19, 0.71, 0.47, 0.02, 0.63, 0.29,
]

/// One resonant peak, used by the filter responses.
private func peak(_ d: CGFloat, _ amount: CGFloat) -> CGFloat {
    amount * 0.32 * exp(-pow(d * 5.5, 2))
}


/// Several independent strokes in one path. Each run gets its own caps, which
/// is what lets a glyph be built from a spine plus separate attachments.
private func strokes(_ c: SymbolContext, _ runs: [[(CGFloat, CGFloat)]]) -> CGPath {
    let path = CGMutablePath()
    for run in runs where !run.isEmpty {
        for (i, q) in run.enumerated() {
            let p = c.at(q.0, q.1)
            if i == 0 { path.move(to: p) } else { path.addLine(to: p) }
        }
    }
    return path
}

/// Arc as a run of unit-space points, degrees, y downward.
private func arc(_ cx: CGFloat, _ cy: CGFloat, _ r: CGFloat,
                 from a0: CGFloat, to a1: CGFloat, steps: Int = 18) -> [(CGFloat, CGFloat)] {
    (0...steps).map { i in
        let a = (a0 + (a1 - a0) * CGFloat(i) / CGFloat(steps)) * .pi / 180
        return (cx + r * cos(a), cy + r * sin(a))
    }
}

/// A round cap on its own. The stroke is too short to see; the cap is the mark.
private func dot(_ x: CGFloat, _ y: CGFloat) -> [(CGFloat, CGFloat)] {
    [(x, y), (x + 0.002, y)]
}

/// Quarter turns about the centre of the unit box, y downward.
private func rotated(_ pts: [(CGFloat, CGFloat)], _ quarter: Int) -> [(CGFloat, CGFloat)] {
    pts.map { p in
        switch ((quarter % 4) + 4) % 4 {
        case 1:  return (1 - p.1, p.0)
        case 2:  return (1 - p.0, 1 - p.1)
        case 3:  return (p.1, 1 - p.0)
        default: return p
        }
    }
}

// MARK: - Catalogue

enum SymbolCatalogue {

    /// Weight as a fraction of the short side. Clamped so the inset rule below
    /// always has room to work.
    static let defaultWeight: CGFloat = 0.16
    static let minWeight: CGFloat = 0.04
    static let maxWeight: CGFloat = 0.28
    /// Never let a ribbon collapse below this in panel pixels — 1.2 px is
    /// roughly 0.4 mm, which is about the finest a panel is worth printing.
    static let minWeightPixels: CGFloat = 1.2

    static let all: [SymbolSpec] = signals + functions + filters + marks + glyphs

    static func spec(_ id: String) -> SymbolSpec {
        all.first { $0.id == id } ?? all[0]
    }

    static func specs(in category: SymbolCategory) -> [SymbolSpec] {
        all.filter { $0.category == category }
    }

    /// The finished, fillable outline for an element, in panel coordinates.
    static func path(for el: PanelElement) -> CGPath {
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

    // MARK: Signal shapes

    private static let signals: [SymbolSpec] = [
        SymbolSpec(id: "sine", name: "Sine", category: .signal, preservesAspect: false,
                   parameters: [nil, nil, nil, nil], defaults: [0.5, 0.5, 0.5, 0.5]) { c in
            sampled(c, 44) { t in 0.5 - 0.5 * sin(2 * .pi * t) }
        },

        SymbolSpec(id: "triangle", name: "Triangle", category: .signal, preservesAspect: false,
                   parameters: [nil, nil, nil, nil], defaults: [0.5, 0.5, 0.5, 0.5]) { c in
            poly(c, [(0, 0.5), (0.25, 0), (0.75, 1), (1, 0.5)])
        },

        SymbolSpec(id: "sawUp", name: "Saw ↗", category: .signal, preservesAspect: false,
                   parameters: [nil, nil, nil, nil], defaults: [0.5, 0.5, 0.5, 0.5]) { c in
            poly(c, [(0, 1), (0.86, 0), (0.86, 1), (1, 1)])
        },

        SymbolSpec(id: "sawDown", name: "Saw ↘", category: .signal, preservesAspect: false,
                   parameters: [nil, nil, nil, nil], defaults: [0.5, 0.5, 0.5, 0.5]) { c in
            poly(c, [(0, 0), (0.14, 1), (1, 0)])
        },

        SymbolSpec(id: "square", name: "Square", category: .signal, preservesAspect: false,
                   parameters: [nil, nil, nil, nil], defaults: [0.5, 0.5, 0.5, 0.5]) { c in
            poly(c, [(0, 1), (0, 0), (0.5, 0), (0.5, 1), (1, 1)])
        },

        SymbolSpec(id: "pulse", name: "Pulse", category: .signal, preservesAspect: false,
                   parameters: ["Width", nil, nil, nil], defaults: [0.3, 0.5, 0.5, 0.5]) { c in
            let w = min(max(c.p[0], 0.08), 0.92)
            return poly(c, [(0, 1), (0, 0), (w, 0), (w, 1), (1, 1)])
        },

        SymbolSpec(id: "noise", name: "Noise", category: .signal, preservesAspect: false,
                   parameters: ["Density", nil, nil, nil], defaults: [0.5, 0.5, 0.5, 0.5]) { c in
            let steps = 8 + Int(min(max(c.p[0], 0), 1) * 10)
            var pts: [(CGFloat, CGFloat)] = []
            for i in 0...steps {
                let t = CGFloat(i) / CGFloat(steps)
                pts.append((t, noiseTable[i % noiseTable.count]))
            }
            return poly(c, pts)
        },

        SymbolSpec(id: "sampleHold", name: "Sample & Hold", category: .signal, preservesAspect: false,
                   parameters: [nil, nil, nil, nil], defaults: [0.5, 0.5, 0.5, 0.5]) { c in
            let levels: [CGFloat] = [0.72, 0.18, 0.55, 0.05, 0.86]
            var pts: [(CGFloat, CGFloat)] = []
            for (i, v) in levels.enumerated() {
                let t0 = CGFloat(i) / CGFloat(levels.count)
                let t1 = CGFloat(i + 1) / CGFloat(levels.count)
                pts.append((t0, v))
                pts.append((t1, v))
            }
            return poly(c, pts)
        },
    ]

    // MARK: Function shapes

    private static let functions: [SymbolSpec] = [
        SymbolSpec(id: "adsr", name: "ADSR", category: .function, preservesAspect: false,
                   parameters: ["Attack", "Decay", "Sustain", "Release"],
                   defaults: [0.18, 0.22, 0.55, 0.28]) { c in
            let a = min(max(c.p[0], 0.02), 0.4)
            let d = min(max(c.p[1], 0.02), 0.4)
            let s = min(max(c.p[2], 0), 1)
            let r = min(max(c.p[3], 0.02), 0.4)
            let sustainY = 1 - s
            let hold = max(0.05, 1 - a - d - r)
            return poly(c, [(0, 1), (a, 0), (a + d, sustainY),
                            (a + d + hold, sustainY), (min(1, a + d + hold + r), 1)])
        },

        SymbolSpec(id: "ad", name: "AD", category: .function, preservesAspect: false,
                   parameters: ["Attack", "Decay", nil, nil], defaults: [0.3, 0.6, 0.5, 0.5]) { c in
            let a = min(max(c.p[0], 0.05), 0.8)
            return poly(c, [(0, 1), (a, 0), (1, 1)])
        },

        SymbolSpec(id: "slew", name: "Slew", category: .function, preservesAspect: false,
                   parameters: ["Rate", nil, nil, nil], defaults: [0.45, 0.5, 0.5, 0.5]) { c in
            // A step whose corner has been rounded off: the point of a slew.
            let rise = min(max(c.p[0], 0.08), 0.8)
            return sampled(c, 36) { t in
                if t < 0.12 { return 0.92 }
                let k = min(1, (t - 0.12) / rise)
                return 0.92 - 0.84 * (1 - exp(-3.2 * k))
            }
        },

        SymbolSpec(id: "clock", name: "Clock", category: .function, preservesAspect: false,
                   parameters: ["Divisions", nil, nil, nil], defaults: [0.35, 0.5, 0.5, 0.5]) { c in
            let n = 2 + Int(min(max(c.p[0], 0), 1) * 4)
            var pts: [(CGFloat, CGFloat)] = [(0, 1)]
            for i in 0..<n {
                let t0 = CGFloat(i) / CGFloat(n)
                let t1 = t0 + 0.45 / CGFloat(n)
                let t2 = CGFloat(i + 1) / CGFloat(n)
                pts += [(t0, 1), (t0, 0), (t1, 0), (t1, 1), (t2, 1)]
            }
            return poly(c, pts)
        },

        SymbolSpec(id: "gate", name: "Gate", category: .function, preservesAspect: false,
                   parameters: ["Length", nil, nil, nil], defaults: [0.6, 0.5, 0.5, 0.5]) { c in
            let len = min(max(c.p[0], 0.15), 0.9)
            let start = (1 - len) / 2
            return poly(c, [(0, 1), (start, 1), (start, 0),
                            (start + len, 0), (start + len, 1), (1, 1)])
        },
    ]

    // MARK: Filter responses

    private static let filters: [SymbolSpec] = [
        SymbolSpec(id: "lowpass", name: "Low Pass", category: .filter, preservesAspect: false,
                   parameters: ["Cutoff", "Resonance", nil, nil], defaults: [0.55, 0.45, 0.5, 0.5]) { c in
            let cut = min(max(c.p[0], 0.15), 0.85)
            let res = min(max(c.p[1], 0), 1)
            return sampled(c, 44) { t in
                let base: CGFloat = 0.34
                if t <= cut { return base - peak((cut - t) / max(cut, 0.001), res) }
                let k = (t - cut) / max(1 - cut, 0.001)
                return min(0.98, base - peak(k, res) + k * 0.64)
            }
        },

        SymbolSpec(id: "highpass", name: "High Pass", category: .filter, preservesAspect: false,
                   parameters: ["Cutoff", "Resonance", nil, nil], defaults: [0.45, 0.45, 0.5, 0.5]) { c in
            let cut = min(max(c.p[0], 0.15), 0.85)
            let res = min(max(c.p[1], 0), 1)
            return sampled(c, 44) { t in
                let base: CGFloat = 0.34
                if t >= cut { return base - peak((t - cut) / max(1 - cut, 0.001), res) }
                let k = (cut - t) / max(cut, 0.001)
                return min(0.98, base - peak(k, res) + k * 0.64)
            }
        },

        SymbolSpec(id: "bandpass", name: "Band Pass", category: .filter, preservesAspect: false,
                   parameters: ["Centre", "Q", nil, nil], defaults: [0.5, 0.5, 0.5, 0.5]) { c in
            let mid = min(max(c.p[0], 0.2), 0.8)
            let q = min(max(c.p[1], 0), 1)
            return sampled(c, 44) { t in
                let d = abs(t - mid) / 0.5
                let width = 0.9 - 0.55 * q
                return min(0.98, 0.16 + 0.82 * min(1, pow(d / max(width, 0.05), 1.6)))
            }
        },

        SymbolSpec(id: "notch", name: "Notch", category: .filter, preservesAspect: false,
                   parameters: ["Centre", "Depth", nil, nil], defaults: [0.5, 0.7, 0.5, 0.5]) { c in
            let mid = min(max(c.p[0], 0.2), 0.8)
            let depth = min(max(c.p[1], 0.1), 1)
            return sampled(c, 44) { t in
                let d = abs(t - mid) / 0.5
                let dip = depth * exp(-pow(d * 6, 2))
                return min(0.98, 0.3 + 0.66 * dip)
            }
        },
    ]

    // MARK: Flow and marks

    private static let marks: [SymbolSpec] = [
        SymbolSpec(id: "arrow", name: "Arrow", category: .mark, preservesAspect: false,
                   parameters: ["Direction", nil, nil, nil], defaults: [0, 0.5, 0.5, 0.5]) { c in
            let quarter = Int((min(max(c.p[0], 0), 0.999) * 4).rounded(.down))
            return strokes(c, [
                rotated([(0.04, 0.5), (0.72, 0.5)], quarter),
                rotated([(0.52, 0.24), (0.88, 0.5), (0.52, 0.76)], quarter),
            ])
        },

        SymbolSpec(id: "mult", name: "Mult", category: .mark, preservesAspect: false,
                   parameters: ["Ways", nil, nil, nil], defaults: [0.0, 0.5, 0.5, 0.5]) { c in
            let ways = c.p[0] < 0.5 ? 2 : 3
            var runs: [[(CGFloat, CGFloat)]] = [[(0.04, 0.5), (0.46, 0.5)]]
            if ways == 2 {
                runs.append([(0.46, 0.5), (0.72, 0.16), (0.96, 0.16)])
                runs.append([(0.46, 0.5), (0.72, 0.84), (0.96, 0.84)])
            } else {
                runs.append([(0.46, 0.5), (0.72, 0.12), (0.96, 0.12)])
                runs.append([(0.46, 0.5), (0.96, 0.5)])
                runs.append([(0.46, 0.5), (0.72, 0.88), (0.96, 0.88)])
            }
            return strokes(c, runs)
        },

        SymbolSpec(id: "sum", name: "Sum", category: .mark, preservesAspect: false,
                   parameters: [nil, nil, nil, nil], defaults: [0.5, 0.5, 0.5, 0.5]) { c in
            strokes(c, [
                [(0.04, 0.16), (0.30, 0.16), (0.54, 0.5)],
                [(0.04, 0.84), (0.30, 0.84), (0.54, 0.5)],
                [(0.54, 0.5), (0.96, 0.5)],
            ])
        },

        SymbolSpec(id: "invert", name: "Invert", category: .mark, preservesAspect: false,
                   parameters: [nil, nil, nil, nil], defaults: [0.5, 0.5, 0.5, 0.5]) { c in
            let path = CGMutablePath()
            for sign in [CGFloat(-1), CGFloat(1)] {
                for i in 0...28 {
                    let t = CGFloat(i) / 28
                    let p = c.at(t, 0.5 + sign * 0.42 * sin(2 * .pi * t))
                    if i == 0 { path.move(to: p) } else { path.addLine(to: p) }
                }
            }
            return path
        },

        SymbolSpec(id: "patchRing", name: "Patch Ring", category: .mark, preservesAspect: true,
                   parameters: [nil, nil, nil, nil], defaults: [0.5, 0.5, 0.5, 0.5]) { c in
            strokes(c, [arc(0.5, 0.5, 0.45, from: 0, to: 360, steps: 40)])
        },

        SymbolSpec(id: "attenuverter", name: "Attenuverter", category: .mark, preservesAspect: true,
                   parameters: ["Sweep", nil, nil, nil], defaults: [0.75, 0.5, 0.5, 0.5]) { c in
            // An arc with a detent mark at twelve o'clock: the zero point of a
            // bipolar control, which is the whole reason the mark exists.
            let span = 120 + min(max(c.p[0], 0), 1) * 190
            return strokes(c, [
                arc(0.5, 0.56, 0.42, from: -90 - span / 2, to: -90 + span / 2, steps: 34),
                [(0.5, 0.02), (0.5, 0.20)],
            ])
        },

        SymbolSpec(id: "bracket", name: "Range Bracket", category: .mark, preservesAspect: false,
                   parameters: ["Depth", nil, nil, nil], defaults: [0.45, 0.5, 0.5, 0.5]) { c in
            let d = min(max(c.p[0], 0.1), 0.9)
            return strokes(c, [[(0.02, 1), (0.02, 1 - d), (0.98, 1 - d), (0.98, 1)]])
        },

        SymbolSpec(id: "ticks", name: "Index Ticks", category: .mark, preservesAspect: false,
                   parameters: ["Count", "Centre mark", nil, nil], defaults: [0.4, 1, 0.5, 0.5]) { c in
            let count = 3 + Int(min(max(c.p[0], 0), 1) * 8)
            var runs: [[(CGFloat, CGFloat)]] = []
            for i in 0..<count {
                let t = count == 1 ? 0.5 : CGFloat(i) / CGFloat(count - 1)
                let tall = c.p[1] > 0.5 && i == count / 2 && count % 2 == 1
                runs.append([(t, tall ? 0.0 : 0.35), (t, 1)])
            }
            return strokes(c, runs)
        },

        SymbolSpec(id: "splitArrow", name: "Split Arrow", category: .mark, preservesAspect: true,
                   parameters: ["Curl", "Spread", nil, nil], defaults: [0.55, 0.45, 0.5, 0.5]) { c in
            // The Serge / Random*Source convention for a bipolar (attenuverting)
            // control: a hooked stroke that rises from beside the knob and
            // forks into two diverging prongs at the tip — "turns split two
            // ways," rather than the single arrowhead of a plain direction mark.
            let cx: CGFloat = 0.55, cy: CGFloat = 0.62, r: CGFloat = 0.36
            let a0: CGFloat = 158
            let curl = min(max(c.p[0], 0), 1)
            let a1 = a0 + 55 + curl * 95   // how far round the hook curls
            let hook = arc(cx, cy, r, from: a0, to: a1, steps: 26)
            let tip = hook.last!
            let rad = a1 * .pi / 180
            let radial = (cos(rad), sin(rad))   // points outward from the hook's own centre
            let spread = (20 + min(max(c.p[1], 0), 1) * 35) * .pi / 180
            let prongLength: CGFloat = 0.34
            func prong(_ sign: CGFloat) -> [(CGFloat, CGFloat)] {
                let a = spread * sign
                let ca = cos(a), sa = sin(a)
                let dx = radial.0 * ca - radial.1 * sa
                let dy = radial.0 * sa + radial.1 * ca
                return [tip, (tip.0 + dx * prongLength, tip.1 + dy * prongLength)]
            }
            func clampRun(_ pts: [(CGFloat, CGFloat)]) -> [(CGFloat, CGFloat)] {
                pts.map { (min(max($0.0, 0), 1), min(max($0.1, 0), 1)) }
            }
            return strokes(c, [clampRun(hook), clampRun(prong(1)), clampRun(prong(-1))])
        },
    ]

    // MARK: Glyphs
    //
    // One writing system, not sixteen marks. Shared grammar: a spine through
    // the centre, attachments landing on a 3 x 5 lattice, arcs of one radius,
    // and never more than four strokes — so density stays even and they sit
    // together on a panel as text rather than as decoration.

    private static let glyphs: [SymbolSpec] = [
        glyph("glyphKa", "Ka", [[(0.5, 0), (0.5, 1)], [(0.5, 0.14), (0.96, 0.14)], dot(0.14, 0.5)]),
        glyph("glyphRu", "Ru", [[(0.5, 0), (0.5, 1)], [(0.5, 0.86), (0.04, 0.86)],
                                arc(0.5, 0.34, 0.3, from: -90, to: 90)]),
        glyph("glyphTe", "Te", [[(0.12, 0.96), (0.88, 0.04)], [(0.12, 0.36), (0.88, 0.36)]]),
        glyph("glyphVo", "Vo", [[(0.14, 0), (0.14, 0.76), (0.86, 0.76), (0.86, 0)], dot(0.5, 0.16)]),
        glyph("glyphSha", "Sha", [[(0.5, 0), (0.5, 1)], [(0.5, 0.26), (0.96, 0.26)],
                                  [(0.5, 0.62), (0.96, 0.62)]]),
        glyph("glyphNu", "Nu", [[(0.56, 0), (0.56, 1)], arc(0.56, 0.5, 0.36, from: 90, to: 270)]),
        glyph("glyphIl", "Il", [[(0.2, 0.16), (0.2, 1)], [(0.5, 0), (0.5, 1)], [(0.8, 0.36), (0.8, 1)]]),
        glyph("glyphQa", "Qa", [[(0.14, 0.26), (0.86, 0.96)], [(0.86, 0.26), (0.14, 0.96)],
                                [(0.14, 0.06), (0.86, 0.06)]]),
        glyph("glyphZi", "Zi", [[(0.14, 0.1), (0.86, 0.1), (0.14, 0.9), (0.86, 0.9)]]),
        glyph("glyphMa", "Ma", [[(0.5, 0), (0.5, 0.68)], [(0.1, 0.3), (0.9, 0.3)],
                                arc(0.5, 0.68, 0.3, from: 0, to: 180)]),
        glyph("glyphOv", "Ov", [arc(0.5, 0.36, 0.32, from: 0, to: 360, steps: 30),
                                [(0.5, 0.68), (0.5, 1)]]),
        glyph("glyphEk", "Ek", [[(0.14, 0.36), (0.5, 0.04), (0.86, 0.36)],
                                [(0.14, 0.78), (0.5, 0.46), (0.86, 0.78)]]),
        glyph("glyphDa", "Da", [[(0.86, 0.1), (0.14, 0.1), (0.14, 0.9), (0.86, 0.9)]]),
        glyph("glyphTi", "Ti", [[(0.5, 0.1), (0.5, 0.9)], dot(0.14, 0.3), dot(0.86, 0.7)]),
        glyph("glyphHu", "Hu", [[(0.14, 0.05), (0.86, 0.05), (0.14, 0.95), (0.86, 0.95)]]),
        glyph("glyphRo", "Ro", [[(0.14, 1), (0.14, 0.4)], [(0.86, 1), (0.86, 0.4)],
                                arc(0.5, 0.4, 0.36, from: 180, to: 360)]),
    ]

    private static func glyph(_ id: String, _ name: String,
                              _ runs: [[(CGFloat, CGFloat)]]) -> SymbolSpec {
        SymbolSpec(id: id, name: name, category: .glyph, preservesAspect: true,
                   parameters: [nil, nil, nil, nil], defaults: [0.5, 0.5, 0.5, 0.5]) { c in
            strokes(c, runs)
        }
    }
}
