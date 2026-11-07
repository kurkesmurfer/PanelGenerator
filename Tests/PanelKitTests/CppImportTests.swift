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

    // MARK: - Plugin helpers, string arrays, sizes (SpaceTime Head)

    private let labelHeader = """
        inline void addLabel(ModuleWidget* w, float xmm, float ymm, const std::string& text,
                std::shared_ptr<Font> f, float size, NVGcolor c, float sp, NVGcolor l) {
            auto* t = new PanelText; t->text = text; w->addChild(t);
        }
        inline void addIoLabel(ModuleWidget* w, float xmm, float ymm, const std::string& text) {
            addLabel(w, xmm, ymm, text, fontLabelBold(), 7.5f, colorLabelIO(), 0.5f, colorLabelIOLight());
        }
        inline void addTitle(ModuleWidget* w, float xmm, float ymm, const std::string& text) {
            addLabel(w, xmm, ymm, text, fontTitle(), 16.f, colorTitle(), 0.4f, colorTitleLight());
        }
        inline void addHeaderLockup(ModuleWidget* w, float panelWidthMm, const std::string& title,
                float titleWidthMm, float markScale = 1.f) {
            const float markHeightMm = 5.2f * markScale;
            constexpr float gapMm = 1.2f;
            float leftMm = (panelWidthMm - markHeightMm - gapMm - titleWidthMm) * 0.5f;
            addTitle(w, leftMm + markHeightMm + gapMm + titleWidthMm * 0.5f, 5.8f, title);
        }
        """

    private func texts(_ o: CppImport.Outcome) -> [(String, CGPoint, CGFloat)] {
        o.elements.filter { $0.kind == .text }.map {
            ($0.params.text, CGPoint(x: PanelMetrics.mm($0.center.x), y: PanelMetrics.mm($0.center.y)), $0.params.fontSize)
        }
    }

    func testLabelsFromStringArrayInLoop() {
        let src = widget("""
            static const char* in1[3] = {"START", "STOP", "ADV"};
            for (int i = 0; i < 3; i++)
                spacetime::addIoLabel(this, 9.4f + 11.f * i, 96.f, in1[i]);
            """)
        let t = texts(CppImport.outcome(from: src, headers: [labelHeader]))
        XCTAssertEqual(t.map(\.0), ["START", "STOP", "ADV"])
        XCTAssertEqual(t.last?.1.x ?? 0, 31.4, accuracy: 0.01)
        XCTAssertEqual(t.first?.2 ?? 0, 7.5 * CppImport.nanoVGToEm, accuracy: 0.001)
    }

    func testHelperInlinedWithDefaultsAndLocals() {
        let src = widget(#"spacetime::addHeaderLockup(this, 50.8f, "Head", 14.2f);"#)
        let t = texts(CppImport.outcome(from: src, headers: [labelHeader]))
        XCTAssertEqual(t.map(\.0), ["Head"])
        // (50.8 - 5.2 - 1.2 - 14.2) / 2 + 5.2 + 1.2 + 7.1
        XCTAssertEqual(t.first?.1.x ?? 0, 28.6, accuracy: 0.01)
        XCTAssertEqual(t.first?.1.y ?? 0, 5.8, accuracy: 0.01)
    }

    func testVecPlusMinusThroughHelper() {
        let header = """
            struct DualSpringButton : app::Switch { DualSpringButton() { box.size = mm2px(Vec(5.f, 6.f)); } };
            inline void addDual(ModuleWidget* w, engine::Module* m, Vec center, int a, int b) {
                w->addParam(createParamCentered<DualSpringButton>(center.plus(mm2px(Vec(0.f, 3.f))), m, b));
                w->addParam(createParamCentered<DualSpringButton>(center.minus(mm2px(Vec(0.f, 3.f))), m, a));
            }
            """
        let src = widget("addDual(this, module, mm2px(Vec(41.f, 45.f)), Demo::UP_PARAM, Demo::DOWN_PARAM);")
        let sizer = ModuleImport.widgetSizer(texts: [header, src], pluginRoot: nil, rackLibrary: nil)
        let o = CppImport.outcome(from: src, headers: [header], widgetSize: sizer)
        let params = o.elements.filter { $0.role == .param }
        XCTAssertEqual(params.count, 2)
        XCTAssertEqual(params.map { PanelMetrics.mm($0.center.y) }.sorted()[0], 42, accuracy: 0.01)
        XCTAssertEqual(params.map { PanelMetrics.mm($0.center.y) }.sorted()[1], 48, accuracy: 0.01)
        XCTAssertTrue(params.allSatisfy { $0.widgetSource == .custom && $0.customWidgetName == "DualSpringButton" })
        XCTAssertEqual(PanelMetrics.mm(params[0].h), 6, accuracy: 0.01)
    }

    func testSplitVecChain() {
        XCTAssertEqual(CppImport.splitVecChain("a.plus(b).minus(c(d))").map { $0.0 + ":" + $0.1 },
                       [":a", "plus:b", "minus:c(d)"])
        XCTAssertEqual(CppImport.splitVecChain("a.plus(b).div(2)").count, 1)
        XCTAssertEqual(CppImport.splitVecChain("mm2px(Vec(1, 2))").count, 1)
    }

    func testIncludesAreFound() {
        XCTAssertEqual(ModuleImport.includes(in: "#include \"plugin.hpp\"\n  # include \"w/x.hpp\"\n#include <vector>"),
                       ["plugin.hpp", "w/x.hpp"])
    }
}
