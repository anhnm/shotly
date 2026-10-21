import Foundation
import SwiftUI
import Observation

enum WatermarkType: String, Codable, CaseIterable, Sendable {
    case image = "Image"
    case text = "Text"
}

enum WatermarkPosition: String, Codable, CaseIterable, Sendable {
    case topLeft = "Top Left"
    case topRight = "Top Right"
    case bottomLeft = "Bottom Left"
    case bottomRight = "Bottom Right"
    case center = "Center"
}

struct WatermarkPreset: Codable, Identifiable, Equatable, Sendable {
    var id: UUID = UUID()
    var name: String
    var type: WatermarkType = .text
    
    // Text watermark options
    var textContent: String?
    var fontName: String = "Helvetica"
    var fontSize: Double = 36.0
    var fontColor: AnnotationSwatch = .white
    
    // Image watermark options
    var imagePath: String?         // relative path/filename in Application Support
    
    // Common settings
    var opacity: Double = 0.8            // 0.0 - 1.0
    var position: WatermarkPosition = .bottomRight
    var rotationDegrees: Double = 0.0    // -180...180
    var scale: Double = 0.2              // relative scale to image shortest edge, default 20%
}

@MainActor
@Observable
final class WatermarkStore {
    static let shared = WatermarkStore()

    private(set) var presets: [WatermarkPreset] = []
    
    private let storageDir: URL
    private let presetsURL: URL
    private let watermarksDir: URL

    private init() {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        storageDir = appSupport.appendingPathComponent("BetterShot", isDirectory: true)
        presetsURL = storageDir.appendingPathComponent("watermark-presets.json")
        watermarksDir = storageDir.appendingPathComponent("Watermarks", isDirectory: true)

        try? FileManager.default.createDirectory(at: storageDir, withIntermediateDirectories: true)
        try? FileManager.default.createDirectory(at: watermarksDir, withIntermediateDirectories: true)
        loadPresets()
    }

    func loadPresets() {
        guard let data = try? Data(contentsOf: presetsURL) else {
            // Default presets
            presets = [
                WatermarkPreset(name: "Shotly Default Text", type: .text, textContent: "Shotly", fontSize: 24.0, fontColor: .white, opacity: 0.6)
            ]
            return
        }
        presets = (try? JSONDecoder().decode([WatermarkPreset].self, from: data)) ?? []
    }

    func savePresets() {
        guard let data = try? JSONEncoder().encode(presets) else { return }
        try? data.write(to: presetsURL, options: .atomic)
    }

    func addPreset(_ preset: WatermarkPreset) {
        presets.append(preset)
        savePresets()
    }

    func updatePreset(_ preset: WatermarkPreset) {
        if let idx = presets.firstIndex(where: { $0.id == preset.id }) {
            presets[idx] = preset
            savePresets()
        }
    }

    func deletePreset(_ preset: WatermarkPreset) {
        if let relativePath = preset.imagePath {
            deleteWatermarkImage(filename: relativePath)
        }
        presets.removeAll { $0.id == preset.id }
        savePresets()
    }

    func importWatermarkImage(from sourceURL: URL) -> String? {
        let ext = sourceURL.pathExtension.isEmpty ? "png" : sourceURL.pathExtension
        let filename = "wm_\(Int(Date().timeIntervalSince1970 * 1000)).\(ext)"
        let destURL = watermarksDir.appendingPathComponent(filename)
        do {
            try FileManager.default.copyItem(at: sourceURL, to: destURL)
            return filename
        } catch {
            print("Failed to copy watermark image: \(error)")
            return nil
        }
    }

    func deleteWatermarkImage(filename: String) {
        let url = watermarksDir.appendingPathComponent(filename)
        try? FileManager.default.removeItem(at: url)
    }

    nonisolated func resolveImagePath(for filename: String) -> URL {
        watermarksDir.appendingPathComponent(filename)
    }
}
