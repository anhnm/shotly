import AppKit
import Vision
import CoreGraphics
import ScreenCaptureKit
import OSLog

/// Capture timings. View with:
/// `log stream --predicate 'subsystem == "com.shotly.app" && category == "capture"'`
private let captureLog = Logger(subsystem: "com.shotly.app", category: "capture")

@MainActor
@Observable
final class ScreenCapture {
    static let shared = ScreenCapture()

    private(set) var isCapturing = false

    private init() {}

    private struct FrozenSnapshot: @unchecked Sendable {
        let displayID: CGDirectDisplayID
        let screen: NSScreen
        let displayFrame: CGRect
        let image: CGImage
    }

    private struct FrozenDisplayRequest: Sendable {
        let displayID: CGDirectDisplayID
        let displayFrame: CGRect
    }

    private struct CapturedDisplay: @unchecked Sendable {
        let displayID: CGDirectDisplayID
        let image: CGImage
    }

    private struct FrozenContent {
        let snapshots: [FrozenSnapshot]
        let windows: [FrozenWindowInfo]
    }

    private struct FrozenWindowInfo: Sendable {
        let frame: CGRect
        let layer: Int
        let isOnScreen: Bool
        let ownerPID: pid_t
    }

    // MARK: - Fullscreen 

    func captureFullscreen(on screen: NSScreen? = nil) async throws -> URL? {
        guard !isCapturing else { return nil }
        isCapturing = true
        defer { isCapturing = false }

        let targetScreen = screen ?? NSScreen.main ?? NSScreen.screens.first
        guard let targetScreen else { return nil }
        let content = try await captureFrozenContent(for: [targetScreen])
        guard let snapshot = content.snapshots.first else { return nil }
        return await writeTemporaryPNG(snapshot.image)
    }

    // MARK: - Region

    func captureRegion() async throws -> URL? {
        guard !isCapturing else { return nil }
        isCapturing = true
        defer { isCapturing = false }

        // Remember a mouse press made while the screen is being frozen, so the
        // overlay can start the selection from there instead of losing the drag.
        let earlyPress = EarlyMouseDownRecorder()
        let started = ContinuousClock.now
        // Region selection does not use window metadata, so skip collecting it.
        let content = try await captureFrozenContent(for: NSScreen.screens)
        let images = Dictionary(uniqueKeysWithValues: content.snapshots.map { ($0.displayID, $0.image) })
        let overlay = RegionSelectionOverlay(frozenImages: images, earlyMouseDown: earlyPress.stop())
        captureLog.notice("Region overlay ready after \(started.duration(to: .now).milliseconds, privacy: .public) ms")
        guard let selection = await overlay.selectRegion(),
              let snapshot = content.snapshots.first(where: { $0.displayID == selection.displayID }),
              let cropped = crop(snapshot.image, to: selection.localRect, on: snapshot.screen) else {
            return nil
        }
        return await writeTemporaryPNG(cropped)
    }

    // MARK: - Window (CLI screencapture -w)

    func captureWindow(includeShadow: Bool = false) async throws -> URL? {
        guard !isCapturing else { return nil }
        isCapturing = true
        defer { isCapturing = false }

        // Window selection needs the WindowServer metadata as well as the frozen
        // display images. Without includeWindows the overlay has no hit regions,
        // so it can only show its dark backdrop and every click is ignored.
        let content = try await captureFrozenContent(for: NSScreen.screens, includeWindows: true)
        let images = Dictionary(uniqueKeysWithValues: content.snapshots.map { ($0.displayID, $0.image) })
        let regions = frozenWindowRegions(from: content)
        guard !regions.isEmpty else {
            throw NSError(
                domain: "Shotly.ScreenCapture",
                code: 2,
                userInfo: [NSLocalizedDescriptionKey: "No selectable windows are currently visible"]
            )
        }
        let overlay = WindowSelectionOverlay(frozenImages: images, regions: regions)
        guard let selection = await overlay.selectWindow(),
              let snapshot = content.snapshots.first(where: { $0.displayID == selection.displayID }),
              let cropped = crop(snapshot.image, to: selection.localRect, on: snapshot.screen) else {
            return nil
        }
        return await writeTemporaryPNG(cropped)
    }

