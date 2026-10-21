import AppKit
import ScreenCaptureKit

struct RegionSelection {
    let pointsRect: CGRect  // In global display points (top-left origin, matching SCK coordinates)
    let scaleFactor: CGFloat
    let displayID: CGDirectDisplayID
    let localRect: CGRect
}

struct FrozenWindowRegion {
    let displayID: CGDirectDisplayID
    let localRect: CGRect
}

struct WindowSelection {
    let displayID: CGDirectDisplayID
    let localRect: CGRect
}

@MainActor
final class RegionSelectionOverlay {

    private var overlayWindows: [NSWindow] = []
    private var selectionViews: [(view: SelectionView, screen: NSScreen)] = []
    private var continuation: CheckedContinuation<RegionSelection?, Never>?
    private let frozenImages: [CGDirectDisplayID: CGImage]
    /// Where the user pressed the mouse while the screen was being frozen, in global
    /// AppKit coordinates. Used to start the selection from that point.
    private let earlyMouseDown: NSPoint?
    private var externalDragMonitors: [Any] = []
    private var isFinished = false

    init(frozenImages: [CGDirectDisplayID: CGImage] = [:], earlyMouseDown: NSPoint? = nil) {
        self.frozenImages = frozenImages
        self.earlyMouseDown = earlyMouseDown
    }

    func selectRegion() async -> RegionSelection? {
        await withCheckedContinuation { cont in
            self.continuation = cont
            showOverlays()
        }
    }

    private func showOverlays() {
        let crosshair = CrosshairCursor.shared.makeCursor()

        for screen in NSScreen.screens {
            guard let displayID = screen.displayID else { continue }
            let window = OverlayWindow(screen: screen)

            let overlayView = SelectionView(
                screen: screen,
                cursor: crosshair
            ) { [weak self] rect in
                self?.finishSelection(rect: rect, screen: screen, displayID: displayID)
            } onCancel: { [weak self] in
                self?.cancelSelection()
            }

            window.contentView = FrozenBackdropView(
                frame: CGRect(origin: .zero, size: screen.frame.size),
                frozenImage: frozenImages[displayID],
                overlayView: overlayView
            )
            overlayWindows.append(window)
            selectionViews.append((overlayView, screen))
        }

        // Show every overlay first, then make the one under the cursor key so it
        // receives Esc immediately. The panels are non-activating, so this does not
        // wait on an app switch (which macOS 14+ may delay or refuse).
        overlayWindows.forEach { $0.orderFrontRegardless() }
        let mouse = NSEvent.mouseLocation
        let keyWindow = overlayWindows.first { $0.frame.contains(mouse) } ?? overlayWindows.first
        keyWindow?.makeKey()

        crosshair.push()
        crosshair.set()

        adoptMousePressMadeBeforeOverlay()
    }

    /// If the user started dragging while the screen was still being frozen, the
    /// press went to the app underneath and its drag events never reach the overlay.
    /// Follow that drag with event monitors instead of making the user start over.
    private func adoptMousePressMadeBeforeOverlay() {
        guard NSEvent.pressedMouseButtons & 1 != 0 else { return }
        let start = earlyMouseDown ?? NSEvent.mouseLocation
        guard let target = selectionViews.first(where: { $0.screen.frame.contains(start) }) else { return }

        target.view.beginDrag(at: localPoint(start, in: target.screen))

        let handle: (NSEvent) -> Void = { [weak self] event in
            guard let self else { return }
            let point = self.localPoint(NSEvent.mouseLocation, in: target.screen)
            if event.type == .leftMouseUp {
                self.removeExternalDragMonitors()
                target.view.endDrag(at: point)
            } else {
                target.view.continueDrag(to: point)
            }
        }
        if let global = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDragged, .leftMouseUp], handler: { event in
            MainActor.assumeIsolated { handle(event) }
        }) {
            externalDragMonitors.append(global)
        }
        if let local = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDragged, .leftMouseUp], handler: { event in
            handle(event)
            return nil
        }) {
            externalDragMonitors.append(local)
        }
    }

    private func localPoint(_ global: NSPoint, in screen: NSScreen) -> NSPoint {
        NSPoint(
            x: min(max(global.x - screen.frame.minX, 0), screen.frame.width),
            y: min(max(global.y - screen.frame.minY, 0), screen.frame.height)
        )
    }

    private func removeExternalDragMonitors() {
        externalDragMonitors.forEach { NSEvent.removeMonitor($0) }
        externalDragMonitors.removeAll()
    }

    private func finishSelection(rect: CGRect, screen: NSScreen, displayID: CGDirectDisplayID) {
        guard !isFinished else { return }
        isFinished = true
        NSCursor.pop()
        removeExternalDragMonitors()

        let primaryHeight = NSScreen.screens.first?.frame.height ?? screen.frame.height

        let globalX = screen.frame.origin.x + rect.origin.x
        let globalY = primaryHeight - (screen.frame.origin.y + rect.origin.y + rect.height)

        let pointsRect = CGRect(
            x: globalX,
            y: globalY,
            width: rect.width,
            height: rect.height
        )

        let selection = RegionSelection(
            pointsRect: pointsRect,
            scaleFactor: screen.backingScaleFactor,
            displayID: displayID,
            localRect: rect
        )

        closeOverlays()
        continuation?.resume(returning: selection)
        continuation = nil
    }

    private func cancelSelection() {
        guard !isFinished else { return }
        isFinished = true
        NSCursor.pop()
        removeExternalDragMonitors()
        closeOverlays()
        continuation?.resume(returning: nil)
        continuation = nil
    }

    private func closeOverlays() {
        for window in overlayWindows {
            window.orderOut(nil)
        }
        overlayWindows.removeAll()
        selectionViews.removeAll()
    }
}

