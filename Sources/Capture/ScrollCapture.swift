import AppKit
import OSLog
import ScreenCaptureKit
import SwiftUI

private let scrollLog = Logger(subsystem: "com.shotly.app", category: "scroll-capture")

/// Scrolling capture: pick an area, then scroll it (by hand or automatically) while Shotly stitches
/// the frames into one tall image.
@MainActor
final class ScrollCapture {
    static let shared = ScrollCapture()

    private init() {}

    /// Runs a whole session. Returns the stitched image, or nil when cancelled.
    func capture() async throws -> CGImage? {
        guard let selection = await RegionSelectionOverlay().selectRegion(),
              selection.pointsRect.width >= 40, selection.pointsRect.height >= 60,
              let session = try await makeSession(for: selection) else { return nil }
        return await session.run()
    }

    func makeSession(for selection: RegionSelection) async throws -> ScrollCaptureSession? {
        guard let screen = NSScreen.screens.first(where: { $0.displayID == selection.displayID }) else { return nil }

        let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
        guard let display = content.displays.first(where: { $0.displayID == selection.displayID }) else { return nil }
        let ownBundleID = Bundle.main.bundleIdentifier ?? ""
        let ownApps = content.applications.filter { $0.bundleIdentifier == ownBundleID }
        let filter = SCContentFilter(display: display, excludingApplications: ownApps, exceptingWindows: [])

        let displayBounds = CGDisplayBounds(selection.displayID)
        let configuration = SCStreamConfiguration()
        configuration.sourceRect = CGRect(
            x: selection.pointsRect.minX - displayBounds.minX,
            y: selection.pointsRect.minY - displayBounds.minY,
            width: selection.pointsRect.width,
            height: selection.pointsRect.height
        )
        configuration.width = Int((selection.pointsRect.width * selection.scaleFactor).rounded())
        configuration.height = Int((selection.pointsRect.height * selection.scaleFactor).rounded())
        configuration.showsCursor = false
        configuration.capturesAudio = false

        return ScrollCaptureSession(
            selection: selection,
            screen: screen,
            filter: filter,
            configuration: configuration
        )
    }
}

// MARK: - Session

@MainActor
@Observable
final class ScrollCaptureSession {
    enum Phase: Equatable { case waiting, manual, auto, finishing }

    private(set) var phase: Phase = .waiting
    private(set) var stitchedHeight = 0
    private(set) var isLost = false
    private(set) var isFull = false

    @ObservationIgnored private let selection: RegionSelection
    @ObservationIgnored private let screen: NSScreen
    @ObservationIgnored private let filter: SCContentFilter
    @ObservationIgnored private let configuration: SCStreamConfiguration
    @ObservationIgnored private let stitcher = ScrollStitcher()
    @ObservationIgnored private var border: NSPanel?
    @ObservationIgnored private var controls: ScrollControlPanel?
    @ObservationIgnored private var keyMonitor: Any?
    @ObservationIgnored private var loop: Task<Void, Never>?
    @ObservationIgnored private var continuation: CheckedContinuation<CGImage?, Never>?
    @ObservationIgnored private var unchangedInARow = 0
    /// Sign of the wheel delta that scrolls down; flipped if the page turns out to move the other way.
    @ObservationIgnored private var scrollSign: Int32 = -1
    /// When set (launch with `--scroll-debug`), every frame and its stitch result are written here.
    @ObservationIgnored var debugDirectory: URL? = CommandLine.arguments.contains("--scroll-debug")
        ? URL(fileURLWithPath: "/tmp/shotly-scrolldebug") : nil
    @ObservationIgnored private var debugIndex = 0

    /// Pixel rows per point on the captured display.
    var scale: CGFloat { selection.scaleFactor }

    init(selection: RegionSelection, screen: NSScreen, filter: SCContentFilter, configuration: SCStreamConfiguration) {
        self.selection = selection
        self.screen = screen
        self.filter = filter
        self.configuration = configuration
    }

    func run() async -> CGImage? {
        await withCheckedContinuation { continuation in
            self.continuation = continuation
            showWindows()
            startLoop()
        }
    }

    // MARK: Actions

