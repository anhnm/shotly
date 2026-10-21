import AppKit
import SwiftUI

/// Routes scroll-wheel and pinch events over the canvas to zoom and pan handlers.
///
/// Uses local event monitors rather than overriding `scrollWheel` so annotation views
/// layered on top of the canvas do not swallow the events. Each handler receives the
/// cursor position relative to the view's center and returns whether it consumed the event.
struct CanvasViewportEventView: NSViewRepresentable {
    let onScroll: (NSEvent, CGPoint) -> Bool
    let onMagnify: (CGFloat, CGPoint) -> Bool

    func makeNSView(context: Context) -> CanvasViewportEventNSView {
        let view = CanvasViewportEventNSView()
        view.onScroll = onScroll
        view.onMagnify = onMagnify
        return view
    }

    func updateNSView(_ nsView: CanvasViewportEventNSView, context: Context) {
        nsView.onScroll = onScroll
        nsView.onMagnify = onMagnify
    }
}

final class CanvasViewportEventNSView: NSView {
    var onScroll: ((NSEvent, CGPoint) -> Bool)?
    var onMagnify: ((CGFloat, CGPoint) -> Bool)?

    nonisolated(unsafe) private var monitor: Any?

    override var isFlipped: Bool { true }

    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if window == nil {
            removeMonitor()
        } else if monitor == nil {
            monitor = NSEvent.addLocalMonitorForEvents(matching: [.scrollWheel, .magnify]) { [weak self] event in
                guard let self else { return event }
                return self.handle(event) ? nil : event
            }
        }
    }

    deinit {
        if let monitor {
            NSEvent.removeMonitor(monitor)
        }
    }

    private func removeMonitor() {
        if let monitor {
            NSEvent.removeMonitor(monitor)
            self.monitor = nil
        }
    }

    private func handle(_ event: NSEvent) -> Bool {
        guard event.window === window, window != nil else { return false }
        let point = convert(event.locationInWindow, from: nil)
        guard bounds.contains(point) else { return false }
        let anchor = CGPoint(x: point.x - bounds.midX, y: point.y - bounds.midY)

        switch event.type {
        case .scrollWheel:
            return onScroll?(event, anchor) ?? false
        case .magnify:
            return onMagnify?(event.magnification, anchor) ?? false
        default:
            return false
        }
    }
}
