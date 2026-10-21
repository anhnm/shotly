import SwiftUI

@main
struct ShotlyApp: App {
    @NSApplicationDelegateAdaptor(ShotlyDelegate.self) var delegate

    var body: some Scene {
        Settings {
            PreferencesView()
        }
    }
}
