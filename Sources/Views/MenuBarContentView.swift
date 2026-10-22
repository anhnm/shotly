import SwiftUI

// MARK: - Panel Root (Arrow + Body)

struct MenuBarPanelView: View {
    var dismissPopover: @MainActor () -> Void
    @State private var isVisible = false

    private let arrowWidth: CGFloat = 22
    private let arrowHeight: CGFloat = 10
    private let panelRadius: CGFloat = 12

    var body: some View {
        VStack(spacing: 0) {
            PopoverArrow()
                .fill(Color(nsColor: .windowBackgroundColor))
                .frame(width: arrowWidth, height: arrowHeight)

            MenuBarContentView(dismissPopover: dismissPopover)
                .background(Color(nsColor: .windowBackgroundColor))
                .clipShape(RoundedRectangle(cornerRadius: panelRadius, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: panelRadius, style: .continuous)
                        .strokeBorder(Color.primary.opacity(0.08), lineWidth: 0.5)
                )
        }
        .shadow(color: .black.opacity(0.18), radius: 20, y: 8)
        .shadow(color: .black.opacity(0.08), radius: 4, y: 2)
        .scaleEffect(isVisible ? 1 : 0.92, anchor: .top)
        .opacity(isVisible ? 1 : 0)
        .blur(radius: isVisible ? 0 : 4)
        .onAppear {
            withAnimation(.spring(response: 0.28, dampingFraction: 0.82)) {
                isVisible = true
            }
        }
    }
}

// MARK: - Arrow Shape

private struct PopoverArrow: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        let radius: CGFloat = 2.5
        path.move(to: CGPoint(x: rect.minX, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.midX - radius, y: rect.minY + radius))
        path.addQuadCurve(
            to: CGPoint(x: rect.midX + radius, y: rect.minY + radius),
            control: CGPoint(x: rect.midX, y: rect.minY)
        )
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
        path.closeSubpath()
        return path
    }
}

// MARK: - Panel Content

struct MenuBarContentView: View {
    var dismissPopover: @MainActor () -> Void

    var body: some View {
        VStack(spacing: 0) {
            captureGrid
                .padding(.horizontal, 10)
                .padding(.top, 10)
                .padding(.bottom, 8)

            TrayDivider()

            utilityGrid
                .padding(.horizontal, 10)
                .padding(.vertical, 8)

            if case .available(let manifest) = AppUpdater.shared.state {
                TrayDivider()

                TrayFullWidthButton(title: "Update to Shotly \(manifest.version)", icon: "arrow.down.circle") {
                    dismissPopover()
                    UpdateWindowController.shared.show()
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 4)
            }

            if PinnedScreenshotController.shared.hasPinnedWindows {
                TrayDivider()

                TrayFullWidthButton(title: "Unpin All", icon: "pin.slash") {
                    PinnedScreenshotController.shared.unpinAll()
                    dismissPopover()
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 4)
            }

            TrayDivider()

            footerGrid
                .padding(.horizontal, 10)
                .padding(.vertical, 8)

            TrayDivider()

            versionRow
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
        }
        .frame(width: 320)
    }

    // MARK: - Capture Grid

    private var captureGrid: some View {
        let columns = [
            GridItem(.flexible(), spacing: 6),
            GridItem(.flexible(), spacing: 6),
        ]

        return LazyVGrid(columns: columns, spacing: 6) {
            TrayGridButton(title: "Region", icon: "rectangle.dashed", shortcut: shortcutLabel(for: .region, default: .defaultRegion)) {
                dismissAndRun(.region)
            }

            TrayGridButton(title: "Screen", icon: "desktopcomputer", shortcut: shortcutLabel(for: .fullscreen, default: .defaultFullscreen)) {
                dismissAndRun(.fullscreen)
            }

            TrayGridButton(title: "Window", icon: "macwindow", shortcut: shortcutLabel(for: .window, default: .defaultWindow)) {
                dismissAndRun(.window)
            }

            TrayGridButton(title: "Pick Color", icon: "eyedropper", shortcut: shortcutLabel(for: .colorPicker, default: .defaultColorPicker)) {
                dismissAndRun(.colorPicker)
            }

            TrayGridMenu(title: "Record", icon: "record.circle", shortcut: shortcutLabel(for: .recording, default: .defaultRecording), menuItems: [
                TrayMenuItem(title: "Full Screen", icon: "desktopcomputer") {
                    let screen = originScreen
                    dismissPopover()
                    Task { @MainActor in
                        try? await Task.sleep(for: .milliseconds(150))
                        await startRecording(mode: .fullScreen, on: screen)
                    }
                },
                TrayMenuItem(title: "Area", icon: "rectangle.dashed") {
                    let screen = originScreen
                    dismissPopover()
                    Task { @MainActor in
                        try? await Task.sleep(for: .milliseconds(150))
                        await startRecording(mode: .area, on: screen)
                    }
                },
            ])

            TrayGridButton(title: "Editor", icon: "square.and.pencil") {
                let screen = originScreen
                dismissPopover()
                EditorWindowController.shared.open(url: nil, on: screen)
            }
        }
    }

