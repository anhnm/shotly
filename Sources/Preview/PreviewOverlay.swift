import AppKit
import AVFoundation
import SwiftUI

/// Sizes for the Shottr-style preview card. The panel is sized from these up
/// front so it can be placed next to the cursor before SwiftUI lays it out.
private enum PreviewLayout {
    static let maxThumbnail = CGSize(width: 240, height: 160)
    static let minContentWidth: CGFloat = 212
    static let padding: CGFloat = 10
    static let spacing: CGFloat = 8
    static let actionRowHeight: CGFloat = 30
    static let stripHeight: CGFloat = 30
    static let cornerRadius: CGFloat = 14
    /// Transparent margin around the card so its shadow is not clipped.
    static let shadowMargin: CGFloat = 18
    /// Distance between the pointer and the card.
    static let cursorGap: CGFloat = 12

    static func thumbnailSize(aspect: CGFloat) -> CGSize {
        guard aspect.isFinite, aspect > 0 else { return maxThumbnail }
        var size = maxThumbnail
        if maxThumbnail.width / maxThumbnail.height > aspect {
            size.width = maxThumbnail.height * aspect
        } else {
            size.height = maxThumbnail.width / aspect
        }
        return CGSize(width: max(size.width.rounded(), 48), height: max(size.height.rounded(), 36))
    }

    static func cardSize(thumbnail: CGSize, showsStrip: Bool) -> CGSize {
        CGSize(
            width: max(thumbnail.width, minContentWidth) + padding * 2,
            height: padding + thumbnail.height + spacing
                + (showsStrip ? stripHeight + spacing : 0)
                + actionRowHeight + padding
        )
    }
}

/// Actions on the capture preview, with the keyboard shortcut for each. Shortcuts
/// work while the pointer is over the preview (the card then takes key focus
/// without activating Shotly).
enum PreviewAction: CaseIterable {
    case edit, copy, save, copyText, pin, collage, close, delete

    var title: String {
        switch self {
        case .edit: "Edit"
        case .copy: "Copy"
        case .save: "Save as…"
        case .copyText: "Copy text (OCR)"
        case .pin: "Pin to screen"
        case .collage: "Make collage"
        case .close: "Close"
        case .delete: "Delete…"
        }
    }

    var systemImage: String {
        switch self {
        case .edit: "pencil"
        case .copy: "doc.on.doc"
        case .save: "square.and.arrow.down"
        case .copyText: "text.viewfinder"
        case .pin: "pin"
        case .collage: "square.grid.2x2"
        case .close: "xmark"
        case .delete: "trash"
        }
    }

    var shortcut: String {
        switch self {
        case .edit: "↩"
        case .copy: "⌘C"
        case .save: "⌘S"
        case .copyText: "T"
        case .pin: "P"
        case .collage: "G"
        case .close: "Esc"
        case .delete: "⌘⌫"
        }
    }

    init?(event: NSEvent) {
        let flags = event.modifierFlags.intersection([.command, .option, .control, .shift])
        let key = event.charactersIgnoringModifiers?.lowercased()
        switch (flags, event.keyCode, key) {
        case ([], 36, _), ([], 76, _), ([], _, "e"): self = .edit
        case (.command, _, "c"): self = .copy
        case (.command, _, "s"): self = .save
        case ([], _, "t"): self = .copyText
        case ([], _, "p"): self = .pin
        case ([], _, "g"): self = .collage
        case ([], 53, _): self = .close
        case (.command, 51, _), (.command, 117, _): self = .delete
        default: return nil
        }
    }
}

/// Floating preview shown after a capture, Shottr-style: a translucent card with
/// the thumbnail and quick actions, placed next to the pointer.
@MainActor
@Observable
final class PreviewOverlay {
    static let shared = PreviewOverlay()

