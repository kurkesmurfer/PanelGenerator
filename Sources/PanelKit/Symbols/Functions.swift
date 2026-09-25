import Foundation
import CoreGraphics

// Function shapes — see SymbolCatalogue.swift for the design rules.

extension SymbolCatalogue {

    // MARK: Function shapes

    static let functions: [SymbolSpec] = [
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
}
