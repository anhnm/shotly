import SwiftUI

enum CollageLayoutType: String, Codable, CaseIterable, Sendable {
    case vertical = "Vertical"
    case horizontal = "Horizontal"
    case grid2x2 = "Grid 2x2"
}

struct CollageSlot: Identifiable, Equatable, Sendable {
    var id: UUID = UUID()
    var image: NSImage
    var panOffset: CGPoint = .zero
    var zoomScale: CGFloat = 1.0
}

struct CollageState: Equatable, Sendable {
    var layoutType: CollageLayoutType
    var slots: [CollageSlot] = []
    var spacing: CGFloat = 8
    var isLocked: Bool = false
}

public extension NSImage {
    func bestCGImage() -> CGImage? {
        var proposedRect = CGRect(origin: .zero, size: size)
        return cgImage(forProposedRect: &proposedRect, context: nil, hints: nil)
    }
}
