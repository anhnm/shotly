import AppKit
import CoreGraphics
import Foundation

enum WatermarkRenderer {
    static func draw(
        preset: WatermarkPreset,
        in ctx: CGContext,
        imageRect: CGRect
    ) {
        ctx.saveGState()
        
        var wmWidth: CGFloat = 0
        var wmHeight: CGFloat = 0
        var imageToDraw: CGImage? = nil
        var attrString: NSAttributedString? = nil
        
        let targetShortEdge = min(imageRect.width, imageRect.height)
        guard targetShortEdge > 0 else {
            ctx.restoreGState()
            return
        }
        
        if preset.type == .image, let relativePath = preset.imagePath {
            let fullURL = resolveImagePath(for: relativePath)
            if let source = CGImageSourceCreateWithURL(fullURL as CFURL, nil),
               let img = CGImageSourceCreateImageAtIndex(source, 0, nil) {
                imageToDraw = img
                let imgW = CGFloat(img.width)
                let imgH = CGFloat(img.height)
                
                let scaleFactor = (targetShortEdge * preset.scale) / max(imgW, imgH, 1.0)
                wmWidth = imgW * scaleFactor
                wmHeight = imgH * scaleFactor
            }
        } else if preset.type == .text, let text = preset.textContent, !text.isEmpty {
            let scaledFontSize = preset.fontSize * (targetShortEdge / 800.0)
            let font = NSFont(name: preset.fontName, size: scaledFontSize) ?? NSFont.systemFont(ofSize: scaledFontSize)
            let color = preset.fontColor.nsColor.withAlphaComponent(preset.opacity)
            
            let attrs: [NSAttributedString.Key: Any] = [
                .font: font,
                .foregroundColor: color
            ]
            let nsStr = text as NSString
            attrString = NSAttributedString(string: text, attributes: attrs)
            let size = nsStr.size(withAttributes: attrs)
            wmWidth = size.width
            wmHeight = size.height
        }
        
        guard wmWidth > 0, wmHeight > 0 else {
            ctx.restoreGState()
            return
        }
        
        let margin = targetShortEdge * 0.04
        
        var x: CGFloat = 0
        var y: CGFloat = 0
        
        switch preset.position {
        case .topLeft:
            x = imageRect.minX + margin
            y = imageRect.maxY - margin - wmHeight
        case .topRight:
            x = imageRect.maxX - margin - wmWidth
            y = imageRect.maxY - margin - wmHeight
        case .bottomLeft:
            x = imageRect.minX + margin
            y = imageRect.minY + margin
        case .bottomRight:
            x = imageRect.maxX - margin - wmWidth
            y = imageRect.minY + margin
        case .center:
            x = imageRect.midX - wmWidth / 2
            y = imageRect.midY - wmHeight / 2
        }
        
        // For images, we apply global alpha since the image pixels don't embed opacity.
        // For text, the NSAttributedString color already has the opacity, but it's safe to apply.
        ctx.setAlpha(preset.opacity)
        
        let centerX = x + wmWidth / 2
        let centerY = y + wmHeight / 2
        
        ctx.translateBy(x: centerX, y: centerY)
        ctx.rotate(by: CGFloat(preset.rotationDegrees * .pi / 180.0))
        
        let drawRect = CGRect(x: -wmWidth / 2, y: -wmHeight / 2, width: wmWidth, height: wmHeight)
        
        if let imageToDraw = imageToDraw {
            ctx.draw(imageToDraw, in: drawRect)
        } else if let attrString = attrString {
            NSGraphicsContext.saveGraphicsState()
            let nsgc = NSGraphicsContext(cgContext: ctx, flipped: false)
            NSGraphicsContext.current = nsgc
            attrString.draw(in: drawRect)
            NSGraphicsContext.restoreGraphicsState()
        }
        
        ctx.restoreGState()
    }

    private static func resolveImagePath(for filename: String) -> URL {
        let watermarksDir = AppPaths.supportDirectory.appendingPathComponent("Watermarks", isDirectory: true)
        return watermarksDir.appendingPathComponent(filename)
    }
}
