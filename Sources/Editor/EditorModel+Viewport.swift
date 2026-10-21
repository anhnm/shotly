import AppKit
import SwiftUI

/// Geometry reported by the canvas so the model can reason about zoom levels.
struct EditorViewportMetrics: Equatable {
    /// Size of the canvas viewport in view points.
    var viewportSize: CGSize = .zero
    /// Size of the canvas (image + padding) in view points when zoomed to fit.
    var fitCanvasSize: CGSize = .zero
    /// View points per image pixel when zoomed to fit.
    var fitScale: CGFloat = 1
    /// Backing scale factor of the window's screen.
    var displayScale: CGFloat = 2
}

struct EditorHoveredPixel: Equatable {
    var x: Int
    var y: Int
    var red: UInt8
    var green: UInt8
    var blue: UInt8

    var hex: String {
        String(format: "#%02X%02X%02X", red, green, blue)
    }

    var color: Color {
        Color(.sRGB, red: Double(red) / 255, green: Double(green) / 255, blue: Double(blue) / 255)
    }
}

extension EditorModel {
    // MARK: - Commands

    /// Returns false when the command does not apply, so the key event can pass through.
    func handleViewportCommand(_ command: EditorViewportCommand) -> Bool {
        switch command {
        case .copyColor:
            return copyHoveredColor(darkestNearby: false)
        case .copyTextColor:
            return copyHoveredColor(darkestNearby: true)
        default:
            break
        }

        guard isViewportZoomable else { return false }
        switch command {
        case .zoomIn: zoomIn()
        case .zoomOut: zoomOut()
        case .zoomToFit: zoomToFit()
        case .zoomToActualSize: zoomToActualSize()
        case .zoomInAtCursor: zoomIn(anchor: hoverAnchor)
        case .zoomOutAtCursor: zoomOut(anchor: hoverAnchor)
        case .copyColor, .copyTextColor: break
        }
        return true
    }

    // MARK: - Zoom

    private static let pixelScaleSteps: [CGFloat] = [0.1, 0.25, 0.5, 0.75, 1, 1.5, 2, 3, 4, 6, 8, 12, 16, 24, 32]
    private static let maximumPixelScale: CGFloat = 32
    private static let minimumZoomScale: CGFloat = 0.2

    var isViewportZoomable: Bool {
        sourceImage != nil && collageState == nil
    }

    /// Screen pixels per image pixel; 1 means the image is shown at actual size.
    var pixelScale: CGFloat {
        viewportMetrics.fitScale * zoomScale * viewportMetrics.displayScale
    }

    var zoomPercent: Int {
        Int((pixelScale * 100).rounded())
    }

    var isZoomedToFit: Bool {
        abs(zoomScale - 1) < 0.001 && panOffset == .zero
    }

    func updateViewportMetrics(_ metrics: EditorViewportMetrics) {
        guard viewportMetrics != metrics else { return }
        viewportMetrics = metrics
        clampPanOffset()
    }

    func resetViewport() {
        zoomScale = 1
        panOffset = .zero
        isSpacePanning = false
        hoveredPixel = nil
        hoverAnchor = nil
    }

    func zoomToFit() {
        guard isViewportZoomable else { return }
        zoomScale = 1
        panOffset = .zero
    }

    func zoomToActualSize(anchor: CGPoint? = nil) {
        setPixelScale(1, anchor: anchor)
    }

    func setPixelScale(_ scale: CGFloat, anchor: CGPoint? = nil) {
        guard fitPixelScale > 0 else { return }
        setZoomScale(scale / fitPixelScale, anchor: anchor)
    }

    func zoomIn(anchor: CGPoint? = nil) {
        let current = pixelScale
        let candidates = zoomStops.filter { $0 > current * 1.01 }
        guard let next = candidates.min() else { return }
        applyZoomStop(next, anchor: anchor)
    }

    func zoomOut(anchor: CGPoint? = nil) {
        let current = pixelScale
        let candidates = zoomStops.filter { $0 < current / 1.01 }
        guard let previous = candidates.max() else { return }
        applyZoomStop(previous, anchor: anchor)
    }

    /// Fixed pixel scales plus "fit", so stepping always passes through the whole-image view.
    private var zoomStops: [CGFloat] {
        Self.pixelScaleSteps + [fitPixelScale]
    }

    private var fitPixelScale: CGFloat {
        viewportMetrics.fitScale * viewportMetrics.displayScale
    }

    private func applyZoomStop(_ scale: CGFloat, anchor: CGPoint?) {
        if abs(scale - fitPixelScale) < 0.0001 {
            zoomToFit()
        } else {
            setPixelScale(scale, anchor: anchor)
        }
    }