    func toggleAutoScroll() {
        guard phase != .finishing else { return }
        if phase == .auto {
            phase = .manual
        } else {
            phase = .auto
            unchangedInARow = 0
            // Scroll events go to the window under the pointer, so park it in the middle of the area.
            CGWarpMouseCursorPosition(CGPoint(x: selection.pointsRect.midX, y: selection.pointsRect.midY))
        }
    }

    func finish() {
        guard phase != .finishing else { return }
        phase = .finishing
        loop?.cancel()
        let image = stitcher.render()
        scrollLog.notice("Scroll capture finished at \(self.stitchedHeight, privacy: .public) px")
        close(with: image)
    }

    func cancel() {
        guard phase != .finishing else { return }
        phase = .finishing
        loop?.cancel()
        close(with: nil)
    }

    // MARK: Capture loop

    private func startLoop() {
        loop = Task { [weak self] in
            // Let the border and controls appear before the first frame.
            try? await Task.sleep(for: .milliseconds(120))
            while let self, !Task.isCancelled, self.phase != .finishing {
                if self.phase == .auto {
                    self.scrollOnce()
                    // Pages animate their scrolling; wait for it to settle.
                    try? await Task.sleep(for: .milliseconds(260))
                } else {
                    try? await Task.sleep(for: .milliseconds(90))
                }
                guard !Task.isCancelled, self.phase != .finishing else { return }
                await self.captureFrame()
            }
        }
    }

    private func captureFrame() async {
        let image: CGImage
        do {
            image = try await SCScreenshotManager.captureImage(contentFilter: filter, configuration: configuration)
        } catch {
            scrollLog.error("Frame capture failed: \(error.localizedDescription, privacy: .public)")
            return
        }
        guard phase != .finishing else { return }

        let result = stitcher.add(image)
        if let debugDirectory {
            if debugIndex == 0 {
                try? FileManager.default.removeItem(at: debugDirectory)
                try? FileManager.default.createDirectory(at: debugDirectory, withIntermediateDirectories: true)
            }
            let name = String(format: "frame-%03d.png", debugIndex)
            try? NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:])?
                .write(to: debugDirectory.appendingPathComponent(name))
            let line = "\(name) \(phase) \(result) height \(stitcher.height) shift \(stitcher.lastShift)\n"
            if let handle = try? FileHandle(forWritingTo: debugDirectory.appendingPathComponent("log.txt")) {
                handle.seekToEndOfFile(); handle.write(Data(line.utf8)); try? handle.close()
            } else {
                try? line.write(to: debugDirectory.appendingPathComponent("log.txt"), atomically: true, encoding: .utf8)
            }
            debugIndex += 1
        }

        switch result {
        case .started:
            stitchedHeight = stitcher.height
            if phase == .waiting { phase = .manual }
        case .appended:
            stitchedHeight = stitcher.height
            isLost = false
            unchangedInARow = 0
        case .moved:
            isLost = false
            unchangedInARow = 0
            // Auto-scroll that moved the page up means this setup reads the wheel the other way.
            if phase == .auto, stitcher.lastShift < 0 { scrollSign = -scrollSign }
        case .unchanged:
            unchangedInARow += 1
            // Auto-scroll stops by itself at the bottom of the page.
            if phase == .auto, unchangedInARow >= 2, stitchedHeight > 0 { finish() }
        case .lost:
            isLost = true
            if phase == .auto { phase = .manual }
        case .full:
            stitchedHeight = stitcher.height
            isFull = true
            finish()
        }
    }

    /// One step down: about two thirds of the area, so consecutive frames overlap.
    private func scrollOnce() {
        let step = Int32(max(40, selection.pointsRect.height * 0.66))
        guard let event = CGEvent(scrollWheelEvent2Source: nil, units: .pixel, wheelCount: 1, wheel1: scrollSign * step, wheel2: 0, wheel3: 0) else { return }
        event.location = CGPoint(x: selection.pointsRect.midX, y: selection.pointsRect.midY)
        event.post(tap: .cghidEventTap)
    }

    // MARK: Windows

    private func showWindows() {
        let primaryHeight = NSScreen.screens.first?.frame.height ?? screen.frame.height
        let area = NSRect(
            x: selection.pointsRect.minX,
            y: primaryHeight - selection.pointsRect.maxY,
            width: selection.pointsRect.width,
            height: selection.pointsRect.height
        )

        // The border sits just outside the area and lets every click and scroll through.
        let inset: CGFloat = 3
        let border = NSPanel(
            contentRect: area.insetBy(dx: -inset, dy: -inset),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        border.isOpaque = false
        border.backgroundColor = .clear
        border.hasShadow = false
        border.ignoresMouseEvents = true
        border.level = .screenSaver
        border.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        border.contentView = NSHostingView(rootView: ScrollAreaBorder())
        border.orderFrontRegardless()
        self.border = border

        let panel = ScrollControlPanel(session: self)
        let size = panel.frame.size
        let visible = screen.visibleFrame
        var origin = NSPoint(x: area.midX - size.width / 2, y: area.minY - inset - 10 - size.height)
        if origin.y < visible.minY {
            origin.y = area.maxY + inset + 10
            if origin.y + size.height > visible.maxY { origin.y = area.minY + 16 }
        }
        origin.x = min(max(origin.x, visible.minX + 8), visible.maxX - size.width - 8)
        panel.setFrameOrigin(origin)
        panel.makeKeyAndOrderFront(nil)
        controls = panel

        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self else { return event }
            switch event.keyCode {
            case 36, 76: self.finish(); return nil       // Return, Enter
            case 53: self.cancel(); return nil           // Escape
            case 49: self.toggleAutoScroll(); return nil // Space
            default: return event
            }
        }
    }

    private func close(with image: CGImage?) {
        if let keyMonitor { NSEvent.removeMonitor(keyMonitor) }
        keyMonitor = nil
        border?.orderOut(nil)
        controls?.orderOut(nil)
        border = nil
        controls = nil
        continuation?.resume(returning: image)
        continuation = nil
    }
}

