import AppKit
import CoreGraphics

/// Translates the text in an image in place: Vision finds each line and its box on this Mac,
/// Gemini translates the lines in context, and each line gets a cover in the background colour
/// with the translation drawn over it in the text colour.
enum ImageTranslator {
    struct Line: Sendable {
        /// Normalized box of the original line, origin top-left.
        let box: CGRect
        let text: String
        let background: AnnotationSwatch
        let foreground: AnnotationSwatch
        /// Whether the original strokes look heavy enough to be bold.
        let isBold: Bool
        /// Whether the line sits centred in its background (a button, a centred heading).
        let isCentered: Bool
        /// Font size in image pixels that fits the translation into the original line's width.
        let fontPixelSize: CGFloat
    }

    enum Failure: LocalizedError {
        case noText
        var errorDescription: String? { "No text found to translate." }
    }

    static func translate(_ image: CGImage, to target: OCRTranslationLanguage) async throws -> [Line] {
        let found = await Task.detached(priority: .userInitiated) { () -> [(String, CGRect)] in
            TextLineReader.read(image).map { ($0.text, $0.box) }
        }.value
        guard !found.isEmpty else { throw Failure.noText }

        let translations = try await GeminiService.translateLines(found.map(\.0), to: target, image: image)

        return await Task.detached(priority: .userInitiated) { () -> [Line] in
            let pixels = PixelReader(image)
            let width = CGFloat(image.width), height = CGFloat(image.height)
            return zip(found, translations).compactMap { line, translation in
                let text = translation.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !text.isEmpty else { return nil }
                let (_, box) = line
                let pixelBox = CGRect(x: box.minX * width, y: box.minY * height, width: box.width * width, height: box.height * height)
                let (background, foreground, stroke) = pixels?.colors(in: pixelBox) ?? (.white, .black, 0)
                let bold = Self.looksBold(stroke: stroke)
                return Line(
                    box: box,
                    text: text,
                    background: background,
                    foreground: foreground,
                    isBold: bold,
                    isCentered: pixels?.isCentered(pixelBox, background: background) ?? false,
                    fontPixelSize: fittedFontSize(for: text, in: pixelBox, bold: bold)
                )
            }
        }.value
    }

    /// Vision's line box spans roughly ascender to descender, so the font is a bit smaller than it;
    /// longer translations shrink to keep to the original width.
    static func fittedFontSize(for text: String, in box: CGRect, bold: Bool) -> CGFloat {
        var size = max(box.height * 0.78, 7)
        let width = textWidth(text, size: size, bold: bold)
        let room = box.width * 1.06
        if width > room, width > 0 {
            size = max(size * room / width, max(box.height * 0.45, 7))
        }
        return size
    }

    /// Bold when the average stroke is thick for the line's height: regular text measures about
    /// 0.08–0.12 of the line height, bold headings 0.15 and up.
    static func looksBold(stroke: Double) -> Bool {
        stroke > 0.14
    }

    static func textWidth(_ text: String, size: CGFloat, bold: Bool = false) -> CGFloat {
        let font = AnnotationTextMetrics.resolvedFont(name: AnnotationTextMetrics.defaultFontName, size: size, bold: bold, italic: false)
        return NSAttributedString(string: text, attributes: [.font: font]).size().width
    }
}

/// Reads RGBA pixels of an image once, top row first.
private struct PixelReader {
    let width: Int
    let height: Int
    let data: [UInt8]

    init?(_ image: CGImage) {
        let width = image.width
        let height = image.height
        self.width = width
        self.height = height
        guard width > 0, height > 0, let space = CGColorSpace(name: CGColorSpace.sRGB) else { return nil }
        var buffer = [UInt8](repeating: 0, count: width * height * 4)
        let drawn = buffer.withUnsafeMutableBytes { raw -> Bool in
            guard let context = CGContext(
                data: raw.baseAddress, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4,
                space: space, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            ) else { return false }
            context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
            return true
        }
        guard drawn else { return nil }
        data = buffer
    }

    private func pixel(_ x: Int, _ y: Int) -> (Int, Int, Int)? {
        guard x >= 0, y >= 0, x < width, y < height else { return nil }
        let i = (y * width + x) * 4
        return (Int(data[i]), Int(data[i + 1]), Int(data[i + 2]))
    }