    /// Multiplies the zoom, used by pinch and command-scroll.
    func zoom(by factor: CGFloat, anchor: CGPoint?) {
        setZoomScale(zoomScale * factor, anchor: anchor)
    }

    /// Changes zoom while keeping the content under `anchor` (relative to the viewport center) in place.
    func setZoomScale(_ newValue: CGFloat, anchor: CGPoint?) {
        guard isViewportZoomable else { return }
        let maxZoom = fitPixelScale > 0 ? max(1, Self.maximumPixelScale / fitPixelScale) : 1
        let clamped = min(max(newValue, Self.minimumZoomScale), maxZoom)
        guard clamped != zoomScale else { return }

        let anchor = anchor ?? .zero
        let ratio = clamped / zoomScale
        panOffset = CGSize(
            width: anchor.x - (anchor.x - panOffset.width) * ratio,
            height: anchor.y - (anchor.y - panOffset.height) * ratio
        )
        zoomScale = clamped
        clampPanOffset()
    }

    func pan(by delta: CGSize) {
        guard isViewportZoomable else { return }
        setPanOffset(CGSize(width: panOffset.width + delta.width, height: panOffset.height + delta.height))
    }

    func setPanOffset(_ offset: CGSize) {
        guard isViewportZoomable else { return }
        panOffset = offset
        clampPanOffset()
    }

    /// Whether panning would move anything, i.e. the canvas overflows the viewport.
    var canPan: Bool {
        let content = zoomedCanvasSize
        let viewport = viewportMetrics.viewportSize
        return content.width > viewport.width || content.height > viewport.height
    }

    private var zoomedCanvasSize: CGSize {
        CGSize(
            width: viewportMetrics.fitCanvasSize.width * zoomScale,
            height: viewportMetrics.fitCanvasSize.height * zoomScale
        )
    }

    private func clampPanOffset() {
        let content = zoomedCanvasSize
        let viewport = viewportMetrics.viewportSize
        let margin: CGFloat = 24
        let limitX = max(0, (content.width - viewport.width) / 2 + margin)
        let limitY = max(0, (content.height - viewport.height) / 2 + margin)
        let clamped = CGSize(
            width: content.width + margin * 2 <= viewport.width ? 0 : min(max(panOffset.width, -limitX), limitX),
            height: content.height + margin * 2 <= viewport.height ? 0 : min(max(panOffset.height, -limitY), limitY)
        )
        if clamped != panOffset {
            panOffset = clamped
        }
    }

    // MARK: - Pixel Inspection

    /// Updates the pixel readout for a hover location in canvas view coordinates.
    func updateHover(at location: CGPoint, imageFrame: CGRect) {
        let viewport = viewportMetrics.viewportSize
        hoverAnchor = CGPoint(x: location.x - viewport.width / 2, y: location.y - viewport.height / 2)

        // Keep the last sampled color when the cursor leaves the image, like Shottr does,
        // so the toolbar readout stays useful and Tab still copies it.
        guard isViewportZoomable, let image = sourceImage,
              imageFrame.width > 0, imageFrame.height > 0,
              imageFrame.contains(location) else { return }

        let x = Int((location.x - imageFrame.minX) / imageFrame.width * CGFloat(image.width))
        let y = Int((location.y - imageFrame.minY) / imageFrame.height * CGFloat(image.height))
        let px = min(max(x, 0), image.width - 1)
        let py = min(max(y, 0), image.height - 1)

        if let current = hoveredPixel, current.x == px, current.y == py { return }
        hoveredPixel = Self.samplePixels(in: image, around: CGPoint(x: px, y: py), radius: 0)
            .first.map { EditorHoveredPixel(x: px, y: py, red: $0.0, green: $0.1, blue: $0.2) }
    }

    func clearHover() {
        hoverAnchor = nil
    }

    /// Copies the hovered color. With `darkestNearby`, copies the darkest pixel in a
    /// 20×20 area instead, which picks up text color without precise aiming.
    /// Returns false when nothing is hovered so the key event can pass through.
    @discardableResult
    func copyHoveredColor(darkestNearby: Bool) -> Bool {
        guard let pixel = hoveredPixel, let image = sourceImage else { return false }

        var target = pixel
        if darkestNearby {
            let samples = Self.samplePixels(in: image, around: CGPoint(x: pixel.x, y: pixel.y), radius: 10)
            if let darkest = samples.min(by: { Self.luminance($0) < Self.luminance($1) }) {
                target = EditorHoveredPixel(x: pixel.x, y: pixel.y, red: darkest.0, green: darkest.1, blue: darkest.2)
            }
        }

        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(target.hex, forType: .string)
        withAnimation { toastMessage = "Copied \(target.hex)" }
        return true
    }

