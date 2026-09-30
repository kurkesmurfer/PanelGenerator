import XCTest
import CoreGraphics
@testable import PanelKit

final class ReplaceTests: XCTestCase {
    private func jack(at c: CGPoint) -> PanelElement {
        var j = ElementKind.jack.defaultElement(at: .zero)
        j.x = c.x - j.w / 2; j.y = c.y - j.h / 2
        return j
    }

    func testKeepsIdentityAndPlacementTakesTheNewShape() {
        var old = ElementKind.knobSmall.defaultElement(at: .zero)
        old.x = 40; old.y = 100
        old.rotation = 30
        old.role = .param
        old.enumName = "CUTOFF"
        old.name = "Cutoff knob"
        old.groupID = UUID()
        let centre = old.center

        let new = old.replaced(by: .knobLarge)
        let fresh = ElementKind.knobLarge.defaultElement(at: .zero)
        XCTAssertEqual(new.id, old.id)
        XCTAssertEqual(new.kind, .knobLarge)
        XCTAssertEqual(new.center.x, centre.x, accuracy: 1e-9)
        XCTAssertEqual(new.center.y, centre.y, accuracy: 1e-9)
        XCTAssertEqual(new.w, fresh.w); XCTAssertEqual(new.h, fresh.h)
        XCTAssertEqual(new.rotation, 30)
        XCTAssertEqual(new.role, .param)
        XCTAssertEqual(new.enumName, "CUTOFF")
        XCTAssertEqual(new.name, "Cutoff knob")
        XCTAssertEqual(new.groupID, old.groupID)
        XCTAssertEqual(new.fill, fresh.fill, "appearance comes from the replacement")
    }

    func testDefaultLayerNameFollowsTheNewKind() {
        let old = ElementKind.knobSmall.defaultElement(at: .zero)
        XCTAssertEqual(old.replaced(by: .faderVertical).name, ElementKind.faderVertical.displayName)
    }

    func testRoleKeptOnlyWhenTheNewKindIsAComponent() {
        var out = jack(at: CGPoint(x: 50, y: 50))
        out.role = .output
        XCTAssertEqual(out.replaced(by: .jack).role, .output)
        XCTAssertEqual(out.replaced(by: .box).role, ElementKind.box.defaultElement(at: .zero).role)
    }

    func testRackTypeKeptOnlyIfTheNewKindOffersIt() {
        var k = ElementKind.knobSmall.defaultElement(at: .zero)
        k.stockWidget = "Trimpot"
        XCTAssertEqual(k.replaced(by: .knobLarge).stockWidget, "Trimpot")
        XCTAssertEqual(k.replaced(by: .faderVertical).stockWidget,
                       ElementKind.faderVertical.defaultElement(at: .zero).stockWidget)
    }

    func testPresetIsApplied() {
        let k = ElementKind.knobMedium.defaultElement(at: .zero)
        XCTAssertEqual(k.replaced(by: .knobMedium, preset: "ring").params.knobStyle, 2)
    }

    func testDocumentReplaceKeepsOrderAndLabelBindings() {
        var doc = PanelDocument()
        let a = jack(at: CGPoint(x: 30, y: 60))
        var label = ElementKind.text.defaultElement(at: CGPoint(x: 20, y: 80))
        label.labelOwner = a.id
        let b = jack(at: CGPoint(x: 90, y: 60))
        doc.elements = [a, label, b]

        XCTAssertEqual(doc.replace(ids: [a.id, b.id], with: .knobSmall), 2)
        XCTAssertEqual(doc.elements.map(\.kind), [.knobSmall, .text, .knobSmall])
        XCTAssertEqual(doc.elements.map(\.id), [a.id, label.id, b.id])
        XCTAssertEqual(doc.elements[1].labelOwner, doc.elements[0].id)
    }
}
