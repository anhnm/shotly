import AppKit
import CryptoKit
import Foundation
import OSLog

private let updateLog = Logger(subsystem: "com.shotly.app", category: "update")

/// Description of a published release, uploaded by `release.sh` as `version.json`
/// next to the DMG on GitHub Releases.
struct UpdateManifest: Decodable, Equatable, Sendable {
    let version: String
    let build: Int
    let minimumOS: String?
    let dmgUrl: URL
    let sha256: String
    let size: Int?
    let notes: [String]
    /// Builds older than this must update before the app can be used.
    let minBuild: Int?
}

/// Checks GitHub Releases for a newer Shotly and installs it in place.
///
/// The app reads `https://github.com/<repo>/releases/latest/download/version.json`,
/// a plain download URL with no API rate limit. The repo comes from the
/// `ShotlyUpdateRepo` Info.plist key.
@MainActor
@Observable
final class AppUpdater {
    static let shared = AppUpdater()

    enum State: Equatable {
        case idle
        case checking
        case upToDate
        case available(UpdateManifest)
        case downloading(UpdateManifest, progress: Double)
        case installing(UpdateManifest)
        case failed(String)
    }

    private(set) var state: State = .idle
    private(set) var lastChecked: Date?

    private static let skippedVersionKey = "bs_skippedUpdateVersion"
    static let automaticChecksKey = "bs_autoCheckUpdates"
    private static let checkInterval: Duration = .seconds(6 * 60 * 60)

    private var periodicCheckTask: Task<Void, Never>?
    private var installTask: Task<Void, Never>?

    private init() {}

    // MARK: - Versions