    private(set) var currentURL: URL?
    private(set) var previewURLs: [URL] = []
    private(set) var isVisible = false
    /// Downsampled thumbnails, keyed by file URL.
    private(set) var thumbnails: [URL: NSImage] = [:]
    private var aspectRatios: [URL: CGFloat] = [:]
    private var panel: NSPanel?
    private var dismissTask: Task<Void, Never>?
    private var targetScreen: NSScreen?
    private var outsideClickMonitors: [Any] = []
    private var keyMonitor: Any?
    private var isHovering = false
    /// Set by the card view, which owns the action implementations.
    var actionHandler: ((PreviewAction) -> Void)?
    var collageState: CollageState?

    private init() {}

    // MARK: - Layout

    var showsStrip: Bool {
        collageState == nil && previewURLs.count >= 2
    }

    var thumbnailSize: CGSize {
        if collageState != nil { return PreviewLayout.maxThumbnail }
        let aspect = currentURL.flatMap { aspectRatios[$0] } ?? 16.0 / 10.0
        return PreviewLayout.thumbnailSize(aspect: aspect)
    }

    var cardSize: CGSize {
        PreviewLayout.cardSize(thumbnail: thumbnailSize, showsStrip: showsStrip)
    }

    private var panelSize: CGSize {
        CGSize(
            width: cardSize.width + PreviewLayout.shadowMargin * 2,
            height: cardSize.height + PreviewLayout.shadowMargin * 2
        )
    }

    // MARK: - Showing

    func show(url: URL, on screen: NSScreen? = nil) {
        dismissTask?.cancel()
        dismissTask = nil

        if Self.isVideoURL(url) {
            previewURLs = [url]
            collageState = nil
        } else {
            previewURLs.removeAll(where: Self.isVideoURL)
            previewURLs.removeAll { $0.standardizedFileURL == url.standardizedFileURL }
            previewURLs.append(url)
            if previewURLs.count > 4 {
                previewURLs.removeFirst(previewURLs.count - 4)
            }

            if var collage = collageState,
               collage.slots.count < 4,
               let image = NSImage(contentsOf: url) {
                collage.slots.append(CollageSlot(image: image))
                collageState = collage
            }
        }
        thumbnails = thumbnails.filter { previewURLs.contains($0.key) }

        aspectRatios[url] = Self.aspectRatio(of: url)
        loadThumbnail(for: url)

        currentURL = url
        targetScreen = screen
        isVisible = true

        if panel == nil {
            createPanel()
        }

        positionPanelAtCursor()
        panel?.orderFrontRegardless()
        installOutsideClickMonitors()
        scheduleDismiss()
    }

    func dismiss() {
        dismissTask?.cancel()
        dismissTask = nil
        removeOutsideClickMonitors()
        if let keyMonitor {
            NSEvent.removeMonitor(keyMonitor)
            self.keyMonitor = nil
        }

        panel?.orderOut(nil)
        panel = nil
        isVisible = false
        isHovering = false
        currentURL = nil
        previewURLs = []
        thumbnails = [:]
        collageState = nil
    }

    func dismissCurrent() {
        guard let currentURL else {
            dismiss()
            return
        }

        previewURLs.removeAll { $0.standardizedFileURL == currentURL.standardizedFileURL }
        collageState = nil

        guard let nextURL = previewURLs.last else {
            dismiss()
            return
        }

        self.currentURL = nextURL
        resizePanelKeepingTopLeft()
        scheduleDismiss()
    }

    func select(url: URL) {
        guard previewURLs.contains(where: { $0.standardizedFileURL == url.standardizedFileURL }) else { return }
        currentURL = url
        collageState = nil
        resizePanelKeepingTopLeft()
        scheduleDismiss()
    }

    func startCollage(_ state: CollageState) {
        collageState = state
        resizePanelKeepingTopLeft()
    }

    func cancelCollage() {
        collageState = nil
        resizePanelKeepingTopLeft()
    }

    /// The auto-hide timer pauses while the pointer is over the card.
    func setHovering(_ hovering: Bool) {
        isHovering = hovering
        if hovering {
            dismissTask?.cancel()
            dismissTask = nil
            // Take key focus so the shortcuts work. The panel is non-activating,
            // so the app the user was in stays frontmost.
            panel?.makeKey()
        } else {
            scheduleDismiss()
        }
    }

    // MARK: - Actions

