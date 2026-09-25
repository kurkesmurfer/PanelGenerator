import Foundation
import CoreGraphics

// Signal shapes — see SymbolCatalogue.swift for the design rules.

extension SymbolCatalogue {

    // MARK: Signal shapes

    static let signals: [SymbolSpec] = [
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
}
