import AppKit

@MainActor
final class BetterShotDelegate: NSObject, NSApplicationDelegate {
    private var permissionPollTimer: Timer?

    func applicationDidFinishLaunching(_ notification: Notification) {
        AppPreferences.applyAppearance()
        NSApp.setActivationPolicy(.accessory)

        MenuBarPopoverController.shared.setup()
        AppUpdater.shared.startAutomaticChecks()
        ScreenCapture.warmUpTextRecognition()
        AnalyticsService.trackAppLaunch()

        if !AppPreferences.hasCompletedOnboarding {
            OnboardingWindowController.shared.open()
        } else {
            initializeShortcutService()
        }
    }

    func initializeShortcutService() {
        if ShortcutService.hasAccessibilityPermission {
            ShortcutService.shared.registerAll()

            if !ShortcutService.shared.isRegistered {
                Self.promptRestart()
            }
        } else {
            ShortcutService.requestAccessibilityPermission()
            startPermissionPolling()
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        permissionPollTimer?.invalidate()
        ShortcutService.shared.unregisterAll()
    }

    /// Opens images passed to the app (Finder "Open With", `open -a Shotly file.png`) in the editor.
    func application(_ application: NSApplication, open urls: [URL]) {
        for url in urls where NSImage(contentsOf: url) != nil {
            EditorWindowController.shared.open(url: url)
        }
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        // Shotly lives in the menu bar, so opening it again from Finder, Launchpad or
        // Spotlight would otherwise do nothing visible. Show Settings instead.
        if !flag {
            SettingsWindowController.shared.open()
        }
        return true
    }

    private func startPermissionPolling() {
        permissionPollTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] timer in
            guard ShortcutService.hasAccessibilityPermission else { return }
            timer.invalidate()

            DispatchQueue.main.async {
                self?.permissionPollTimer = nil
                ShortcutService.shared.registerAll()

                if !ShortcutService.shared.isRegistered {
                    Self.promptRestart()
                }
            }
        }
    }

    private static func promptRestart() {
        let alert = NSAlert()
        alert.messageText = "Restart Required"
        alert.informativeText = "Shotly needs to restart to activate keyboard shortcut overrides. Restart now?"
        alert.alertStyle = .informational
        alert.addButton(withTitle: "Restart")
        alert.addButton(withTitle: "Later")

        if alert.runModal() == .alertFirstButtonReturn {
            let task = Process()
            task.launchPath = "/bin/sh"
            task.arguments = ["-c", "sleep 0.5; open \"\(Bundle.main.bundlePath)\""]
            try? task.run()
            NSApp.terminate(nil)
        }
    }
}