@MainActor
final class WindowSelectionOverlay {
    private var overlayWindows: [NSWindow] = []
    private var continuation: CheckedContinuation<WindowSelection?, Never>?
    private let frozenImages: [CGDirectDisplayID: CGImage]
    private let regions: [FrozenWindowRegion]

    init(frozenImages: [CGDirectDisplayID: CGImage], regions: [FrozenWindowRegion]) {
        self.frozenImages = frozenImages
        self.regions = regions
    }

    func selectWindow() async -> WindowSelection? {
        guard !regions.isEmpty else { return nil }
        return await withCheckedContinuation { continuation in
            self.continuation = continuation
            showOverlays()
        }
    }

    private func showOverlays() {
        for screen in NSScreen.screens {
            guard let displayID = screen.displayID,
                  let frozenImage = frozenImages[displayID] else { continue }

            let window = OverlayWindow(screen: screen)

            let displayRegions = regions.filter { $0.displayID == displayID }
            let selectionView = FrozenWindowSelectionView(
                regions: displayRegions,
                onSelect: { [weak self] region in
                    self?.finishSelection(region)
                },
                onCancel: { [weak self] in
                    self?.cancelSelection()
                }
            )
            window.contentView = FrozenBackdropView(
                frame: CGRect(origin: .zero, size: screen.frame.size),
                frozenImage: frozenImage,
                overlayView: selectionView
            )
            window.orderFrontRegardless()
            overlayWindows.append(window)
        }

        let mouse = NSEvent.mouseLocation
        (overlayWindows.first { $0.frame.contains(mouse) } ?? overlayWindows.first)?.makeKey()
        NSCursor.pointingHand.push()
    }

    private func finishSelection(_ region: FrozenWindowRegion) {
        NSCursor.pop()
        closeOverlays()
        continuation?.resume(returning: WindowSelection(displayID: region.displayID, localRect: region.localRect))
        continuation = nil
    }

    private func cancelSelection() {
        NSCursor.pop()
        closeOverlays()
        continuation?.resume(returning: nil)
        continuation = nil
    }

    private func closeOverlays() {
        overlayWindows.forEach { $0.orderOut(nil) }
        overlayWindows.removeAll()
    }
}

// MARK: - Custom Crosshair "+" Cursor (matches macOS screenshot tool)

@MainActor
final class CrosshairCursor {
    static let shared = CrosshairCursor()

