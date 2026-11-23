import CoreGraphics

/// Joins frames of a scrolling area into one tall image.
///
/// Each frame is reduced to one hash per pixel row, leaving out the side edges where the scroll bar
/// and window corners sit. A new frame is matched against the previous one by finding how far its
/// rows moved, up or down, and the session keeps track of where the view is in the stitched image:
/// scrolling back up adds nothing, scrolling down past what was captured adds the new rows. Rows that
/// stay put at the top or bottom of both frames (a sticky header or footer) are left out of the
/// match, kept once from the first frame and once from the last.
final class ScrollStitcher {
    enum Result: Equatable {
        /// The first frame was stored.
        case started
        /// Nothing moved.
        case unchanged
        /// This many new pixel rows were added.
        case appended(Int)
        /// The view moved but showed nothing new (it scrolled back up, or within what was captured).
        case moved
        /// The frame could not be matched to the previous one (scrolled too far, or the content changed).
        case lost
        /// The image reached `maxHeight`.
        case full
    }

    let maxHeight: Int
    /// Total height of the stitched image so far, in pixels.
    private(set) var height = 0
    private(set) var width = 0

    private var pieces: [CGImage] = []
    private var previous: Frame?
    private var footerRows: Int?
    /// Where the top of the latest frame sits in the stitched image.
    private var position = 0
    /// The last movement found, in pixel rows; positive means the content moved up (scrolled down).
    private(set) var lastShift = 0

    init(maxHeight: Int = 20_000) {
        self.maxHeight = maxHeight
    }

    @discardableResult
    func add(_ image: CGImage) -> Result {
        guard let frame = Frame(image) else { return .lost }

        guard let previous else {
            width = frame.width
            pieces = [image]
            height = frame.height
            self.previous = frame
            return .started
        }
        guard frame.width == previous.width, frame.height == previous.height else { return .lost }
        if height >= maxHeight { return .full }

        let rows = frame.height
        let (top, bottom) = Self.fixedBands(previous, frame)
        if top + bottom >= rows - 4 { return .unchanged }

        guard let shift = Self.shift(from: previous, to: frame, top: top, bottom: bottom) else { return .lost }
        if shift == 0 { return .unchanged }
        lastShift = shift

        // The footer is decided once, by the first pair that moves, and trimmed off the first frame.
        if footerRows == nil {
            footerRows = bottom
            if bottom > 0, let first = pieces.first,
               let trimmed = first.cropping(to: CGRect(x: 0, y: 0, width: first.width, height: first.height - bottom)) {
                pieces[0] = trimmed
                height -= bottom
            }
        }
        let footer = footerRows ?? 0
        position = max(0, position + shift)
        self.previous = frame
        // Rows of this frame that reach below what has been stitched so far are new.
        let visibleBottom = position + rows - footer
        let added = min(visibleBottom - height, maxHeight - height)
        guard added > 0 else { return .moved }
        let stripTop = rows - footer - added
        guard stripTop >= 0,
              let strip = Self.copy(image, rows: stripTop..<(stripTop + added)) else { return .lost }

        pieces.append(strip)
        height += added
        return height >= maxHeight ? .full : .appended(added)
    }

    /// The stitched image, with the footer of the last frame added back at the bottom.
    func render() -> CGImage? {
        guard width > 0, height > 0 else { return nil }
        var footer: CGImage?
        if let footerRows, footerRows > 0, let last = previous?.image {
            footer = Self.copy(last, rows: (last.height - footerRows)..<last.height)
        }
        let total = height + (footer?.height ?? 0)
        guard let space = CGColorSpace(name: CGColorSpace.sRGB),
              let context = CGContext(
                data: nil, width: width, height: total, bitsPerComponent: 8, bytesPerRow: 0,
                space: space, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
              ) else { return nil }
        // CoreGraphics draws from the bottom up; place pieces from the top of the canvas down.
        var y = total
        for piece in pieces + (footer.map { [$0] } ?? []) {
            y -= piece.height
            context.draw(piece, in: CGRect(x: 0, y: y, width: piece.width, height: piece.height))
        }
        return context.makeImage()
    }

    // MARK: - Matching

    /// Rows at the top and bottom that are identical in both frames (sticky bars), at most a third each.
    private static func fixedBands(_ a: Frame, _ b: Frame) -> (Int, Int) {
        let limit = a.height / 3
        var top = 0
        while top < limit, a.hashes[top] == b.hashes[top] { top += 1 }
        var bottom = 0
        while bottom < limit, a.hashes[a.height - 1 - bottom] == b.hashes[b.height - 1 - bottom] { bottom += 1 }
        // A band of page background that happens to match is harmless: its rows still reach the
        // image as they scroll through the middle, and the last frame's bottom band is added at the end.
        return (top, bottom)
    }

    /// How many rows the content moved between `a` and `b` (positive: up). Whole rows are tried
    /// first; when part of the area stays still (a sidebar beside a scrolling page), each column
    /// band is matched on its own and the movement of the bands that scrolled wins.
    private static func shift(from a: Frame, to b: Frame, top: Int, bottom: Int) -> Int? {
        if let whole = bestShift(a.hashes, a.informative, b.hashes, top: top, end: a.height - bottom) {
            return whole.shift
        }
        var votes: [Int: Int] = [:]
        var anyStill = false
        for band in 0..<Frame.bandCount {
            guard let found = bestShift(a.bandHashes[band], a.bandInformative[band], b.bandHashes[band],
                                        top: top, end: a.height - bottom) else { continue }
            if found.shift == 0 { anyStill = true } else { votes[found.shift, default: 0] += found.matches }
        }
        if let moved = votes.max(by: { $0.value < $1.value }) { return moved.key }
        return anyStill ? 0 : nil
    }