// MARK: - Views

private struct ScrollAreaBorder: View {
    var body: some View {
        RoundedRectangle(cornerRadius: 3)
            .strokeBorder(Color(red: 0.24, green: 0.81, blue: 0.56), lineWidth: 2)
            .padding(1)
    }
}

/// A small floating bar under the area: what to do, how much is stitched, and the three actions.
private final class ScrollControlPanel: NSPanel {
    init(session: ScrollCaptureSession) {
        let view = NSHostingView(rootView: ScrollControlView(session: session))
        let size = view.fittingSize
        super.init(
            contentRect: NSRect(origin: .zero, size: NSSize(width: max(size.width, 420), height: size.height)),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        isOpaque = false
        backgroundColor = .clear
        hasShadow = true
        level = .screenSaver
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        contentView = view
    }

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}

private struct ScrollControlView: View {
    let session: ScrollCaptureSession

    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 13, weight: .semibold))
                Text(detail)
                    .font(.system(size: 11))
                    .foregroundStyle(session.isLost ? Color.orange : .secondary)
                    .monospacedDigit()
            }
            .frame(minWidth: 170, alignment: .leading)

            Spacer(minLength: 0)

            Button {
                session.toggleAutoScroll()
            } label: {
                Label(session.phase == .auto ? "Pause" : "Auto-scroll",
                      systemImage: session.phase == .auto ? "pause.fill" : "arrow.down.to.line")
            }
            .help("Space")

            Button("Cancel") { session.cancel() }
                .help("Esc")

            Button("Done") { session.finish() }
                .keyboardShortcut(.defaultAction)
                .help("Return")
        }
        .controlSize(.regular)
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .fixedSize()
    }

    private var title: String {
        switch session.phase {
        case .waiting, .manual: "Scroll to capture"
        case .auto: "Scrolling…"
        case .finishing: "Finishing…"
        }
    }

    private var detail: String {
        if session.isFull { return "Reached the 20,000 px limit" }
        if session.isLost { return "Lost track, scroll back up a little" }
        let points = Int((CGFloat(session.stitchedHeight) / max(session.scale, 1)).rounded())
        return session.stitchedHeight == 0 ? "Space to scroll automatically" : "\(points.formatted()) pt tall"
    }
}