    func makeCursor() -> NSCursor {
        let size: CGFloat = 40
        let center = size / 2
        let lineLength: CGFloat = 16
        let gap: CGFloat = 4

        let image = NSImage(size: NSSize(width: size, height: size))
        image.lockFocus()

        NSGraphicsContext.current?.shouldAntialias = true

        let shadow = NSShadow()
        shadow.shadowColor = NSColor.black.withAlphaComponent(0.5)
        shadow.shadowOffset = NSSize(width: 0, height: -0.5)
        shadow.shadowBlurRadius = 1.5
        shadow.set()

        NSColor.white.setStroke()
        let path = NSBezierPath()
        path.lineWidth = 1.5
        path.lineCapStyle = .round

        // Horizontal line (left segment)
        path.move(to: NSPoint(x: center - lineLength, y: center))
        path.line(to: NSPoint(x: center - gap, y: center))
        // Horizontal line (right segment)
        path.move(to: NSPoint(x: center + gap, y: center))
        path.line(to: NSPoint(x: center + lineLength, y: center))
        // Vertical line (bottom segment)
        path.move(to: NSPoint(x: center, y: center - lineLength))
        path.line(to: NSPoint(x: center, y: center - gap))
        // Vertical line (top segment)
        path.move(to: NSPoint(x: center, y: center + gap))
        path.line(to: NSPoint(x: center, y: center + lineLength))

        path.stroke()

        // Draw center "+" cross
        let plusPath = NSBezierPath()
        plusPath.lineWidth = 1.5
        plusPath.lineCapStyle = .round
        let plusSize: CGFloat = 2.5
        plusPath.move(to: NSPoint(x: center - plusSize, y: center))
        plusPath.line(to: NSPoint(x: center + plusSize, y: center))
        plusPath.move(to: NSPoint(x: center, y: center - plusSize))
        plusPath.line(to: NSPoint(x: center, y: center + plusSize))
        plusPath.stroke()

        image.unlockFocus()

        return NSCursor(image: image, hotSpot: NSPoint(x: center, y: center))
    }
}

// MARK: - Overlay Window (prevents AppKit cursor resets)

/// Full-screen, non-activating panel. It takes key focus (for Esc) without
/// activating Shotly, so it is interactive the moment it appears.
private final class OverlayWindow: NSPanel {
    init(screen: NSScreen) {
        super.init(
            contentRect: screen.frame,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        isOpaque = false
        backgroundColor = .clear
        level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.maximumWindow)))
        hasShadow = false
        ignoresMouseEvents = false
        acceptsMouseMovedEvents = true
        isFloatingPanel = true
        hidesOnDeactivate = false
        becomesKeyOnlyIfNeeded = false
        isReleasedWhenClosed = false
        animationBehavior = .none
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
    }

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }

    override func cursorUpdate(with event: NSEvent) {
        // Swallow cursor updates — we manage the cursor ourselves in SelectionView
    }
}

// MARK: - Selection View

/// Keeps the full-resolution frozen screenshot in its own layer-backed image
/// view. The interaction overlay can then redraw guides and selection borders
/// without resampling a Retina screenshot for every mouse-move event.
private final class FrozenBackdropView: NSView {
    init(frame: CGRect, frozenImage: CGImage?, overlayView: NSView) {
        super.init(frame: frame)
        wantsLayer = true

        if let frozenImage {
            let imageView = NSImageView(frame: bounds)
            imageView.autoresizingMask = [.width, .height]
            imageView.imageScaling = .scaleAxesIndependently
            imageView.wantsLayer = true
            imageView.image = NSImage(
                cgImage: frozenImage,
                size: NSSize(width: bounds.width, height: bounds.height)
            )
            addSubview(imageView)
        }

        overlayView.frame = bounds
        overlayView.autoresizingMask = [.width, .height]
        addSubview(overlayView)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }
}

/// Draws the dimming, guides and selection with Core Animation shape layers.
/// Only paths change per mouse event, so nothing is redrawn on the CPU; the old
/// `draw(_:)` repainted the whole screen on every mouse move, which stuttered on
/// large Retina displays.
private final class SelectionView: NSView {
    private var dragStart: NSPoint?
    private var dragCurrent: NSPoint?
    private var mouseLocation: NSPoint?
    private var trackingArea: NSTrackingArea?
    private var lastDragLocation: NSPoint?
    private let screen: NSScreen
    private let crosshairCursor: NSCursor
    private let onSelect: (CGRect) -> Void
    private let onCancel: () -> Void

    private let dimLayer = CAShapeLayer()
    private let guideLayer = CAShapeLayer()
    private let borderLayer = CAShapeLayer()
    private let coordinateLabel = OverlayLabelLayer(fontSize: 10, weight: .regular, backgroundAlpha: 0.65)
    private let sizeLabel = OverlayLabelLayer(fontSize: 11, weight: .medium, backgroundAlpha: 0.7)

