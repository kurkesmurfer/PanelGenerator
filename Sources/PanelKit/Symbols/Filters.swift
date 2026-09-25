import Foundation
import CoreGraphics

// Filter responses — see SymbolCatalogue.swift for the design rules.

extension SymbolCatalogue {

    // MARK: Filter responses

    static let filters: [SymbolSpec] = [
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
}
