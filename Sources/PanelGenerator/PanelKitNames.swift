import PanelKit

// Names PanelKit shares with the macOS SDK. Inside PanelKit its own types win;
// across a module boundary two imported types of the same name are ambiguous,
// so the editor pins them here once.
//
// ColorSpec: QuickDraw (ApplicationServices) still declares one.
typealias ColorSpec = PanelKit.ColorSpec