    /// The movement that best lines up row hashes `b` with `a`, trying small movements first.
    private static func bestShift(_ a: [UInt64], _ informativeA: [Bool], _ b: [UInt64], top: Int, end: Int) -> (shift: Int, matches: Int)? {
        let span = end - top
        let minimumOverlap = max(24, span / 8)
        guard span > minimumOverlap else { return nil }
        let limit = span - minimumOverlap

        var best: (shift: Int, ratio: Double, matches: Int)?
        for magnitude in 0...limit {
            for shift in magnitude == 0 ? [0] : [magnitude, -magnitude] {
                // Row r of `b` shows what row r + shift of `a` showed.
                let first = max(top, top - shift)
                let last = min(end, end - shift)
                var matches = 0
                var considered = 0
                var row = first
                while row < last {
                    if informativeA[row + shift] {
                        considered += 1
                        if b[row] == a[row + shift] { matches += 1 }
                    }
                    row += 1
                }
                guard considered >= 8 else { continue }
                let ratio = Double(matches) / Double(considered)
                guard ratio >= 0.8 else { continue }
                if best == nil || ratio > best!.ratio + 0.001 || (abs(ratio - best!.ratio) <= 0.001 && matches > best!.matches) {
                    best = (shift, ratio, matches)
                }
                if ratio >= 0.98, matches >= 32 { return (shift, matches) }
            }
        }
        return best.map { ($0.shift, $0.matches) }
    }

    private static func copy(_ image: CGImage, rows: Range<Int>) -> CGImage? {
        guard !rows.isEmpty,
              let cropped = image.cropping(to: CGRect(x: 0, y: rows.lowerBound, width: image.width, height: rows.count)),
              let space = CGColorSpace(name: CGColorSpace.sRGB),
              let context = CGContext(
                data: nil, width: cropped.width, height: cropped.height, bitsPerComponent: 8, bytesPerRow: 0,
                space: space, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
              ) else { return nil }
        // Copy the rows so the full frame they came from can be released.
        context.draw(cropped, in: CGRect(x: 0, y: 0, width: cropped.width, height: cropped.height))
        return context.makeImage()
    }

    // MARK: - Frames

    private struct Frame {
        let image: CGImage
        let width: Int
        let height: Int
        /// One hash per pixel row, top to bottom.
        let hashes: [UInt64]
        /// Whether a row differs from the one above it; flat background rows say little about position.
        let informative: [Bool]
        static let bandCount = 4
        /// The same, per vertical band of columns, for areas where only part of the width scrolls.
        let bandHashes: [[UInt64]]
        let bandInformative: [[Bool]]

        init?(_ image: CGImage) {
            let width = image.width
            let height = image.height
            guard width > 0, height > 0,
                  let space = CGColorSpace(name: CGColorSpace.sRGB) else { return nil }
            // Rows only need about 600 samples each, so draw the frame squeezed horizontally:
            // every row keeps its own pixels, at a fraction of the memory and time. The side
            // edges are left out: the scroll bar moves with every frame and window corners don't.
            let sampleWidth = min(width, 600)
            let leftSkip = max(2, sampleWidth / 40)
            let rightSkip = max(4, Int((Double(max(36, width / 25)) * Double(sampleWidth) / Double(width)).rounded(.up)))
            var pixels = [UInt8](repeating: 0, count: sampleWidth * height * 4)
            let drawn = pixels.withUnsafeMutableBytes { raw -> Bool in
                guard let context = CGContext(
                    data: raw.baseAddress, width: sampleWidth, height: height, bitsPerComponent: 8,
                    bytesPerRow: sampleWidth * 4, space: space,
                    bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
                ) else { return false }
                context.interpolationQuality = .none
                context.draw(image, in: CGRect(x: 0, y: 0, width: sampleWidth, height: height))
                return true
            }
            guard drawn else { return nil }

            // Drop the low bits so tiny rendering noise still matches. Each row gets a hash per band
            // and a hash of the whole row built from them.
            let columns = max(Self.bandCount, sampleWidth - leftSkip - rightSkip)
            var hashes = [UInt64](repeating: 0, count: height)
            var bandHashes = [[UInt64]](repeating: [UInt64](repeating: 0, count: height), count: Self.bandCount)
            for y in 0..<height {
                var whole: UInt64 = 0xcbf2_9ce4_8422_2325
                for band in 0..<Self.bandCount {
                    var hash: UInt64 = 0xcbf2_9ce4_8422_2325
                    let from = leftSkip + columns * band / Self.bandCount
                    let to = leftSkip + columns * (band + 1) / Self.bandCount
                    var index = (y * sampleWidth + from) * 4
                    let rowEnd = (y * sampleWidth + to) * 4
                    while index < rowEnd {
                        let value = UInt64(pixels[index] >> 2) << 12 | UInt64(pixels[index + 1] >> 2) << 6 | UInt64(pixels[index + 2] >> 2)
                        hash = (hash ^ value) &* 0x0000_0100_0000_01b3
                        index += 4
                    }
                    bandHashes[band][y] = hash
                    whole = (whole ^ hash) &* 0x0000_0100_0000_01b3
                }
                hashes[y] = whole
            }
            func changes(_ values: [UInt64]) -> [Bool] {
                var result = [Bool](repeating: false, count: values.count)
                for y in 1..<max(values.count, 1) where values[y] != values[y - 1] { result[y] = true }
                return result
            }
            let informative = changes(hashes)

            self.image = image
            self.width = width
            self.height = height
            self.hashes = hashes
            self.informative = informative
            self.bandHashes = bandHashes
            self.bandInformative = bandHashes.map(changes)
        }
    }
}
