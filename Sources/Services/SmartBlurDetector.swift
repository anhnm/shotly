import Foundation
import CoreGraphics
import Vision

enum SmartBlurDetector {
    private static let emailRegex = try! NSRegularExpression(pattern: #"[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}"#, options: [])
    private static let phoneRegex = try! NSRegularExpression(pattern: #"(?:\+84|0)(?:\d[\s.-]?){9,10}"#, options: [])
    private static let cardRegex = try! NSRegularExpression(pattern: #"\b(?:\d[ -]*?){13,19}\b"#, options: [])

    private static func checkLuhn(_ numberString: String) -> Bool {
        let digits = numberString.compactMap { $0.wholeNumberValue }
        guard digits.count >= 13 && digits.count <= 19 else { return false }
        
        var sum = 0
        let reversed = digits.reversed()
        for (index, digit) in reversed.enumerated() {
            if index % 2 == 1 {
                let doubled = digit * 2
                sum += doubled > 9 ? doubled - 9 : doubled
            } else {
                sum += digit
            }
        }
        return sum % 10 == 0
    }

    private static func isSensitiveText(_ text: String) -> Bool {
        let nsRange = NSRange(text.startIndex..<text.endIndex, in: text)
        
        // 1. Check Email
        if emailRegex.firstMatch(in: text, options: [], range: nsRange) != nil {
            return true
        }
        
        // 2. Check VN Phone
        if phoneRegex.firstMatch(in: text, options: [], range: nsRange) != nil {
            return true
        }
        
        // 3. Check Credit Card
        let cardMatches = cardRegex.matches(in: text, options: [], range: nsRange)
        for match in cardMatches {
            if let range = Range(match.range, in: text) {
                let matchedString = String(text[range])
                if checkLuhn(matchedString) {
                    return true
                }
            }
        }
        
        return false
    }

    static func detectSensitiveRects(in image: CGImage) async -> [CGRect] {
        return await Task.detached(priority: .userInitiated) { () -> [CGRect] in
            let request = VNRecognizeTextRequest()
            request.recognitionLevel = .accurate
            request.usesLanguageCorrection = false
            request.automaticallyDetectsLanguage = true

            let handler = VNImageRequestHandler(cgImage: image, options: [:])
            do {
                try handler.perform([request])
            } catch {
                print("Failed to perform OCR for Smart Blur: \(error)")
                return []
            }

            guard let observations = request.results else { return [] }
            var rects: [CGRect] = []

            for observation in observations {
                guard let candidate = observation.topCandidates(1).first else { continue }
                let text = candidate.string
                if isSensitiveText(text) {
                    let box = observation.boundingBox
                    // Convert Vision coordinates (origin bottom-left, y up) to SwiftUI (origin top-left, y down)
                    let swiftUIRect = CGRect(
                        x: box.origin.x,
                        y: 1.0 - (box.origin.y + box.size.height),
                        width: box.size.width,
                        height: box.size.height
                    )
                    rects.append(swiftUIRect)
                }
            }

            return rects
        }.value
    }
}
