import AppKit
import SwiftUI

/// Coordinates the full capture pipeline: hide window -> capture -> sound -> preview/editor.
@MainActor
@Observable
final class CaptureOrchestrator {
    static let shared = CaptureOrchestrator()

    private(set) var lastCaptureURL: URL?
    private var captureInProgress = false
    private var pendingCapture: (ShortcutService.Action, NSScreen?)?
    private var captureScreen: NSScreen?

    private init() {}

    func performCapture(_ action: ShortcutService.Action, on screen: NSScreen? = nil) async {
        if captureInProgress {
            // Keep only the latest intent. Repeated clicks while an overlay is active
            // must not produce a burst of stale capture windows later.
            pendingCapture = (action, screen)
            return
        }
        captureInProgress = true
        captureScreen = screen
        await executeCapture(action)
        while let (next, nextScreen) = pendingCapture {
            pendingCapture = nil
            captureScreen = nextScreen
            await executeCapture(next)
        }
        captureScreen = nil
        captureInProgress = false
    }

    private func executeCapture(_ action: ShortcutService.Action) async {
        switch action {
        case .region:
            AnalyticsService.track(.captureRegion)
            await captureAndProcess { try await ScreenCapture.shared.captureRegion() }
        case .fullscreen:
            AnalyticsService.track(.captureFullscreen)
            await captureAndProcess { try await ScreenCapture.shared.captureFullscreen(on: captureScreen) }
        case .window:
            AnalyticsService.track(.captureWindow)
            await captureAndProcess { try await ScreenCapture.shared.captureWindow() }
        case .ocr:
            await performOCR()
        case .colorPicker:
            AnalyticsService.track(.colorPickerUsed)
            await performColorPick()
        case .recording:
            break
        }
    }

    // MARK: - Private

    private func captureAndProcess(_ capture: () async throws -> URL?) async {
        let delay = AppPreferences.selfTimerDelay
        if delay != .off {
            await CountdownOverlay.shared.showCountdown(seconds: delay.rawValue)
        }

        let metadata = CaptureMetadata.capture()

        do {
            guard let url = try await capture() else { return }

            ScreenCapture.shared.playShutterSound()

            let automaticallySaves = AppPreferences.autoSaveCaptures
            let record = automaticallySaves
                ? HistoryStore.shared.importCapture(from: url, metadata: metadata)
                : nil
            let capturedURL: URL
            if let record {
                capturedURL = HistoryStore.shared.urlForRecord(record)
                lastCaptureURL = capturedURL
            } else {
                capturedURL = url
                lastCaptureURL = url
            }

            let targetScreen = captureScreen
            Task { @MainActor [weak self] in
                guard let self else { return }
                await self.galleryApplyAndSave(
                    capturedURL,
                    recordID: record?.id,
                    metadata: metadata,
                    on: targetScreen
                )
            }
        } catch {
            print("Capture failed: \(error.localizedDescription)")
            ToastWindow.shared.show(
                title: "Capture failed",
                message: error.localizedDescription,
                systemIcon: "exclamationmark.triangle",
                on: captureScreen
            )
        }
    }


    private func performColorPick() async {
        let overlay = ColorPickerOverlay()
        guard let hex = await overlay.pickColor() else { return }
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(hex, forType: .string)
        ScreenCapture.shared.playShutterSound()
        ToastWindow.shared.show(
            title: "Copied",
            message: "\(hex) copied to clipboard",
            systemIcon: "eyedropper",
            on: captureScreen
        )
    }

    private func performOCR() async {
        do {
            guard let text = try await ScreenCapture.shared.captureAndOCR(),
                  !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
            let pasteboard = NSPasteboard.general
            pasteboard.clearContents()
            pasteboard.setString(text, forType: .string)
            AnalyticsService.track(.ocrCompleted)
            ScreenCapture.shared.playShutterSound()
            if AppPreferences.ocrTranslationEnabled {
                OCRTranslationWindow.shared.show(originalText: text, on: captureScreen)
            } else {
                OCRTranslationWindow.shared.dismiss()
                ToastWindow.shared.show(
                    title: "OCR copied",
                    message: "Recognized text copied to clipboard",
                    systemIcon: "doc.on.clipboard",
                    on: captureScreen
                )
            }
        } catch {
            print("OCR failed: \(error.localizedDescription)")
        }
    }

