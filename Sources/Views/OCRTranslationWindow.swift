import AppKit
import SwiftUI
@preconcurrency import Translation

@MainActor
final class OCRTranslationWindow {
    static let shared = OCRTranslationWindow()

    private var panel: NSPanel?

    private init() {}

    func show(originalText: String, on preferredScreen: NSScreen? = nil) {
        if #available(macOS 15.0, *) {
            showTranslationPanel(originalText: originalText, on: preferredScreen)
        } else {
            ToastWindow.shared.show(
                title: "Text copied",
                message: "Translation requires macOS 15 or later.",
                systemIcon: "character.book.closed",
                on: preferredScreen
            )
        }
    }

    func dismiss() {
        panel?.orderOut(nil)
        panel = nil
    }

    @available(macOS 15.0, *)
    private func showTranslationPanel(originalText: String, on preferredScreen: NSScreen?) {
        dismiss()

        let content = OCRTranslationResultView(
            originalText: originalText,
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

    init(originalText: String, onClose: @escaping () -> Void) {
        _sourceText = State(initialValue: originalText)
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
                        Text("Original")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(.secondary)
                        Spacer()
                        Button {
                            copyOriginalText()
                        } label: {
                            Label("Copy original", systemImage: "doc.on.doc")
                        }
                        .controlSize(.small)
                        .disabled(sourceText.isEmpty)
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
                errorMessage = nil
                AnalyticsService.track(.translationCompleted, properties: ["target_language": targetLanguage.rawValue])
            } catch {
                guard requestedText == textToTranslate else { return }
                translatedText = ""
                errorMessage = error.localizedDescription
            }
            isTranslating = false
        }
        .task(id: sourceText) {
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



    private func requestTranslation() {
        guard !sourceText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            configuration = nil
            textToTranslate = ""
            translatedText = ""
            errorMessage = nil
            isTranslating = false
            return
        }

        textToTranslate = sourceText
        translatedText = ""
        errorMessage = nil
        isTranslating = true
        configuration = TranslationSession.Configuration(
            source: nil,
            target: targetLanguage.localeLanguage
        )
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
