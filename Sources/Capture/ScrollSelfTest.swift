import AppKit
import ScreenCaptureKit

/// Temporary diagnostics for scrolling capture: `Shotly --scroll-self-test` opens a long scrollable
/// window, scrolls it with the same events and captures it with the same configuration as a real
/// session, and writes every frame and the stitch results to /tmp/shotly-scrolltest.
@MainActor
enum ScrollSelfTest {
    /// `--scroll-self-test-browser <app> <file>`: opens the file in that browser, captures its window
    /// with a real session on auto-scroll and saves the result to /tmp/shotly-scrolldebug/result.png.
    static func runBrowser(app: String, file: String) {
        Task { @MainActor in
            _ = try? await NSWorkspace.shared.open([URL(fileURLWithPath: file)], withApplicationAt: URL(fileURLWithPath: "/Applications/\(app).app"), configuration: NSWorkspace.OpenConfiguration())
            try? await Task.sleep(for: .seconds(3))
            let infos = (CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]]) ?? []
            guard let info = infos.first(where: { ($0[kCGWindowOwnerName as String] as? String) == app && ($0[kCGWindowLayer as String] as? Int) == 0 }),
                  let boundsDict = info[kCGWindowBounds as String] as? [String: CGFloat] else { NSApp.terminate(nil); return }
            let bounds = CGRect(x: boundsDict["X"] ?? 0, y: boundsDict["Y"] ?? 0, width: boundsDict["Width"] ?? 0, height: boundsDict["Height"] ?? 0)
            // The page area: below the toolbar, inside the window edges.
            let area = CGRect(x: bounds.minX + 4, y: bounds.minY + 120, width: bounds.width - 8, height: min(bounds.height - 130, 700))
            guard let screen = NSScreen.screens.first(where: {
                guard let id = $0.displayID else { return false }
                return CGDisplayBounds(id).contains(CGPoint(x: area.midX, y: area.midY))
            }), let displayID = screen.displayID else { NSApp.terminate(nil); return }
            let primaryHeight = NSScreen.screens.first?.frame.height ?? screen.frame.height
            let local = NSRect(x: area.minX - screen.frame.minX, y: primaryHeight - area.maxY - screen.frame.minY, width: area.width, height: area.height)
            let selection = RegionSelection(pointsRect: area, scaleFactor: screen.backingScaleFactor, displayID: displayID, localRect: local)
            guard let session = try? await ScrollCapture.shared.makeSession(for: selection) else { NSApp.terminate(nil); return }
            session.debugDirectory = URL(fileURLWithPath: "/tmp/shotly-scrolldebug")
            Task { @MainActor in
                try? await Task.sleep(for: .milliseconds(800))
                session.toggleAutoScroll()
                try? await Task.sleep(for: .seconds(25))
                session.finish()
            }
            if let image = await session.run() {
                try? NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:])?
                    .write(to: URL(fileURLWithPath: "/tmp/shotly-scrolldebug/result.png"))
            }
            NSApp.terminate(nil)
        }
    }

    static func run() {
        Task { @MainActor in
            let dir = URL(fileURLWithPath: "/tmp/shotly-scrolltest")
            try? FileManager.default.removeItem(at: dir)
            try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            var log: [String] = []
            func note(_ s: String) { log.append(s); try? log.joined(separator: "\n").write(to: dir.appendingPathComponent("log.txt"), atomically: true, encoding: .utf8) }

            guard let screen = NSScreen.main else { note("no screen"); return }
            let window = NSWindow(contentRect: NSRect(x: screen.frame.minX + 120, y: screen.frame.maxY - 900, width: 760, height: 760),
                                  styleMask: [.titled], backing: .buffered, defer: false)
            let scroll = NSScrollView(frame: window.contentView!.bounds)
            scroll.hasVerticalScroller = true
            scroll.autoresizingMask = [.width, .height]
            let text = NSTextView(frame: NSRect(x: 0, y: 0, width: 740, height: 760))
            text.isVerticallyResizable = true
            text.textContainerInset = NSSize(width: 24, height: 24)
            let body = NSMutableAttributedString()
            let words = "màn hình chụp ảnh cuộn trang ghép nối pixel hàng cột dài ngắn nhanh chậm xanh đỏ vàng tiêu đề nội dung bảng giá tài khoản".split(separator: " ")
            var seed: UInt64 = 7
            func rnd(_ n: Int) -> Int { seed = seed &* 6364136223846793005 &+ 1442695040888963407; return Int((seed >> 33) % UInt64(n)) }
            for i in 0..<70 {
                if i % 8 == 0 {
                    body.append(NSAttributedString(string: "Section \(i / 8 + 1)\n", attributes: [.font: NSFont.boldSystemFont(ofSize: 26)]))
                } else {
                    let line = (0..<(30 + rnd(40))).map { _ in String(words[rnd(words.count)]) }.joined(separator: " ")
                    body.append(NSAttributedString(string: "\(i). " + line + "\n\n", attributes: [.font: NSFont.systemFont(ofSize: 16)]))
                }
            }
            text.textStorage?.setAttributedString(body)
            scroll.documentView = text
            window.contentView?.addSubview(scroll)
            NSApp.activate(ignoringOtherApps: true)
            window.makeKeyAndOrderFront(nil)
            text.scroll(.zero)
            try? await Task.sleep(for: .milliseconds(900))

            // The visible part of the scroll view, in global top-left points.
            let local = scroll.convert(scroll.bounds, to: nil)
            let onScreen = window.convertToScreen(local)
            let primaryHeight = NSScreen.screens.first?.frame.height ?? screen.frame.height
            let pointsRect = CGRect(x: onScreen.minX, y: primaryHeight - onScreen.maxY, width: onScreen.width, height: onScreen.height).insetBy(dx: 0, dy: 0)
            note("area \(pointsRect) scale \(screen.backingScaleFactor)")

            do {
                let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
                guard let displayID = screen.displayID,
                      let display = content.displays.first(where: { $0.displayID == displayID }) else { note("no display"); return }
                let filter = SCContentFilter(display: display, excludingApplications: [], exceptingWindows: [])
                let bounds = CGDisplayBounds(displayID)
                let configuration = SCStreamConfiguration()
                configuration.sourceRect = CGRect(x: pointsRect.minX - bounds.minX, y: pointsRect.minY - bounds.minY, width: pointsRect.width, height: pointsRect.height)
                configuration.width = Int((pointsRect.width * screen.backingScaleFactor).rounded())
                configuration.height = Int((pointsRect.height * screen.backingScaleFactor).rounded())
                configuration.showsCursor = false

                let stitcher = ScrollStitcher()
                CGWarpMouseCursorPosition(CGPoint(x: pointsRect.midX, y: pointsRect.midY))
                for step in 0..<10 {
                    let started = Date()
                    let image = try await SCScreenshotManager.captureImage(contentFilter: filter, configuration: configuration)
                    let took = Date().timeIntervalSince(started) * 1000
                    let rep = NSBitmapImageRep(cgImage: image)
                    try? rep.representation(using: .png, properties: [:])?.write(to: dir.appendingPathComponent(String(format: "frame-%02d.png", step)))
                    let result = stitcher.add(image)
                    note("step \(step): \(image.width)x\(image.height) capture \(Int(took)) ms, scrollY \(Int(scroll.contentView.bounds.origin.y)), result \(result), height \(stitcher.height)")

                    let delta = Int32(max(40, pointsRect.height * 0.66))
                    if let event = CGEvent(scrollWheelEvent2Source: nil, units: .pixel, wheelCount: 1, wheel1: -delta, wheel2: 0, wheel3: 0) {
                        event.location = CGPoint(x: pointsRect.midX, y: pointsRect.midY)
                        event.post(tap: .cghidEventTap)
                    }
                    try? await Task.sleep(for: .milliseconds(500))
                }
                if let out = stitcher.render() {
                    try? NSBitmapImageRep(cgImage: out).representation(using: .png, properties: [:])?.write(to: dir.appendingPathComponent("result.png"))
                    note("result \(out.width)x\(out.height)")
                }
            } catch {
                note("error \(error)")
            }
            note("done")
            NSApp.terminate(nil)
        }
    }
}
