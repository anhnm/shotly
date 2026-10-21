import AppKit
import ImageIO
import UniformTypeIdentifiers

@MainActor
enum ImageSavePanel {
    static func chooseDestination(
        suggestedName: String,
        fileExtension: String,
        contentType: UTType,
        prompt: String = "Save"
    ) -> URL? {
        let panel = NSSavePanel()
        panel.title = "Save Image"
        panel.prompt = prompt
        panel.canCreateDirectories = true
        panel.isExtensionHidden = false
        panel.allowedContentTypes = [contentType]
        panel.nameFieldStringValue = "\(suggestedName).\(fileExtension)"

        let preferredDirectory = URL(fileURLWithPath: AppPreferences.saveDirectory, isDirectory: true)
        if FileManager.default.fileExists(atPath: preferredDirectory.path) {
            panel.directoryURL = preferredDirectory
        }

        guard panel.runModal() == .OK else { return nil }
        return panel.url
    }

    static func export(_ image: CGImage, suggestedName: String) -> URL? {
        let format = AppPreferences.exportFormat
        let contentType = UTType(format.utType) ?? .png
        guard let url = chooseDestination(
            suggestedName: suggestedName,
            fileExtension: format.fileExtension,
            contentType: contentType,
            prompt: "Save"
        ) else { return nil }

        guard let destination = CGImageDestinationCreateWithURL(
            url as CFURL,
            format.utType as CFString,
            1,
            nil
        ) else { return nil }

        var options: [CFString: Any] = [:]
        if format == .jpeg {
            options[kCGImageDestinationLossyCompressionQuality] = AppPreferences.exportQuality
        }

        CGImageDestinationAddImage(destination, image, options as CFDictionary)
        guard CGImageDestinationFinalize(destination) else { return nil }
        return url
    }

    static func copyFile(from sourceURL: URL) -> URL? {
        let fileExtension = sourceURL.pathExtension.isEmpty ? "png" : sourceURL.pathExtension
        let contentType = UTType(filenameExtension: fileExtension) ?? .data
        let suggestedName = sourceURL.deletingPathExtension().lastPathComponent

        guard let destinationURL = chooseDestination(
            suggestedName: suggestedName,
            fileExtension: fileExtension,
            contentType: contentType,
            prompt: "Save"
        ) else { return nil }

        if sourceURL.standardizedFileURL == destinationURL.standardizedFileURL {
            return sourceURL
        }

        do {
            if FileManager.default.fileExists(atPath: destinationURL.path) {
                try FileManager.default.removeItem(at: destinationURL)
            }
            try FileManager.default.copyItem(at: sourceURL, to: destinationURL)
            return destinationURL
        } catch {
            let alert = NSAlert(error: error)
            alert.messageText = "Couldn’t save the file"
            alert.runModal()
            return nil
        }
    }
}
