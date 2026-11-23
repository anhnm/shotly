import AppKit
import AVFoundation
import ScreenCaptureKit

/// Records scripted scenes of the real app for the video project:
///
///     Shotly --record-scene <scene> <output dir> <demo image> [--appearance light|dark]
///
/// The scene's window is recorded on its own with ScreenCaptureKit (no cursor, no desktop) while
/// real key and mouse events drive it. Next to `<scene>.mov`, `<scene>.json` lists every action
/// with its time and position in window points (top-left origin), so the video can draw the
/// pointer and the keys in sync.
@MainActor
enum UIRecord {
    private struct Action: Encodable {
        let t: Double
        let kind: String
        var x: Double?
        var y: Double?
        var key: String?
    }

    private struct Timeline: Encodable {
        let scene: String
        let width: Double
        let height: Double
        let scale: Double
        let duration: Double
        let actions: [Action]
    }

    private static var actions: [Action] = []
    private static var started = Date()
    private static var window: NSWindow?

    static func run(scene: String, outputPath: String, demoImagePath: String) {
        Task { @MainActor in
            let output = URL(fileURLWithPath: outputPath)
            try? FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
            if let i = CommandLine.arguments.firstIndex(of: "--appearance"), CommandLine.arguments.count > i + 1 {
                NSApp.appearance = NSAppearance(named: CommandLine.arguments[i + 1] == "light" ? .aqua : .darkAqua)
            }
            NSApp.activate()

            guard #available(macOS 15.0, *) else { print("UIRecord: needs macOS 15"); NSApp.terminate(nil); return }
            guard scene == "editor-tools" else { print("UIRecord: unknown scene \(scene)"); NSApp.terminate(nil); return }

            EditorWindowController.shared.open(url: URL(fileURLWithPath: demoImagePath))
            try? await Task.sleep(for: .milliseconds(1800))
            guard let editor = NSApp.windows.last(where: { $0.isVisible && $0.title == "Shotly Editor" }) else {
                print("UIRecord: no editor"); NSApp.terminate(nil); return
            }
            // Record on the sharpest display, and make sure the editor takes keys before starting.
            let screen = NSScreen.screens.max { $0.backingScaleFactor < $1.backingScaleFactor } ?? NSScreen.main
            editor.setContentSize(NSSize(width: 1320, height: 800))
            if let visible = screen?.visibleFrame {
                editor.setFrameOrigin(NSPoint(x: visible.midX - editor.frame.width / 2, y: visible.midY - editor.frame.height / 2))
            }
            window = editor
            for _ in 0..<20 where !editor.isKeyWindow {
                NSApp.activate(ignoringOtherApps: true)
                editor.makeKeyAndOrderFront(nil)
                editor.orderFrontRegardless()
                try? await Task.sleep(for: .milliseconds(150))
            }
            guard editor.isKeyWindow else { print("UIRecord: editor never became key"); NSApp.terminate(nil); return }
            try? await Task.sleep(for: .milliseconds(500))
            imageFrame = await measureImageFrame(in: editor) ?? imageFrame
            print("UIRecord: image frame \(imageFrame)")

            let movie = output.appendingPathComponent("\(scene).mov")
            try? FileManager.default.removeItem(at: movie)
            do {
                debug("before recorder: active \(NSApp.isActive) frontmost \(NSWorkspace.shared.frontmostApplication?.localizedName ?? "?")")
                let recorder = try await WindowRecorder(window: editor, url: movie)
                try await recorder.start()
                debug("after start: active \(NSApp.isActive) frontmost \(NSWorkspace.shared.frontmostApplication?.localizedName ?? "?")")
                try? await Task.sleep(for: .milliseconds(400))
                debug("after 400ms: active \(NSApp.isActive) frontmost \(NSWorkspace.shared.frontmostApplication?.localizedName ?? "?")")
                started = Date()
                actions = []
                await editorTools()
                try await recorder.stop()
            } catch {
                print("UIRecord: \(error.localizedDescription)")
            }

            let timeline = Timeline(
                scene: scene, width: editor.frame.width, height: editor.frame.height,
                scale: editor.backingScaleFactor, duration: Date().timeIntervalSince(started), actions: actions
            )
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            try? encoder.encode(timeline).write(to: output.appendingPathComponent("\(scene).json"))
            print("UIRecord: wrote \(movie.path)")
            NSApp.terminate(nil)
        }
    }

    // MARK: - Scenes

    /// The demo image inside the editor window, in points from the top-left corner.
    private static var imageFrame = CGRect(x: 131, y: 91, width: 1064, height: 665)

    /// Where a point of the 2000 × 1250 demo-image grid lands in the editor window (points, top-left).
    private static func onImage(_ x: Double, _ y: Double) -> CGPoint {
        CGPoint(x: imageFrame.minX + x / 2000 * imageFrame.width, y: imageFrame.minY + y / 1250 * imageFrame.height)
    }