    func openAnnotateEditor() {
        AnalyticsService.track(.previewEdited)
        let screen = targetScreen
        let collage = collageState
        let url = currentURL
        if let collage = collage {
            dismiss()
            EditorWindowController.shared.open(url: nil, collage: collage, on: screen)
        } else if let url = url {
            dismissCurrent()
            if Self.isVideoURL(url) {
                VideoEditorWindowController.shared.open(url: url, on: screen)
            } else {
                EditorWindowController.shared.open(url: url, on: screen)
            }
        }
    }

    func imagesForCollage() -> [NSImage] {
        previewURLs
            .filter { !Self.isVideoURL($0) }
            .compactMap(NSImage.init(contentsOf:))
    }

    var currentIsVideo: Bool {
        currentURL.map(Self.isVideoURL) ?? false
    }

    var collageCandidateCount: Int {
        previewURLs.filter { !Self.isVideoURL($0) }.count
    }

    // MARK: - Panel

    private func createPanel() {
        let panel = PreviewPanel(
            contentRect: NSRect(origin: .zero, size: panelSize),
            styleMask: [.borderless, .nonactivatingPanel, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.level = .floating
        panel.hidesOnDeactivate = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.isMovableByWindowBackground = false
        panel.animationBehavior = .none

        panel.becomesKeyOnlyIfNeeded = false
        panel.contentView = NSHostingView(rootView: PreviewCardView(overlay: self))
        self.panel = panel

        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self, let panel = self.panel, event.window === panel,
                  let action = PreviewAction(event: event),
                  let handler = self.actionHandler else { return event }
            handler(action)
            return nil
        }
    }

    /// Places the card just below and to the right of the pointer (where a region
    /// capture ended), flipping sides when it would run off the screen.
    private func positionPanelAtCursor() {
        guard let panel else { return }
        let mouse = NSEvent.mouseLocation
        let screen = NSScreen.screens.first { $0.frame.contains(mouse) }
            ?? targetScreen
            ?? NSScreen.main
        guard let screen else { return }

        let visible = screen.visibleFrame
        let size = panelSize
        let margin = PreviewLayout.shadowMargin
        let gap = PreviewLayout.cursorGap

        var origin: CGPoint
        switch AppPreferences.overlayPosition {
        case .bottomRight:
            origin = CGPoint(x: visible.maxX - size.width, y: visible.minY)
        case .bottomLeft:
            origin = CGPoint(x: visible.minX, y: visible.minY)
        case .cursor:
            origin = CGPoint(x: mouse.x + gap - margin, y: mouse.y - gap + margin - size.height)
            if origin.x + size.width > visible.maxX {
                origin.x = mouse.x - gap + margin - size.width
            }
            if origin.y < visible.minY {
                origin.y = mouse.y + gap - margin
            }
        }
        origin.x = min(max(origin.x, visible.minX - margin), visible.maxX - size.width + margin)
        origin.y = min(max(origin.y, visible.minY - margin), visible.maxY - size.height + margin)

        panel.setFrame(NSRect(origin: origin, size: size), display: true)
    }

    /// Resizes for a different thumbnail without moving the card's top-left corner.
    private func resizePanelKeepingTopLeft() {
        guard let panel else { return }
        let size = panelSize
        let top = panel.frame.maxY
        panel.setFrame(NSRect(x: panel.frame.minX, y: top - size.height, width: size.width, height: size.height), display: true)
    }

    private func scheduleDismiss() {
        dismissTask?.cancel()
        guard AppPreferences.overlayAutoDismiss, !isHovering else { return }
        dismissTask = Task {
            try? await Task.sleep(for: .seconds(AppPreferences.overlayDismissDelay))
            guard !Task.isCancelled else { return }
            dismiss()
        }
    }

    /// With auto-hide on, clicking anywhere else hides the preview, like Shottr.
    private func installOutsideClickMonitors() {
        removeOutsideClickMonitors()
        guard AppPreferences.overlayAutoDismiss else { return }

        let mask: NSEvent.EventTypeMask = [.leftMouseDown, .rightMouseDown]
        if let global = NSEvent.addGlobalMonitorForEvents(matching: mask, handler: { [weak self] _ in
            MainActor.assumeIsolated { self?.dismiss() }
        }) {
            outsideClickMonitors.append(global)
        }
        if let local = NSEvent.addLocalMonitorForEvents(matching: mask, handler: { [weak self] event in
            // Ignore clicks in the card itself and in its context menu, which
            // AppKit tracks in its own menu window.
            if let self, let window = event.window, window !== self.panel,
               !String(describing: type(of: window)).contains("Menu") {
                self.dismiss()
            }
            return event
        }) {
            outsideClickMonitors.append(local)
        }
    }

    private func removeOutsideClickMonitors() {
        outsideClickMonitors.forEach { NSEvent.removeMonitor($0) }
        outsideClickMonitors.removeAll()
    }

    // MARK: - Thumbnails

    private func loadThumbnail(for url: URL) {
        guard thumbnails[url] == nil else { return }
        let isVideo = Self.isVideoURL(url)
        Task {
            let image = await Task.detached(priority: .userInitiated) { () -> UncheckedSendable<CGImage?> in
                UncheckedSendable(isVideo ? await Self.videoFrame(url) : Self.downsampledImage(url))
            }.value.value
            guard let image, self.previewURLs.contains(url) else { return }
            self.thumbnails[url] = NSImage(cgImage: image, size: NSSize(width: image.width, height: image.height))
            if isVideo {
                self.aspectRatios[url] = CGFloat(image.width) / CGFloat(max(image.height, 1))
                if self.currentURL == url { self.resizePanelKeepingTopLeft() }
            }
        }
    }

    private nonisolated static func downsampledImage(_ url: URL) -> CGImage? {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: 640,
        ]
        return CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary)
    }

    private nonisolated static func videoFrame(_ url: URL) async -> CGImage? {
        let generator = AVAssetImageGenerator(asset: AVURLAsset(url: url))
        generator.appliesPreferredTrackTransform = true
        generator.maximumSize = CGSize(width: 640, height: 640)
        return try? await generator.image(at: .zero).image
    }

    private static func aspectRatio(of url: URL) -> CGFloat {
        guard !isVideoURL(url),
              let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let props = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let width = props[kCGImagePropertyPixelWidth] as? CGFloat,
              let height = props[kCGImagePropertyPixelHeight] as? CGFloat,
              height > 0 else { return 16.0 / 9.0 }
        return width / height
    }

    static func isVideoURL(_ url: URL) -> Bool {
        let ext = url.pathExtension.lowercased()
        return ext == "mov" || ext == "mp4"
    }
}