    // MARK: - Utility Grid

    private var recentScreenshots: [CaptureRecord] {
        HistoryStore.shared.records.filter { $0.kind == .screenshot }
    }

    private var recentRecordings: [CaptureRecord] {
        HistoryStore.shared.records.filter { $0.kind == .recording }
    }

    private var utilityGrid: some View {
        let columns = [
            GridItem(.flexible(), spacing: 6),
            GridItem(.flexible(), spacing: 6),
        ]

        return LazyVGrid(columns: columns, spacing: 6) {
            TrayGridButton(title: "OCR", icon: "doc.text.viewfinder", shortcut: shortcutLabel(for: .ocr, default: .defaultOCR)) {
                dismissAndRun(.ocr)
            }

            TrayGridMenu(title: "Recent", icon: "clock.arrow.circlepath", menuItems: recentMenuItems())
        }
    }

    // MARK: - Footer

    private var footerGrid: some View {
        let columns = [
            GridItem(.flexible(), spacing: 6),
            GridItem(.flexible(), spacing: 6),
        ]

        return LazyVGrid(columns: columns, spacing: 6) {
            TrayGridButton(title: "Settings", icon: "gearshape", shortcut: "\u{2318},") {
                openSettings()
            }

            TrayGridButton(title: "Quit", icon: "power", shortcut: "\u{2318}Q") {
                NSApplication.shared.terminate(nil)
            }
        }
    }

    // MARK: - Version

    /// Version on the left; on the right, a one-click update check and its result.
    private var versionRow: some View {
        let updater = AppUpdater.shared
        return HStack(spacing: 8) {
            Text("Shotly \(updater.currentVersion)")
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.secondary)

            Spacer(minLength: 8)

            switch updater.state {
            case .checking:
                HStack(spacing: 5) {
                    ProgressView().controlSize(.mini)
                    Text("Checking…")
                }
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
            case .upToDate:
                Label("Up to date", systemImage: "checkmark.circle.fill")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.secondary)
            case .available, .downloading, .installing:
                EmptyView()
            default:
                Button {
                    Task { await updater.checkForUpdates(userInitiated: true) }
                } label: {
                    Text("Check for Updates")
                        .font(.system(size: 11, weight: .medium))
                }
                .buttonStyle(.link)
            }
        }
    }

    // MARK: - Actions

    private var originScreen: NSScreen? {
        MenuBarPopoverController.shared.originScreen
    }

    private func shortcutLabel(
        for action: ShortcutService.Action,
        default defaultShortcut: ShortcutService.Shortcut
    ) -> String? {
        let shortcut = ShortcutService.shared.loadShortcut(for: action) ?? defaultShortcut
        return shortcut.enabled ? shortcut.displayString : nil
    }

    private func dismissAndRun(_ action: ShortcutService.Action) {
        let screen = originScreen
        dismissPopover()
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(150))
            await CaptureOrchestrator.shared.performCapture(action, on: screen)
        }
    }

    private func recentMenuItems() -> [TrayMenuItem] {
        var items: [TrayMenuItem] = []

        var screenshotItems: [TrayMenuItem] = []
        if recentScreenshots.isEmpty {
            screenshotItems.append(TrayMenuItem(title: "No screenshots yet", icon: "photo", action: {}, isDisabled: true))
        } else {
            for record in recentScreenshots.prefix(8) {
                screenshotItems.append(TrayMenuItem(title: record.filename, icon: "photo") { [record] in
                    let screen = originScreen
                    dismissPopover()
                    let url = HistoryStore.shared.displayURLForRecord(record)
                    PreviewOverlay.shared.show(url: url, on: screen)
                })
            }
            screenshotItems.append(.separator())
            screenshotItems.append(TrayMenuItem(title: "Clear Screenshots", icon: "trash", action: {
                HistoryStore.shared.records
                    .filter { $0.kind == .screenshot }
                    .forEach { HistoryStore.shared.deleteRecord($0) }
            }, isDestructive: true))
        }
        items.append(TrayMenuItem(title: "Screenshots", icon: "photo.on.rectangle", action: {}, submenu: screenshotItems))

        var recordingItems: [TrayMenuItem] = []
        if recentRecordings.isEmpty {
            recordingItems.append(TrayMenuItem(title: "No recordings yet", icon: "video", action: {}, isDisabled: true))
        } else {
            for record in recentRecordings.prefix(8) {
                recordingItems.append(TrayMenuItem(title: record.filename, icon: "video") { [record] in
                    let screen = originScreen
                    dismissPopover()
                    let url = HistoryStore.shared.displayURLForRecord(record)
                    PreviewOverlay.shared.show(url: url, on: screen)
                })
            }
            recordingItems.append(.separator())
            recordingItems.append(TrayMenuItem(title: "Clear Recordings", icon: "trash", action: {
                HistoryStore.shared.records
                    .filter { $0.kind == .recording }
                    .forEach { HistoryStore.shared.deleteRecord($0) }
            }, isDestructive: true))
        }
        items.append(TrayMenuItem(title: "Recordings", icon: "video.circle", action: {}, submenu: recordingItems))

        return items
    }

    private func openSettings() {
        let screen = originScreen
        dismissPopover()
        SettingsWindowController.shared.open(on: screen)
    }

    private enum RecordingMode {
        case fullScreen, area
    }

    @MainActor
    private func startRecording(mode: RecordingMode = .fullScreen, on screen: NSScreen? = nil) async {
        do {
            let started: Bool
            switch mode {
            case .fullScreen:
                started = try await ScreenRecordingManager.shared.startFullScreenRecording()
            case .area:
                started = try await ScreenRecordingManager.shared.startAreaRecording()
            }
            if started {
                RecordingStatusBarController.shared.show(on: screen)
            }
        } catch {
            print("Recording failed: \(error.localizedDescription)")
        }
    }

}