    private func galleryApplyAndSave(
        _ url: URL,
        recordID: UUID? = nil,
        metadata: CaptureMetadata? = nil,
        on targetScreen: NSScreen? = nil
    ) async {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let cgImage = CGImageSourceCreateImageAtIndex(source, 0, nil) else { return }

        let config = AppPreferences.defaultBeautifierConfig
        let showMeta = AppPreferences.showMetadata
        let activePresetID = AppPreferences.lastWatermarkPresetID
        let activePreset = WatermarkStore.shared.presets.first(where: { $0.id.uuidString == activePresetID })

        var annotations: [AnnotationItem] = []
        if AppPreferences.smartBlurEnabled {
            let rects = await SmartBlurDetector.detectSensitiveRects(in: cgImage)
            for rect in rects {
                annotations.append(AnnotationItem(
                    tool: .blur,
                    rect: rect,
                    swatch: .black,
                    strokeWidth: 2.0,
                    redactionDensity: 0.55
                ))
            }
        }

        let automaticallySaves = AppPreferences.autoSaveCaptures
        let destination = automaticallySaves ? savedImageURL() : temporaryImageURL()
        let format = AppPreferences.exportFormat
        let quality = AppPreferences.exportQuality

        // Rendering the backdrop and encoding the file take long enough on a Retina
        // capture to freeze the UI right after the selection, so do both off the main actor.
        let job = UncheckedSendable((cgImage, config, annotations, metadata, showMeta, activePreset))
        let result = await Task.detached(priority: .userInitiated) { () -> UncheckedSendable<(CGImage, URL?)>? in
            let (image, config, annotations, metadata, showMeta, preset) = job.value
            guard let rendered = BeautifierRenderer.render(
                image: image,
                config: config,
                annotations: annotations,
                metadata: metadata,
                showMetadata: showMeta,
                watermarkPreset: preset
            ) else { return nil }
            let written = Self.writeImage(rendered, to: destination, format: format, quality: quality)
            return UncheckedSendable((rendered, written))
        }.value

        guard let (rendered, outputURL) = result?.value else { return }

        if automaticallySaves, let outputURL {
            saveBaseImage(rawURL: url, alongside: outputURL)

            if let recordID {
                HistoryStore.shared.setBeautifiedPath(outputURL.path, for: recordID)
            }
        }

        if outputURL != nil,
           !automaticallySaves || AppPreferences.copyAfterSave {
            copyToClipboard(rendered)
        }

        let displayURL = outputURL ?? url

        if outputURL != nil {
            let appIcon = NSImage(named: "AppIcon") ?? NSApp.applicationIconImage
            if automaticallySaves {
                ToastWindow.shared.show(
                    message: AppPreferences.copyAfterSave ? "Screenshot saved & copied!" : "Screenshot saved!",
                    icon: appIcon,
                    duration: 1.6,
                    on: targetScreen
                )
            } else {
                ToastWindow.shared.show(
                    title: "Copied",
                    message: "Screenshot copied to clipboard",
                    icon: appIcon,
                    duration: 1.6,
                    on: targetScreen
                )
            }
        }

        PreviewOverlay.shared.show(url: displayURL, on: targetScreen)

        if !automaticallySaves, outputURL != nil, url != outputURL {
            try? FileManager.default.removeItem(at: url)
        }
    }

    private func savedImageURL() -> URL {
        let dir = AppPreferences.saveDirectory
        let stamp = Int(Date().timeIntervalSince1970 * 1000)
        let ext = AppPreferences.exportFormat.fileExtension
        return URL(fileURLWithPath: "\(dir)/shotly_\(stamp).\(ext)")
    }

    private func temporaryImageURL() -> URL {
        let stamp = Int(Date().timeIntervalSince1970 * 1000)
        let ext = AppPreferences.exportFormat.fileExtension
        return FileManager.default.temporaryDirectory
            .appendingPathComponent("shotly_\(stamp)_\(UUID().uuidString.prefix(6)).\(ext)")
    }

    private nonisolated static func writeImage(
        _ cgImage: CGImage,
        to url: URL,
        format: ExportFormat,
        quality: Double
    ) -> URL? {
        guard let destination = CGImageDestinationCreateWithURL(
            url as CFURL,
            format.utType as CFString,
            1, nil
        ) else { return nil }

        var options: [CFString: Any] = [:]
        if format == .jpeg {
            options[kCGImageDestinationLossyCompressionQuality] = quality
        }

        CGImageDestinationAddImage(destination, cgImage, options as CFDictionary)

        guard CGImageDestinationFinalize(destination) else { return nil }
        return url
    }

    private func saveBaseImage(rawURL: URL, alongside beautifiedURL: URL) {
        let baseURL = Self.baseImageURL(for: beautifiedURL)
        try? FileManager.default.copyItem(at: rawURL, to: baseURL)
    }

    private static var baseStorageDir: URL {
        let dir = AppPaths.supportDirectory.appendingPathComponent("bases", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    static func baseImageURL(for url: URL) -> URL {
        let name = url.deletingPathExtension().lastPathComponent
        return baseStorageDir.appendingPathComponent("\(name).base.png")
    }

    static func resolveRawSource(for url: URL) -> URL {
        let baseURL = baseImageURL(for: url)
        if FileManager.default.fileExists(atPath: baseURL.path) {
            return baseURL
        }
        // Legacy: check alongside the file for old .base.png files
        let legacyDir = url.deletingLastPathComponent()
        let legacyName = url.deletingPathExtension().lastPathComponent
        let legacyURL = legacyDir.appendingPathComponent("\(legacyName).base.png")
        if FileManager.default.fileExists(atPath: legacyURL.path) {
            return legacyURL
        }
        return url
    }

    private func copyToClipboard(_ cgImage: CGImage) {
        let nsImage = NSImage(cgImage: cgImage, size: NSSize(width: cgImage.width, height: cgImage.height))
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.writeObjects([nsImage])
    }
}
