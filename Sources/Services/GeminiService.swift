import AppKit
import Foundation
import Security

/// The user's own Gemini API key, kept in the login keychain.
enum GeminiKey {
    private static let service = "com.shotly.app.gemini"
    private static let account = "api-key"

    static var current: String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var result: AnyObject?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
              let data = result as? Data,
              let key = String(data: data, encoding: .utf8),
              !key.isEmpty else { return nil }
        return key
    }

    static var isSet: Bool { current != nil }

    @discardableResult
    static func save(_ key: String) -> Bool {
        let trimmed = key.trimmingCharacters(in: .whitespacesAndNewlines)
        remove()
        guard !trimmed.isEmpty else { return true }
        let item: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecAttrLabel as String: "Shotly Gemini API key",
            kSecValueData as String: Data(trimmed.utf8),
        ]
        let saved = SecItemAdd(item as CFDictionary, nil) == errSecSuccess
        NotificationCenter.default.post(name: .geminiKeyChanged, object: nil)
        return saved
    }

    static func remove() {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
        SecItemDelete(query as CFDictionary)
        NotificationCenter.default.post(name: .geminiKeyChanged, object: nil)
    }
}

extension Notification.Name {
    static let geminiKeyChanged = Notification.Name("ShotlyGeminiKeyChanged")
}

enum GeminiError: LocalizedError {
    case noKey
    case invalidKey
    case quota
    case blocked
    case server(String)
    case badResponse

    var errorDescription: String? {
        switch self {
        case .noKey: return "Add a Gemini API key in Settings → AI."
        case .invalidKey: return "Gemini rejected the API key. Check it in Settings → AI."
        case .quota: return "Gemini quota reached. Wait a minute and try again."
        case .blocked: return "Gemini declined to answer for this image."
        case .server(let message): return message
        case .badResponse: return "Gemini returned an answer Shotly could not read."
        }
    }
}

/// Calls the Gemini API with the user's key. Only runs when the user picks an AI action;
/// nothing is sent in the background.
enum GeminiService {
    static let defaultModel = "gemini-flash-latest"

    static var model: String {
        let saved = AppPreferences.geminiModel.trimmingCharacters(in: .whitespacesAndNewlines)
        return saved.isEmpty ? defaultModel : saved
    }

    /// Whether AI actions can run: a key is saved.
    static var isAvailable: Bool { GeminiKey.isSet }

    // MARK: - Tasks

    struct Recognition: Decodable, Sendable {
        let text: String
        let language: String?
        let translation: String?
    }

    /// Reads all text in `image`, in any language and script, and translates it when `target` is given.
    static func recognize(_ image: CGImage, translatingTo target: OCRTranslationLanguage?) async throws -> Recognition {
        var instructions = """
        Transcribe all text in this screenshot exactly as written, in its original language and script. \
        Keep the reading order and line breaks; keep code and tables aligned with spaces. \
        Include the content of QR codes or barcodes if any can be read. Do not add commentary. \
        In "language", give the English name of the main language of the text.
        """
        var properties: [String: Any] = [
            "text": ["type": "STRING"],
            "language": ["type": "STRING"],
        ]
        var required = ["text", "language"]
        if let target {
            instructions += " In \"translation\", translate the transcribed text into \(target.englishName), keeping the same line breaks. If the text is already in \(target.englishName), repeat it."
            properties["translation"] = ["type": "STRING"]
            required.append("translation")
        }
        let schema: [String: Any] = ["type": "OBJECT", "properties": properties, "required": required]
        guard let imagePart = imagePart(image) else { throw GeminiError.badResponse }
        return try await generate(parts: [imagePart, ["text": instructions]], schema: schema, as: Recognition.self)
    }

    /// Translates plain text.
    static func translate(_ text: String, to target: OCRTranslationLanguage) async throws -> String {
        struct Answer: Decodable { let translation: String }
        let prompt = """
        Translate the following text into \(target.englishName). Keep line breaks, numbers, names, URLs and code as they are. \
        Return only the translation.

        \(text)
        """
        let schema: [String: Any] = [
            "type": "OBJECT",
            "properties": ["translation": ["type": "STRING"]],
            "required": ["translation"],
        ]
        return try await generate(parts: [["text": prompt]], schema: schema, as: Answer.self).translation
    }

    struct SensitiveFinding: Decodable, Sendable {
        let line: Int
        let value: String
        let kind: String?
    }

    /// Which of these recognised lines contain personal or secret data. Only the text is sent.
    static func findSensitive(in lines: [String]) async throws -> [SensitiveFinding] {
        struct Answer: Decodable { let findings: [SensitiveFinding] }
        let numbered = lines.enumerated().map { "\($0.offset): \($0.element)" }.joined(separator: "\n")
        let prompt = """
        These numbered lines were read from a screenshot. Find every value that should be hidden before the \
        screenshot is shared: email addresses, phone numbers, street addresses, full names of private people, \
        bank account and card numbers, ID or passport numbers, passwords, one-time codes, API keys, tokens, \
        secrets, private URLs with tokens, IP addresses, license keys, and amounts on personal financial documents. \
        Do not include labels (such as "Email:"), product names, public company names, or UI text. \
        For each value give the line number and the exact characters of the value as they appear in that line.

        \(numbered)
        """
        let schema: [String: Any] = [
            "type": "OBJECT",
            "properties": [
                "findings": [
                    "type": "ARRAY",
                    "items": [
                        "type": "OBJECT",
                        "properties": [
                            "line": ["type": "INTEGER"],
                            "value": ["type": "STRING"],
                            "kind": ["type": "STRING"],
                        ],
                        "required": ["line", "value"],
                    ],
                ],
            ],
            "required": ["findings"],
        ]
        return try await generate(parts: [["text": prompt]], schema: schema, as: Answer.self).findings
    }

