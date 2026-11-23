import AppKit

/// AI actions in the editor. Each one runs only when the user picks it.
extension EditorModel {
    /// Finds sensitive text and covers it with blurs the user can adjust or delete. Patterns are
    /// matched on this Mac; with a Gemini key (and the option on), the recognised text is also
    /// checked by Gemini. Returns a message for the user.
    func redactSensitiveInfo() async -> AIActionOutcome {
        guard collageState == nil, let image = sourceImage else { return .failure("Open a screenshot first.") }
        let url = sourceURL
        let usesAI = AppPreferences.aiRedactionEnabled && GeminiService.isAvailable
        let detection = await SmartBlurDetector.detect(in: image, useAI: usesAI)
        guard sourceURL == url else { return .failure("The image changed.") }

        let existing = items.filter { $0.tool == .blur || $0.tool == .pixelate }.map(\.bounds)
        let fresh = detection.rects.filter { rect in
            !existing.contains { SmartBlurDetector.overlapRatio($0, rect) > 0.6 }
        }
        if !fresh.isEmpty {
            history.push(items)
            let added = fresh.map {
                AnnotationItem(tool: .blur, rect: $0, swatch: .black, strokeWidth: 2, redactionDensity: max(redactionDensity, 0.55))
            }
            items.append(contentsOf: added)
            selectedItemIDs = Set(added.map(\.id))
        }

        if let error = detection.aiError {
            return fresh.isEmpty
                ? .failure(error)
                : .success("Blurred \(fresh.count) on-device match\(fresh.count == 1 ? "" : "es"). \(error)")
        }
        if fresh.isEmpty {
            return .success(detection.rects.isEmpty ? "No sensitive info found." : "Everything found is already blurred.")
        }
        return .success("Blurred \(fresh.count) item\(fresh.count == 1 ? "" : "s"). Delete any you want to keep visible.")
    }

    /// Translates the text in the image in place: each line gets a cover in its background colour
    /// and the translation as a text annotation, all editable and undoable as one step.
    func translateImage(to target: OCRTranslationLanguage) async -> AIActionOutcome {
        guard collageState == nil, let image = sourceImage else { return .failure("Open a screenshot first.") }
        guard GeminiService.isAvailable else { return .failure(GeminiError.noKey.localizedDescription) }
        let url = sourceURL
        let lines: [ImageTranslator.Line]
        do {
            lines = try await ImageTranslator.translate(image, to: target)
        } catch {
            return .failure(error.localizedDescription)
        }
        guard sourceURL == url, sourceImage === image else { return .failure("The image changed.") }
        guard !lines.isEmpty else { return .failure("Nothing to translate.") }

        let width = CGFloat(image.width), height = CGFloat(image.height)
        var added: [AnnotationItem] = []
        for line in lines {
            let pad = line.box.height * 0.14
            let cover = line.box.insetBy(dx: -pad * height / width, dy: -pad)
            added.append(AnnotationItem(tool: .filledRectangle, rect: cover, swatch: line.background, strokeWidth: 0))

            let font = AnnotationTextMetrics.resolvedFont(name: AnnotationTextMetrics.defaultFontName, size: line.fontPixelSize, bold: line.isBold, italic: false)
            let textWidth = ImageTranslator.textWidth(line.text, size: line.fontPixelSize, bold: line.isBold) + 2
            let lineHeight = ceil(font.ascender - font.descender + font.leading)
            let textRect = CGRect(
                x: line.isCentered ? line.box.midX - textWidth / 2 / width : line.box.minX,
                y: line.box.midY - lineHeight / 2 / height,
                width: textWidth / width,
                height: lineHeight / height
            )
            added.append(AnnotationItem(
                tool: .text,
                rect: textRect,
                swatch: line.foreground,
                strokeWidth: 0,
                text: line.text,
                textLineHeight: line.fontPixelSize / AnnotationTextMetrics.fontScale / height,
                isBold: line.isBold,
                textHasShadow: false
            ))
        }
        history.push(items)
        items.append(contentsOf: added)
        selectedItemIDs = []
        return .success("Translated \(lines.count) line\(lines.count == 1 ? "" : "s") into \(target.label). Undo to remove.")
    }
}

enum AIActionOutcome {
    case success(String)
    case failure(String)
}
