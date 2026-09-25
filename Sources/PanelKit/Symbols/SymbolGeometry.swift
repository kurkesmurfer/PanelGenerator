import Foundation
import CoreGraphics

// MARK: - Geometry helpers

func poly(_ c: SymbolContext, _ pts: [(CGFloat, CGFloat)]) -> CGPath {
    let path = CGMutablePath()
    for (i, q) in pts.enumerated() {
        let point = c.at(q.0, q.1)
        if i == 0 { path.move(to: point) } else { path.addLine(to: point) }
    }
    return path
}

func sampled(_ c: SymbolContext, _ count: Int = 40, _ f: (CGFloat) -> CGFloat) -> CGPath {
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
let noiseTable: [CGFloat] = [
    0.52, 0.14, 0.83, 0.31, 0.67, 0.05, 0.94, 0.42, 0.23, 0.78,
    0.11, 0.60, 0.36, 0.88, 0.19, 0.71, 0.47, 0.02, 0.63, 0.29,
]

/// One resonant peak, used by the filter responses.
func peak(_ d: CGFloat, _ amount: CGFloat) -> CGFloat {
    amount * 0.32 * exp(-pow(d * 5.5, 2))
}


/// Several independent strokes in one path. Each run gets its own caps, which
/// is what lets a glyph be built from a spine plus separate attachments.
func strokes(_ c: SymbolContext, _ runs: [[(CGFloat, CGFloat)]]) -> CGPath {
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
func arc(_ cx: CGFloat, _ cy: CGFloat, _ r: CGFloat,
                 from a0: CGFloat, to a1: CGFloat, steps: Int = 18) -> [(CGFloat, CGFloat)] {
    (0...steps).map { i in
        let a = (a0 + (a1 - a0) * CGFloat(i) / CGFloat(steps)) * .pi / 180
        return (cx + r * cos(a), cy + r * sin(a))
    }
}

/// A round cap on its own. The stroke is too short to see; the cap is the mark.
func dot(_ x: CGFloat, _ y: CGFloat) -> [(CGFloat, CGFloat)] {
    [(x, y), (x + 0.002, y)]
}

/// Quarter turns about the centre of the unit box, y downward.
func rotated(_ pts: [(CGFloat, CGFloat)], _ quarter: Int) -> [(CGFloat, CGFloat)] {
    pts.map { p in
        switch ((quarter % 4) + 4) % 4 {
        case 1:  return (1 - p.1, p.0)
        case 2:  return (1 - p.0, 1 - p.1)
        case 3:  return (p.1, 1 - p.0)
        default: return p
        }
    }
}
