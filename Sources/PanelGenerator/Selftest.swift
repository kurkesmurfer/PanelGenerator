import Foundation

/// Headless verification harness: builds a showcase panel exercising every
/// element kind, exports SVG + PNG, and exits. Runs without a window server,
/// so it doubles as the CI smoke test.
enum Selftest {

    static func demoDocument() -> PanelDocument {
        var doc = PanelDocument()
        doc.name = "Demo"
        doc.widthHP = 12
        doc.format = .u3
        doc.background = .hex("#0D0D13")

        func add(_ kind: ElementKind, _ x: CGFloat, _ y: CGFloat, _ w: CGFloat? = nil, _ h: CGFloat? = nil,
                 fill: ColorSpec? = nil, mutate: (inout PanelElement) -> Void = { _ in }) {
            var e = kind.defaultElement(at: CGPoint(x: x, y: y))
            if let w { e.w = w }
            if let h { e.h = h }
            if let fill { e.fill = fill }
            mutate(&e)
            doc.elements.append(e)
        }

        // LCARS backdrop
        add(.box, 8, 10, 164, 24) { $0.params.cornerTL = 12; $0.params.cornerTR = 12; $0.params.cornerBR = 12; $0.params.cornerBL = 12 }
        add(.box, 8, 42, 88, 18, fill: .hex("#FFCC99")) { $0.params.cornerTL = 9; $0.params.cornerTR = 9; $0.params.cornerBR = 9; $0.params.cornerBL = 9 }
        add(.box, 152, 74, 20, 118, fill: .hex("#CC99CC")) { $0.params.cornerTL = 10; $0.params.cornerTR = 10; $0.params.cornerBR = 10; $0.params.cornerBL = 10 }
        add(.elbow, 8, 234) { $0.w = 106; $0.h = 138
            $0.params.thickness = 16; $0.params.innerRadius = 8
            $0.params.armH = 66; $0.params.armV = 98; $0.params.flipY = true }
        add(.ringSector, 108, 66, 64, 64) { $0.params.thickness = 12; $0.params.startAngle = -90; $0.params.sweepAngle = 95 }

        // Titles
        add(.text, 30, 46, 96, 18, fill: .hex("#FFCC66")) { $0.params.text = "NX-1786"; $0.params.fontSize = 15 }
        add(.text, 30, 68, 116, 10, fill: .hex("#9999CC")) { $0.params.text = "PANELGEN CONTROL"; $0.params.fontSize = 7.5 }

        // Primitives
        add(.jack, 20, 128); add(.jack, 48, 128); add(.jack, 76, 128)
        add(.knobMedium, 112, 126)
        add(.knobLarge, 20, 168)
        add(.faderVertical, 62, 160)
        add(.faderHorizontal, 92, 204)
        add(.led, 100, 172, fill: .hex("#EE4444"))
        add(.led, 100, 188, fill: .hex("#44DD66"))
        add(.knobSmall, 116, 170)

        add(.text, 92, 360, 80, 9, fill: .hex("#8888A8")) { $0.params.text = "SN 4071-GK"; $0.params.fontSize = 6.5 }

        doc.addCornerScrews()
        return doc
    }

    static func run(outDir rawPath: String) -> Never {
        let dir = (rawPath as NSString).expandingTildeInPath
        do {
            try FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
            let doc = demoDocument()

            let svg = SVGExporter.documentSVG(doc)
            let svgURL = URL(fileURLWithPath: dir).appendingPathComponent("pg_demo.svg")
            try svg.write(to: svgURL, atomically: true, encoding: .utf8)

            let png = try PNGExporter.pngData(doc, scale: 4)
            let pngURL = URL(fileURLWithPath: dir).appendingPathComponent("pg_demo.png")
            try png.write(to: pngURL)

            print("SELFTEST OK")
            print("  elements : \(doc.elements.count)")
            print("  panel    : \(doc.widthHP)HP \(doc.format.rawValue) (\(Int(doc.pixelSize.width))×\(Int(doc.pixelSize.height)) px)")
            print("  svg      : \(svgURL.path) (\(svg.utf8.count) bytes)")
            print("  png      : \(pngURL.path) (\(png.count) bytes)")
            fflush(stdout)
            exit(0)
        } catch {
            print("SELFTEST FAILED: \(error)")
            fflush(stdout)
            exit(1)
        }
    }
}
