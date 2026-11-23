import Foundation
import CoreGraphics
import Vision

/// Finds sensitive text to redact. Text is always read on this Mac with Vision; patterns (email,
/// phone, card numbers) are matched locally, and with AI on, the recognised lines (text only, never
/// the image) are sent to Gemini to find names, addresses, codes, keys and the like.
enum SmartBlurDetector {
    struct Detection: Sendable {
        /// Normalized rects, origin top-left.
        let rects: [CGRect]
        /// Set when Gemini was asked but failed; the local matches are still returned.
        let aiError: String?
    }

    private static let emailRegex = try! NSRegularExpression(pattern: #"[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}"#, options: [])
    private static let phoneRegex = try! NSRegularExpression(pattern: #"(?:\+84|0)(?:\d[\s.-]?){9,10}"#, options: [])
    private static let cardRegex = try! NSRegularExpression(pattern: #"\b(?:\d[ -]*?){13,19}\b"#, options: [])

    private static func checkLuhn(_ numberString: String) -> Bool {
        let digits = numberString.compactMap { $0.wholeNumberValue }
        guard digits.count >= 13 && digits.count <= 19 else { return false }

        var sum = 0
        for (index, digit) in digits.reversed().enumerated() {
            if index % 2 == 1 {
                let doubled = digit * 2
                sum += doubled > 9 ? doubled - 9 : doubled
            } else {
                sum += digit
            }
        }
        return sum % 10 == 0
    }

    /// Ranges of `text` that match a local pattern.
    private static func sensitiveRanges(in text: String) -> [Range<String.Index>] {
        let nsRange = NSRange(text.startIndex..<text.endIndex, in: text)
        var ranges: [Range<String.Index>] = []
        for regex in [emailRegex, phoneRegex] {
            for match in regex.matches(in: text, range: nsRange) {
                if let range = Range(match.range, in: text) { ranges.append(range) }
            }
        }
        for match in cardRegex.matches(in: text, range: nsRange) {
            if let range = Range(match.range, in: text), checkLuhn(String(text[range])) { ranges.append(range) }
        }
        return ranges
    }

    /// Local pattern matching only; used right after a capture, where a network round trip would slow the preview.
    static func detectSensitiveRects(in image: CGImage) async -> [CGRect] {
        await detect(in: image, useAI: false).rects
    }

    static func detect(in image: CGImage, useAI: Bool) async -> Detection {
        await Task.detached(priority: .userInitiated) { () -> Detection in
            let lines = TextLineReader.read(image)
            guard !lines.isEmpty else { return Detection(rects: [], aiError: nil) }

            var rects: [CGRect] = []
            for line in lines {
                for range in sensitiveRanges(in: line.text) {
                    rects.append(line.rect(for: range))
                }
            }

            var aiError: String?
            if useAI {
                do {
                    let findings = try await GeminiService.findSensitive(in: lines.map(\.text))
                    for finding in findings where lines.indices.contains(finding.line) {
                        let line = lines[finding.line]
                        let value = finding.value.trimmingCharacters(in: .whitespacesAndNewlines)
                        guard !value.isEmpty else { continue }
                        if let range = line.text.range(of: value) ?? line.text.range(of: value, options: [.caseInsensitive, .diacriticInsensitive]) {
                            rects.append(line.rect(for: range))
                        } else {
                            rects.append(line.box)
                        }
                    }
                } catch {
                    aiError = error.localizedDescription
                }
            }
            return Detection(rects: merged(rects.map(padded)), aiError: aiError)
        }.value
    }

    /// A little room around the text so the blur covers the glyph edges.
    private static func padded(_ rect: CGRect) -> CGRect {
        let pad = rect.height * 0.15
        return rect.insetBy(dx: -pad, dy: -pad).intersection(CGRect(x: 0, y: 0, width: 1, height: 1))
    }

    /// Joins rects that mostly overlap, so a value found by both the patterns and Gemini gets one blur.
    private static func merged(_ rects: [CGRect]) -> [CGRect] {
        var result: [CGRect] = []
        for rect in rects where !rect.isEmpty {
            if let index = result.firstIndex(where: { overlapRatio($0, rect) > 0.5 }) {
                result[index] = result[index].union(rect)
            } else {
                result.append(rect)
            }
        }
        return result
    }

    static func overlapRatio(_ a: CGRect, _ b: CGRect) -> CGFloat {
        let intersection = a.intersection(b)
        guard !intersection.isNull else { return 0 }
        let smaller = min(a.width * a.height, b.width * b.height)
        return smaller > 0 ? (intersection.width * intersection.height) / smaller : 0
    }
}

/// Lines of text read by Vision, with their boxes in normalized top-left coordinates.
struct TextLine {
    let text: String
    let box: CGRect
    fileprivate let candidate: VNRecognizedText

    /// The box of part of the line, or the whole line if Vision cannot place it.
    func rect(for range: Range<String.Index>) -> CGRect {
        guard let observation = try? candidate.boundingBox(for: range) else { return box }
        return TextLineReader.topLeft(observation.boundingBox)
    }
}

enum TextLineReader {
    static func read(_ image: CGImage) -> [TextLine] {
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.usesLanguageCorrection = false
        request.automaticallyDetectsLanguage = true
        do {
            try VNImageRequestHandler(cgImage: image, options: [:]).perform([request])
        } catch {
            print("Text recognition failed: \(error)")
            return []
        }
        return (request.results ?? []).compactMap { observation in
            guard let candidate = observation.topCandidates(1).first,
                  !candidate.string.trimmingCharacters(in: .whitespaces).isEmpty else { return nil }
            return TextLine(text: candidate.string, box: topLeft(observation.boundingBox), candidate: candidate)
        }
    }

    /// Vision's bottom-left normalized rect, flipped to top-left.
    static func topLeft(_ box: CGRect) -> CGRect {
        CGRect(x: box.origin.x, y: 1 - (box.origin.y + box.height), width: box.width, height: box.height)
    }
}