// MARK: - Grid Button

struct TrayGridButton: View {
    let title: String
    let icon: String
    var shortcut: String? = nil
    let action: () -> Void

    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Image(systemName: icon)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.primary.opacity(0.7))
                    .frame(width: 16)

                Text(title)
                    .font(.system(size: 12, weight: .medium))
                    .lineLimit(1)

                Spacer(minLength: 2)

                if let shortcut {
                    ShortcutKeycaps(shortcut: shortcut, isHighlighted: isHovered)
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 8)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(isHovered ? Color.primary.opacity(0.15) : Color.primary.opacity(0.08))
            )
            .contentShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
    }
}

// MARK: - Shortcut keycaps

/// Shows a shortcut such as "⌘⇧4" as one small key per symbol, readable at a glance.
struct ShortcutKeycaps: View {
    let shortcut: String
    var isHighlighted = false

    var body: some View {
        HStack(spacing: 2) {
            ForEach(Array(TrayShortcut.keys(in: shortcut).enumerated()), id: \.offset) { _, key in
                Text(key)
                    .font(.system(size: 11, weight: .semibold, design: .rounded))
                    .foregroundStyle(.primary.opacity(isHighlighted ? 0.85 : 0.6))
                    .frame(minWidth: 17, minHeight: 18)
                    .padding(.horizontal, 2)
                    .background(
                        RoundedRectangle(cornerRadius: 4, style: .continuous)
                            .fill(Color.primary.opacity(isHighlighted ? 0.14 : 0.09))
                    )
            }
        }
        .accessibilityLabel("Shortcut \(shortcut)")
    }
}

enum TrayShortcut {
    /// "⌘⇧4" → ["⌘", "⇧", "4"]; a trailing key name of several letters stays whole.
    static func keys(in shortcut: String) -> [String] {
        let modifiers: Set<Character> = ["⌘", "⇧", "⌥", "⌃"]
        var keys: [String] = []
        var rest = ""
        for character in shortcut {
            if modifiers.contains(character) { keys.append(String(character)) } else { rest.append(character) }
        }
        if !rest.isEmpty { keys.append(rest) }
        return keys
    }
}

// MARK: - Grid Menu (dropdown matching grid button style via NSMenu)

