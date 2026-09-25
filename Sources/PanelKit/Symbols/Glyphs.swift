import Foundation
import CoreGraphics

// Glyphs — see SymbolCatalogue.swift for the design rules.

extension SymbolCatalogue {

    // MARK: Glyphs
    //
    // One writing system, not sixteen marks. Shared grammar: a spine through
    // the centre, attachments landing on a 3 x 5 lattice, arcs of one radius,
    // and never more than four strokes — so density stays even and they sit
    // together on a panel as text rather than as decoration.

    static let glyphs: [SymbolSpec] = [
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

    static func glyph(_ id: String, _ name: String,
                              _ runs: [[(CGFloat, CGFloat)]]) -> SymbolSpec {
        SymbolSpec(id: id, name: name, category: .glyph, preservesAspect: true,
                   parameters: [nil, nil, nil, nil], defaults: [0.5, 0.5, 0.5, 0.5]) { c in
            strokes(c, runs)
        }
    }
}
