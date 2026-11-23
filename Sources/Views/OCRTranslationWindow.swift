import AppKit
import SwiftUI
@preconcurrency import Translation

@MainActor
final class OCRTranslationWindow {
    static let shared = OCRTranslationWindow()

    private var panel: NSPanel?
    /// The open translation panel, for the UI export.
    var openPanel: NSPanel? { panel }

    private init() {}

    func show(originalText: String, on preferredScreen: NSScreen? = nil) {
        if #available(macOS 15.0, *) {
            showTranslationPanel(originalText: originalText, image: nil, on: preferredScreen)
        } else {
            ToastWindow.shared.show(
                title: "Text copied",
                message: "Translation requires macOS 15 or later.",
                systemIcon: "character.book.closed",
                on: preferredScreen
            )
        }
    }

    /// Reads the text with Gemini, then shows it with its translation. The text is copied to the
    /// clipboard once it is read; if Gemini fails, on-device OCR and Apple Translation take over.
    func show(image: CGImage, on preferredScreen: NSScreen? = nil) {
        if #available(macOS 15.0, *) {
            showTranslationPanel(originalText: "", image: image, on: preferredScreen)
        }
    }

    func dismiss() {
        panel?.orderOut(nil)
        panel = nil
    }

    @available(macOS 15.0, *)
    private func showTranslationPanel(originalText: String, image: CGImage?, on preferredScreen: NSScreen?) {
        dismiss()

        let content = OCRTranslationResultView(
            originalText: originalText,
            image: image,
            onClose: { OCRTranslationWindow.shared.dismiss() }
        )
        let hostingView = NSHostingView(rootView: content)
        let panelSize = NSSize(width: 720, height: 390)
        hostingView.frame = NSRect(origin: .zero, size: panelSize)

        let panel = NSPanel(
            contentRect: NSRect(origin: .zero, size: panelSize),
            styleMask: [.titled, .closable, .resizable, .utilityWindow, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        panel.title = "OCR Translation"
        panel.titleVisibility = .hidden
        panel.titlebarAppearsTransparent = true
        panel.isFloatingPanel = true
        panel.level = .floating
        panel.hidesOnDeactivate = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.minSize = NSSize(width: 620, height: 330)
        panel.contentView = hostingView
        panel.isReleasedWhenClosed = false

        guard let screen = preferredScreen ?? NSScreen.main ?? NSScreen.screens.first else { return }
        let visibleFrame = screen.visibleFrame
        panel.setFrameOrigin(NSPoint(
            x: visibleFrame.maxX - panelSize.width - 18,
            y: visibleFrame.maxY - panelSize.height - 18
        ))

        self.panel = panel
        panel.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
}

@available(macOS 15.0, *)
private struct OCRTranslationResultView: View {
    let onClose: () -> Void

    @AppStorage("bs_ocrTranslationTargetLanguage") private var targetLanguageRaw = OCRTranslationLanguage.vietnamese.rawValue
    @State private var sourceText: String
    @State private var textToTranslate = ""
    @State private var configuration: TranslationSession.Configuration?
    @State private var translatedText = ""
    @State private var errorMessage: String?
    @State private var isTranslating = true
    /// Gemini handles reading and translating; off, or after Gemini fails, on-device Vision and Apple Translation do.
    @State private var usesGemini: Bool
    @State private var isRecognizing: Bool
    @State private var detectedLanguage: String?
    @State private var notice: String?
    /// The text and language of the translation on screen, so the same pair is not translated twice.
    @State private var translatedPair: (String, String)?
    @State private var geminiTask: Task<Void, Never>?
    private let image: CGImage?

    init(originalText: String, image: CGImage?, onClose: @escaping () -> Void) {
        _sourceText = State(initialValue: originalText)
        self.image = image
        _usesGemini = State(initialValue: image != nil || (AppPreferences.aiOCREnabled && GeminiService.isAvailable))
        _isRecognizing = State(initialValue: image != nil)
        self.onClose = onClose
    }

    private var targetLanguage: OCRTranslationLanguage {
        OCRTranslationLanguage(rawValue: targetLanguageRaw) ?? .vietnamese
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                Image(systemName: "character.book.closed")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(.tint)

                Text("OCR Translation")
                    .font(.system(size: 15, weight: .semibold))

                if usesGemini {
                    Label("Gemini", systemImage: "sparkles")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.secondary)
                        .help("Read and translated with Gemini (Settings → AI)")
                }

                Spacer()

                Picker("Translate to", selection: $targetLanguageRaw) {
                    ForEach(OCRTranslationLanguage.allCases) { language in
                        Text(language.label).tag(language.rawValue)
                    }
                }
                .labelsHidden()
                .frame(width: 185)

                Button(action: onClose) {
                    Image(systemName: "xmark")
                        .frame(width: 22, height: 22)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Close OCR translation")
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 14)

            Divider()

            HStack(spacing: 0) {
                VStack(alignment: .leading, spacing: 10) {
                    HStack {
                        Text(detectedLanguage.map { "Original · \($0)" } ?? "Original")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                        Spacer()
                        Button {
                            copyOriginalText()
                        } label: {
                            Label("Copy original", systemImage: "doc.on.doc")
                        }
                        .controlSize(.small)
                        .disabled(sourceText.isEmpty || isRecognizing)
                    }

                    TextEditor(text: $sourceText)
                        .font(.system(size: 13))
                        .scrollContentBackground(.hidden)
                        .padding(8)
                        .background(Color.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 8))
                        .overlay {
                            RoundedRectangle(cornerRadius: 8)
                                .strokeBorder(Color.primary.opacity(0.09), lineWidth: 1)
                        }
                        .disabled(isRecognizing)
                        .overlay {
                            if isRecognizing {
                                VStack(spacing: 10) {
                                    ProgressView()
                                    Text("Reading text…")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }

                    if let notice {
                        Label(notice, systemImage: "exclamationmark.triangle")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                    }
                }
                .padding(16)
                .frame(maxWidth: .infinity, maxHeight: .infinity)

                Divider()

                VStack(alignment: .leading, spacing: 10) {
                    HStack {
                        Text(targetLanguage.label)
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(.secondary)
                        Spacer()
                        Button {
                            copyTranslatedText()
                        } label: {
                            Label("Copy translation", systemImage: "doc.on.doc")
                        }
                        .controlSize(.small)
                        .disabled(translatedText.isEmpty || isTranslating)
                    }

                    ZStack {
                        TextEditor(text: $translatedText)
                            .font(.system(size: 13))
                            .scrollContentBackground(.hidden)
                            .padding(8)
                            .background(Color.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 8))
                            .overlay {
                                RoundedRectangle(cornerRadius: 8)
                                    .strokeBorder(Color.primary.opacity(0.09), lineWidth: 1)
                            }
                            .disabled(isTranslating || errorMessage != nil)

                        if isTranslating {
                            VStack(spacing: 10) {
                                ProgressView()
                                Text("Translating…")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                        } else if let errorMessage {
                            ContentUnavailableView(
                                "Translation unavailable",
                                systemImage: "exclamationmark.triangle",
                                description: Text(errorMessage)
                            )
                        }
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
                .padding(16)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .frame(minWidth: 620, minHeight: 330)
        .background(.regularMaterial)
        .translationTask(configuration) { session in
            let requestedText = textToTranslate
            do {
                let response = try await session.translate(requestedText)
                guard requestedText == textToTranslate else { return }
                translatedText = response.targetText
                translatedPair = (requestedText, targetLanguage.rawValue)
                errorMessage = nil
                AnalyticsService.track(.translationCompleted, properties: ["target_language": targetLanguage.rawValue])
            } catch {
                guard requestedText == textToTranslate else { return }
                translatedText = ""
                errorMessage = error.localizedDescription
            }
            isTranslating = false
        }
        .task {
            await recognizeImage()
        }
        .task(id: sourceText) {
            guard !isRecognizing else { return }
            do {
                try await Task.sleep(for: .milliseconds(450))
            } catch {
                return
            }
            requestTranslation()
        }
        .onChange(of: targetLanguageRaw) { _, _ in
            requestTranslation()
        }
    }

    /// Reads the captured image with Gemini, translating in the same request.
    private func recognizeImage() async {
        guard let image, isRecognizing else { return }
        let target = targetLanguage
        do {
            let result = try await GeminiService.recognize(image, translatingTo: target)
            let text = result.text.trimmingCharacters(in: .whitespacesAndNewlines)
            detectedLanguage = result.language.flatMap { $0.isEmpty ? nil : $0 }
            if let translation = result.translation, target == targetLanguage {
                translatedText = translation.trimmingCharacters(in: .whitespacesAndNewlines)
                translatedPair = (text, target.rawValue)
                isTranslating = false
                errorMessage = nil
                AnalyticsService.track(.translationCompleted, properties: ["target_language": target.rawValue])
            }
            sourceText = text
            isRecognizing = false
            if text.isEmpty {
                notice = "No text found in the selection."
                isTranslating = false
            } else {
                copyToClipboard(text)
                if translatedPair?.1 != targetLanguage.rawValue { requestTranslation() }
            }
        } catch {
            // Fall back to on-device recognition and translation.
            notice = "\(error.localizedDescription) Used on-device OCR instead."
            usesGemini = false
            detectedLanguage = nil
            let text = (try? await ScreenCapture.shared.recognizeContent(in: image)) ?? ""
            sourceText = text
            isRecognizing = false
            if !text.isEmpty { copyToClipboard(text) }
            requestTranslation()
        }
    }

    private func requestTranslation() {
        guard !sourceText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            configuration = nil
            textToTranslate = ""
            translatedText = ""
            errorMessage = nil
            isTranslating = false
            return
        }

        if let translatedPair, translatedPair.0 == sourceText, translatedPair.1 == targetLanguage.rawValue {
            isTranslating = false
            return
        }

        textToTranslate = sourceText
        translatedText = ""
        errorMessage = nil
        isTranslating = true

        guard usesGemini else {
            configuration = TranslationSession.Configuration(
                source: nil,
                target: targetLanguage.localeLanguage
            )
            return
        }
        geminiTask?.cancel()
        let requestedText = sourceText
        let target = targetLanguage
        geminiTask = Task {
            do {
                let translation = try await GeminiService.translate(requestedText, to: target)
                guard !Task.isCancelled, requestedText == textToTranslate, target == targetLanguage else { return }
                translatedText = translation.trimmingCharacters(in: .whitespacesAndNewlines)
                translatedPair = (requestedText, target.rawValue)
                errorMessage = nil
                AnalyticsService.track(.translationCompleted, properties: ["target_language": target.rawValue])
            } catch {
                guard !Task.isCancelled, requestedText == textToTranslate else { return }
                translatedText = ""
                errorMessage = error.localizedDescription
            }
            isTranslating = false
        }
    }

    private func copyToClipboard(_ text: String) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
    }

    private func copyOriginalText() {
        guard !sourceText.isEmpty else { return }
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(sourceText, forType: .string)
    }

    private func copyTranslatedText() {
        guard !translatedText.isEmpty else { return }
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(translatedText, forType: .string)
        AnalyticsService.track(.translationCopied, properties: ["target_language": targetLanguage.rawValue])
    }
}
