import AppKit
import SwiftUI

@MainActor
final class EditorWindowController {
    static let shared = EditorWindowController()

    private var windows: [NSWindow] = []

    var hasOpenWindows: Bool { !windows.isEmpty }

    private init() {}

    func open(url: URL? = nil, collage: CollageState? = nil, on screen: NSScreen? = nil) {
        let urlHolder = CurrentURL(url: url)

        let hostingView = NSHostingView(rootView:
            EditorWindowView(urlHolder: urlHolder, initialCollage: collage)
                .frame(minWidth: 1240, minHeight: 550)
        )

        let win = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 1320, height: 800),
            styleMask: [.titled, .closable, .resizable, .miniaturizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        win.contentView = hostingView
        win.title = "Shotly Editor"
        win.titleVisibility = .hidden
        // The editor draws its own flat title bar (see EditorTitleBar). An empty unified
        // toolbar only makes the title bar tall enough to center the traffic lights in it.
        win.titlebarAppearsTransparent = true
        let toolbar = NSToolbar(identifier: "ShotlyEditorTitleBar")
        toolbar.showsBaselineSeparator = false
        win.toolbar = toolbar
        win.toolbarStyle = .unified
        win.isReleasedWhenClosed = false
        win.delegate = EditorWindowDelegate.shared
        win.collectionBehavior = [.transient, .moveToActiveSpace]

        centerOnActiveScreen(win, preferring: screen)

        windows.append(win)

        win.orderFrontRegardless()
        NSApp.setActivationPolicy(.regular)
        win.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    func close(window: NSWindow? = nil) {
        if let window {
            windows.removeAll { $0 === window }
            window.close()
        } else {
            let windowToClose = NSApp.keyWindow ?? windows.last
            if let windowToClose {
                windows.removeAll { $0 === windowToClose }
                windowToClose.close()
            }
        }

        if windows.isEmpty {
            DispatchQueue.main.async {
                if !VideoEditorWindowController.shared.hasOpenWindow {
                    NSApp.setActivationPolicy(.accessory)
                }
            }
        }
    }

    func windowDidClose(_ window: NSWindow) {
        windows.removeAll { $0 === window }
        if windows.isEmpty {
            DispatchQueue.main.async {
                if !VideoEditorWindowController.shared.hasOpenWindow {
                    NSApp.setActivationPolicy(.accessory)
                }
            }
        }
    }

    private func centerOnActiveScreen(_ window: NSWindow, preferring preferred: NSScreen? = nil) {
        let mouseLocation = NSEvent.mouseLocation
        let targetScreen = NSScreen.screens.first { $0.frame.contains(mouseLocation) }
            ?? preferred
            ?? NSScreen.main
            ?? NSScreen.screens.first

        guard let screen = targetScreen else { return }

        let screenFrame = screen.visibleFrame
        let windowSize = window.frame.size

        let x = screenFrame.midX - windowSize.width / 2
        let y = screenFrame.midY - windowSize.height / 2

        window.setFrameOrigin(NSPoint(x: x, y: y))
    }
}

@MainActor
@Observable
final class CurrentURL {
    var url: URL?

    init(url: URL?) {
        self.url = url
    }
}

private final class EditorWindowDelegate: NSObject, NSWindowDelegate, @unchecked Sendable {
    static let shared = EditorWindowDelegate()

    func windowWillClose(_ notification: Notification) {
        guard let window = notification.object as? NSWindow else { return }
        DispatchQueue.main.async {
            EditorWindowController.shared.windowDidClose(window)
        }
    }
}
