import AppKit
import SwiftUI

/// "Software Update" window shown when a newer Shotly is published.
@MainActor
final class UpdateWindowController: NSObject, NSWindowDelegate {
    static let shared = UpdateWindowController()

    private var window: NSWindow?

    private override init() { super.init() }

    func show() {
        if let window {
            window.makeKeyAndOrderFront(nil)
            NSApp.activate()
            return
        }

        let hostingView = NSHostingView(rootView: UpdateView(onClose: { [weak self] in self?.close() }))
        let win = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 480, height: 360),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        win.contentView = hostingView
        win.title = "Software Update"
        win.isReleasedWhenClosed = false
        win.delegate = self
        win.level = .floating
        win.collectionBehavior = [.moveToActiveSpace]
        win.setContentSize(hostingView.fittingSize)
        win.center()
        window = win

        NSApp.setActivationPolicy(.regular)
        win.makeKeyAndOrderFront(nil)
        NSApp.activate()
    }

    func close() {
        window?.close()
    }

    func windowShouldClose(_ sender: NSWindow) -> Bool {
        // A required update can only be installed or the app quit.
        if case .available(let manifest) = AppUpdater.shared.state, AppUpdater.shared.isRequired(manifest) {
            NSApp.terminate(nil)
            return false
        }
        if case .installing = AppUpdater.shared.state { return false }
        AppUpdater.shared.cancelInstall()
        return true
    }

    func windowWillClose(_ notification: Notification) {
        window = nil
        DispatchQueue.main.async {
            if !EditorWindowController.shared.hasOpenWindows
                && !VideoEditorWindowController.shared.hasOpenWindow
                && !NSApp.windows.contains(where: { $0.isVisible && $0.title == "Settings" }) {
                NSApp.setActivationPolicy(.accessory)
            }
        }
    }
}

private struct UpdateView: View {
    let onClose: () -> Void
    @State private var updater = AppUpdater.shared

    private var manifest: UpdateManifest? {
        switch updater.state {
        case .available(let manifest), .installing(let manifest):
            return manifest
        case .downloading(let manifest, _):
            return manifest
        default:
            return nil
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .top, spacing: 14) {
                Image(nsImage: NSApp.applicationIconImage)
                    .resizable()
                    .frame(width: 64, height: 64)
                    .accessibilityHidden(true)

                VStack(alignment: .leading, spacing: 4) {
                    Text(headline)
                        .font(.system(size: 15, weight: .semibold))
                        .fixedSize(horizontal: false, vertical: true)
                    Text(subheadline)
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            if let manifest, !manifest.notes.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    Text("What's new")
                        .font(.system(size: 12, weight: .semibold))
                    ScrollView {
                        VStack(alignment: .leading, spacing: 4) {
                            ForEach(Array(manifest.notes.enumerated()), id: \.offset) { _, note in
                                HStack(alignment: .firstTextBaseline, spacing: 6) {
                                    Text("•")
                                    Text(note)
                                        .fixedSize(horizontal: false, vertical: true)
                                }
                                .font(.system(size: 12))
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(10)
                    }
                    .frame(maxHeight: 140)
                    .background(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .fill(Color.primary.opacity(0.05))
                    )
                }
            }

            statusArea

            HStack {
                if let manifest, case .available = updater.state, !updater.isRequired(manifest) {
                    Button("Skip This Version") {
                        updater.skip(manifest)
                        onClose()
                    }
                }
                Spacer()
                secondaryButton
                primaryButton
            }
        }
        .padding(20)
        .frame(width: 480)
    }

    private var headline: String {
        guard let manifest else { return "Shotly is up to date" }
        return updater.isRequired(manifest)
            ? "Shotly \(manifest.version) is required"
            : "A new version of Shotly is available"
    }

    private var subheadline: String {
        guard let manifest else { return "You have the latest version (\(updater.currentVersion))." }
        let base = "Shotly \(manifest.version) is available — you have \(updater.currentVersion)."
        return updater.isRequired(manifest)
            ? base + " This version can no longer be used; please update to continue."
            : base + " Install it now? Shotly will restart."
    }

    @ViewBuilder
    private var statusArea: some View {
        switch updater.state {
        case .downloading(_, let progress):
            VStack(alignment: .leading, spacing: 4) {
                ProgressView(value: progress)
                Text("Downloading… \(Int(progress * 100))%")
                    .font(.caption)
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
            }
        case .installing:
            HStack(spacing: 8) {
                ProgressView().controlSize(.small)
                Text("Installing and restarting…")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        case .failed(let message):
            Text(message)
                .font(.caption)
                .foregroundStyle(.red)
                .fixedSize(horizontal: false, vertical: true)
        default:
            EmptyView()
        }
    }

    @ViewBuilder
    private var secondaryButton: some View {
        switch updater.state {
        case .downloading:
            Button("Cancel") { updater.cancelInstall() }
        case .installing:
            EmptyView()
        default:
            if let manifest, updater.isRequired(manifest) {
                Button("Quit Shotly") { NSApp.terminate(nil) }
            } else {
                Button(manifest == nil ? "Close" : "Remind Me Later") { onClose() }
                    .keyboardShortcut(.cancelAction)
            }
        }
    }

    @ViewBuilder
    private var primaryButton: some View {
        switch updater.state {
        case .available(let manifest):
            Button("Install and Relaunch") { updater.install(manifest) }
                .keyboardShortcut(.defaultAction)
        case .failed:
            Button("Try Again") {
                Task { await updater.checkForUpdates(userInitiated: true) }
            }
            .keyboardShortcut(.defaultAction)
        default:
            EmptyView()
        }
    }
}