/// Borderless panels cannot become key by default; the preview needs to, for its shortcuts.
private final class PreviewPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}

// MARK: - Preview Card

struct PreviewCardView: View {
    let overlay: PreviewOverlay
    @State private var isThumbnailHovered = false
    @State private var showingLayoutSelector = false
    @State private var pendingCollageImages: [NSImage] = []
    @State private var hoveredAction: PreviewAction?
    @State private var tooltipAction: PreviewAction?
    @State private var isRecognizingText = false

    var body: some View {
        let cardSize = overlay.cardSize

        VStack(spacing: PreviewLayout.spacing) {
            thumbnail
                .frame(width: overlay.thumbnailSize.width, height: overlay.thumbnailSize.height)

            if overlay.showsStrip {
                recentStrip
                    .frame(height: PreviewLayout.stripHeight)
            }

            actionRow
                .frame(height: PreviewLayout.actionRowHeight)
        }
        .padding(PreviewLayout.padding)
        .frame(width: cardSize.width, height: cardSize.height)
        .background(PreviewMaterial(cornerRadius: PreviewLayout.cornerRadius))
        .overlay(
            RoundedRectangle(cornerRadius: PreviewLayout.cornerRadius, style: .continuous)
                .strokeBorder(Color.white.opacity(0.14), lineWidth: 0.5)
        )
        .background(
            RoundedRectangle(cornerRadius: PreviewLayout.cornerRadius, style: .continuous)
                .fill(Color.black.opacity(0.001))
                .shadow(color: .black.opacity(0.35), radius: 12, y: 5)
        )
        // One tooltip centered above the action row, so it is never clipped at
        // the card's edges the way per-button tooltips would be.
        .overlay(alignment: .bottom) {
            if isRecognizingText {
                HStack(spacing: 6) {
                    ProgressView().controlSize(.small)
                    Text("Recognizing text…")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(.white)
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 5)
                .background(Color.black.opacity(0.85), in: RoundedRectangle(cornerRadius: 6, style: .continuous))
                .padding(.bottom, PreviewLayout.padding + PreviewLayout.actionRowHeight + 6)
            } else if let tooltipAction {
                ShortcutTooltip(title: tooltipAction.title, shortcut: tooltipAction.shortcut)
                    .padding(.bottom, PreviewLayout.padding + PreviewLayout.actionRowHeight + 6)
            }
        }
        .task(id: hoveredAction) {
            guard let hoveredAction else {
                tooltipAction = nil
                return
            }
            // Short delay so moving across the row does not flash every tooltip,
            // but switch immediately once one is showing.
            if tooltipAction == nil {
                try? await Task.sleep(for: .milliseconds(350))
                guard !Task.isCancelled else { return }
            }
            tooltipAction = hoveredAction
        }
        .onHover { overlay.setHovering($0) }
        .onAppear { overlay.actionHandler = perform }
        .padding(PreviewLayout.shadowMargin)
        .environment(\.colorScheme, .dark)
    }

