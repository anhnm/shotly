import AppKit

/// Which spans the smart ruler shows: the measure tool shows both; holding
/// 1 / ← → or 2 / ↑ ↓ shows one direction, with any tool.
enum SmartRulerAxis {
    case both
    case horizontal
    case vertical

    var showsHorizontal: Bool { self != .vertical }
    var showsVertical: Bool { self != .horizontal }
}

/// Runs of same-colored pixels through the hovered pixel, in image pixels
/// (top-left origin, inclusive bounds).
struct SmartRulerSpans: Equatable {
    var x: Int
    var y: Int
    var left: Int
    var right: Int
    var top: Int
    var bottom: Int
}

/// Decoded RGBA copy of the source image, kept while the measure tool is active.
final class SmartRulerPixelBuffer {
    let image: CGImage
    let width: Int
    let height: Int
    private let pixels: [UInt32]

    init?(image: CGImage) {
        let width = image.width
        let height = image.height
        guard width > 0, height > 0 else { return nil }
        var pixels = [UInt32](repeating: 0, count: width * height)
        let drawn = pixels.withUnsafeMutableBytes { raw -> Bool in
            guard let space = CGColorSpace(name: CGColorSpace.sRGB),
                  let context = CGContext(
                    data: raw.baseAddress,
                    width: width,
                    height: height,
                    bitsPerComponent: 8,
                    bytesPerRow: width * 4,
                    space: space,
                    bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
                  ) else { return false }
            context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
            return true
        }
        guard drawn else { return nil }
        self.image = image
        self.width = width
        self.height = height
        self.pixels = pixels
    }

    func spans(atX x: Int, y: Int) -> SmartRulerSpans {
        let reference = pixels[y * width + x]
        var left = x, right = x, top = y, bottom = y
        while left > 0, Self.matches(pixels[y * width + left - 1], reference) { left -= 1 }
        while right < width - 1, Self.matches(pixels[y * width + right + 1], reference) { right += 1 }
        while top > 0, Self.matches(pixels[(top - 1) * width + x], reference) { top -= 1 }
        while bottom < height - 1, Self.matches(pixels[(bottom + 1) * width + x], reference) { bottom += 1 }
        return SmartRulerSpans(x: x, y: y, left: left, right: right, top: top, bottom: bottom)
    }

    /// Treats small differences (compression noise, subtle gradients) as the same color.
    private static func matches(_ lhs: UInt32, _ rhs: UInt32) -> Bool {
        let tolerance: UInt32 = 12
        for shift in stride(from: UInt32(0), to: 32, by: 8) {
            let a = (lhs >> shift) & 0xFF
            let b = (rhs >> shift) & 0xFF
            if (a > b ? a - b : b - a) > tolerance { return false }
        }
        return true
    }
}

extension EditorModel {
    /// Measure annotations for the spans under the cursor, shown before clicking.
    var smartRulerItems: [AnnotationItem] {
        guard let axis = activeSmartRulerAxis, interaction == nil,
              let spans = smartRulerSpans, let buffer = smartRulerBuffer else { return [] }
        let width = CGFloat(buffer.width)
        let height = CGFloat(buffer.height)
        var result: [AnnotationItem] = []

        if axis.showsHorizontal, spans.right > spans.left {
            let y = (CGFloat(spans.y) + 0.5) / height
            result.append(smartRulerItem(
                from: CGPoint(x: CGFloat(spans.left) / width, y: y),
                to: CGPoint(x: CGFloat(spans.right + 1) / width, y: y)
            ))
        }
        if axis.showsVertical, spans.bottom > spans.top {
            let x = (CGFloat(spans.x) + 0.5) / width
            result.append(smartRulerItem(
                from: CGPoint(x: x, y: CGFloat(spans.top) / height),
                to: CGPoint(x: x, y: CGFloat(spans.bottom + 1) / height)
            ))
        }
        return result
    }

    /// The held key's direction, or both with the measure tool; nil when the ruler is off.
    var activeSmartRulerAxis: SmartRulerAxis? {
        heldRulerAxis ?? (selectedTool == .measure && editingTextItemID == nil ? .both : nil)
    }

    /// Recomputes the spans for the hovered pixel while the ruler is active.
    func updateSmartRuler(pixelX: Int, pixelY: Int, image: CGImage) {
        guard activeSmartRulerAxis != nil, collageState == nil else {
            clearSmartRuler()
            return
        }
        if smartRulerBuffer?.image !== image {
            smartRulerBuffer = SmartRulerPixelBuffer(image: image)
        }
        guard let buffer = smartRulerBuffer,
              pixelX < buffer.width, pixelY < buffer.height else { return }
        let spans = buffer.spans(atX: pixelX, y: pixelY)
        if spans != smartRulerSpans { smartRulerSpans = spans }
    }

    func clearSmartRuler() {
        if smartRulerSpans != nil { smartRulerSpans = nil }
    }

    /// Releases the decoded image when leaving the measure tool.
    func releaseSmartRulerBuffer() {
        smartRulerBuffer = nil
        clearSmartRuler()
    }

    /// Key down (an axis) or key up (nil) for the ruler keys.
    func setHeldRulerAxis(_ axis: SmartRulerAxis?) -> Bool {
        guard collageState == nil, !isCropping else { return false }
        if heldRulerAxis != axis { heldRulerAxis = axis }
        if axis != nil, let pixel = hoveredPixel, let image = sourceImage {
            updateSmartRuler(pixelX: pixel.x, pixelY: pixel.y, image: image)
        } else if activeSmartRulerAxis == nil {
            releaseSmartRulerBuffer()
        }
        return true
    }

    /// Adds the hovered spans as annotations. Returns false when nothing is hovered.
    @discardableResult
    func imprintSmartRuler() -> Bool {
        let imprinted = smartRulerItems
        guard !imprinted.isEmpty else { return false }
        history.push(items)
        items.append(contentsOf: imprinted)
        return true
    }

    private func smartRulerItem(from start: CGPoint, to end: CGPoint) -> AnnotationItem {
        AnnotationItem(
            tool: .measure,
            rect: CGRect(
                x: min(start.x, end.x), y: min(start.y, end.y),
                width: abs(end.x - start.x), height: abs(end.y - start.y)
            ),
            points: [start, end],
            swatch: selectedSwatch,
            strokeWidth: strokeWidth
        )
    }
}
