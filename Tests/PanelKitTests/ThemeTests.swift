import XCTest
@testable import PanelKit

final class ThemeTests: XCTestCase {
    func testUnthemedDocumentLooksTheSameInBothVariants() {
        let d = PanelDocument()
        XCTAssertFalse(d.isThemed)
        XCTAssertEqual(d.paper(for: .dark), d.background)
        XCTAssertEqual(d.paper(for: .light), d.background)
    }

    func testLightBackgroundOnlyAppliesToTheLightVariant() {
        var d = PanelDocument()
        d.lightBackground = .hex("#E7E4DE")
        XCTAssertTrue(d.isThemed)
        XCTAssertEqual(d.paper(for: .dark), d.background)
        XCTAssertEqual(d.paper(for: .light), .hex("#E7E4DE"))
    }

    func testFollowersResolvePerVariantOthersKeepTheirFill() {
        var d = PanelDocument()
        d.lightBackground = .white
        var plain = ElementKind.box.defaultElement(at: .zero)
        plain.fill = .hex("#FF9C00")
        var ink = plain;   ink.followsInk = true
        var paper = plain; paper.followsPaper = true

        XCTAssertEqual(d.resolved(plain, for: .light).fill, .hex("#FF9C00"))
        XCTAssertEqual(d.resolved(ink, for: .dark).fill, d.inkDark)
        XCTAssertEqual(d.resolved(ink, for: .light).fill, d.inkLight)
        XCTAssertEqual(d.resolved(paper, for: .light).fill, .white)

        var both = plain; both.followsInk = true; both.followsPaper = true
        XCTAssertEqual(d.resolved(both, for: .light).fill, d.paper(for: .light), "paper wins over ink")
    }
}