    private static func luminance(_ rgb: (UInt8, UInt8, UInt8)) -> Double {
        0.2126 * Double(rgb.0) + 0.7152 * Double(rgb.1) + 0.0722 * Double(rgb.2)
    }

    /// Reads sRGB pixels in a square around `center` (image pixel coordinates, top-left origin).
    private static func samplePixels(in image: CGImage, around center: CGPoint, radius: Int) -> [(UInt8, UInt8, UInt8)] {
        let rect = CGRect(
            x: Int(center.x) - radius,
            y: Int(center.y) - radius,
            width: radius * 2 + 1,
            height: radius * 2 + 1
        ).intersection(CGRect(x: 0, y: 0, width: image.width, height: image.height))
        guard !rect.isNull, rect.width >= 1, rect.height >= 1,
              let cropped = image.cropping(to: rect) else { return [] }

        let width = cropped.width
        let height = cropped.height
        var buffer = [UInt8](repeating: 0, count: width * height * 4)
        let drawn: Bool = buffer.withUnsafeMutableBytes { raw in
            guard let space = CGColorSpace(name: CGColorSpace.sRGB),
                  let context = CGContext(
                    data: raw.baseAddress,
                    width: width,
                    height: height,
                    bitsPerComponent: 8,
                    bytesPerRow: width * 4,
                    space: space,
                    bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
                  ) else { return false }
            context.draw(cropped, in: CGRect(x: 0, y: 0, width: width, height: height))
            return true
        }
        guard drawn else { return [] }

        var result: [(UInt8, UInt8, UInt8)] = []
        result.reserveCapacity(width * height)
        for index in stride(from: 0, to: buffer.count, by: 4) {
            let alpha = buffer[index + 3]
            guard alpha > 0 else { continue }
            if alpha == 255 {
                result.append((buffer[index], buffer[index + 1], buffer[index + 2]))
            } else {
                // Un-premultiply so semi-transparent pixels report their real color.
                let a = Double(alpha) / 255
                result.append((
                    UInt8(min(255, (Double(buffer[index]) / a).rounded())),
                    UInt8(min(255, (Double(buffer[index + 1]) / a).rounded())),
                    UInt8(min(255, (Double(buffer[index + 2]) / a).rounded()))
                ))
            }
        }
        return result
    }

    // MARK: - Resize

    static let maximumImageDimension = 16_384

    var canRevertImageSize: Bool { imageBeforeResize != nil }

    func resizeImage(to size: CGSize) {
        guard collageState == nil, let image = sourceImage else { return }
        let width = Int(size.width.rounded())
        let height = Int(size.height.rounded())
        guard width >= 1, height >= 1,
              width <= Self.maximumImageDimension, height <= Self.maximumImageDimension,
              width != image.width || height != image.height else { return }

        let original = imageBeforeResize ?? image
        // Resample from the original each time so repeated resizes do not compound blur.
        guard let resized = Self.resample(original, width: width, height: height) else { return }
        if imageBeforeResize == nil { imageBeforeResize = image }
        replaceSourceImage(resized)
        withAnimation { toastMessage = "Resized to \(width) × \(height) px" }
    }

    func revertImageSize() {
        guard let original = imageBeforeResize else { return }
        imageBeforeResize = nil
        replaceSourceImage(original)
        withAnimation { toastMessage = "Restored original size" }
    }

    private func replaceSourceImage(_ image: CGImage) {
        sourceImage = image
        imageSize = CGSize(width: image.width, height: image.height)
        previewImage = NSImage(cgImage: image, size: NSSize(width: image.width, height: image.height))
        hoveredPixel = nil
        RedactionImageProcessor.removeAllCachedPreviewImages()
    }

    private static func resample(_ image: CGImage, width: Int, height: Int) -> CGImage? {
        let bitmapInfo = CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue
        let preferredSpace = image.colorSpace.flatMap { $0.model == .rgb ? $0 : nil }
        guard let space = preferredSpace ?? CGColorSpace(name: CGColorSpace.sRGB),
              let context = CGContext(
                data: nil,
                width: width,
                height: height,
                bitsPerComponent: 8,
                bytesPerRow: 0,
                space: space,
                bitmapInfo: bitmapInfo
              ) else { return nil }
        context.interpolationQuality = .high
        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        return context.makeImage()
    }
}