    // MARK: - OCR Region

    func captureAndOCR() async throws -> String? {
        guard let url = try await captureRegion() else { return nil }
        defer { try? FileManager.default.removeItem(at: url) }

        guard let image = NSImage(contentsOf: url),
              let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
            return nil
        }

        return try await recognizeContent(in: cgImage)
    }

    /// Text (and QR/barcode payloads) found in `image`.
    func recognizeContent(in image: CGImage) async throws -> String {
        let started = ContinuousClock.now
        let text = try await Task.detached(priority: .userInitiated) {
            let textRequest = VNRecognizeTextRequest()
            textRequest.recognitionLevel = .accurate
            textRequest.usesLanguageCorrection = false
            textRequest.automaticallyDetectsLanguage = true

            let barcodeRequest = VNDetectBarcodesRequest()

            let handler = VNImageRequestHandler(cgImage: image)
            try handler.perform([textRequest, barcodeRequest])

            var parts: [String] = []

            // QR/Barcode results first
            if let barcodeResults = barcodeRequest.results {
                for barcode in barcodeResults {
                    if let payload = barcode.payloadStringValue, !payload.isEmpty {
                        parts.append(payload)
                    }
                }
            }

            // Text results
            if let textResults = textRequest.results {
                let text = textResults
                    .compactMap { $0.topCandidates(1).first?.string }
                    .joined(separator: "\n")
                if !text.isEmpty {
                    parts.append(text)
                }
            }

            return parts.joined(separator: "\n")
        }.value
        captureLog.notice("OCR took \(started.duration(to: .now).milliseconds, privacy: .public) ms (\(text.count, privacy: .public) characters)")
        return text
    }

    /// On macOS 27 the first accurate text recognition by a new build of the app
    /// takes ~50 s while Vision prepares its models; macOS then caches that per
    /// build, so later runs take well under a second. Pay that cost in the
    /// background at launch so the user's first OCR is fast. The warm-up image must
    /// contain real text: on a blank image Vision stops early and loads nothing.
    nonisolated static func warmUpTextRecognition() {
        Task.detached(priority: .utility) {
            let width = 360, height = 60
            guard let context = CGContext(
                data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            ) else { return }
            context.setFillColor(gray: 1, alpha: 1)
            context.fill(CGRect(x: 0, y: 0, width: width, height: height))
            let attributes: [NSAttributedString.Key: Any] = [
                .font: CTFontCreateWithName("Helvetica" as CFString, 28, nil),
                .foregroundColor: CGColor(gray: 0, alpha: 1),
            ]
            let line = CTLineCreateWithAttributedString(NSAttributedString(string: "Shotly OCR 123", attributes: attributes))
            context.textPosition = CGPoint(x: 10, y: 18)
            CTLineDraw(line, context)
            guard let image = context.makeImage() else { return }

            let started = ContinuousClock.now
            let request = VNRecognizeTextRequest()
            request.recognitionLevel = .accurate
            request.usesLanguageCorrection = false
            request.automaticallyDetectsLanguage = true
            try? VNImageRequestHandler(cgImage: image).perform([request])
            captureLog.notice("OCR warm-up took \(started.duration(to: .now).milliseconds, privacy: .public) ms")
        }
    }

    // MARK: - Sound

    func playShutterSound() {
        guard AppPreferences.playSound else { return }
        let path = "/System/Library/Components/CoreAudio.component/Contents/SharedSupport/SystemSounds/system/Screen Capture.aif"
        let url = URL(fileURLWithPath: path)
        if let sound = NSSound(contentsOf: url, byReference: true) {
            sound.play()
        }
    }

    // MARK: - Helpers

    private func makeTempPath() -> String {
        let dir = NSTemporaryDirectory()
        let stamp = Int(Date().timeIntervalSince1970 * 1000)
        return "\(dir)shotly_\(stamp)_\(UUID().uuidString.prefix(6)).png"
    }

    private func captureFrozenContent(
        for screens: [NSScreen],
        includeWindows: Bool = false
    ) async throws -> FrozenContent {
        let started = ContinuousClock.now
        // Hide Shotly's own windows (preview, editor, toasts) so they are not in the
        // shot. Skip the menu bar status item window: hiding it makes the icon
        // flicker and, since it is always visible, forced the wait below every time.
        let visibleAppWindows = NSApp.windows.filter {
            $0.isVisible && !String(describing: type(of: $0)).contains("StatusBar")
        }
        visibleAppWindows.forEach { $0.orderOut(nil) }
        defer { visibleAppWindows.forEach { $0.orderFront(nil) } }

        // Only wait for WindowServer when Shotly actually had a visible window to
        // remove. The old unconditional delay was paid on every hotkey, even while
        // the app was idle. One compositor turn is enough on current displays.
        if !visibleAppWindows.isEmpty {
            try? await Task.sleep(for: .milliseconds(12))
        }

        let requests = screens.compactMap { screen -> FrozenDisplayRequest? in
            guard let displayID = screen.displayID else { return nil }
            return FrozenDisplayRequest(
                displayID: displayID,
                displayFrame: CGDisplayBounds(displayID)
            )
        }
        let screensByID = Dictionary(uniqueKeysWithValues: screens.compactMap { screen in
            screen.displayID.map { ($0, screen) }
        })

        // Each display used to be captured serially. That becomes very noticeable
        // with two or three Retina displays. Capture them concurrently and use the
        // modern ScreenCaptureKit screenshot path on macOS 26+ (including macOS 27).
        let capturedDisplays = await withTaskGroup(
            of: CapturedDisplay?.self,
            returning: [CapturedDisplay].self
        ) { group in
            for request in requests {
                group.addTask(priority: .userInitiated) {
                    await Self.captureDisplay(request)
                }
            }

            var results: [CapturedDisplay] = []
            results.reserveCapacity(requests.count)
            for await result in group {
                if let result { results.append(result) }
            }
            return results
        }

        let requestByID = Dictionary(uniqueKeysWithValues: requests.map { ($0.displayID, $0) })
        let snapshots = capturedDisplays.compactMap { captured -> FrozenSnapshot? in
            guard let screen = screensByID[captured.displayID],
                  let request = requestByID[captured.displayID] else { return nil }
            return FrozenSnapshot(
                displayID: captured.displayID,
                screen: screen,
                displayFrame: request.displayFrame,
                image: captured.image
            )
        }

        guard !snapshots.isEmpty else {
            throw NSError(
                domain: "Shotly.ScreenCapture",
                code: 1,
                userInfo: [NSLocalizedDescriptionKey: "Unable to capture the selected display"]
            )
        }

        let windows = includeWindows ? currentWindowInfo() : []
        captureLog.notice("Froze \(snapshots.count, privacy: .public) display(s) in \(started.duration(to: .now).milliseconds, privacy: .public) ms")
        return FrozenContent(snapshots: snapshots, windows: windows)
    }

    private nonisolated static func captureDisplay(
        _ request: FrozenDisplayRequest
    ) async -> CapturedDisplay? {
        if #available(macOS 26.0, *) {
            do {
                let configuration = SCScreenshotConfiguration()
                configuration.showsCursor = false
                configuration.dynamicRange = .sdr
                configuration.displayIntent = .local

                let output = try await SCScreenshotManager.captureScreenshot(
                    rect: request.displayFrame,
                    configuration: configuration
                )
                if let image = output.sdrImage {
                    return CapturedDisplay(displayID: request.displayID, image: image)
                }
            } catch {
                // Keep the legacy fallback so capture still works on unusual display
                // configurations or early macOS betas with ScreenCaptureKit issues.
                NSLog("Shotly: ScreenCaptureKit screenshot failed: %@", error.localizedDescription)
            }
        }

        guard let image = CGDisplayCreateImage(request.displayID) else { return nil }
        return CapturedDisplay(displayID: request.displayID, image: image)
    }

    private func currentWindowInfo() -> [FrozenWindowInfo] {
        let options: CGWindowListOption = [.optionOnScreenOnly, .excludeDesktopElements]
        guard let rawWindows = CGWindowListCopyWindowInfo(options, kCGNullWindowID) as? [[String: Any]] else {
            return []
        }

        return rawWindows.compactMap { info in
            guard let bounds = info[kCGWindowBounds as String] as? [String: Any],
                  let frame = CGRect(dictionaryRepresentation: bounds as CFDictionary),
                  let layer = (info[kCGWindowLayer as String] as? NSNumber)?.intValue,
                  let ownerPID = (info[kCGWindowOwnerPID as String] as? NSNumber)?.int32Value else {
                return nil
            }
            let isOnScreen = (info[kCGWindowIsOnscreen as String] as? NSNumber)?.boolValue ?? true
            return FrozenWindowInfo(
                frame: frame,
                layer: layer,
                isOnScreen: isOnScreen,
                ownerPID: ownerPID
            )
        }
    }

    private func frozenWindowRegions(from content: FrozenContent) -> [FrozenWindowRegion] {
        let ownPID = ProcessInfo.processInfo.processIdentifier

        return content.windows.compactMap { window in
            guard window.isOnScreen,
                  window.layer == 0,
                  window.frame.width >= 80,
                  window.frame.height >= 60,
                  window.ownerPID != ownPID else { return nil }

            let center = CGPoint(x: window.frame.midX, y: window.frame.midY)
            guard let snapshot = content.snapshots.first(where: { $0.displayFrame.contains(center) }) else { return nil }

            let localX = window.frame.minX - snapshot.displayFrame.minX
            let localTop = window.frame.minY - snapshot.displayFrame.minY
            let localY = snapshot.screen.frame.height - localTop - window.frame.height
            let localRect = CGRect(
                x: localX,
                y: localY,
                width: window.frame.width,
                height: window.frame.height
            ).intersection(CGRect(origin: .zero, size: snapshot.screen.frame.size))

            guard localRect.width >= 40, localRect.height >= 40 else { return nil }
            return FrozenWindowRegion(displayID: snapshot.displayID, localRect: localRect)
        }
    }

    private func crop(_ image: CGImage, to rect: CGRect, on screen: NSScreen) -> CGImage? {
        let scaleX = CGFloat(image.width) / screen.frame.width
        let scaleY = CGFloat(image.height) / screen.frame.height
        let pixelRect = CGRect(
            x: rect.minX * scaleX,
            y: (screen.frame.height - rect.maxY) * scaleY,
            width: rect.width * scaleX,
            height: rect.height * scaleY
        ).integral.intersection(CGRect(x: 0, y: 0, width: image.width, height: image.height))

        guard pixelRect.width > 0, pixelRect.height > 0 else { return nil }
        return image.cropping(to: pixelRect)
    }

    /// PNG encoding of a full Retina screen takes long enough to stall the UI,
    /// so it runs off the main actor.
    private func writeTemporaryPNG(_ image: CGImage) async -> URL? {
        let url = URL(fileURLWithPath: makeTempPath())
        let box = UncheckedSendable(image)
        return await Task.detached(priority: .userInitiated) {
            guard let destination = CGImageDestinationCreateWithURL(url as CFURL, "public.png" as CFString, 1, nil) else {
                return nil
            }
            CGImageDestinationAddImage(destination, box.value, nil)
            return CGImageDestinationFinalize(destination) ? url : nil
        }.value
    }

}

/// Wraps a value that is safe to hand to another task but is not marked `Sendable`
/// (for example an immutable `CGImage`).
struct UncheckedSendable<Value>: @unchecked Sendable {
    let value: Value
    init(_ value: Value) { self.value = value }
}

/// Records where the first mouse press lands while a capture is being prepared.
@MainActor
private final class EarlyMouseDownRecorder {
    private var monitor: Any?
    private var location: NSPoint?

    init() {
        monitor = NSEvent.addGlobalMonitorForEvents(matching: .leftMouseDown) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self, self.location == nil else { return }
                self.location = NSEvent.mouseLocation
            }
        }
    }

    /// Stops recording and returns the press location, if any.
    func stop() -> NSPoint? {
        if let monitor {
            NSEvent.removeMonitor(monitor)
            self.monitor = nil
        }
        return location
    }
}

private extension Duration {
    var milliseconds: Int {
        Int(components.seconds * 1000 + components.attoseconds / 1_000_000_000_000_000)
    }
}
