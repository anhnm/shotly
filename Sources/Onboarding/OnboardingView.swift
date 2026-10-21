import SwiftUI
import AppKit
import CoreGraphics
import Carbon

@MainActor
final class OnboardingWindowController: NSObject, NSWindowDelegate {
    static let shared = OnboardingWindowController()

    private var window: NSWindow?

    private override init() { super.init() }

    func open() {
        if let existing = window, existing.isVisible {
            existing.orderFrontRegardless()
            NSApp.activate(ignoringOtherApps: true)
            existing.makeKeyAndOrderFront(nil)
            return
        }

        let win = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 460, height: 600),
            styleMask: [.titled, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        win.isOpaque = false
        win.backgroundColor = .clear
        win.hasShadow = true
        win.titlebarAppearsTransparent = true
        win.titleVisibility = .hidden
        win.isMovableByWindowBackground = true
        win.isReleasedWhenClosed = false
        win.delegate = self

        win.standardWindowButton(.closeButton)?.isHidden = true
        win.standardWindowButton(.miniaturizeButton)?.isHidden = true
        win.standardWindowButton(.zoomButton)?.isHidden = true

        let hostingView = NSHostingView(rootView: OnboardingView { [weak self] in
            self?.close()
        })
        win.contentView = hostingView

        if let screen = NSScreen.main {
            let screenFrame = screen.visibleFrame
            let x = screenFrame.midX - 460 / 2
            let y = screenFrame.midY - 600 / 2
            win.setFrameOrigin(NSPoint(x: x, y: y))
        }

        window = win
        win.orderFrontRegardless()
        NSApp.setActivationPolicy(.regular)
        win.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    func close() {
        window?.close()
        window = nil

        DispatchQueue.main.async {
            if !EditorWindowController.shared.hasOpenWindows
                && !VideoEditorWindowController.shared.hasOpenWindow {
                NSApp.setActivationPolicy(.accessory)
            }
        }
    }

    func windowWillClose(_ notification: Notification) {
        window = nil
    }
}

struct OnboardingView: View {
    let onFinished: () -> Void

    @State private var currentStep = 1
    @State private var screenCaptureGranted = false
    @State private var accessibilityGranted = false
    @State private var timer: Timer?

    private var appIcon: NSImage? {
        if let icon = NSImage(named: "AppIcon") {
            return icon
        }
        return NSApp.applicationIconImage
    }

    var body: some View {
        VStack(spacing: 0) {
            ZStack {
                if currentStep == 1 {
                    step1View
                        .transition(.asymmetric(
                            insertion: .move(edge: .trailing).combined(with: .opacity),
                            removal: .move(edge: .leading).combined(with: .opacity)
                        ))
                } else if currentStep == 2 {
                    step2View
                        .transition(.asymmetric(
                            insertion: .move(edge: .trailing).combined(with: .opacity),
                            removal: .move(edge: .leading).combined(with: .opacity)
                        ))
                } else if currentStep == 3 {
                    step3View
                        .transition(.asymmetric(
                            insertion: .move(edge: .trailing).combined(with: .opacity),
                            removal: .move(edge: .leading).combined(with: .opacity)
                        ))
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            footerView
        }
        .frame(width: 460, height: 600)
        .background(Color(red: 44/255, green: 44/255, blue: 46/255))
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(Color.white.opacity(0.12), lineWidth: 0.5)
        )
        .preferredColorScheme(.dark)
        .onAppear {
            checkPermissionStatus()
            setupNotificationObserver()
        }
    }

    // MARK: - Step 1: Welcome
    private var step1View: some View {
        VStack(spacing: 0) {
            Spacer().frame(height: 32)

            // App Icon
            if let icon = appIcon {
                Image(nsImage: icon)
                    .resizable()
                    .interpolation(.high)
                    .frame(width: 64, height: 64)
                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .stroke(Color.white.opacity(0.1), lineWidth: 0.5)
                    )
            } else {
                Image(systemName: "camera.fill")
                    .font(.system(size: 32))
                    .frame(width: 64, height: 64)
                    .background(Color.accentColor.opacity(0.15))
                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            }

            Spacer().frame(height: 18)

            Text("Welcome to Shotly")
                .font(.system(size: 22, weight: .bold))

            Spacer().frame(height: 6)

            Text("Everything you need to capture, edit, and share your screen.")
                .font(.system(size: 13))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)

            Spacer().frame(height: 24)

            // Features Grid
            LazyVGrid(columns: [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)], spacing: 10) {
                featureItem(icon: "crop", text: "Capture a region, window, or full screen")
                featureItem(icon: "video", text: "Record your screen as MP4")
                featureItem(icon: "doc.text.viewfinder", text: "Extract text from images with OCR")
                featureItem(icon: "eyedropper", text: "Pick colors and copy the hex code")
                featureItem(icon: "arrow.up.right", text: "Annotate with arrows and numbered steps")
                featureItem(icon: "ruler", text: "Measure pixel distances with the ruler")
                featureItem(icon: "eye.slash", text: "Blur out sensitive information")
                featureItem(icon: "seal", text: "Add a custom watermark or logo")
                featureItem(icon: "info.circle", text: "Attach OS, app, and time metadata")
                featureItem(icon: "photo", text: "Backgrounds, shadows, and rounded corners")
            }
            .padding(.horizontal, 24)