    /// Finds the demo image in a still of the window: the sample page starts with a full-width white bar.
    private static func measureImageFrame(in window: NSWindow) async -> CGRect? {
        guard let content = try? await SCShareableContent.current,
              let scWindow = content.windows.first(where: { $0.windowID == CGWindowID(window.windowNumber) }) else { return nil }
        let scale = window.backingScaleFactor
        let configuration = SCStreamConfiguration()
        configuration.width = Int(window.frame.width * scale)
        configuration.height = Int(window.frame.height * scale)
        configuration.ignoreShadowsSingleWindow = true
        guard let image = try? await SCScreenshotManager.captureImage(
            contentFilter: SCContentFilter(desktopIndependentWindow: scWindow), configuration: configuration
        ) else { return nil }
        let rep = NSBitmapImageRep(cgImage: image)
        func white(_ x: Int, _ y: Int) -> Bool {
            guard let c = rep.colorAt(x: x, y: y)?.usingColorSpace(.sRGB) else { return false }
            return c.redComponent > 0.98 && c.greenComponent > 0.98 && c.blueComponent > 0.98
        }
        let w = rep.pixelsWide, h = rep.pixelsHigh
        for y in stride(from: h / 10, to: h / 3, by: 1) {
            let row = (0..<w).filter { white($0, y) }
            guard row.count > w / 2, let first = row.first, let last = row.last else { continue }
            let width = Double(last - first + 1) / scale
            return CGRect(x: Double(first) / scale, y: Double(y) / scale, width: width, height: width * 1250 / 2000)
        }
        return nil
    }

    /// Numbered badges, an arrow, a magnifier and a ruler on the sign-in sample.
    private static func editorTools() async {
        await pause(0.8)
        await moveTo(onImage(1000, 300), over: 0.5)

        await press("n", 45)
        for (x, y) in [(548.0, 530.0), (548.0, 686.0), (1460.0, 810.0)] {
            await moveTo(onImage(x, y), over: 0.45)
            await click()
            await pause(0.25)
        }
        await pause(0.6)

        await press("a", 0)
        await moveTo(onImage(1720, 520), over: 0.5)
        await drag(to: onImage(1322, 808), over: 0.7)
        await pause(0.6)

        // Ruler: hold 2 over the plain right part of the Continue button to measure its height.
        await moveTo(onImage(1240, 700), over: 0.4)
        await keyDown("2", 19)
        await moveTo(onImage(1240, 812), over: 0.6)
        await pause(0.5)
        await click()
        await keyUp("2", 19)
        await pause(0.6)

        await press("x", 7)
        await moveTo(onImage(784, 897), over: 0.5)
        await drag(to: onImage(840, 950), over: 0.5)
        await pause(1.2)
    }

    // MARK: - Input

    private static var pointer = CGPoint.zero
    private static var debugLines: [String] = []

    private static func debug(_ line: String) {
        debugLines.append(line)
        try? debugLines.joined(separator: "\n").write(toFile: "/tmp/shotly-record-debug.txt", atomically: true, encoding: .utf8)
    }

    private static func note(_ kind: String, at point: CGPoint? = nil, key: String? = nil) {
        actions.append(Action(t: Date().timeIntervalSince(started), kind: kind,
                              x: point.map { Double($0.x) }, y: point.map { Double($0.y) }, key: key))
    }

    private static func pause(_ seconds: Double) async {
        try? await Task.sleep(for: .milliseconds(Int(seconds * 1000)))
    }

    private static func post(_ type: NSEvent.EventType, _ point: CGPoint) {
        guard let window else { return }
        let height = window.contentView?.bounds.height ?? window.frame.height
        // Hover effects (the ruler, the pixel readout) follow the real pointer, so move it too.
        // The recording leaves the system pointer out; the video draws its own.
        let primaryHeight = NSScreen.screens.first?.frame.height ?? 0
        CGWarpMouseCursorPosition(CGPoint(x: window.frame.minX + point.x, y: primaryHeight - (window.frame.maxY - point.y)))
        if let event = NSEvent.mouseEvent(
            with: type, location: NSPoint(x: point.x, y: height - point.y), modifierFlags: [],
            timestamp: ProcessInfo.processInfo.systemUptime, windowNumber: window.windowNumber, context: nil,
            eventNumber: 0, clickCount: 1, pressure: type == .leftMouseUp ? 0 : 1
        ) { NSApp.postEvent(event, atStart: false) }
    }

