import CoreGraphics
import Foundation

// MARK: - Ellipse styles

/// Ellipse looks: a hand-drawn loop, a plain outline, a translucent highlight, or solid.
enum AnnotationEllipseStyle: String, CaseIterable, Identifiable {
    case sketch
    case outline
    case highlight
    case filled

    var id: String { rawValue }

    var title: String {
        switch self {
        case .sketch: "Hand-drawn"
        case .outline: "Outline"
        case .highlight: "Highlight"
        case .filled: "Filled"
        }
    }

    /// Opacity of the fill, or nil when the ellipse is only stroked.
    var fillOpacity: CGFloat? {
        switch self {
        case .sketch, .outline: nil
        case .highlight: 0.35
        case .filled: 1
        }
    }

    /// Outline of the ellipse inscribed in `rect`. The sketch style overshoots its
    /// start like a loop drawn by hand.
    func path(in rect: CGRect) -> CGPath {
        guard self == .sketch else { return CGPath(ellipseIn: rect, transform: nil) }

        let path = CGMutablePath()
        let center = CGPoint(x: rect.midX, y: rect.midY)
        let rx = rect.width / 2
        let ry = rect.height / 2
        let startAngle = -CGFloat.pi * 0.3
        let sweep = CGFloat.pi * 2.18
        let steps = 72
        for step in 0...steps {
            let t = CGFloat(step) / CGFloat(steps)
            let angle = startAngle + sweep * t
            // Starts slightly outside the ellipse and ends slightly inside it.
            let scale = 1.04 - 0.1 * t + 0.015 * sin(angle * 3)
            let point = CGPoint(x: center.x + cos(angle) * rx * scale, y: center.y + sin(angle) * ry * scale)
            if step == 0 { path.move(to: point) } else { path.addLine(to: point) }
        }
        return path
    }
}

// MARK: - Arrow styles

/// Arrow looks: a hollow outline, a tapered filled arrow, or a thin line with an open head.
enum AnnotationArrowStyle: String, CaseIterable, Identifiable {
    case outline
    case filled
    case line

    var id: String { rawValue }

    var title: String {
        switch self {
        case .outline: "Outlined arrow"
        case .filled: "Bold arrow"
        case .line: "Line arrow"
        }
    }
}

/// Builds the closed outline of a bold arrow along a quadratic curve. Works in any
/// coordinate space, so the editor preview and the export share it.
enum AnnotationArrowShape {
    static func path(
        start: CGPoint,
        control: CGPoint,
        end: CGPoint,
        lineWidth: CGFloat,
        doubleHeaded: Bool,
        widthScale: CGFloat = 1
    ) -> CGPath? {
        let samples = (0...40).map { quadraticPoint(start, control, end, CGFloat($0) / 40) }
        var lengths: [CGFloat] = [0]
        for index in 1..<samples.count {
            lengths.append(lengths[index - 1] + distance(samples[index - 1], samples[index]))
        }
        guard let total = lengths.last, total > 2 else { return nil }

        let unit = max(lineWidth, 1) * widthScale
        let headLength = min(max(14, unit * 4.6), total * (doubleHeaded ? 0.3 : 0.45))
        let headHalfWidth = max(7, unit * 2.6)
        let bodyStart = doubleHeaded ? headLength : 0
        let bodyEnd = total - headLength
        // Single arrows taper from a thin tail; double arrows keep an even body.
        let tailHalfWidth = doubleHeaded ? unit * 0.9 : unit * 0.45
        let neckHalfWidth = unit * 0.95

        func point(at length: CGFloat) -> (CGPoint, CGPoint) {
            let clamped = min(max(length, 0), total)
            var index = 1
            while index < lengths.count - 1, lengths[index] < clamped { index += 1 }
            let segment = max(lengths[index] - lengths[index - 1], 0.0001)
            let t = (clamped - lengths[index - 1]) / segment
            let a = samples[index - 1]
            let b = samples[index]
            let p = CGPoint(x: a.x + (b.x - a.x) * t, y: a.y + (b.y - a.y) * t)
            let d = distance(a, b)
            let tangent = d > 0 ? CGPoint(x: (b.x - a.x) / d, y: (b.y - a.y) / d) : CGPoint(x: 1, y: 0)
            return (p, CGPoint(x: -tangent.y, y: tangent.x))
        }

        func offset(_ p: CGPoint, _ n: CGPoint, _ amount: CGFloat) -> CGPoint {
            CGPoint(x: p.x + n.x * amount, y: p.y + n.y * amount)
        }

        let bodySteps = 24
        var left: [CGPoint] = []
        var right: [CGPoint] = []
        for step in 0...bodySteps {
            let t = CGFloat(step) / CGFloat(bodySteps)
            let length = bodyStart + (bodyEnd - bodyStart) * t
            let (p, n) = point(at: length)
            let halfWidth = tailHalfWidth + (neckHalfWidth - tailHalfWidth) * t
            left.append(offset(p, n, halfWidth))
            right.append(offset(p, n, -halfWidth))
        }

        let (headBase, headNormal) = point(at: bodyEnd)
        let path = CGMutablePath()
        path.move(to: left[0])
        left.dropFirst().forEach { path.addLine(to: $0) }
        path.addLine(to: offset(headBase, headNormal, headHalfWidth))
        path.addLine(to: end)
        path.addLine(to: offset(headBase, headNormal, -headHalfWidth))
        right.reversed().forEach { path.addLine(to: $0) }
        if doubleHeaded {
            let (tailBase, tailNormal) = point(at: bodyStart)
            path.addLine(to: offset(tailBase, tailNormal, -headHalfWidth))
            path.addLine(to: start)
            path.addLine(to: offset(tailBase, tailNormal, headHalfWidth))
        }
        path.closeSubpath()
        return path
    }

