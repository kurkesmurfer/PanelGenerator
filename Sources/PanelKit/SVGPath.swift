import Foundation
import CoreGraphics

/// SVG path data and transform lists, read into CoreGraphics.
///
/// The counterpart to `PathSVG`, which writes a CGPath out as a `d`
/// attribute. Keeping both directions honest is what lets an imported panel
/// export again without losing its shape.
///
/// The subset is the one a panel actually uses: every path command including
/// elliptical arcs, and the whole transform list. Not supported, deliberately:
/// nothing at all, because a `d` string that is only partly understood draws a
/// wrong shape silently. Anything unparseable returns nil so the caller can
/// warn rather than draw a lie.
package enum SVGPath {

    // MARK: - Path data

    package static func path(fromD d: String) -> CGPath? {
        var scanner = Tokens(d)
        let path = CGMutablePath()

        var current = CGPoint.zero        // current point
        var start = CGPoint.zero          // subpath start, for Z
        var lastCubic: CGPoint? = nil     // reflection point for S
        var lastQuad: CGPoint? = nil      // reflection point for T
        var command: Character = " "
        var haveStarted = false

        func rel(_ p: CGPoint, _ relative: Bool) -> CGPoint {
            relative ? CGPoint(x: current.x + p.x, y: current.y + p.y) : p
        }

        while true {
            if let c = scanner.peekCommand() {
                command = c
                scanner.advance()
            } else if scanner.atEnd {
                break
            } else if !haveStarted {
                // Numbers before any command: not a path.
                return nil
            } else if command == "M" || command == "m" {
                // An implicit repeat of moveto is lineto, per the spec. Getting
                // this wrong turns a polygon into a scatter of dots.
                command = command == "M" ? "L" : "l"
            } else if command == "Z" || command == "z" {
                return nil
            }

            let lower = Character(command.lowercased())
            let isRelative = command.isLowercase

            switch lower {
            case "m":
                guard let x = scanner.number(), let y = scanner.number() else { return nil }
                current = rel(CGPoint(x: x, y: y), isRelative)
                start = current
                path.move(to: current)
                haveStarted = true
                lastCubic = nil; lastQuad = nil

            case "l":
                guard let x = scanner.number(), let y = scanner.number() else { return nil }
                current = rel(CGPoint(x: x, y: y), isRelative)
                path.addLine(to: current)
                lastCubic = nil; lastQuad = nil

            case "h":
                guard let x = scanner.number() else { return nil }
                current = CGPoint(x: isRelative ? current.x + x : x, y: current.y)
                path.addLine(to: current)
                lastCubic = nil; lastQuad = nil

            case "v":
                guard let y = scanner.number() else { return nil }
                current = CGPoint(x: current.x, y: isRelative ? current.y + y : y)
                path.addLine(to: current)
                lastCubic = nil; lastQuad = nil

            case "c":
                guard let a = scanner.point(), let b = scanner.point(), let e = scanner.point() else { return nil }
                let c1 = rel(a, isRelative), c2 = rel(b, isRelative), end = rel(e, isRelative)
                path.addCurve(to: end, control1: c1, control2: c2)
                current = end; lastCubic = c2; lastQuad = nil

            case "s":
                guard let b = scanner.point(), let e = scanner.point() else { return nil }
                let c1 = reflect(lastCubic, about: current)
                let c2 = rel(b, isRelative), end = rel(e, isRelative)
                path.addCurve(to: end, control1: c1, control2: c2)
                current = end; lastCubic = c2; lastQuad = nil

            case "q":
                guard let a = scanner.point(), let e = scanner.point() else { return nil }
                let c = rel(a, isRelative), end = rel(e, isRelative)
                path.addQuadCurve(to: end, control: c)
                current = end; lastQuad = c; lastCubic = nil

            case "t":
                guard let e = scanner.point() else { return nil }
                let c = reflect(lastQuad, about: current)
                let end = rel(e, isRelative)
                path.addQuadCurve(to: end, control: c)
                current = end; lastQuad = c; lastCubic = nil

            case "a":
                guard let rx = scanner.number(), let ry = scanner.number(),
                      let rotation = scanner.number(),
                      let largeArc = scanner.flag(), let sweep = scanner.flag(),
                      let e = scanner.point() else { return nil }
                let end = rel(e, isRelative)
                addArc(to: path, from: current, to: end,
                       rx: rx, ry: ry, rotationDegrees: rotation,
                       largeArc: largeArc, sweep: sweep)
                current = end; lastCubic = nil; lastQuad = nil

            case "z":
                path.closeSubpath()
                current = start
                lastCubic = nil; lastQuad = nil

            default:
                return nil
            }

            scanner.skipSeparators()
            if scanner.atEnd { break }
        }

        return path.isEmpty ? nil : path.copy()
    }

    private static func reflect(_ previous: CGPoint?, about p: CGPoint) -> CGPoint {
        // With no previous curve the control point coincides with the current
        // point, which is what the spec says and what makes S-after-L behave.
        guard let previous else { return p }
        return CGPoint(x: 2 * p.x - previous.x, y: 2 * p.y - previous.y)
    }

    /// Endpoint-parameterised elliptical arc, per SVG's own implementation
    /// notes (F.6.5), emitted as up to four cubic segments.
    private static func addArc(to path: CGMutablePath,
                               from p0: CGPoint, to p1: CGPoint,
                               rx rxIn: CGFloat, ry ryIn: CGFloat,
                               rotationDegrees: CGFloat,
                               largeArc: Bool, sweep: Bool) {
        // Degenerate radii mean a straight line, not a dropped segment.
        var rx = abs(rxIn), ry = abs(ryIn)
        if rx < 1e-9 || ry < 1e-9 || (p0.x == p1.x && p0.y == p1.y) {
            path.addLine(to: p1)
            return
        }

        let phi = rotationDegrees * .pi / 180
        let cosPhi = cos(phi), sinPhi = sin(phi)

        let dx2 = (p0.x - p1.x) / 2, dy2 = (p0.y - p1.y) / 2
        let x1p = cosPhi * dx2 + sinPhi * dy2
        let y1p = -sinPhi * dx2 + cosPhi * dy2

        // Scale the radii up if they are too small to span the chord.
        let lambda = (x1p * x1p) / (rx * rx) + (y1p * y1p) / (ry * ry)
        if lambda > 1 {
            let s = sqrt(lambda)
            rx *= s; ry *= s
        }

        let sign: CGFloat = (largeArc != sweep) ? 1 : -1
        let num = rx * rx * ry * ry - rx * rx * y1p * y1p - ry * ry * x1p * x1p
        let den = rx * rx * y1p * y1p + ry * ry * x1p * x1p
        let coef = sign * sqrt(max(0, num) / max(den, 1e-12))
        let cxp = coef * rx * y1p / ry
        let cyp = -coef * ry * x1p / rx

        let cx = cosPhi * cxp - sinPhi * cyp + (p0.x + p1.x) / 2
        let cy = sinPhi * cxp + cosPhi * cyp + (p0.y + p1.y) / 2

        func angle(_ ux: CGFloat, _ uy: CGFloat, _ vx: CGFloat, _ vy: CGFloat) -> CGFloat {
            let dot = ux * vx + uy * vy
            let len = sqrt(ux * ux + uy * uy) * sqrt(vx * vx + vy * vy)
            var a = acos(min(max(dot / max(len, 1e-12), -1), 1))
            if ux * vy - uy * vx < 0 { a = -a }
            return a
        }

        let ux = (x1p - cxp) / rx, uy = (y1p - cyp) / ry
        let vx = (-x1p - cxp) / rx, vy = (-y1p - cyp) / ry
        let theta1 = angle(1, 0, ux, uy)
        var delta = angle(ux, uy, vx, vy)
        if !sweep && delta > 0 { delta -= 2 * .pi }
        if sweep && delta < 0 { delta += 2 * .pi }

        // Four segments per full turn keeps the cubic approximation inside a
        // fraction of a pixel at panel scale.
        let segments = max(1, Int(ceil(abs(delta) / (.pi / 2))))
        let step = delta / CGFloat(segments)
        let alpha = 4.0 / 3.0 * tan(step / 4)

        var theta = theta1
        for _ in 0..<segments {
            let cosT1 = cos(theta), sinT1 = sin(theta)
            let theta2 = theta + step
            let cosT2 = cos(theta2), sinT2 = sin(theta2)

            func point(_ c: CGFloat, _ s: CGFloat) -> CGPoint {
                CGPoint(x: cx + rx * cosPhi * c - ry * sinPhi * s,
                        y: cy + rx * sinPhi * c + ry * cosPhi * s)
            }
            func derivative(_ c: CGFloat, _ s: CGFloat) -> CGPoint {
                CGPoint(x: -rx * cosPhi * s - ry * sinPhi * c,
                        y: -rx * sinPhi * s + ry * cosPhi * c)
            }

            let p = point(cosT1, sinT1), q = point(cosT2, sinT2)
            let dp = derivative(cosT1, sinT1), dq = derivative(cosT2, sinT2)
            path.addCurve(to: q,
                          control1: CGPoint(x: p.x + alpha * dp.x, y: p.y + alpha * dp.y),
                          control2: CGPoint(x: q.x - alpha * dq.x, y: q.y - alpha * dq.y))
            theta = theta2
        }
    }

    // MARK: - Transform lists

    /// `transform="translate(3 4) rotate(45 10 10) scale(2)"`.
    ///
    /// Returns identity for an empty or absent list and nil for a malformed
    /// one — a transform that is silently ignored puts artwork in the wrong
    /// place, which is harder to spot than nothing being drawn.
    package static func transform(from text: String) -> CGAffineTransform? {
        var result = CGAffineTransform.identity
        var rest = Substring(text)
        var sawOne = false

        while let open = rest.firstIndex(of: "(") {
            let nameText = rest[rest.startIndex..<open]
                .trimmingCharacters(in: CharacterSet(charactersIn: " \t\n\r,"))
            guard let close = rest[open...].firstIndex(of: ")") else { return nil }
            let argText = String(rest[rest.index(after: open)..<close])
            rest = rest[rest.index(after: close)...]

            var tokens = Tokens(argText)
            var args: [CGFloat] = []
            while let v = tokens.number() { args.append(v) }
            guard tokens.atEnd else { return nil }

            let t: CGAffineTransform
            switch nameText {
            case "matrix":
                guard args.count == 6 else { return nil }
                t = CGAffineTransform(a: args[0], b: args[1], c: args[2],
                                      d: args[3], tx: args[4], ty: args[5])
            case "translate":
                guard args.count == 1 || args.count == 2 else { return nil }
                t = CGAffineTransform(translationX: args[0], y: args.count > 1 ? args[1] : 0)
            case "scale":
                guard args.count == 1 || args.count == 2 else { return nil }
                t = CGAffineTransform(scaleX: args[0], y: args.count > 1 ? args[1] : args[0])
            case "rotate":
                guard args.count == 1 || args.count == 3 else { return nil }
                let a = args[0] * .pi / 180
                if args.count == 3 {
                    t = CGAffineTransform(translationX: args[1], y: args[2])
                        .rotated(by: a)
                        .translatedBy(x: -args[1], y: -args[2])
                } else {
                    t = CGAffineTransform(rotationAngle: a)
                }
            case "skewX":
                guard args.count == 1 else { return nil }
                t = CGAffineTransform(a: 1, b: 0, c: tan(args[0] * .pi / 180), d: 1, tx: 0, ty: 0)
            case "skewY":
                guard args.count == 1 else { return nil }
                t = CGAffineTransform(a: 1, b: tan(args[0] * .pi / 180), c: 0, d: 1, tx: 0, ty: 0)
            default:
                return nil
            }
            // SVG applies the list left to right, outermost first.
            result = t.concatenating(result)
            sawOne = true
        }

        let leftovers = rest.trimmingCharacters(in: CharacterSet(charactersIn: " \t\n\r,"))
        guard leftovers.isEmpty else { return nil }
        return sawOne ? result : .identity
    }

    // MARK: - Number scanner

    /// SVG number grammar, which is not Double(String): "1-2" is two numbers,
    /// ".5.5" is two numbers, and flags in an arc may be written without any
    /// separator at all.
    package struct Tokens {
        private let chars: [Character]
        private var i: Int = 0

        package init(_ s: String) { chars = Array(s) }

        package var atEnd: Bool {
            var j = i
            while j < chars.count, isSeparator(chars[j]) { j += 1 }
            return j >= chars.count
        }

        private func isSeparator(_ c: Character) -> Bool {
            c == " " || c == "," || c == "\n" || c == "\r" || c == "\t"
        }

        package mutating func skipSeparators() {
            while i < chars.count, isSeparator(chars[i]) { i += 1 }
        }

        package mutating func advance() { i += 1 }

        /// The next command letter, if the scanner is sitting on one.
        package mutating func peekCommand() -> Character? {
            skipSeparators()
            guard i < chars.count else { return nil }
            let c = chars[i]
            return "MmZzLlHhVvCcSsQqTtAa".contains(c) ? c : nil
        }

        package mutating func number() -> CGFloat? {
            skipSeparators()
            guard i < chars.count else { return nil }
            let startIndex = i

            if chars[i] == "+" || chars[i] == "-" { i += 1 }
            var digits = 0
            while i < chars.count, chars[i].isNumber { i += 1; digits += 1 }
            if i < chars.count, chars[i] == "." {
                i += 1
                while i < chars.count, chars[i].isNumber { i += 1; digits += 1 }
            }
            guard digits > 0 else { i = startIndex; return nil }
            if i < chars.count, chars[i] == "e" || chars[i] == "E" {
                let mark = i
                i += 1
                if i < chars.count, chars[i] == "+" || chars[i] == "-" { i += 1 }
                var expDigits = 0
                while i < chars.count, chars[i].isNumber { i += 1; expDigits += 1 }
                if expDigits == 0 { i = mark }
            }
            guard let v = Double(String(chars[startIndex..<i])) else { i = startIndex; return nil }
            return CGFloat(v)
        }

        package mutating func point() -> CGPoint? {
            guard let x = number(), let y = number() else { return nil }
            return CGPoint(x: x, y: y)
        }

        /// An arc flag is a single character, and "a1 1 0 011 1" is legal:
        /// the two flags and the first coordinate run together.
        package mutating func flag() -> Bool? {
            skipSeparators()
            guard i < chars.count else { return nil }
            switch chars[i] {
            case "0": i += 1; return false
            case "1": i += 1; return true
            default:  return nil
            }
        }
    }
}