    init(
        screen: NSScreen,
        cursor: NSCursor,
        onSelect: @escaping (CGRect) -> Void,
        onCancel: @escaping () -> Void
    ) {
        self.screen = screen
        self.crosshairCursor = cursor
        self.onSelect = onSelect
        self.onCancel = onCancel
        super.init(frame: CGRect(origin: .zero, size: screen.frame.size))
        wantsLayer = true
        setUpLayers()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    override var acceptsFirstResponder: Bool { true }

    /// The overlay may not be key yet when the user presses; without this the first
    /// click only focuses the window and the drag is lost.
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    private func setUpLayers() {
        guard let root = layer else { return }
        let scale = screen.backingScaleFactor

        dimLayer.fillColor = NSColor.black.withAlphaComponent(0.3).cgColor
        dimLayer.fillRule = .evenOdd

        guideLayer.strokeColor = NSColor.white.withAlphaComponent(0.4).cgColor
        guideLayer.fillColor = nil
        guideLayer.lineWidth = 0.5

        borderLayer.strokeColor = NSColor.white.cgColor
        borderLayer.fillColor = nil
        borderLayer.lineWidth = 1.5

        for sublayer in [dimLayer, guideLayer, borderLayer, coordinateLabel, sizeLabel] as [CALayer] {
            sublayer.contentsScale = scale
            sublayer.actions = OverlayLabelLayer.noAnimations
            root.addSublayer(sublayer)
        }
        coordinateLabel.setScale(scale)
        sizeLabel.setScale(scale)
        updateLayers()
    }

    override func layout() {
        super.layout()
        updateLayers()
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        window?.makeFirstResponder(self)
        updateTrackingAreas()
    }

    override func updateTrackingAreas() {
        if let existing = trackingArea {
            removeTrackingArea(existing)
        }
        let area = NSTrackingArea(
            rect: bounds,
            options: [.mouseMoved, .mouseEnteredAndExited, .activeAlways, .inVisibleRect],
            owner: self,
            userInfo: nil
        )
        addTrackingArea(area)
        trackingArea = area
        super.updateTrackingAreas()
    }

    override func resetCursorRects() {
        addCursorRect(bounds, cursor: crosshairCursor)
        crosshairCursor.set()
    }

    override func cursorUpdate(with event: NSEvent) {
        crosshairCursor.set()
    }

    // MARK: - Drawing

    private func updateLayers() {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        defer { CATransaction.commit() }

        dimLayer.frame = bounds
        guideLayer.frame = bounds
        borderLayer.frame = bounds

        let selectionRect: CGRect? = {
            guard let start = dragStart, let current = dragCurrent else { return nil }
            let rect = rectFromPoints(start, current)
            return rect.width > 2 && rect.height > 2 ? rect : nil
        }()

        let dimPath = CGMutablePath()
        dimPath.addRect(bounds)
        if let selectionRect { dimPath.addRect(selectionRect) }
        dimLayer.path = dimPath

        if let guidePoint = dragCurrent ?? mouseLocation {
            let guides = CGMutablePath()
            guides.move(to: CGPoint(x: guidePoint.x, y: bounds.minY))
            guides.addLine(to: CGPoint(x: guidePoint.x, y: bounds.maxY))
            guides.move(to: CGPoint(x: bounds.minX, y: guidePoint.y))
            guides.addLine(to: CGPoint(x: bounds.maxX, y: guidePoint.y))
            guideLayer.path = guides
            updateCoordinateLabel(at: guidePoint)
        } else {
            guideLayer.path = nil
            coordinateLabel.isHidden = true
        }

        if let selectionRect {
            borderLayer.path = CGPath(rect: selectionRect, transform: nil)
            let scale = screen.backingScaleFactor
            sizeLabel.text = "\(Int(selectionRect.width * scale)) × \(Int(selectionRect.height * scale))"
            let size = sizeLabel.preferredFrameSize()
            sizeLabel.frame = CGRect(
                x: selectionRect.midX - size.width / 2,
                y: max(bounds.minY + 4, selectionRect.minY - size.height - 6),
                width: size.width,
                height: size.height
            )
            sizeLabel.isHidden = false
        } else {
            borderLayer.path = nil
            sizeLabel.isHidden = true
        }
    }

    private func updateCoordinateLabel(at point: NSPoint) {
        let scale = screen.backingScaleFactor
        coordinateLabel.text = "X: \(Int(point.x * scale))  Y: \(Int((screen.frame.height - point.y) * scale))"
        let size = coordinateLabel.preferredFrameSize()
        var x = point.x + 8
        var y = point.y - size.height - 8
        if x + size.width > bounds.maxX { x = point.x - size.width - 8 }
        if y < bounds.minY { y = point.y + 8 }
        coordinateLabel.frame = CGRect(x: x, y: y, width: size.width, height: size.height)
        coordinateLabel.isHidden = false
    }

    // MARK: - Drag (shared by mouse events and the overlay's external drag monitors)

    func beginDrag(at point: NSPoint) {
        crosshairCursor.set()
        dragStart = point
        dragCurrent = point
        lastDragLocation = point
        mouseLocation = nil
        updateLayers()
    }

    func continueDrag(to point: NSPoint) {
        crosshairCursor.set()
        let isSpacePressed = CGEventSource.keyState(.combinedSessionState, key: CGKeyCode(49))

        if isSpacePressed, let lastLoc = lastDragLocation, let start = dragStart, let current = dragCurrent {
            let deltaX = point.x - lastLoc.x
            let deltaY = point.y - lastLoc.y
            dragStart = NSPoint(x: start.x + deltaX, y: start.y + deltaY)
            dragCurrent = NSPoint(x: current.x + deltaX, y: current.y + deltaY)
        } else {
            dragCurrent = point
        }

        lastDragLocation = point
        updateLayers()
    }

    func endDrag(at point: NSPoint) {
        guard let start = dragStart else { return }
        // While Space is held the selection was moved, so keep the moved corner;
        // otherwise the release point is the final corner.
        let isSpacePressed = CGEventSource.keyState(.combinedSessionState, key: CGKeyCode(49))
        let end = isSpacePressed ? (dragCurrent ?? point) : point
        let rect = rectFromPoints(start, end)
        lastDragLocation = nil
        dragStart = nil

        if rect.width > 3, rect.height > 3 {
            onSelect(rect)
        } else {
            onCancel()
        }
    }

    // MARK: - Mouse Events

    override func mouseEntered(with event: NSEvent) {
        crosshairCursor.set()
    }

    override func mouseMoved(with event: NSEvent) {
        crosshairCursor.set()
        guard dragStart == nil else { return }
        mouseLocation = convert(event.locationInWindow, from: nil)
        updateLayers()
    }

    override func mouseDown(with event: NSEvent) {
        beginDrag(at: convert(event.locationInWindow, from: nil))
    }

    override func mouseDragged(with event: NSEvent) {
        continueDrag(to: convert(event.locationInWindow, from: nil))
    }

    override func mouseUp(with event: NSEvent) {
        endDrag(at: convert(event.locationInWindow, from: nil))
    }

    override func keyDown(with event: NSEvent) {
        if event.keyCode == 53 { // ESC
            onCancel()
        } else if event.keyCode == 49 { // Space
            // Swallow event to prevent system beep alert sound
        } else {
            super.keyDown(with: event)
        }
    }

    private func rectFromPoints(_ a: NSPoint, _ b: NSPoint) -> CGRect {
        CGRect(
            x: min(a.x, b.x),
            y: min(a.y, b.y),
            width: abs(b.x - a.x),
            height: abs(b.y - a.y)
        )
    }
}

/// Small rounded label (coordinates, selection size) drawn by Core Animation.
private final class OverlayLabelLayer: CALayer {
    /// Built on demand: `CAAction` is not `Sendable`, so this cannot be a stored static.
    static var noAnimations: [String: CAAction] { [
        "position": NSNull(), "bounds": NSNull(), "frame": NSNull(),
        "path": NSNull(), "contents": NSNull(), "hidden": NSNull(), "string": NSNull(),
    ] }