    /// The background is the most common colour on a ring just outside the box; the text colour is
    /// the most common colour inside it that stands clearly apart from the background.
    func colors(in box: CGRect) -> (AnnotationSwatch, AnnotationSwatch, Double) {
        let margin = max(2, Int(box.height * 0.18))
        let minX = Int(box.minX) - margin, maxX = Int(box.maxX) + margin
        let minY = Int(box.minY) - margin, maxY = Int(box.maxY) + margin
        let step = max(1, Int(box.height / 12))

        var ring: [(Int, Int, Int)] = []
        var x = minX
        while x <= maxX {
            if let p = pixel(x, minY) { ring.append(p) }
            if let p = pixel(x, maxY) { ring.append(p) }
            x += step
        }
        var y = minY
        while y <= maxY {
            if let p = pixel(minX, y) { ring.append(p) }
            if let p = pixel(maxX, y) { ring.append(p) }
            y += step
        }
        let background = Self.dominant(ring) ?? (255, 255, 255)

        var inside: [(Int, Int, Int)] = []
        var sampled = 0
        let innerStep = max(1, Int(box.height / 24))
        y = Int(box.minY)
        while y < Int(box.maxY) {
            x = Int(box.minX)
            while x < Int(box.maxX) {
                if let p = pixel(x, y) {
                    sampled += 1
                    if Self.distance(p, background) > 90 { inside.append(p) }
                }
                x += innerStep
            }
            y += innerStep
        }
        let foreground = Self.dominant(inside) ?? (Self.luminance(background) > 140 ? (20, 20, 20) : (245, 245, 245))
        return (Self.swatch(background), Self.swatch(foreground), strokeWidth(in: box, background: background))
    }

    /// Whether the background reaches about as far left of the line as right of it, with real room
    /// on both sides: the line is centred in a button, card or banner rather than starting at its edge.
    func isCentered(_ box: CGRect, background swatch: AnnotationSwatch) -> Bool {
        let background = (Int(swatch.red * 255), Int(swatch.green * 255), Int(swatch.blue * 255))
        let y = Int(box.midY)
        func reach(from start: Int, step: Int) -> Int {
            var x = start, tolerance = 0
            while let p = pixel(x, y) {
                if Self.distance(p, background) > 24 {
                    tolerance += 1
                    if tolerance > 2 { break }
                } else {
                    tolerance = 0
                }
                x += step
            }
            return abs(x - start)
        }
        let left = Double(reach(from: Int(box.minX) - 1, step: -1))
        let right = Double(reach(from: Int(box.maxX) + 1, step: 1))
        guard min(left, right) > Double(box.height) else { return false }
        return abs(left - right) < 0.2 * (left + right + Double(box.width))
    }

    /// Average horizontal run of ink across the middle rows of the line, relative to the line's height.
    /// Stroke thickness tells regular from bold text regardless of how many letters there are.
    private func strokeWidth(in box: CGRect, background: (Int, Int, Int)) -> Double {
        guard box.height >= 4 else { return 0 }
        var runs = 0, total = 0
        let rows = stride(from: Int(box.minY + box.height * 0.3), to: Int(box.maxY - box.height * 0.3), by: max(1, Int(box.height / 16)))
        for y in rows {
            var run = 0
            for x in Int(box.minX)..<Int(box.maxX) {
                if let p = pixel(x, y), Self.distance(p, background) > 200 {
                    run += 1
                } else if run > 0 {
                    runs += 1; total += run; run = 0
                }
            }
            if run > 0 { runs += 1; total += run }
        }
        return runs > 0 ? Double(total) / Double(runs) / box.height : 0
    }

    /// Average of the most common bucket of colours (4 bits per channel).
    private static func dominant(_ pixels: [(Int, Int, Int)]) -> (Int, Int, Int)? {
        guard !pixels.isEmpty else { return nil }
        var buckets: [Int: (count: Int, r: Int, g: Int, b: Int)] = [:]
        for (r, g, b) in pixels {
            let key = (r >> 4) << 8 | (g >> 4) << 4 | (b >> 4)
            var entry = buckets[key] ?? (0, 0, 0, 0)
            entry.count += 1; entry.r += r; entry.g += g; entry.b += b
            buckets[key] = entry
        }
        guard let best = buckets.values.max(by: { $0.count < $1.count }) else { return nil }
        return (best.r / best.count, best.g / best.count, best.b / best.count)
    }

    private static func distance(_ a: (Int, Int, Int), _ b: (Int, Int, Int)) -> Int {
        abs(a.0 - b.0) + abs(a.1 - b.1) + abs(a.2 - b.2)
    }

    private static func luminance(_ c: (Int, Int, Int)) -> Double {
        0.299 * Double(c.0) + 0.587 * Double(c.1) + 0.114 * Double(c.2)
    }

    private static func swatch(_ c: (Int, Int, Int)) -> AnnotationSwatch {
        let id = String(format: "sampled-%02x%02x%02x", c.0, c.1, c.2)
        return AnnotationSwatch(id, title: "Sampled", red: CGFloat(c.0) / 255, green: CGFloat(c.1) / 255, blue: CGFloat(c.2) / 255)
    }
}