    /// Runs an action from a button or a keyboard shortcut.
    private func perform(_ action: PreviewAction) {
        switch action {
        case .edit: overlay.openAnnotateEditor()
        case .copy: if overlay.collageState == nil { copyCurrent() }
        case .save: if overlay.collageState == nil { saveCurrentCapture() }
        case .copyText: if overlay.collageState == nil && !overlay.currentIsVideo { copyRecognizedText() }
        case .pin: if overlay.collageState == nil && !overlay.currentIsVideo { pinCurrent() }
        case .collage: if overlay.collageState == nil && overlay.collageCandidateCount >= 2 { prepareRecentCollage() }
        case .close:
            if showingLayoutSelector {
                showingLayoutSelector = false
                pendingCollageImages = []
            } else if overlay.collageState != nil {
                overlay.cancelCollage()
            } else {
                overlay.dismissCurrent()
            }
        case .delete: if overlay.collageState == nil { confirmDelete() }
        }
    }

    private func actionButton(_ action: PreviewAction, title: String? = nil) -> some View {
        PreviewActionButton(systemImage: action.systemImage, accessibilityTitle: title ?? action.title) {
            perform(action)
        }
        .onHover { hovering in
            if hovering {
                hoveredAction = action
            } else if hoveredAction == action {
                hoveredAction = nil
            }
        }
    }

    // MARK: Thumbnail

