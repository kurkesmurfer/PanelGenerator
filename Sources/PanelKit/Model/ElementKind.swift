import Foundation
import CoreGraphics
import AppKit

// MARK: - Element kinds

package enum ElementKind: String, Codable, CaseIterable {
    // Primitives
    case jack
    case knobLarge, knobMedium, knobSmall
    case faderVertical, faderHorizontal
    case led
    case pushButton
    case buttonGroup     // n buttons: column / row / cross / circular
    case screw
    // Shapes (backdrop)
    case box            // rounded rect with per-corner radii → pills/capsules too
    case ellipse
    case triangle
    /// A straight or gently bowed connector line -- Serge's own convention
    /// for tying a knob to the jack it belongs to (e.g. GTO's CYCLE knob to
    /// its IN jack), rather than relying on proximity or a label alone.
    case line
    case elbow          // LCARS elbow: two arms joined by a curved corner
    case swirl          // LCARS swirl: two elbow corners of opposite sense,
                         // joined by a straight spine -- a horizontal run that
                         // jogs up (or down) a level and keeps going the same way
    case ringSector     // annulus arc — the big sweeping TNG curves
    case symbol         // parametric synth iconography — see SymbolCatalogue
    /// Imported artwork: an arbitrary path, held normalised to a unit box so
    /// the frame scales it like every other element. Not parametric — a bezier
    /// blob does not carry the fact that it was once an elbow.
    case path
    // Text
    case text

    package enum Category { case primitive, shape, text }

    package var isKnob: Bool { self == .knobLarge || self == .knobMedium || self == .knobSmall }

    package var category: Category {
        switch self {
        case .box, .ellipse, .triangle, .line, .elbow, .swirl, .ringSector, .symbol, .path: return .shape
        case .text: return .text
        default: return .primitive
        }
    }

    package var displayName: String {
        switch self {
        case .jack: return "Jack (3.5 mm)"
        case .knobLarge: return "Knob · Large"
        case .knobMedium: return "Knob · Medium"
        case .knobSmall: return "Knob · Small"
        case .faderVertical: return "Fader · Vertical"
        case .faderHorizontal: return "Fader · Horizontal"
        case .led: return "LED"
        case .pushButton: return "Push Button"
        case .buttonGroup: return "Button Group"
        case .screw: return "Screw"
        case .box: return "Box / Rounded Rect"
        case .ellipse: return "Ellipse"
        case .triangle: return "Triangle"
        case .line: return "Line"
        case .elbow: return "LCARS Elbow"
        case .swirl: return "LCARS Swirl"
        case .ringSector: return "Ring Sector"
        case .symbol: return "Symbol"
        case .path: return "Imported Path"
        case .text: return "Text Label"
        }
    }

    /// Identifier stem for an element still carrying its default layer name.
    ///
    /// The display name is written for the palette, not for C++, and using it
    /// produced JACK_3_5_MM_7_INPUT — which names the widget you dropped rather
    /// than the thing it controls. These at least read like a Rack enum while
    /// you are still deciding what to call it.
    package var shortIdentifier: String {
        switch self {
        case .jack: return "JACK"
        case .knobLarge, .knobMedium, .knobSmall: return "KNOB"
        case .faderVertical, .faderHorizontal: return "FADER"
        case .led: return "LED"
        case .pushButton: return "BUTTON"
        case .buttonGroup: return "SWITCH"
        case .screw: return "SCREW"
        case .text: return "LABEL"
        default: return "PART"
        }
    }

    /// What a freshly dropped element most likely is. Jacks default to input
    /// because that is the commoner case; flip it in the inspector.
    package var defaultRole: ComponentRole {
        switch self {
        case .jack: return .input
        case .knobLarge, .knobMedium, .knobSmall,
             .faderVertical, .faderHorizontal,
             .pushButton, .buttonGroup: return .param
        case .led: return .light
        default: return .decoration
        }
    }

    /// Rack ComponentLibrary type that matches this primitive most closely.
    package var defaultStockWidget: String {
        switch self {
        case .jack: return "PJ301MPort"
        case .knobLarge: return "RoundLargeBlackKnob"
        case .knobMedium: return "RoundBlackKnob"
        case .knobSmall: return "RoundSmallBlackKnob"
        case .faderVertical, .faderHorizontal: return "VCVSlider"
        case .led: return "MediumLight<RedLight>"
        case .pushButton, .buttonGroup: return "VCVButton"
        case .screw: return "ScrewSilver"
        default: return ""
        }
    }

    /// Rack types worth offering for this primitive. Free text either way —
    /// the list is a shortcut, not a constraint.
    package var stockWidgetChoices: [String] {
        switch self {
        case .jack:
            return ["PJ301MPort", "PJ3410Port"]
        case .knobLarge, .knobMedium, .knobSmall:
            return ["RoundBlackKnob", "RoundSmallBlackKnob", "RoundLargeBlackKnob",
                    "RoundBigBlackKnob", "RoundHugeBlackKnob", "Trimpot",
                    "BefacoBigKnob", "BefacoTinyKnob"]
        case .faderVertical, .faderHorizontal:
            return ["VCVSlider", "VCVLightSlider", "BefacoSlidePot",
                    "LEDSliderGreen", "LEDSliderRed"]
        case .led:
            return ["MediumLight<RedLight>", "SmallLight<GreenLight>",
                    "LargeLight<BlueLight>", "MediumLight<GreenRedLight>",
                    "TinyLight<WhiteLight>"]
        case .pushButton, .buttonGroup:
            return ["VCVButton", "VCVLatch", "BefacoPush", "CKD6",
                    "VCVBezel", "NKK", "CKSS", "CKSSThree"]
        case .screw:
            return ["ScrewSilver", "ScrewBlack"]
        default:
            return []
        }
    }

    package func defaultElement(at point: CGPoint) -> PanelElement {
        var e = PanelElement(kind: self)
        e.role = defaultRole
        e.stockWidget = defaultStockWidget
        switch self {
        case .jack:
            e.w = 22; e.h = 22; e.fill = .hex("#9AA0AB")
        case .knobLarge:
            e.w = 30; e.h = 30; e.fill = .swatch("Orange")
        case .knobMedium:
            e.w = 25; e.h = 25; e.fill = .swatch("Orange")
        case .knobSmall:
            e.w = 19; e.h = 19; e.fill = .swatch("Sky")
        case .faderVertical:
            e.w = 17; e.h = 64; e.fill = .swatch("Lavender")
        case .faderHorizontal:
            e.w = 64; e.h = 17; e.fill = .swatch("Lavender")
        case .led:
            e.w = 8; e.h = 8; e.fill = .swatch("LED Red")
        case .pushButton:
            e.w = 14; e.h = 14; e.fill = .swatch("Alert Red")
        case .buttonGroup:
            e.w = 24; e.h = 88; e.fill = .swatch("Orange")
        case .screw:
            e.w = 11; e.h = 11; e.fill = .hex("#B9BEC8")
        case .box:
            e.w = 90; e.h = 34; e.fill = .swatch("Orange")
            e.params.cornerTL = 10; e.params.cornerTR = 10
            e.params.cornerBR = 10; e.params.cornerBL = 10
        case .ellipse:
            e.w = 56; e.h = 38; e.fill = .swatch("Lavender")
        case .triangle:
            e.w = 46; e.h = 40; e.fill = .swatch("Gold")
        case .line:
            // Straight by default (bow 0): runs down the frame's vertical
            // centre-line, top-mid to bottom-mid -- rotate for a horizontal
            // or diagonal run. Neutral hardware grey, matching jack/screw,
            // since a plain connector reads as wiring, not a decorative accent.
            e.w = 20; e.h = 60; e.stroke = .hex("#9AA0AB"); e.strokeWidth = 1.2
        case .elbow:
            e.w = 96; e.h = 96; e.fill = .swatch("Vanilla")
            e.params.thickness = 16; e.params.innerRadius = 8
            e.params.armH = 80; e.params.armV = 80
        case .swirl:
            e.w = 90; e.h = 150; e.fill = .swatch("Vanilla")
            e.params.thickness = 16; e.params.innerRadius = 8
            e.params.armH = 80; e.params.armH2 = 80; e.params.armV = 40
        case .ringSector:
            e.w = 84; e.h = 84; e.fill = .swatch("Sky")
            e.params.thickness = 14; e.params.startAngle = -90; e.params.sweepAngle = 100
        case .symbol:
            e.w = 44; e.h = 30; e.fill = .swatch("Sky")
            e.params.symbol = "sine"
            e.params.weight = SymbolCatalogue.defaultWeight
            let d = SymbolCatalogue.spec("sine").defaults
            e.params.symbolA = d[0]; e.params.symbolB = d[1]
            e.params.symbolC = d[2]; e.params.symbolD = d[3]
        case .path:
            // Placed by the importer, which overwrites all of this; the
            // defaults only matter if a path element is ever made by hand.
            e.w = 40; e.h = 40; e.fill = .hex("#9AA0AB")
        case .text:
            e.w = 120; e.h = 20; e.fill = .hex("#E8E8F0")
            e.params.text = "LABEL"; e.params.fontSize = 12; e.params.bold = true
        }
        e.frame.origin = point
        e.name = displayName
        return e
    }
}