            Spacer()
        }
    }

    private func featureItem(icon: String, text: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(Color.accentColor)
                .frame(width: 18, height: 18)
                .padding(.top, 2)

            Text(text)
                .font(.system(size: 11.5))
                .foregroundStyle(.primary.opacity(0.85))
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
                
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .frame(height: 48)
        .background(Color.white.opacity(0.04))
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(Color.white.opacity(0.06), lineWidth: 0.5)
        )
    }

    // MARK: - Step 2: Permissions
    private var step2View: some View {
        VStack(spacing: 0) {
            Spacer().frame(height: 42)

            // Shield Icon
            Image(systemName: "shield.fill")
                .font(.system(size: 32))
                .foregroundStyle(.green)
                .frame(width: 64, height: 64)
                .background(Color.green.opacity(0.12))
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .stroke(Color.green.opacity(0.2), lineWidth: 0.5)
                )

            Spacer().frame(height: 18)

            Text("Grant permissions")
                .font(.system(size: 22, weight: .bold))

            Spacer().frame(height: 6)

            Text("Shotly needs 2 system permissions to capture and control your screen.")
                .font(.system(size: 13))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)

            Spacer().frame(height: 36)

            // Permissions Rows
            VStack(spacing: 12) {
                permissionRow(
                    icon: "display",
                    title: "Screen recording",
                    description: "To capture and record what's on your screen",
                    isGranted: screenCaptureGranted,
                    action: { requestScreenRecording() }
                )

                permissionRow(
                    icon: "accessibility",
                    title: "Accessibility",
                    description: "To use global shortcuts and auto-scroll",
                    isGranted: accessibilityGranted,
                    action: { requestAccessibility() }
                )
            }
            .padding(.horizontal, 24)

            Spacer().frame(height: 32)

            Text("Tapping \"Grant access\" opens System Settings. Come back here once it's on — Shotly detects it automatically.")
                .font(.system(size: 11))
                .foregroundStyle(.tertiary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 36)
                .lineSpacing(2)

            Spacer()
        }
    }

    private func permissionRow(
        icon: String,
        title: String,
        description: String,
        isGranted: Bool,
        action: @escaping () -> Void
    ) -> some View {
        HStack(spacing: 14) {
            Image(systemName: isGranted ? "checkmark.circle.fill" : icon)
                .font(.system(size: 18))
                .foregroundStyle(isGranted ? .green : Color.accentColor)
                .frame(width: 24)

            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.system(size: 13, weight: .bold))
                Text(description)
                    .font(.system(size: 11.5))
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Button(action: action) {
                Text(isGranted ? "Granted" : "Grant access")
                    .font(.system(size: 12, weight: .medium))
                    .padding(.horizontal, 14)
                    .padding(.vertical, 6)
                    .background(isGranted ? Color.green.opacity(0.12) : Color.accentColor)
                    .foregroundStyle(isGranted ? .green : .white)
                    .clipShape(RoundedRectangle(cornerRadius: 6))
            }
            .buttonStyle(.plain)
            .disabled(isGranted)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .background(Color.white.opacity(0.03))
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(isGranted ? Color.green.opacity(0.3) : Color.white.opacity(0.08), lineWidth: 1)
        )
    }

    // MARK: - Step 3: Shortcuts Summary
    private var step3View: some View {
        let region = ShortcutService.shared.loadShortcut(for: .region) ?? .defaultRegion
        let fullscreen = ShortcutService.shared.loadShortcut(for: .fullscreen) ?? .defaultFullscreen
        let window = ShortcutService.shared.loadShortcut(for: .window) ?? .defaultWindow
        let ocr = ShortcutService.shared.loadShortcut(for: .ocr) ?? .defaultOCR
        let picker = ShortcutService.shared.loadShortcut(for: .colorPicker) ?? .defaultColorPicker
        let recording = ShortcutService.shared.loadShortcut(for: .recording) ?? .defaultRecording

        return VStack(spacing: 0) {
            Spacer().frame(height: 32)

            // Checkmark Icon
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 32))
                .foregroundStyle(.green)
                .frame(width: 64, height: 64)
                .background(Color.green.opacity(0.12))
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))

            Spacer().frame(height: 18)

            Text("You're all set")
                .font(.system(size: 22, weight: .bold))

            Spacer().frame(height: 6)

            Text("Here are your default shortcuts.")
                .font(.system(size: 13))
                .foregroundStyle(.secondary)

            Spacer().frame(height: 20)

            // Shortcut list
            VStack(spacing: 6) {
                shortcutRow(label: "Capture region", shortcut: region)
                shortcutRow(label: "Capture full screen", shortcut: fullscreen)
                shortcutRow(label: "Capture window", shortcut: window)
                shortcutRow(label: "OCR region", shortcut: ocr)
                shortcutRow(label: "Color picker", shortcut: picker)
                shortcutRow(label: "Record screen", shortcut: recording)
            }
            .padding(.horizontal, 24)

            // Conflict Warning Block
            if hasShortcutConflict {
                Spacer().frame(height: 10)
                HStack(alignment: .top, spacing: 8) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.system(size: 12))
                        .foregroundStyle(.orange)
                        .padding(.top, 1)

                    Text("If you switch these back to ⌘⇧3/⌘⇧4/⌘⇧5, they'll conflict with macOS's built-in screenshot shortcuts.")
                        .font(.system(size: 11))
                        .foregroundStyle(.orange.opacity(0.85))
                        .lineSpacing(2)
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .background(Color.orange.opacity(0.08))
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(Color.orange.opacity(0.2), lineWidth: 0.5)
                )
                .padding(.horizontal, 24)
            }

            Spacer().frame(height: 14)

            // Actions Buttons
            VStack(spacing: 8) {
                Button(action: { openKeyboardPreferences() }) {
                    Text("Open Keyboard Shortcuts to disable macOS defaults ↗")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(Color.accentColor)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 8)
                        .background(Color.white.opacity(0.04))
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                        .overlay(
                            RoundedRectangle(cornerRadius: 8)
                                .stroke(Color.white.opacity(0.08), lineWidth: 0.5)
                        )
                }
                .buttonStyle(.plain)

                Button(action: { openAppShortcutSettings() }) {
                    Text("Change shortcuts in Settings")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 8)
                        .background(Color.white.opacity(0.02))
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                        .overlay(
                            RoundedRectangle(cornerRadius: 8)
                                .stroke(Color.white.opacity(0.05), lineWidth: 0.5)
                        )
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 24)

            Spacer()
        }
    }

    private func shortcutRow(label: String, shortcut: ShortcutService.Shortcut) -> some View {
        HStack {
            Text(label)
                .font(.system(size: 12))
                .foregroundStyle(.secondary)

            Spacer()

            Text(shortcut.enabled ? shortcut.displayString : "—")
                .font(.system(.caption, design: .monospaced))
                .padding(.horizontal, 6)
                .padding(.vertical, 3)
                .background(Color.white.opacity(0.06))
                .clipShape(RoundedRectangle(cornerRadius: 4))
                .overlay(
                    RoundedRectangle(cornerRadius: 4)
                        .stroke(Color.white.opacity(0.08), lineWidth: 0.5)
                )
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 6)
        .background(Color.white.opacity(0.02))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    // MARK: - Footer (dots + action)
    private var footerView: some View {
        VStack(spacing: 0) {
            Divider().background(Color.white.opacity(0.08))

            HStack {
                // Page Indicator
                HStack(spacing: 6) {
                    ForEach(1...3, id: \.self) { step in
                        Circle()
                            .frame(width: 6, height: 6)
                            .foregroundStyle(step == currentStep ? .white : .white.opacity(0.25))
                    }
                }

                Spacer()

                // Continue / Skip / Finish
                Button(action: { handleNextButton() }) {
                    Text(nextButtonText)
                        .font(.system(size: 13, weight: .bold))
                        .padding(.horizontal, 20)
                        .padding(.vertical, 8)
                        .background(Color.accentColor)
                        .foregroundStyle(.white)
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 16)
        }
        .background(Color.black.opacity(0.15))
    }

    private var nextButtonText: String {
        if currentStep == 1 {
            return "Continue"
        } else if currentStep == 2 {
            return (screenCaptureGranted && accessibilityGranted) ? "Continue" : "Skip for now"
        } else {
            return "Start using Shotly"
        }
    }

    private func handleNextButton() {
        if currentStep < 3 {
            withAnimation(.easeInOut(duration: 0.25)) {
                currentStep += 1
            }
        } else {
            AppPreferences.hasCompletedOnboarding = true
            if let delegate = NSApp.delegate as? ShotlyDelegate {
                delegate.initializeShortcutService()
            }
            onFinished()
        }
    }

    // MARK: - Action Helpers
    private func checkPermissionStatus() {
        screenCaptureGranted = CGPreflightScreenCaptureAccess()
        accessibilityGranted = AXIsProcessTrusted()
    }

    private func setupNotificationObserver() {
        NotificationCenter.default.addObserver(
            forName: NSApplication.didBecomeActiveNotification,
            object: nil, queue: .main
        ) { _ in
            Task { @MainActor in
                self.checkPermissionStatus()
            }
        }
    }

    private func requestScreenRecording() {
        CGRequestScreenCaptureAccess()
    }

    private func requestAccessibility() {
        let options = ["AXTrustedCheckOptionPrompt": true] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(options)
    }

    private var hasShortcutConflict: Bool {
        let region = ShortcutService.shared.loadShortcut(for: .region) ?? .defaultRegion
        let fullscreen = ShortcutService.shared.loadShortcut(for: .fullscreen) ?? .defaultFullscreen
        let window = ShortcutService.shared.loadShortcut(for: .window) ?? .defaultWindow
        let ocr = ShortcutService.shared.loadShortcut(for: .ocr) ?? .defaultOCR
        let picker = ShortcutService.shared.loadShortcut(for: .colorPicker) ?? .defaultColorPicker
        let recording = ShortcutService.shared.loadShortcut(for: .recording) ?? .defaultRecording

        let cmdShift: UInt32 = 0x0300

        let shortcuts = [region, fullscreen, window, ocr, picker, recording]
        for s in shortcuts {
            if s.enabled && s.modifiers == cmdShift {
                if s.keyCode == 20 || s.keyCode == 21 || s.keyCode == 23 {
                    return true
                }
            }
        }
        return false
    }

    private func openKeyboardPreferences() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.keyboard?Shortcuts") {
            let success = NSWorkspace.shared.open(url)
            if !success {
                let alert = NSAlert()
                alert.messageText = "Instructions"
                alert.informativeText = "Open System Settings → Keyboard → Keyboard Shortcuts → Screenshots, then uncheck 'Save picture of screen as a file' and 'Save picture of selected area as a file'."
                alert.alertStyle = .informational
                alert.addButton(withTitle: "OK")
                alert.runModal()
            }
        }
    }

    private func openAppShortcutSettings() {
        SettingsWindowController.shared.open(on: nil, section: .hotkeys)
    }
}