    private var thumbnail: some View {
        ZStack {
            Group {
                if let collage = overlay.collageState {
                    CollageThumbnailView(state: collage, size: overlay.thumbnailSize)
                } else if let url = overlay.currentURL, let image = overlay.thumbnails[url] {
                    Image(nsImage: image)
                        .resizable()
                        .interpolation(.high)
                        .aspectRatio(contentMode: .fill)
                } else {
                    Color.white.opacity(0.06)
                }
            }
            .frame(width: overlay.thumbnailSize.width, height: overlay.thumbnailSize.height)
            .clipped()

            if overlay.currentIsVideo && overlay.collageState == nil {
                Image(systemName: "play.circle.fill")
                    .font(.system(size: 30))
                    .foregroundStyle(.white.opacity(0.9))
                    .shadow(radius: 4)
            }

            if isThumbnailHovered && !showingLayoutSelector {
                VStack {
                    HStack {
                        Spacer()
                        Button {
                            perform(.close)
                        } label: {
                            Image(systemName: "xmark")
                                .font(.system(size: 10, weight: .bold))
                                .foregroundStyle(.white)
                                .frame(width: 22, height: 22)
                                .background(Color.black.opacity(0.6), in: Circle())
                        }
                        .buttonStyle(.plain)
                        .help("Close (Esc)")
                        .accessibilityLabel("Close preview")
                    }
                    Spacer()
                }
                .padding(6)
            }

            if showingLayoutSelector, pendingCollageImages.count >= 2 {
                layoutSelector
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .strokeBorder(Color.white.opacity(0.12), lineWidth: 0.5)
        )
        .contentShape(Rectangle())
        .onHover { isThumbnailHovered = $0 }
        .onTapGesture {
            if !showingLayoutSelector {
                overlay.openAnnotateEditor()
            }
        }
        .onDrag {
            if let url = overlay.currentURL {
                return NSItemProvider(object: url as NSURL)
            }
            return NSItemProvider()
        }
        .onDrop(of: [.fileURL, .image], isTargeted: nil, perform: handleDrop)
        .contextMenu { contextMenu }
        .help("Click to edit (↩) · drag into any app")
    }

    private var layoutSelector: some View {
        ZStack {
            Color.black.opacity(0.78)
            VStack(spacing: 8) {
                Text("Choose collage layout")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.white)
                HStack(spacing: 6) {
                    layoutButton("Vertical", icon: "square.split.2x1") {
                        beginCollage(layout: .vertical, images: pendingCollageImages)
                    }
                    layoutButton("Horizontal", icon: "square.split.1x2") {
                        beginCollage(layout: .horizontal, images: pendingCollageImages)
                    }
                    layoutButton("Grid", icon: "square.grid.2x2") {
                        beginCollage(layout: .grid2x2, images: Array(pendingCollageImages.prefix(4)))
                    }
                }
                Button("Cancel") {
                    showingLayoutSelector = false
                    pendingCollageImages = []
                }
                .buttonStyle(.plain)
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(.white.opacity(0.7))
            }
        }
    }

    // MARK: Recent captures strip

    private var recentStrip: some View {
        HStack(spacing: 6) {
            ForEach(overlay.previewURLs, id: \.self) { url in
                let isCurrent = url.standardizedFileURL == overlay.currentURL?.standardizedFileURL
                Button {
                    overlay.select(url: url)
                } label: {
                    Group {
                        if let image = overlay.thumbnails[url] {
                            Image(nsImage: image)
                                .resizable()
                                .aspectRatio(contentMode: .fill)
                        } else {
                            Color.white.opacity(0.08)
                        }
                    }
                    .frame(width: 40, height: 28)
                    .clipShape(RoundedRectangle(cornerRadius: 5, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 5, style: .continuous)
                            .strokeBorder(isCurrent ? Color.accentColor : Color.white.opacity(0.18), lineWidth: isCurrent ? 2 : 0.5)
                    )
                }
                .buttonStyle(.plain)
                .help(isCurrent ? "Current capture" : "Show this capture")
                .accessibilityLabel(isCurrent ? "Current capture" : "Show earlier capture")
            }
            Spacer(minLength: 0)
        }
    }

    // MARK: Actions

    @ViewBuilder
    private var actionRow: some View {
        HStack(spacing: 4) {
            if overlay.collageState != nil {
                actionButton(.edit, title: "Edit collage")
                actionButton(.close, title: "Cancel collage")
            } else {
                actionButton(.edit)
                actionButton(.copy)
                actionButton(.save)
                if !overlay.currentIsVideo {
                    actionButton(.copyText)
                    actionButton(.pin)
                }
                if overlay.collageCandidateCount >= 2 {
                    actionButton(.collage, title: "Collage of \(overlay.collageCandidateCount) captures")
                }
            }
        }
        .frame(maxWidth: .infinity)
    }

    @ViewBuilder
    private var contextMenu: some View {
        Button("Edit") { perform(.edit) }
            .keyboardShortcut(.return, modifiers: [])
        Button("Copy") { perform(.copy) }
            .keyboardShortcut("c", modifiers: .command)
        Button("Save as…") { perform(.save) }
            .keyboardShortcut("s", modifiers: .command)
        if !overlay.currentIsVideo {
            Button("Copy Text (OCR)") { perform(.copyText) }
                .keyboardShortcut("t", modifiers: [])
            Button("Pin to Screen") { perform(.pin) }
                .keyboardShortcut("p", modifiers: [])
        }
        Divider()
        Button("Delete…", role: .destructive) { perform(.delete) }
            .keyboardShortcut(.delete, modifiers: .command)
        Button("Close") { perform(.close) }
            .keyboardShortcut(.escape, modifiers: [])
    }