    private let textLayer = CATextLayer()
    private let font: NSFont
    private let horizontalPadding: CGFloat = 6
    private let verticalPadding: CGFloat = 2

    var text: String = "" {
        didSet { textLayer.string = text }
    }

    init(fontSize: CGFloat, weight: NSFont.Weight, backgroundAlpha: CGFloat) {
        font = NSFont.monospacedSystemFont(ofSize: fontSize, weight: weight)
        super.init()
        backgroundColor = NSColor.black.withAlphaComponent(backgroundAlpha).cgColor
        cornerRadius = 4
        isHidden = true
        textLayer.font = font
        textLayer.fontSize = fontSize
        textLayer.foregroundColor = NSColor.white.cgColor
        textLayer.alignmentMode = .center
        textLayer.actions = Self.noAnimations
        addSublayer(textLayer)
    }

    override init(layer: Any) {
        font = (layer as? OverlayLabelLayer)?.font ?? .systemFont(ofSize: 10)
        super.init(layer: layer)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    func setScale(_ scale: CGFloat) {
        contentsScale = scale
        textLayer.contentsScale = scale
    }

    override func preferredFrameSize() -> CGSize {
        let size = (text as NSString).size(withAttributes: [.font: font])
        return CGSize(
            width: ceil(size.width) + horizontalPadding * 2,
            height: ceil(size.height) + verticalPadding * 2
        )
    }

    override func layoutSublayers() {
        super.layoutSublayers()
        textLayer.frame = bounds.insetBy(dx: horizontalPadding, dy: verticalPadding)
    }
}

private final class FrozenWindowSelectionView: NSView {
    private let regions: [FrozenWindowRegion]
    private let onSelect: (FrozenWindowRegion) -> Void
    private let onCancel: () -> Void
    private var hoveredRegion: FrozenWindowRegion?
    private var trackingArea: NSTrackingArea?

