import Foundation

/// Locations of Shotly's own files.
enum AppPaths {
    /// `~/Library/Application Support/Shotly`. Builds made before the rename
    /// stored data (history, base images, watermarks) in `.../BetterShot`; that
    /// folder is moved here the first time this is used.
    static let supportDirectory: URL = {
        let fileManager = FileManager.default
        let base = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let current = base.appendingPathComponent("Shotly", isDirectory: true)
        let legacy = base.appendingPathComponent("BetterShot", isDirectory: true)
        if !fileManager.fileExists(atPath: current.path), fileManager.fileExists(atPath: legacy.path) {
            try? fileManager.moveItem(at: legacy, to: current)
        }
        try? fileManager.createDirectory(at: current, withIntermediateDirectories: true)
        return current
    }()
}
