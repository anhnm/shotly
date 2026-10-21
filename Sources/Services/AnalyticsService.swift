import Foundation

enum AnalyticsEvent: String, Sendable {
    case appLaunched = "app_launched"
    case appFirstLaunch = "app_first_launch"
    case captureRegion = "capture_region"
    case captureFullscreen = "capture_fullscreen"
    case captureWindow = "capture_window"
    case colorPickerUsed = "color_picker_used"
    case ocrCompleted = "ocr_completed"
    case translationCompleted = "translation_completed"
    case translationCopied = "translation_copied"
    case recordingStarted = "recording_started"
    case recordingCompleted = "recording_completed"
    case previewCopied = "preview_copied"
    case previewSaved = "preview_saved"
    case previewEdited = "preview_edited"
    case previewPinned = "preview_pinned"
    case collageStarted = "collage_started"
    case collageCreated = "collage_created"
    case editorToolUsed = "editor_tool_used"
    case editorExported = "editor_exported"
}

private struct AnalyticsPayloadEvent: Codable, Identifiable, Sendable {
    let id: UUID
    let name: String
    let installationID: String
    let sessionID: String
    let appVersion: String
    let macosVersion: String
    let properties: [String: String]
    let occurredAt: Date

    enum CodingKeys: String, CodingKey {
        case id, name, properties
        case installationID = "installation_id"
        case sessionID = "session_id"
        case appVersion = "app_version"
        case macosVersion = "macos_version"
        case occurredAt = "occurred_at"
    }
}

private struct AnalyticsBatch: Codable, Sendable {
    let events: [AnalyticsPayloadEvent]
}

/// Small first-party analytics queue. It never receives screenshots, OCR text,
/// file paths, clipboard data or other free-form user content.
actor AnalyticsService {
    static let shared = AnalyticsService()

    private static let queueKey = "bs_analyticsEventQueue"
    private static let firstLaunchKey = "bs_analyticsFirstLaunchSent"
    private static let installationIDKey = "bs_analyticsInstallationID"

    private let installationID: String
    private let sessionID = UUID().uuidString.lowercased()
    private var queue: [AnalyticsPayloadEvent]
    private var flushTask: Task<Void, Never>?
    private var isFlushing = false

    private init() {
        installationID = Self.loadOrCreateInstallationID()
        queue = Self.loadQueue()
    }

    nonisolated static func track(_ event: AnalyticsEvent, properties: [String: String] = [:]) {
        guard AppPreferences.analyticsEnabled, endpoint != nil, ingestKey != nil else { return }
        Task { await shared.enqueue(event, properties: properties) }
    }

    nonisolated static func trackAppLaunch() {
        guard AppPreferences.analyticsEnabled, endpoint != nil, ingestKey != nil else { return }
        track(.appLaunched)
        if !UserDefaults.standard.bool(forKey: firstLaunchKey) {
            UserDefaults.standard.set(true, forKey: firstLaunchKey)
            track(.appFirstLaunch)
        }
    }

    nonisolated static func updateConsent(_ enabled: Bool) {
        Task { await shared.setEnabled(enabled) }
    }

    private func setEnabled(_ enabled: Bool) {
        if enabled {
            Self.trackAppLaunch()
        } else {
            flushTask?.cancel()
            flushTask = nil
            queue.removeAll()
            persistQueue()
        }
    }

    private func enqueue(_ event: AnalyticsEvent, properties: [String: String]) {
        guard AppPreferences.analyticsEnabled else { return }
        let cleanProperties = Dictionary(uniqueKeysWithValues: properties.prefix(12).map {
            (String($0.key.prefix(32)), String($0.value.prefix(100)))
        })
        queue.append(AnalyticsPayloadEvent(
            id: UUID(),
            name: event.rawValue,
            installationID: installationID,
            sessionID: sessionID,
            appVersion: Self.appVersion,
            macosVersion: ProcessInfo.processInfo.operatingSystemVersionString,
            properties: cleanProperties,
            occurredAt: Date()
        ))
        if queue.count > 500 {
            queue.removeFirst(queue.count - 500)
        }
        persistQueue()
        scheduleFlush(immediately: queue.count >= 10)
    }

    private func scheduleFlush(immediately: Bool = false) {
        flushTask?.cancel()
        flushTask = Task {
            if !immediately {
                try? await Task.sleep(for: .seconds(2))
            }
            guard !Task.isCancelled else { return }
            await flush()
        }
    }

    private func flush() async {
        guard !isFlushing,
              AppPreferences.analyticsEnabled,
              let endpoint = Self.endpoint,
              let ingestKey = Self.ingestKey,
              !queue.isEmpty else { return }

        isFlushing = true
        defer { isFlushing = false }

        let batch = Array(queue.prefix(25))
        do {
            var request = URLRequest(url: endpoint)
            request.httpMethod = "POST"
            request.timeoutInterval = 12
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.setValue(ingestKey, forHTTPHeaderField: "X-Shotly-App-Key")
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            request.httpBody = try encoder.encode(AnalyticsBatch(events: batch))

            let (_, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else { return }
            let sentIDs = Set(batch.map(\.id))
            queue.removeAll { sentIDs.contains($0.id) }
            persistQueue()
            if !queue.isEmpty {
                scheduleFlush(immediately: true)
            }
        } catch {
            // Retain the batch for a later event or the next app launch.
        }
    }

    private func persistQueue() {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        if let data = try? encoder.encode(queue) {
            UserDefaults.standard.set(data, forKey: Self.queueKey)
        }
    }

    private static func loadQueue() -> [AnalyticsPayloadEvent] {
        guard let data = UserDefaults.standard.data(forKey: queueKey) else { return [] }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return (try? decoder.decode([AnalyticsPayloadEvent].self, from: data)) ?? []
    }

    private static var endpoint: URL? {
        guard let value = Bundle.main.object(forInfoDictionaryKey: "ShotlyAnalyticsEndpoint") as? String,
              value.hasPrefix("https://") else { return nil }
        return URL(string: value)
    }

    private static var ingestKey: String? {
        guard let value = Bundle.main.object(forInfoDictionaryKey: "ShotlyAnalyticsIngestKey") as? String,
              value.count >= 24 else { return nil }
        return value
    }

    private static var appVersion: String {
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "unknown"
        let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "unknown"
        return "\(version) (\(build))"
    }

    private static func loadOrCreateInstallationID() -> String {
        let defaults = UserDefaults.standard
        if let value = defaults.string(forKey: installationIDKey),
           UUID(uuidString: value) != nil {
            return value.lowercased()
        }

        let value = UUID().uuidString.lowercased()
        defaults.set(value, forKey: installationIDKey)
        return value
    }
}