    init(
        regions: [FrozenWindowRegion],
        onSelect: @escaping (FrozenWindowRegion) -> Void,
        onCancel: @escaping () -> Void
    ) {
        self.regions = regions
        self.onSelect = onSelect
        self.onCancel = onCancel
        super.init(frame: .zero)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    override var acceptsFirstResponder: Bool { true }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        window?.makeFirstResponder(self)
        updateTrackingAreas()
    }

    override func updateTrackingAreas() {
        if let trackingArea { removeTrackingArea(trackingArea) }
        let area = NSTrackingArea(
            rect: bounds,
            options: [.mouseMoved, .mouseEnteredAndExited, .activeAlways, .inVisibleRect],
            owner: self,
            userInfo: nil
        )
        addTrackingArea(area)
        trackingArea = area
        super.updateTrackingAreas()
    }

    override func draw(_ dirtyRect: NSRect) {
        NSColor.black.withAlphaComponent(0.32).setFill()
        let dimPath = NSBezierPath(rect: bounds)
        if let hoveredRegion {
            dimPath.appendRect(hoveredRegion.localRect)
            dimPath.windingRule = .evenOdd
        }
        dimPath.fill()

        guard let hoveredRegion else { return }
        NSColor.controlAccentColor.setStroke()
        let border = NSBezierPath(roundedRect: hoveredRegion.localRect, xRadius: 6, yRadius: 6)
        border.lineWidth = 3
        border.stroke()
    }

    override func mouseMoved(with event: NSEvent) {
        let location = convert(event.locationInWindow, from: nil)
        NSCursor.pointingHand.set()
        let region = region(at: location)
        // Repaint only when the highlighted window changes, not on every mouse move.
        guard region?.localRect != hoveredRegion?.localRect else { return }
        hoveredRegion = region
        needsDisplay = true
    }

    override func mouseExited(with event: NSEvent) {
        hoveredRegion = nil
        needsDisplay = true
    }

    override func mouseDown(with event: NSEvent) {
        // Resolve the hit again on mouse-down. This also handles a click made
        // immediately after the overlay appears, before mouseMoved is delivered.
        let location = convert(event.locationInWindow, from: nil)
        if let region = region(at: location) {
            onSelect(region)
        }
    }

    private func region(at location: NSPoint) -> FrozenWindowRegion? {
        regions.first { $0.localRect.contains(location) }
    }

    override func keyDown(with event: NSEvent) {
        if event.keyCode == 53 {
            onCancel()
        }
    }
}

extension NSScreen {
    var displayID: CGDirectDisplayID? {
        (deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)
            .map { CGDirectDisplayID($0.uint32Value) }
    }
}