    var currentVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0.0.0"
    }

    var currentBuild: Int {
        Int(Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "") ?? 0
    }

    private static var repository: String? {
        let value = (Bundle.main.object(forInfoDictionaryKey: "ShotlyUpdateRepo") as? String)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard let value, !value.isEmpty, !value.hasPrefix("$(") else { return nil }
        return value
    }

    private static var manifestURL: URL? {
        repository.flatMap { URL(string: "https://github.com/\($0)/releases/latest/download/version.json") }
    }

    static var automaticChecksEnabled: Bool {
        UserDefaults.standard.object(forKey: automaticChecksKey) as? Bool ?? true
    }

    /// The available update must be installed before Shotly can be used.
    func isRequired(_ manifest: UpdateManifest) -> Bool {
        currentBuild < (manifest.minBuild ?? 0)
    }

    // MARK: - Checking

    /// Checks shortly after launch and then every few hours while the app runs.
    func startAutomaticChecks() {
        periodicCheckTask?.cancel()
        periodicCheckTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(5))
            while !Task.isCancelled {
                if Self.automaticChecksEnabled {
                    await self?.checkForUpdates(userInitiated: false)
                }
                try? await Task.sleep(for: Self.checkInterval)
            }
        }
    }

    /// `userInitiated` checks always show the result; background checks only
    /// speak up when there is an update the user has not skipped.
    func checkForUpdates(userInitiated: Bool) async {
        switch state {
        case .checking, .downloading, .installing: return
        default: break
        }
        guard let url = Self.manifestURL else {
            if userInitiated { state = .failed("Updates are not configured for this build.") }
            return
        }

        state = .checking
        do {
            var request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 20)
            request.setValue("Shotly/\(currentVersion)", forHTTPHeaderField: "User-Agent")
            let (data, response) = try await URLSession.shared.data(for: request)
            lastChecked = Date()

            guard let http = response as? HTTPURLResponse else {
                throw UpdateError.message("The update server sent an invalid response.")
            }
            // No release published yet.
            if http.statusCode == 404 {
                state = .upToDate
                return
            }
            guard http.statusCode == 200 else {
                throw UpdateError.message("The update server returned an error (\(http.statusCode)).")
            }

            let manifest = try JSONDecoder().decode(UpdateManifest.self, from: data)
            guard manifest.build > currentBuild else {
                state = .upToDate
                return
            }
            if let minimumOS = manifest.minimumOS, !Self.systemSatisfies(minimumOS) {
                state = userInitiated
                    ? .failed("Shotly \(manifest.version) needs macOS \(minimumOS) or later.")
                    : .upToDate
                return
            }

            state = .available(manifest)
            updateLog.notice("Update available: \(manifest.version, privacy: .public) (build \(manifest.build))")

            let skipped = UserDefaults.standard.string(forKey: Self.skippedVersionKey)
            if userInitiated || isRequired(manifest) || skipped != manifest.version {
                UpdateWindowController.shared.show()
            }
        } catch {
            updateLog.error("Update check failed: \(error.localizedDescription, privacy: .public)")
            state = userInitiated ? .failed(Self.describe(error)) : .idle
        }
    }

    func skip(_ manifest: UpdateManifest) {
        UserDefaults.standard.set(manifest.version, forKey: Self.skippedVersionKey)
    }

    // MARK: - Installing

    func install(_ manifest: UpdateManifest) {
        guard installTask == nil else { return }
        installTask = Task { [weak self] in
            await self?.performInstall(manifest)
            self?.installTask = nil
        }
    }

    func cancelInstall() {
        guard case .downloading(let manifest, _) = state else { return }
        installTask?.cancel()
        installTask = nil
        state = .available(manifest)
    }

    private func performInstall(_ manifest: UpdateManifest) async {
        let appURL = Bundle.main.bundleURL
        if let problem = Self.installLocationProblem(for: appURL) {
            state = .failed(problem)
            return
        }

        state = .downloading(manifest, progress: 0)
        do {
            let dmg = try await download(manifest)
            try Task.checkCancellation()

            state = .installing(manifest)
            try await Self.verify(dmg, sha256: manifest.sha256)
            try await Self.replaceApp(at: appURL, withAppFrom: dmg, expectedBuild: manifest.build)
            try? FileManager.default.removeItem(at: dmg.deletingLastPathComponent())

            updateLog.notice("Installed \(manifest.version, privacy: .public); relaunching")
            UserDefaults.standard.removeObject(forKey: Self.skippedVersionKey)
            Self.relaunch(appURL)
        } catch is CancellationError {
            state = .available(manifest)
        } catch {
            updateLog.error("Install failed: \(error.localizedDescription, privacy: .public)")
            state = .failed(Self.describe(error))
        }
    }

    private func download(_ manifest: UpdateManifest) async throws -> URL {
        let progress = DownloadProgressReporter { [weak self] fraction in
            Task { @MainActor in
                guard let self, case .downloading(let current, _) = self.state else { return }
                self.state = .downloading(current, progress: fraction)
            }
        }
        let (tempURL, response) = try await URLSession.shared.download(from: manifest.dmgUrl, delegate: progress)
        guard (response as? HTTPURLResponse)?.statusCode == 200 else {
            throw UpdateError.message("The update could not be downloaded.")
        }

        let folder = FileManager.default.temporaryDirectory
            .appendingPathComponent("ShotlyUpdate-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let dmg = folder.appendingPathComponent("Shotly-\(manifest.version).dmg")
        try FileManager.default.moveItem(at: tempURL, to: dmg)
        return dmg
    }

    // MARK: - Helpers (run off the main actor)

    private nonisolated static func verify(_ file: URL, sha256 expected: String) async throws {
        try await Task.detached(priority: .userInitiated) {
            let handle = try FileHandle(forReadingFrom: file)
            defer { try? handle.close() }
            var hasher = SHA256()
            while let chunk = try handle.read(upToCount: 1 << 20), !chunk.isEmpty {
                hasher.update(data: chunk)
            }
            let actual = hasher.finalize().map { String(format: "%02x", $0) }.joined()
            guard actual == expected.lowercased() else {
                throw UpdateError.message("The downloaded update is damaged (checksum mismatch). Please try again.")
            }
        }.value
    }

    /// Mounts the DMG, checks the app inside, and swaps it in for the running app.
    private nonisolated static func replaceApp(at appURL: URL, withAppFrom dmg: URL, expectedBuild: Int) async throws {
        try await Task.detached(priority: .userInitiated) {
            let mountPoint = try mount(dmg)
            defer { _ = try? run("/usr/bin/hdiutil", ["detach", mountPoint, "-quiet", "-force"]) }

            let contents = try FileManager.default.contentsOfDirectory(
                at: URL(fileURLWithPath: mountPoint),
                includingPropertiesForKeys: nil
            )
            guard let newApp = contents.first(where: { $0.pathExtension == "app" }),
                  let info = Bundle(url: newApp)?.infoDictionary else {
                throw UpdateError.message("The update does not contain Shotly.")
            }
            guard info["CFBundleIdentifier"] as? String == Bundle.main.bundleIdentifier else {
                throw UpdateError.message("The update contains a different app.")
            }
            guard Int(info["CFBundleVersion"] as? String ?? "") == expectedBuild else {
                throw UpdateError.message("The update's version does not match the release.")
            }

            // Copy next to the current app first (same volume), then swap atomically,
            // so a failure part-way never leaves a broken Shotly behind.
            let staging = appURL.deletingLastPathComponent()
                .appendingPathComponent(".Shotly-update-\(UUID().uuidString).app")
            try run("/usr/bin/ditto", [newApp.path, staging.path])
            _ = try? run("/usr/bin/xattr", ["-dr", "com.apple.quarantine", staging.path])
            do {
                _ = try FileManager.default.replaceItemAt(appURL, withItemAt: staging)
            } catch {
                try? FileManager.default.removeItem(at: staging)
                throw UpdateError.message("Shotly could not replace itself: \(error.localizedDescription)")
            }
        }.value
    }

    private nonisolated static func mount(_ dmg: URL) throws -> String {
        let output = try run("/usr/bin/hdiutil", ["attach", dmg.path, "-nobrowse", "-readonly", "-noverify", "-plist"])
        guard let plist = try PropertyListSerialization.propertyList(from: output, format: nil) as? [String: Any],
              let entities = plist["system-entities"] as? [[String: Any]],
              let mountPoint = entities.compactMap({ $0["mount-point"] as? String }).first else {
            throw UpdateError.message("The update disk image could not be opened.")
        }
        return mountPoint
    }

    @discardableResult
    private nonisolated static func run(_ tool: String, _ arguments: [String]) throws -> Data {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: tool)
        process.arguments = arguments
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = Pipe()
        try process.run()
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else {
            throw UpdateError.message("\(URL(fileURLWithPath: tool).lastPathComponent) failed (\(process.terminationStatus)).")
        }
        return data
    }

    /// Why the running copy cannot update itself, if it can't.
    private static func installLocationProblem(for appURL: URL) -> String? {
        if appURL.path.contains("/AppTranslocation/") || appURL.path.hasPrefix("/Volumes/") {
            return "Move Shotly to your Applications folder, open it from there, then update."
        }
        if !FileManager.default.isWritableFile(atPath: appURL.deletingLastPathComponent().path) {
            return "Shotly can't write to \(appURL.deletingLastPathComponent().path). Download the update from GitHub instead."
        }
        return nil
    }

    /// Waits for this process to exit, then opens the updated app.
    private static func relaunch(_ appURL: URL) {
        let pid = ProcessInfo.processInfo.processIdentifier
        let script = "while /bin/kill -0 \(pid) 2>/dev/null; do /bin/sleep 0.2; done; /usr/bin/open \"\(appURL.path)\""
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/sh")
        process.arguments = ["-c", script]
        try? process.run()
        NSApp.terminate(nil)
    }

    private static func systemSatisfies(_ minimum: String) -> Bool {
        let parts = minimum.split(separator: ".").compactMap { Int($0) }
        let required = OperatingSystemVersion(
            majorVersion: parts.first ?? 0,
            minorVersion: parts.count > 1 ? parts[1] : 0,
            patchVersion: parts.count > 2 ? parts[2] : 0
        )
        return ProcessInfo.processInfo.isOperatingSystemAtLeast(required)
    }

    private static func describe(_ error: Error) -> String {
        if case UpdateError.message(let text) = error { return text }
        if (error as? URLError)?.code == .notConnectedToInternet {
            return "You're offline. Connect to the internet and try again."
        }
        return error.localizedDescription
    }
}

private enum UpdateError: Error {
    case message(String)
}

/// Forwards download progress from URLSession to the updater.
private final class DownloadProgressReporter: NSObject, URLSessionDownloadDelegate, Sendable {
    private let onProgress: @Sendable (Double) -> Void

    init(onProgress: @escaping @Sendable (Double) -> Void) {
        self.onProgress = onProgress
    }

    func urlSession(
        _ session: URLSession,
        downloadTask: URLSessionDownloadTask,
        didWriteData bytesWritten: Int64,
        totalBytesWritten: Int64,
        totalBytesExpectedToWrite: Int64
    ) {
        guard totalBytesExpectedToWrite > 0 else { return }
        onProgress(Double(totalBytesWritten) / Double(totalBytesExpectedToWrite))
    }

    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didFinishDownloadingTo location: URL) {
        // The async download API moves the file itself.
    }
}