struct TrayGridMenu: NSViewRepresentable {
    let title: String
    let icon: String
    var shortcut: String? = nil
    let menuItems: [TrayMenuItem]

    func makeNSView(context: Context) -> TrayGridMenuButton {
        let button = TrayGridMenuButton(title: title, icon: icon, menuItems: menuItems)
        button.shortcut = shortcut
        return button
    }

    func updateNSView(_ nsView: TrayGridMenuButton, context: Context) {
        nsView.menuItems = menuItems
        if nsView.shortcut != shortcut {
            nsView.shortcut = shortcut
            nsView.needsDisplay = true
        }
    }
}

struct TrayMenuItem {
    let title: String
    let icon: String
    let action: () -> Void
    var isDestructive: Bool = false
    var isSeparator: Bool = false
    var isDisabled: Bool = false
    var submenu: [TrayMenuItem]? = nil

    static func separator() -> TrayMenuItem {
        TrayMenuItem(title: "", icon: "", action: {}, isSeparator: true)
    }
}

final class TrayGridMenuButton: NSView {
    var menuItems: [TrayMenuItem]
    var shortcut: String?
    private let titleText: String
    private let iconName: String
    private var isHovered = false
    private var trackingArea: NSTrackingArea?

    init(title: String, icon: String, menuItems: [TrayMenuItem]) {
        self.titleText = title
        self.iconName = icon
        self.menuItems = menuItems
        super.init(frame: .zero)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    override var intrinsicContentSize: NSSize {
        NSSize(width: NSView.noIntrinsicMetric, height: 32)
    }

    override func updateTrackingAreas() {
        if let existing = trackingArea { removeTrackingArea(existing) }
        let area = NSTrackingArea(rect: bounds, options: [.mouseEnteredAndExited, .activeAlways], owner: self)
        addTrackingArea(area)
        trackingArea = area
        super.updateTrackingAreas()
    }

    override func mouseEntered(with event: NSEvent) {
        isHovered = true
        needsDisplay = true
    }

    override func mouseExited(with event: NSEvent) {
        isHovered = false
        needsDisplay = true
    }

    override func mouseDown(with event: NSEvent) {
        let menu = NSMenu()
        for item in menuItems {
            if item.isSeparator {
                menu.addItem(.separator())
                continue
            }
            if let submenuItems = item.submenu {
                let parentItem = NSMenuItem(title: item.title, action: nil, keyEquivalent: "")
                if let img = NSImage(systemSymbolName: item.icon, accessibilityDescription: nil) {
                    parentItem.image = img
                }
                let sub = NSMenu()
                for subItem in submenuItems {
                    if subItem.isSeparator {
                        sub.addItem(.separator())
                        continue
                    }
                    let mi = NSMenuItem(title: subItem.title, action: #selector(menuAction(_:)), keyEquivalent: "")
                    mi.target = self
                    mi.representedObject = subItem.action
                    if let img = NSImage(systemSymbolName: subItem.icon, accessibilityDescription: nil) {
                        mi.image = img
                    }
                    if subItem.isDestructive {
                        mi.attributedTitle = NSAttributedString(string: subItem.title, attributes: [.foregroundColor: NSColor.systemRed])
                    }
                    mi.isEnabled = !subItem.isDisabled
                    sub.addItem(mi)
                }
                parentItem.submenu = sub
                menu.addItem(parentItem)
            } else {
                let mi = NSMenuItem(title: item.title, action: #selector(menuAction(_:)), keyEquivalent: "")
                mi.target = self
                mi.representedObject = item.action
                if let img = NSImage(systemSymbolName: item.icon, accessibilityDescription: nil) {
                    mi.image = img
                }
                if item.isDestructive {
                    mi.attributedTitle = NSAttributedString(string: item.title, attributes: [.foregroundColor: NSColor.systemRed])
                }
                mi.isEnabled = !item.isDisabled
                menu.addItem(mi)
            }
        }
        let point = NSPoint(x: 0, y: bounds.height + 4)
        menu.popUp(positioning: nil, at: point, in: self)
    }

    @objc private func menuAction(_ sender: NSMenuItem) {
        if let action = sender.representedObject as? () -> Void {
            action()
        }
    }

    override func draw(_ dirtyRect: NSRect) {
        let bgColor: NSColor = isHovered
            ? NSColor.labelColor.withAlphaComponent(0.15)
            : NSColor.labelColor.withAlphaComponent(0.08)

        let path = NSBezierPath(roundedRect: bounds, xRadius: 8, yRadius: 8)
        bgColor.setFill()
        path.fill()

        let iconColor = NSColor.labelColor.withAlphaComponent(0.7)
        let iconConfig = NSImage.SymbolConfiguration(pointSize: 12, weight: .medium)

        let iconX: CGFloat = 8
        let textX: CGFloat = 30
        let chevronWidth: CGFloat = 20
        let centerY = bounds.midY

        if let img = NSImage(systemSymbolName: iconName, accessibilityDescription: nil)?
            .withSymbolConfiguration(iconConfig) {
            let tinted = tintImage(img, color: iconColor)
            let imgSize = tinted.size
            let imgRect = NSRect(x: iconX, y: centerY - imgSize.height / 2, width: imgSize.width, height: imgSize.height)
            tinted.draw(in: imgRect)
        }

        let attrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 12, weight: .medium),
            .foregroundColor: NSColor.labelColor,
        ]
        let textSize = (titleText as NSString).size(withAttributes: attrs)
        let textPoint = NSPoint(x: textX, y: centerY - textSize.height / 2)
        (titleText as NSString).draw(at: textPoint, withAttributes: attrs)

        let chevronColor = NSColor.labelColor.withAlphaComponent(0.25)
        let chevronConfig = NSImage.SymbolConfiguration(pointSize: 8, weight: .bold)
        if let chevron = NSImage(systemSymbolName: "chevron.down", accessibilityDescription: nil)?
            .withSymbolConfiguration(chevronConfig) {
            let tinted = tintImage(chevron, color: chevronColor)
            let chevronSize = tinted.size
            let chevronRect = NSRect(
                x: bounds.maxX - chevronWidth,
                y: centerY - chevronSize.height / 2,
                width: chevronSize.width,
                height: chevronSize.height
            )
            tinted.draw(in: chevronRect)
        }

        // Keycaps for the shortcut, drawn to match ShortcutKeycaps, left of the chevron.
        if let shortcut {
            let keyFont = NSFont.systemFont(ofSize: 11, weight: .semibold)
            let roundedFont = keyFont.fontDescriptor.withDesign(.rounded).flatMap { NSFont(descriptor: $0, size: 11) } ?? keyFont
            let keyAttrs: [NSAttributedString.Key: Any] = [
                .font: roundedFont,
                .foregroundColor: NSColor.labelColor.withAlphaComponent(isHovered ? 0.85 : 0.6),
            ]
            let keys = TrayShortcut.keys(in: shortcut)
            let widths = keys.map { max(17, ($0 as NSString).size(withAttributes: keyAttrs).width) + 4 }
            var x = bounds.maxX - chevronWidth - 6 - widths.reduce(0, +) - CGFloat(max(0, keys.count - 1)) * 2
            for (key, width) in zip(keys, widths) {
                let capRect = NSRect(x: x, y: centerY - 9, width: width, height: 18)
                NSColor.labelColor.withAlphaComponent(isHovered ? 0.14 : 0.09).setFill()
                NSBezierPath(roundedRect: capRect, xRadius: 4, yRadius: 4).fill()
                let size = (key as NSString).size(withAttributes: keyAttrs)
                (key as NSString).draw(at: NSPoint(x: capRect.midX - size.width / 2, y: capRect.midY - size.height / 2), withAttributes: keyAttrs)
                x += width + 2
            }
        }
    }

    private func tintImage(_ image: NSImage, color: NSColor) -> NSImage {
        let tinted = image.copy() as! NSImage
        tinted.isTemplate = false
        tinted.lockFocus()
        color.set()
        let rect = NSRect(origin: .zero, size: tinted.size)
        rect.fill(using: .sourceAtop)
        tinted.unlockFocus()
        return tinted
    }
}

// MARK: - Full Width Button

private struct TrayFullWidthButton: View {
    let title: String
    let icon: String
    let action: () -> Void

    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Image(systemName: icon)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.primary.opacity(0.7))
                    .frame(width: 16)

                Text(title)
                    .font(.system(size: 12, weight: .medium))

                Spacer()
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 8)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(isHovered ? Color.primary.opacity(0.15) : Color.primary.opacity(0.08))
            )
            .contentShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
    }
}

// MARK: - Divider

private struct TrayDivider: View {
    var body: some View {
        Divider()
            .padding(.horizontal, 12)
    }
}