    private static func quadraticPoint(_ a: CGPoint, _ c: CGPoint, _ b: CGPoint, _ t: CGFloat) -> CGPoint {
        let u = 1 - t
        return CGPoint(
            x: u * u * a.x + 2 * u * t * c.x + t * t * b.x,
            y: u * u * a.y + 2 * u * t * c.y + t * t * b.y
        )
    }

    private static func distance(_ a: CGPoint, _ b: CGPoint) -> CGFloat {
        hypot(b.x - a.x, b.y - a.y)
    }
}

// MARK: - Magnifier

/// A magnifier has a small source circle (`rect`) and a larger lens showing it
/// enlarged. The lens centre is stored in `points[0]`; its size is the source
/// size times `magnification`.
enum AnnotationMagnifierMetrics {
    static let defaultMagnification: CGFloat = 2.5
    static let magnificationRange: ClosedRange<CGFloat> = 1.2...8

    /// Where to draw the whole image so that the source circle's centre lands on
    /// the lens centre, enlarged by `magnification`.
    static func zoomedImageRect(
        _ imageRect: CGRect,
        source: CGRect,
        lens: CGRect,
        magnification: CGFloat
    ) -> CGRect {
        CGRect(
            x: lens.midX + (imageRect.minX - source.midX) * magnification,
            y: lens.midY + (imageRect.minY - source.midY) * magnification,
            width: imageRect.width * magnification,
            height: imageRect.height * magnification
        )
    }

    /// Lens rect (normalized) for a source rect and lens centre.
    static func lensRect(source: CGRect, center: CGPoint, magnification: CGFloat) -> CGRect {
        let width = source.width * magnification
        let height = source.height * magnification
        return CGRect(x: center.x - width / 2, y: center.y - height / 2, width: width, height: height)
    }

    /// Picks a lens centre beside the source, preferring up-right, that keeps the
    /// lens inside `bounds` when possible.
    static func defaultLensCenter(
        source: CGRect,
        magnification: CGFloat,
        imageSize: CGSize,
        within bounds: CGRect
    ) -> CGPoint {
        let w = max(imageSize.width, 1)
        let h = max(imageSize.height, 1)
        let sourceRadius = source.width * w / 2
        let lensRadius = sourceRadius * magnification
        let distance = sourceRadius + lensRadius + max(8, lensRadius * 0.25)
        let angles: [CGFloat] = [-.pi / 4, -3 * .pi / 4, .pi / 4, 3 * .pi / 4, 0, .pi]
        let candidates = angles.map { angle in
            CGPoint(
                x: source.midX + cos(angle) * distance / w,
                y: source.midY + sin(angle) * distance / h
            )
        }
        return candidates.first { center in
            bounds.contains(lensRect(source: source, center: center, magnification: magnification))
        } ?? candidates[0]
    }

    /// Segment joining the two circles' edges along the line between their centres,
    /// or nil when they overlap. Points are in a uniformly scaled space.
    static func connector(source: CGRect, lens: CGRect) -> (CGPoint, CGPoint)? {
        let a = CGPoint(x: source.midX, y: source.midY)
        let b = CGPoint(x: lens.midX, y: lens.midY)
        let d = hypot(b.x - a.x, b.y - a.y)
        let sourceRadius = source.width / 2
        let lensRadius = lens.width / 2
        guard d > sourceRadius + lensRadius else { return nil }
        let ux = (b.x - a.x) / d
        let uy = (b.y - a.y) / d
        return (
            CGPoint(x: a.x + ux * sourceRadius, y: a.y + uy * sourceRadius),
            CGPoint(x: b.x - ux * lensRadius, y: b.y - uy * lensRadius)
        )
    }
}
