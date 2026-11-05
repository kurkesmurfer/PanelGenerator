import XCTest
import CoreGraphics
@testable import PanelKit

/// Module sources in the shapes that used to defeat the reader.
final class CppImportTests: XCTestCase {
    private func px(_ mm: CGFloat) -> CGFloat { mm / PanelMetrics.mmPerPixel }

    private func centres(_ src: String, role: ComponentRole? = nil) -> [CGPoint] {
        CppImport.outcome(from: src).elements
            .filter { role == nil || $0.role == role }
            .map { CGPoint(x: PanelMetrics.mm($0.center.x), y: PanelMetrics.mm($0.center.y)) }
    }

    private func widget(_ body: String, globals: String = "") -> String {
        """
        \(globals)
        struct DemoWidget : ModuleWidget {
            DemoWidget(Demo* module) {
                setModule(module);
                \(body)
            }
        };
        """
    }

    func testSeveralDeclaratorsInOneDeclaration() {
        let src = widget("addInput(createInputCentered<PJ301MPort>(mm2px(Vec(JACK_X0 + 2 * JACK_PITCH, 100.f)), module, Demo::IN_INPUT));",
                         globals: "constexpr float JACK_X0 = 9.4f, JACK_PITCH = 11.f;")
        XCTAssertEqual(centres(src).first?.x ?? 0, 31.4, accuracy: 0.01)
    }

    func testConstantArrays() {
        let src = widget("""
            constexpr float laneY[5] = {27.2f, 48.2f, 69.2f, 90.2f, 111.2f};
            constexpr float ioA = 10.668f, ioB = 32.004f;
            addOutput(createOutputCentered<PJ301MPort>(mm2px(Vec(ioB, laneY[3])), module, Demo::OUT_OUTPUT));
            """)
        let c = centres(src).first
        XCTAssertEqual(c?.x ?? 0, 32.004, accuracy: 0.01)
        XCTAssertEqual(c?.y ?? 0, 90.2, accuracy: 0.01)
    }

    func testLoopsAreUnrolledAndNamed() {
        let src = widget("""
            for (int i = 0; i < 4; i++) {
                addInput(createInputCentered<PJ301MPort>(mm2px(Vec(7.62f + i * 10.16f, 100.f)), module, Demo::IN_INPUT + i));
            }
            """)
        let out = CppImport.outcome(from: src)
        XCTAssertEqual(out.elements.count, 4)
        XCTAssertEqual(out.elements.map(\.enumName), ["IN_1", "IN_2", "IN_3", "IN_4"])
        XCTAssertEqual(PanelMetrics.mm(out.elements[3].center.x), 38.1, accuracy: 0.01)
    }

    func testNestedLoopsWithConstantBounds() {
        let src = widget("""
            for (int r = 0; r < ROWS; ++r)
                for (int c = 0; c < 2; c++)
                    addParam(createParamCentered<Trimpot>(mm2px(Vec(10 + c * 20, 20 + r * 15)), module, Demo::P_PARAM + r * 2 + c));
            """, globals: "#define ROWS 3")
        XCTAssertEqual(centres(src).count, 6)
    }

    func testLocalsAreEvaluatedInOrder() {
        let src = widget("""
            float row1Y = 50.0f;
            float col1X = 31.5f;
            addParam(createParamCentered<Trimpot>(mm2px(Vec(col1X, row1Y)), module, Demo::A_PARAM));
            row1Y = 91.0f;
            addParam(createParamCentered<Trimpot>(mm2px(Vec(col1X, row1Y)), module, Demo::B_PARAM));
            row1Y += 10.f;
            addParam(createParamCentered<Trimpot>(mm2px(Vec(col1X, row1Y)), module, Demo::C_PARAM));
            """)
        XCTAssertEqual(centres(src).map(\.y), [50, 91, 101])
    }

    func testMillimetreHelpersAndCasts() {
        let src = widget("""
            addParam(createParamCentered<Trimpot>(millimetersToPixelsVec(8.326, 19.457), module, Demo::A_PARAM));
            addParam(createParamCentered<Trimpot>(Vec(mm2px(10.f), mm2px((float) 20)), module, Demo::B_PARAM));
            addParam(createParamCentered<Trimpot>(rack::mm2px(Vec(static_cast<float>(5), float(6))), module, Demo::C_PARAM));
            """)
        let c = centres(src)
        XCTAssertEqual(c.count, 3)
        XCTAssertEqual(c[0].x, 8.326, accuracy: 0.001)
        XCTAssertEqual(c[1].y, 20, accuracy: 0.001)
        XCTAssertEqual(c[2].x, 5, accuracy: 0.001)
    }

    func testGeneratedDSPCodeBeforeTheWidgetIsIgnored() {
        // An assignment to the same name far ahead of the widget must not leak in.
        let src = "void process() { float y = inputs[0].getVoltage(); }\n" + widget("""
            float y = 40.f;
            addOutput(createOutputCentered<PJ301MPort>(mm2px(Vec(10, y)), module, Demo::OUT_OUTPUT));
            """)
        XCTAssertEqual(centres(src).first?.y ?? 0, 40, accuracy: 0.001)
    }
}
