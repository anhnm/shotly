import Foundation
import AppKit

/// Represents a captured screenshot or recording in the history.
struct CaptureRecord: Identifiable, Codable, Equatable, Sendable {
    let id: UUID
    let createdAt: Date
    var filename: String
    var pixelWidth: Int
    var pixelHeight: Int
    var kind: CaptureKind
    var hasAnnotations: Bool
    var beautifiedPath: String?
    var metadata: CaptureMetadata?

    init(
        filename: String,
        pixelWidth: Int,
        pixelHeight: Int,
        kind: CaptureKind = .screenshot,
        hasAnnotations: Bool = false,
        beautifiedPath: String? = nil,
        metadata: CaptureMetadata? = nil
    ) {
        self.id = UUID()
        self.createdAt = Date()
        self.filename = filename
        self.pixelWidth = pixelWidth
        self.pixelHeight = pixelHeight
        self.kind = kind
        self.hasAnnotations = hasAnnotations
        self.beautifiedPath = beautifiedPath
        self.metadata = metadata
    }
}

enum CaptureKind: String, Codable, Sendable {
    case screenshot
    case recording
}

/// Background configuration for the beautifier.
struct BeautifierConfig: Codable, Equatable {
    var style: BackgroundStyle = .none
    var padding: CGFloat = 0.08
    var cornerRadius: CGFloat = 0.018
    var shadowStrength: CGFloat = 0.36
    var alignment: ImageAlignment = .center
    var aspectRatio: CanvasAspectRatio = .auto
    var metadataColor: AnnotationSwatch = .black
    var metadataFontSize: CGFloat = 12.0

    static let `default` = BeautifierConfig()

    enum CodingKeys: String, CodingKey {
        case style, padding, cornerRadius, shadowStrength, alignment, aspectRatio, metadataColor, metadataFontSize
    }

    init() {}

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        style = try container.decodeIfPresent(BackgroundStyle.self, forKey: .style) ?? BackgroundStyle.none
        padding = try container.decodeIfPresent(CGFloat.self, forKey: .padding) ?? 0.08
        cornerRadius = try container.decodeIfPresent(CGFloat.self, forKey: .cornerRadius) ?? 0.018
        shadowStrength = try container.decodeIfPresent(CGFloat.self, forKey: .shadowStrength) ?? 0.36
        alignment = try container.decodeIfPresent(ImageAlignment.self, forKey: .alignment) ?? ImageAlignment.center
        aspectRatio = try container.decodeIfPresent(CanvasAspectRatio.self, forKey: .aspectRatio) ?? CanvasAspectRatio.auto
        metadataColor = try container.decodeIfPresent(AnnotationSwatch.self, forKey: .metadataColor) ?? AnnotationSwatch.black
        metadataFontSize = try container.decodeIfPresent(CGFloat.self, forKey: .metadataFontSize) ?? 12.0
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(style, forKey: .style)
        try container.encode(padding, forKey: .padding)
        try container.encode(cornerRadius, forKey: .cornerRadius)
        try container.encode(shadowStrength, forKey: .shadowStrength)
        try container.encode(alignment, forKey: .alignment)
        try container.encode(aspectRatio, forKey: .aspectRatio)
        try container.encode(metadataColor, forKey: .metadataColor)
        try container.encode(metadataFontSize, forKey: .metadataFontSize)
    }
}

public struct CaptureMetadata: Codable, Equatable, Sendable {
    public let osVersion: String
    public let appName: String?
    public let appVersion: String?
    public let timestamp: Date

    public init(osVersion: String, appName: String?, appVersion: String?, timestamp: Date) {
        self.osVersion = osVersion
        self.appName = appName
        self.appVersion = appVersion
        self.timestamp = timestamp
    }

    public static func capture() -> CaptureMetadata {
        let workspace = NSWorkspace.shared
        var appName: String? = nil
        var appVersion: String? = nil

        let ownBundleID = Bundle.main.bundleIdentifier ?? ""
        if let app = workspace.frontmostApplication, app.bundleIdentifier != ownBundleID {
            appName = app.localizedName
            if let bundleURL = app.bundleURL,
               let bundle = Bundle(url: bundleURL) {
                appVersion = bundle.infoDictionary?["CFBundleShortVersionString"] as? String
            }
        }

        return CaptureMetadata(
            osVersion: ProcessInfo.processInfo.operatingSystemVersionString,
            appName: appName,
            appVersion: appVersion,
            timestamp: Date()
        )
    }

    public var displayString: String {
        var parts: [String] = []
        
        var cleanOS = osVersion
        if cleanOS.hasPrefix("Version ") {
            cleanOS = cleanOS.replacingOccurrences(of: "Version ", with: "macOS ")
        }
        cleanOS = cleanOS.replacingOccurrences(of: "Build ", with: "")
        parts.append(cleanOS)
        
        if let appName = appName {
            if let appVersion = appVersion {
                parts.append("\(appName) \(appVersion)")
            } else {
                parts.append(appName)
            }
        }
        
        let formatter = DateFormatter()
        formatter.dateFormat = "d MMM yyyy, HH:mm:ss"
        formatter.locale = Locale(identifier: "en_US_POSIX")
        parts.append(formatter.string(from: timestamp))
        
        return parts.joined(separator: "  \u{2022}  ")
    }
}
