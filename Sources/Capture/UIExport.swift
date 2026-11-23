import AppKit
import ScreenCaptureKit

/// Exports the app's real windows as transparent PNGs for the video project:
///
///     Shotly --export-ui <output dir> <demo image> [--appearance light|dark]
///
/// Each window is opened the way a user would see it, driven with real key and mouse events where a
/// state needs them (a tool selected, an annotation drawn), and captured on its own with
/// ScreenCaptureKit at the display's scale. A `manifest.json` lists every file with its size in points.
@MainActor
enum UIExport {
    private struct Entry: Encodable {
        let name: String
        let file: String
        let width: Double
        let height: Double
        let scale: Double
    }

    private static var entries: [Entry] = []
    private static var output = URL(fileURLWithPath: "/tmp")
    private static var logLines: [String] = []

    private static func log(_ line: String) {
        print("UIExport: \(line)")
        logLines.append(line)
        try? logLines.joined(separator: "\n").write(to: output.appendingPathComponent("export-log.txt"), atomically: true, encoding: .utf8)
    }

    private static func newWindow(after action: () -> Void, wait: Duration = .milliseconds(900)) async -> NSWindow? {
        let before = Set(NSApp.windows.filter(\.isVisible).map(\.windowNumber))
        action()
        try? await Task.sleep(for: wait)
        return NSApp.windows.last { $0.isVisible && !before.contains($0.windowNumber) && $0.frame.width > 60 }
    }