    /// Translates each line in context, returning exactly one translation per line.
    static func translateLines(_ lines: [String], to target: OCRTranslationLanguage, image: CGImage?) async throws -> [String] {
        struct Answer: Decodable { let translations: [String] }
        let numbered = lines.enumerated().map { "\($0.offset): \($0.element)" }.joined(separator: "\n")
        let prompt = """
        These numbered lines were read from the attached screenshot, top to bottom. Translate each line into \
        \(target.englishName), using the surrounding lines and the screenshot for context so sentences that wrap \
        across lines read naturally. Return exactly \(lines.count) translations in the same order, one per line, \
        each short enough to fit where the original line was. Keep numbers, names, URLs, code and prices as they are; \
        if a line needs no translation, repeat it unchanged. Do not number the translations.

        \(numbered)
        """
        let schema: [String: Any] = [
            "type": "OBJECT",
            "properties": ["translations": ["type": "ARRAY", "items": ["type": "STRING"]]],
            "required": ["translations"],
        ]
        var parts: [[String: Any]] = []
        if let image, let part = imagePart(image) { parts.append(part) }
        parts.append(["text": prompt])
        let answer = try await generate(parts: parts, schema: schema, as: Answer.self)
        guard answer.translations.count == lines.count else {
            // Pad or trim rather than fail; a missing line keeps its original text.
            return lines.indices.map { $0 < answer.translations.count ? answer.translations[$0] : lines[$0] }
        }
        return answer.translations
    }

    /// A tiny request that confirms the key and model work.
    static func test(key: String, model: String) async throws {
        struct Answer: Decodable { let ok: Bool }
        let schema: [String: Any] = ["type": "OBJECT", "properties": ["ok": ["type": "BOOLEAN"]], "required": ["ok"]]
        _ = try await generate(parts: [["text": "Reply with ok = true."]], schema: schema, as: Answer.self, key: key, model: model)
    }

    // MARK: - Request

    private static func generate<T: Decodable>(
        parts: [[String: Any]],
        schema: [String: Any],
        as type: T.Type,
        key: String? = nil,
        model: String? = nil
    ) async throws -> T {
        guard let key = key ?? GeminiKey.current else { throw GeminiError.noKey }
        let modelName = (model ?? self.model).addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? defaultModel
        guard let url = URL(string: "https://generativelanguage.googleapis.com/v1beta/models/\(modelName):generateContent") else {
            throw GeminiError.badResponse
        }
        let body: [String: Any] = [
            "contents": [["role": "user", "parts": parts]],
            "generationConfig": [
                "temperature": 0,
                "responseMimeType": "application/json",
                "responseSchema": schema,
            ],
        ]
        var request = URLRequest(url: url, timeoutInterval: 60)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(key, forHTTPHeaderField: "x-goog-api-key")
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await URLSession.shared.data(for: request)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard status == 200 else { throw error(status: status, data: data) }

        let envelope = try JSONDecoder().decode(Envelope.self, from: data)
        if envelope.promptFeedback?.blockReason != nil { throw GeminiError.blocked }
        guard let candidate = envelope.candidates?.first else { throw GeminiError.blocked }
        let text = candidate.content?.parts?.compactMap(\.text).joined() ?? ""
        guard !text.isEmpty else {
            throw candidate.finishReason == "SAFETY" ? GeminiError.blocked : GeminiError.badResponse
        }
        do {
            return try JSONDecoder().decode(T.self, from: Data(text.utf8))
        } catch {
            throw GeminiError.badResponse
        }
    }

    private struct Envelope: Decodable {
        struct Candidate: Decodable {
            struct Content: Decodable {
                struct Part: Decodable { let text: String? }
                let parts: [Part]?
            }
            let content: Content?
            let finishReason: String?
        }
        struct Feedback: Decodable { let blockReason: String? }
        let candidates: [Candidate]?
        let promptFeedback: Feedback?
    }

    private static func error(status: Int, data: Data) -> GeminiError {
        struct Body: Decodable {
            struct Inner: Decodable { let message: String?; let status: String? }
            let error: Inner?
        }
        let body = try? JSONDecoder().decode(Body.self, from: data)
        let message = body?.error?.message ?? ""
        switch status {
        case 400 where message.localizedCaseInsensitiveContains("API key"), 401, 403:
            return .invalidKey
        case 429:
            return .quota
        default:
            return .server(message.isEmpty ? "Gemini request failed (HTTP \(status))." : "Gemini: \(message)")
        }
    }

    /// The image as an inline part, scaled down so its longest side is at most 3072 pixels.
    private static func imagePart(_ image: CGImage) -> [String: Any]? {
        let longest = max(image.width, image.height)
        var source = image
        if longest > 3072 {
            let scale = 3072 / CGFloat(longest)
            let width = Int(CGFloat(image.width) * scale), height = Int(CGFloat(image.height) * scale)
            guard let space = CGColorSpace(name: CGColorSpace.sRGB),
                  let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                                          space: space, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
            context.interpolationQuality = .high
            context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
            guard let scaled = context.makeImage() else { return nil }
            source = scaled
        }
        guard let png = NSBitmapImageRep(cgImage: source).representation(using: .png, properties: [:]) else { return nil }
        return ["inline_data": ["mime_type": "image/png", "data": png.base64EncodedString()]]
    }
}