    private func copyCurrent() {
        guard let url = overlay.currentURL else { return }
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        if overlay.currentIsVideo {
            pasteboard.writeObjects([url as NSURL])
        } else if let image = NSImage(contentsOf: url) {
            pasteboard.writeObjects([image])
        }
        AnalyticsService.track(.previewCopied)
        overlay.dismissCurrent()
        toast(title: "Copied", message: "Capture copied to clipboard", icon: "doc.on.doc")
    }

    private func saveCurrentCapture() {
        guard let sourceURL = overlay.currentURL,
              ImageSavePanel.copyFile(from: sourceURL) != nil else { return }
        AnalyticsService.track(.previewSaved)
        overlay.dismissCurrent()
        toast(title: "Saved", message: "Image saved to the selected location", icon: "square.and.arrow.down")
    }

    private func pinCurrent() {
        guard let url = overlay.currentURL else { return }
        PinnedScreenshotController.shared.pin(url: url)
        AnalyticsService.track(.previewPinned)
        overlay.dismissCurrent()
    }

    /// Recognizes text in the capture and replaces the clipboard (which still holds
    /// the image from the capture) with it. Shows progress, since the first run
    /// after boot can take a while.
    private func copyRecognizedText() {
        guard !isRecognizingText,
              let url = overlay.currentURL,
              let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else { return }
        isRecognizingText = true
        overlay.setHovering(true)
        Task {
            let text = (try? await ScreenCapture.shared.recognizeContent(in: image)) ?? ""
            isRecognizingText = false
            let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else {
                overlay.setHovering(false)
                toast(title: "No text found", message: "Couldn't recognize any text in this capture", icon: "text.viewfinder")
                return
            }
            let pasteboard = NSPasteboard.general
            pasteboard.clearContents()
            pasteboard.setString(trimmed, forType: .string)
            AnalyticsService.track(.ocrCompleted)
            let lines = trimmed.split(whereSeparator: \.isNewline).count
            overlay.dismissCurrent()
            toast(title: "Text copied", message: "\(lines) line\(lines == 1 ? "" : "s") of text copied to clipboard", icon: "text.viewfinder")
        }
    }

    /// Deleting removes the file and its history entry, so ask first.
    private func confirmDelete() {
        guard let url = overlay.currentURL else { return }
        let alert = NSAlert()
        alert.messageText = "Delete this capture?"
        alert.informativeText = "The file is removed from disk and from your capture history. This can't be undone."
        alert.alertStyle = .warning
        alert.addButton(withTitle: "Delete").hasDestructiveAction = true
        alert.addButton(withTitle: "Cancel")
        NSApp.activate()
        guard alert.runModal() == .alertFirstButtonReturn else { return }

        if let record = HistoryStore.shared.records.first(where: { HistoryStore.shared.urlForRecord($0) == url }) {
            HistoryStore.shared.deleteRecord(record)
        } else {
            try? FileManager.default.removeItem(at: url)
        }
        overlay.dismissCurrent()
    }

    private func toast(title: String, message: String, icon: String) {
        let screen = NSScreen.screens.first { $0.frame.contains(NSEvent.mouseLocation) } ?? NSScreen.main
        ToastWindow.shared.show(title: title, message: message, systemIcon: icon, duration: 1.6, on: screen)
    }

    // MARK: Collage

    private func handleDrop(_ providers: [NSItemProvider]) -> Bool {
        guard overlay.collageState.map({ !$0.isLocked }) ?? true else { return false }
        for provider in providers {
            if provider.canLoadObject(ofClass: URL.self) {
                _ = provider.loadObject(ofClass: URL.self) { url, _ in
                    guard let url, let image = NSImage(contentsOf: url) else { return }
                    DispatchQueue.main.async { handleDroppedImage(image) }
                }
                return true
            } else if provider.canLoadObject(ofClass: NSImage.self) {
                _ = provider.loadObject(ofClass: NSImage.self) { image, _ in
                    guard let image = image as? NSImage else { return }
                    DispatchQueue.main.async { handleDroppedImage(image) }
                }
                return true
            }
        }
        return false
    }