    private static func moveTo(_ target: CGPoint, over seconds: Double, dragging: Bool = false) async {
        let start = pointer
        let steps = max(1, Int(seconds * 60))
        for step in 1...steps {
            let t = Double(step) / Double(steps)
            let eased = t < 0.5 ? 2 * t * t : 1 - pow(-2 * t + 2, 2) / 2
            pointer = CGPoint(x: start.x + (target.x - start.x) * eased, y: start.y + (target.y - start.y) * eased)
            post(dragging ? .leftMouseDragged : .mouseMoved, pointer)
            note(dragging ? "drag" : "move", at: pointer)
            try? await Task.sleep(for: .milliseconds(16))
        }
    }

    private static func click() async {
        await ensureFocus()
        post(.leftMouseDown, pointer)
        note("down", at: pointer)
        try? await Task.sleep(for: .milliseconds(70))
        post(.leftMouseUp, pointer)
        note("up", at: pointer)
        try? await Task.sleep(for: .milliseconds(120))
    }

    private static func drag(to target: CGPoint, over seconds: Double) async {
        await ensureFocus()
        post(.leftMouseDown, pointer)
        note("down", at: pointer)
        await moveTo(target, over: seconds, dragging: true)
        post(.leftMouseUp, pointer)
        note("up", at: pointer)
        try? await Task.sleep(for: .milliseconds(150))
    }

    private static func keyEvent(_ type: NSEvent.EventType, _ characters: String, _ code: UInt16) {
        guard let window,
              let event = NSEvent.keyEvent(
                with: type, location: .zero, modifierFlags: [], timestamp: ProcessInfo.processInfo.systemUptime,
                windowNumber: window.windowNumber, context: nil, characters: characters,
                charactersIgnoringModifiers: characters, isARepeat: false, keyCode: code
              ) else { return }
        NSApp.postEvent(event, atStart: false)
    }

    /// Other apps can take the focus while the scene runs; take it back before each input.
    private static func ensureFocus() async {
        guard let window, !(NSApp.isActive && window.isKeyWindow) else { return }
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
        try? await Task.sleep(for: .milliseconds(120))
        debug("refocused: active \(NSApp.isActive)")
    }

    private static func keyDown(_ characters: String, _ code: UInt16) async {
        await ensureFocus()
        debug("key \(characters): active \(NSApp.isActive) key \(NSApp.keyWindow?.title ?? "nil") main \(NSApp.mainWindow?.title ?? "nil") first \(String(describing: type(of: NSApp.keyWindow?.firstResponder as Any)))")
        keyEvent(.keyDown, characters, code)
        note("keyDown", key: characters.uppercased())
        try? await Task.sleep(for: .milliseconds(120))
    }

    private static func keyUp(_ characters: String, _ code: UInt16) async {
        keyEvent(.keyUp, characters, code)
        note("keyUp", key: characters.uppercased())
        try? await Task.sleep(for: .milliseconds(80))
    }

    private static func press(_ characters: String, _ code: UInt16) async {
        await keyDown(characters, code)
        await keyUp(characters, code)
        try? await Task.sleep(for: .milliseconds(250))
    }
}

/// Records one window to a movie file.
@available(macOS 15.0, *)
@MainActor
private final class WindowRecorder {
    private let stream: SCStream
    private let output: SCRecordingOutput

    init(window: NSWindow, url: URL) async throws {
        let content = try await SCShareableContent.current
        guard let scWindow = content.windows.first(where: { $0.windowID == CGWindowID(window.windowNumber) }) else {
            throw NSError(domain: "UIRecord", code: 1, userInfo: [NSLocalizedDescriptionKey: "Window is not shareable"])
        }
        let configuration = SCStreamConfiguration()
        configuration.width = Int(window.frame.width * window.backingScaleFactor)
        configuration.height = Int(window.frame.height * window.backingScaleFactor)
        configuration.minimumFrameInterval = CMTime(value: 1, timescale: 60)
        configuration.showsCursor = false
        configuration.ignoreShadowsSingleWindow = true
        configuration.capturesAudio = false
        stream = SCStream(filter: SCContentFilter(desktopIndependentWindow: scWindow), configuration: configuration, delegate: nil)

        let recording = SCRecordingOutputConfiguration()
        recording.outputURL = url
        recording.outputFileType = .mov
        recording.videoCodecType = .h264
        output = SCRecordingOutput(configuration: recording, delegate: RecordingDelegate.shared)
    }

    func start() async throws {
        try stream.addRecordingOutput(output)
        try await stream.startCapture()
    }

    func stop() async throws {
        try await stream.stopCapture()
        // Give the writer a moment to close the file.
        try? await Task.sleep(for: .milliseconds(600))
    }
}

@available(macOS 15.0, *)
private final class RecordingDelegate: NSObject, SCRecordingOutputDelegate, @unchecked Sendable {
    static let shared = RecordingDelegate()

    func recordingOutput(_ recordingOutput: SCRecordingOutput, didFailWithError error: any Error) {
        print("UIRecord: recording failed: \(error.localizedDescription)")
    }
}
