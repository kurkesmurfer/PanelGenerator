import XCTest
@testable import PanelKit

final class DesignLanguageTests: XCTestCase {
    func testLanguageIdsAreUnique() {
        let ids = DesignLanguage.all.map(\.id)
        XCTAssertEqual(Set(ids).count, ids.count)
    }

    func testSwatchNamesAreUniqueAndLookupRoundTrips() {
        let names = DesignLanguage.allSwatches.map(\.name)
        XCTAssertEqual(Set(names).count, names.count, "duplicate swatch name")
        for s in DesignLanguage.allSwatches {
            XCTAssertEqual(ColorSpec.swatch(s.name), s.color, s.name)
        }
        XCTAssertEqual(ColorSpec.swatch("no such swatch"), DesignLanguage.allSwatches[0].color)
    }

    /// The swatch bank is the union of what the languages declare.
    func testBankMatchesLanguageGroups() {
        let declared = Set(DesignLanguage.all.flatMap(\.swatchGroups).flatMap(\.swatches).map(\.name))
        XCTAssertEqual(Set(DesignLanguage.allSwatches.map(\.name)), declared)
    }

    /// Every palette preset is owned by exactly one language and applies to
    /// the kind its entry drops.
    func testEveryPalettePresetHasExactlyOneOwner() {
        for section in DesignLanguage.paletteSections {
            for entry in section.entries {
                guard let preset = entry.preset else { continue }
                let owners = DesignLanguage.all.filter { lang in
                    var e = entry.kind.defaultElement(at: .zero)
                    return lang.applyPreset(preset, &e)
                }
                XCTAssertEqual(owners.count, 1, "\(section.title) / \(entry.title) (\(preset))")
            }
        }
    }

    func testPresetIgnoresTheWrongKind() {
        var jack = ElementKind.jack.defaultElement(at: .zero)
        let before = jack
        XCTAssertFalse(DesignLanguage.applyPreset("delineationSerge", to: &jack))
        XCTAssertEqual(jack, before)
    }

    func testEveryPlaceableKindIsInThePalette() {
        let listed = Set(DesignLanguage.paletteSections.flatMap(\.entries).map(\.kind))
        // symbol has its own grid, text its own section, path comes from import.
        let expected = Set(ElementKind.allCases).subtracting([.symbol, .text, .path])
        XCTAssertEqual(listed, expected)
    }

    func testSergeAndKurkesmurferDelineationsDifferOnlyInWeightAndAlpha() {
        var km = ElementKind.box.defaultElement(at: .zero)
        var sg = km
        km.applyPreset("delineationKM")
        sg.applyPreset("delineationSerge")
        XCTAssertEqual(km.params.cornerTL, sg.params.cornerTL)
        XCTAssertEqual(sg.strokeWidth, 2 * km.strokeWidth, accuracy: 1e-9)
        XCTAssertEqual(km.stroke?.a, 0.5)
        XCTAssertEqual(sg.stroke?.a, 1)
    }

    func testNewDocumentUsesTheKurkesmurferBackground() {
        XCTAssertEqual(PanelDocument().background, Kurkesmurfer.background)
    }
}