    private func handleDroppedImage(_ image: NSImage) {
        if var current = overlay.collageState {
            if current.layoutType == .grid2x2 && current.slots.count >= 4 { return }
            current.slots.append(CollageSlot(image: image))
            overlay.collageState = current
        } else if let url = overlay.currentURL, let currentImage = NSImage(contentsOf: url) {
            pendingCollageImages = [currentImage, image]
            showingLayoutSelector = true
        }
    }

    private func beginCollage(layout: CollageLayoutType, images: [NSImage]) {
        AnalyticsService.track(.collageStarted, properties: [
            "image_count": "\(images.count)",
            "layout": layout.rawValue,
        ])
        overlay.startCollage(CollageState(layoutType: layout, slots: images.map { CollageSlot(image: $0) }))
        showingLayoutSelector = false
        pendingCollageImages = []
    }

    private func prepareRecentCollage() {
        let images = overlay.imagesForCollage()
        guard images.count >= 2 else { return }
        pendingCollageImages = images
        showingLayoutSelector = true
    }

    private func layoutButton(_ title: String, icon: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 4) {
                Image(systemName: icon)
                    .font(.system(size: 14))
                Text(title)
                    .font(.system(size: 9, weight: .medium))
            }
            .frame(width: 52, height: 44)
            .background(Color.white.opacity(0.12), in: RoundedRectangle(cornerRadius: 6))
        }
        .buttonStyle(.plain)
        .foregroundStyle(.white)
    }
}

private struct PreviewActionButton: View {
    let systemImage: String
    let accessibilityTitle: String
    let action: () -> Void
    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: 14, weight: .regular))
                .foregroundStyle(.white.opacity(0.92))
                .frame(width: 32, height: 28)
                .background(
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(Color.white.opacity(isHovered ? 0.14 : 0))
                )
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
        .accessibilityLabel(accessibilityTitle)
    }
}

/// Translucent HUD material behind the card, rounded with a mask image so the
/// behind-window blur respects the corners.
private struct PreviewMaterial: NSViewRepresentable {
    let cornerRadius: CGFloat

    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = .hudWindow
        view.blendingMode = .behindWindow
        view.state = .active
        view.maskImage = Self.mask(radius: cornerRadius)
        return view
    }

    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {}

    private static func mask(radius: CGFloat) -> NSImage {
        let edge = radius * 2 + 1
        let image = NSImage(size: NSSize(width: edge, height: edge), flipped: false) { rect in
            NSColor.black.setFill()
            NSBezierPath(roundedRect: rect, xRadius: radius, yRadius: radius).fill()
            return true
        }
        image.capInsets = NSEdgeInsets(top: radius, left: radius, bottom: radius, right: radius)
        image.resizingMode = .stretch
        return image
    }
}

struct CollageThumbnailView: View {
    let state: CollageState
    let size: CGSize
    
    var body: some View {
        let gap = min(8, max(1.5, state.spacing / 4))
        switch state.layoutType {
        case .vertical:
            VStack(spacing: gap) {
                ForEach(state.slots) { slot in
                    Image(nsImage: slot.image)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .clipped()
                }
            }
            .frame(width: size.width, height: size.height)
        case .horizontal:
            HStack(spacing: gap) {
                ForEach(state.slots) { slot in
                    Image(nsImage: slot.image)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .clipped()
                }
            }
            .frame(width: size.width, height: size.height)
        case .grid2x2:
            LazyVGrid(columns: [GridItem(.flexible(), spacing: gap), GridItem(.flexible(), spacing: gap)], spacing: gap) {
                ForEach(0..<4) { index in
                    if index < state.slots.count {
                        Image(nsImage: state.slots[index].image)
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                            .clipped()
                    } else {
                        Color.black.opacity(0.12)
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                    }
                }
            }
            .frame(width: size.width, height: size.height)
        }
    }
}
