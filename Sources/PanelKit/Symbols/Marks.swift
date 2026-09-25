import Foundation
import CoreGraphics

// Flow and marks — see SymbolCatalogue.swift for the design rules.

extension SymbolCatalogue {

    // MARK: Flow and marks

    static let marks: [SymbolSpec] = [
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
}