    private static func shoot(_ window: NSWindow?, _ name: String) async {
        guard let window else { log("no window for \(name)"); return }
        // Windows that pick their own look (Settings follows its Appearance option) get the forced one.
        if let forced = NSApp.appearance, window.appearance != forced {
            window.appearance = forced
            try? await Task.sleep(for: .milliseconds(300))
        }
        do {
            let content = try await SCShareableContent.current
            guard let scWindow = content.windows.first(where: { $0.windowID == CGWindowID(window.windowNumber) }) else {
                log("window not shareable for \(name)"); return
            }
            let scale = window.backingScaleFactor
            let configuration = SCStreamConfiguration()
            configuration.width = Int(window.frame.width * scale)
            configuration.height = Int(window.frame.height * scale)
            configuration.showsCursor = false
            configuration.ignoreShadowsSingleWindow = true
            configuration.capturesAudio = false
            let image = try await SCScreenshotManager.captureImage(
                contentFilter: SCContentFilter(desktopIndependentWindow: scWindow),
                configuration: configuration
            )
            let file = "\(name).png"
            try NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:])?
                .write(to: output.appendingPathComponent(file))
            entries.append(Entry(name: name, file: file, width: window.frame.width, height: window.frame.height, scale: scale))
            log("\(file) \(Int(window.frame.width))×\(Int(window.frame.height)) pt")
        } catch {
            log("\(name) failed: \(error.localizedDescription)")
        }
    }

    private static func key(_ characters: String, _ keyCode: UInt16, in window: NSWindow, modifiers: NSEvent.ModifierFlags = []) {
        for type in [NSEvent.EventType.keyDown, .keyUp] {
            if let event = NSEvent.keyEvent(
                with: type, location: .zero, modifierFlags: modifiers, timestamp: ProcessInfo.processInfo.systemUptime,
                windowNumber: window.windowNumber, context: nil, characters: characters,
                charactersIgnoringModifiers: characters, isARepeat: false, keyCode: keyCode
            ) { NSApp.postEvent(event, atStart: false) }
        }
    }

    /// Drags in window coordinates, measured from the top-left corner.
    private static func drag(in window: NSWindow, from start: CGPoint, to end: CGPoint) async {
        let height = window.contentView?.bounds.height ?? window.frame.height
        func point(_ p: CGPoint) -> NSPoint { NSPoint(x: p.x, y: height - p.y) }
        func post(_ type: NSEvent.EventType, _ p: CGPoint) {
            if let event = NSEvent.mouseEvent(
                with: type, location: point(p), modifierFlags: [], timestamp: ProcessInfo.processInfo.systemUptime,
                windowNumber: window.windowNumber, context: nil, eventNumber: 0, clickCount: 1, pressure: 1
            ) { NSApp.postEvent(event, atStart: false) }
        }
        post(.leftMouseDown, start)
        for step in 1...12 {
            let t = CGFloat(step) / 12
            post(.leftMouseDragged, CGPoint(x: start.x + (end.x - start.x) * t, y: start.y + (end.y - start.y) * t))
            try? await Task.sleep(for: .milliseconds(16))
        }
        post(.leftMouseUp, end)
        try? await Task.sleep(for: .milliseconds(250))
    }


    static func run(outputPath: String, demoImagePath: String) {
        Task { @MainActor in
            output = URL(fileURLWithPath: outputPath)
            try? FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
            let demo = URL(fileURLWithPath: demoImagePath)

            // `--appearance light|dark` forces one look, so a video does not depend on the Mac's setting.
            if let i = CommandLine.arguments.firstIndex(of: "--appearance"), CommandLine.arguments.count > i + 1 {
                NSApp.appearance = NSAppearance(named: CommandLine.arguments[i + 1] == "light" ? .aqua : .darkAqua)
            }
            NSApp.activate()

            // Menu bar panel.
            let menu = MenuBarPopoverController.shared.showDetachedForExport()
            try? await Task.sleep(for: .milliseconds(900))
            await shoot(menu, "menu-bar")
            menu?.orderOut(nil)

            // Preview card at the pointer.
            PreviewOverlay.shared.show(url: demo)
            // The card loads its thumbnail first; wait until it is on screen.
            for _ in 0..<40 where PreviewOverlay.shared.openPanel?.isVisible != true {
                try? await Task.sleep(for: .milliseconds(100))
            }
            try? await Task.sleep(for: .milliseconds(600))
            await shoot(PreviewOverlay.shared.openPanel, "preview")
            PreviewOverlay.shared.dismiss()

            // OCR translation window, with the real recognised text of the Japanese sample page.
            let original = "二段階認証\n認証アプリに表示された6桁のコードを入力して、ログインを完\n了してください。\n482 913\n認証する\n安全のため、このコードを誰とも共有しないでください。"
            OCRTranslationWindow.shared.show(originalText: original)
            // Apple Translation can take a while the first time; give it time to finish.
            try? await Task.sleep(for: .seconds(12))
            await shoot(OCRTranslationWindow.shared.openPanel, "ocr-translation")
            OCRTranslationWindow.shared.dismiss()

            // Settings, one tab per file.
            for section in [SettingsSection.general, .hotkeys, .capture, .backdrop] {
                let settings = await newWindow(after: { SettingsWindowController.shared.open(section: section) }, wait: .milliseconds(900))
                await shoot(settings ?? NSApp.windows.last { $0.isVisible && $0.title.contains("Settings") }, "settings-\(section.rawValue.lowercased())")
                (settings ?? NSApp.keyWindow)?.close()
                try? await Task.sleep(for: .milliseconds(300))
            }

            // Editor: the plain window, then each tool selected with its options bar.
            guard let editor = await newWindow(after: { EditorWindowController.shared.open(url: demo) }, wait: .milliseconds(1800)) else {
                log("editor did not open"); NSApp.terminate(nil); return
            }
            editor.makeKeyAndOrderFront(nil)
            await shoot(editor, "editor")
            let tools: [(String, UInt16)] = [("v", 9), ("t", 17), ("m", 46), ("r", 15), ("d", 2), ("a", 0), ("b", 11), ("g", 5), ("x", 7), ("n", 45), ("o", 31), ("l", 37)]
            for (character, code) in tools {
                key(character, code, in: editor)
                try? await Task.sleep(for: .milliseconds(450))
                await shoot(editor, "editor-tool-\(character)")
            }

            // A few tools in use, drawn with the mouse on the demo image.
            let size = editor.frame.size
            let center = CGPoint(x: size.width * 0.5, y: size.height * 0.55)
            key("n", 45, in: editor)
            for dx in [-120.0, 0, 120] { await drag(in: editor, from: CGPoint(x: center.x + dx, y: center.y), to: CGPoint(x: center.x + dx, y: center.y)) }
            await shoot(editor, "editor-badges")
            key("a", 0, in: editor)
            await drag(in: editor, from: CGPoint(x: center.x + 260, y: center.y - 160), to: CGPoint(x: center.x + 40, y: center.y - 20))
            await shoot(editor, "editor-arrow")
            key("x", 7, in: editor)
            await drag(in: editor, from: CGPoint(x: center.x - 200, y: center.y + 120), to: CGPoint(x: center.x - 170, y: center.y + 150))
            await shoot(editor, "editor-magnifier")

            let manifest = try? JSONEncoder().encode(entries)
            try? manifest?.write(to: output.appendingPathComponent("manifest.json"))
            log("done, \(entries.count) files in \(output.path)")
            NSApp.terminate(nil)
        }
    }
}
