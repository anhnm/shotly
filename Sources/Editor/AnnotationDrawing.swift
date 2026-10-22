import CoreGraphics
import CoreImage
import CoreImage.CIFilterBuiltins
import AppKit

enum AnnotationDrawing {

    private static let ciContext = CIContext(options: [.cacheIntermediates: false])

    static func draw(_ items: [AnnotationItem], in ctx: CGContext, imageRect: CGRect, fullCanvasRect: CGRect, sourceImage: CGImage?, flipped: Bool = false) {
        ctx.setLineCap(.round)
        ctx.setLineJoin(.round)

        let hasRedaction = items.contains { $0.tool.isRedactionTool || $0.tool == .magnifier }
        let canvasSnapshot: CGImage? = hasRedaction ? ctx.makeImage() : nil

        for item in items {
            autoreleasepool {
                ctx.setStrokeColor(item.swatch.nsColor.cgColor)
                ctx.setFillColor(item.swatch.nsColor.cgColor)

                let lineWidth = renderedLineWidth(for: item, imageSize: imageRect.size)
                ctx.setLineWidth(lineWidth)

                switch item.tool {
                case .select:
                    return

                case .rectangle:
                    let rect = renderedRect(item.bounds, in: imageRect, flipped: flipped)
                    let radius = item.shapeStyle.cornerRadius(for: rect, lineWidth: lineWidth)
                    ctx.saveGState()
                    if item.shapeStyle == .sharp { ctx.setLineJoin(.miter) }
                    if let dash = item.shapeStyle.dashPattern(lineWidth: lineWidth) {
                        ctx.setLineCap(.butt)
                        ctx.setLineDash(phase: 0, lengths: dash)
                    }
                    ctx.addPath(CGPath(roundedRect: rect, cornerWidth: radius, cornerHeight: radius, transform: nil))
                    ctx.strokePath()
                    ctx.restoreGState()

                case .filledRectangle:
                    let rect = renderedRect(item.bounds, in: imageRect, flipped: flipped)
                    ctx.addPath(CGPath(
                        roundedRect: rect,
                        cornerWidth: AnnotationFilledRectangleMetrics.cornerRadius(for: rect),
                        cornerHeight: AnnotationFilledRectangleMetrics.cornerRadius(for: rect),
                        transform: nil
                    ))
                    ctx.fillPath()

                case .ellipse:
                    let path = item.ellipseStyle.path(in: renderedRect(item.bounds, in: imageRect, flipped: flipped))
                    if let opacity = item.ellipseStyle.fillOpacity {
                        ctx.saveGState()
                        ctx.setFillColor(item.swatch.nsColor.withAlphaComponent(item.swatch.alpha * opacity).cgColor)
                        ctx.addPath(path)
                        ctx.fillPath()
                        ctx.restoreGState()
                    }
                    if item.ellipseStyle != .filled {
                        ctx.addPath(path)
                        ctx.strokePath()
                    }

                case .numberedCircle:
                    drawNumberedCircle(item, in: renderedRect(item.bounds, in: imageRect, flipped: flipped), context: ctx, flipped: flipped)

                case .pixelate:
                    guard let canvasSnapshot else { return }
                    applyPixelation(
                        in: renderedRect(item.bounds, in: imageRect, flipped: flipped),
                        canvasSnapshot: canvasSnapshot,
                        context: ctx,
                        canvasSize: fullCanvasRect.size,
                        colorSpace: CGColorSpaceCreateDeviceRGB(),
                        density: item.redactionDensity,
                        flipped: flipped
                    )

                case .blur:
                    guard let canvasSnapshot else { return }
                    applyBlur(
                        in: renderedRect(item.bounds, in: imageRect, flipped: flipped),
                        canvasSnapshot: canvasSnapshot,
                        context: ctx,
                        canvasSize: fullCanvasRect.size,
                        density: item.redactionDensity,
                        flipped: flipped
                    )

                case .magnifier:
                    guard let canvasSnapshot else { return }
                    drawMagnifier(
                        item,
                        imageRect: imageRect,
                        canvasSnapshot: canvasSnapshot,
                        context: ctx,
                        lineWidth: lineWidth,
                        flipped: flipped
                    )

                case .spotlight:
                    let targetRect = renderedRect(item.bounds, in: imageRect, flipped: flipped)
                    let overlayColor = CGColor(gray: 0, alpha: item.redactionDensity)
                    ctx.saveGState()
                    let fullPath = CGMutablePath()
                    fullPath.addRect(fullCanvasRect)
                    fullPath.addRect(targetRect)
                    ctx.addPath(fullPath)
                    ctx.setFillColor(overlayColor)
                    ctx.fillPath(using: .evenOdd)
                    ctx.restoreGState()

                case .text:
                    drawText(item, in: renderedRect(item.bounds, in: imageRect, flipped: flipped), imageHeight: imageRect.height, context: ctx, flipped: flipped)

                case .line:
                    guard let first = item.points.first,
                          let last = item.points.last else { return }
                    let start = renderedPoint(first, in: imageRect, flipped: flipped)
                    let end = renderedPoint(last, in: imageRect, flipped: flipped)
                    ctx.beginPath()
                    ctx.move(to: start)
                    ctx.addLine(to: end)
                    ctx.strokePath()

                case .measure:
                    drawMeasure(
                        item,
                        imageRect: imageRect,
                        context: ctx,
                        lineWidth: lineWidth,
                        flipped: flipped
                    )

                case .freehand:
                    drawFreehand(points: item.points, imageRect: imageRect, context: ctx, flipped: flipped)

                case .arrow:
                    guard let first = item.points.first,
                          let control = item.controlPoint,
                          let last = item.points.last,
                          let geometry = AnnotationArrowGeometry(
                            start: renderedPoint(first, in: imageRect, flipped: flipped),
                            control: renderedPoint(control, in: imageRect, flipped: flipped),
                            end: renderedPoint(last, in: imageRect, flipped: flipped),
                            lineWidth: lineWidth
                          ) else { return }
                    let start = renderedPoint(first, in: imageRect, flipped: flipped)
                    let controlPoint = renderedPoint(control, in: imageRect, flipped: flipped)
                    if item.arrowStyle == .line {
                        ctx.beginPath()
                        ctx.move(to: start)
                        ctx.addQuadCurve(to: geometry.tip, control: geometry.shaftControl)
                        ctx.strokePath()
                        drawArrowHead(geometry, context: ctx)
                        if item.arrowDoubleHeaded,
                           let tail = AnnotationArrowGeometry(start: geometry.tip, control: controlPoint, end: start, lineWidth: lineWidth) {
                            drawArrowHead(tail, context: ctx)
                        }
                    } else if let path = AnnotationArrowShape.path(
                        start: start,
                        control: controlPoint,
                        end: geometry.tip,
                        lineWidth: lineWidth,
                        doubleHeaded: item.arrowDoubleHeaded,
                        widthScale: item.arrowStyle == .outline ? 1.5 : 1
                    ) {
                        ctx.addPath(path)
                        if item.arrowStyle == .filled {
                            ctx.fillPath()
                        } else {
                            ctx.saveGState()
                            ctx.setLineWidth(max(1.5, lineWidth * 0.45))
                            ctx.strokePath()
                            ctx.restoreGState()
                        }
                    }
                }
            }
        }
    }

    static func draw(_ items: [AnnotationItem], in ctx: CGContext, canvasSize: CGSize, sourceImage: CGImage?) {
        let rect = CGRect(origin: .zero, size: canvasSize)
        draw(items, in: ctx, imageRect: rect, fullCanvasRect: rect, sourceImage: sourceImage)
    }

    private static func renderedRect(_ rect: CGRect, in imageRect: CGRect, flipped: Bool = false) -> CGRect {
        if flipped {
            return CGRect(
                x: imageRect.minX + rect.minX * imageRect.width,
                y: imageRect.minY + rect.minY * imageRect.height,
                width: rect.width * imageRect.width,
                height: rect.height * imageRect.height
            )
        }
        return CGRect(
            x: imageRect.minX + rect.minX * imageRect.width,
            y: imageRect.minY + (1 - rect.maxY) * imageRect.height,
            width: rect.width * imageRect.width,
            height: rect.height * imageRect.height
        )
    }

    private static func renderedPoint(_ point: CGPoint, in imageRect: CGRect, flipped: Bool = false) -> CGPoint {
        if flipped {
            return CGPoint(
                x: imageRect.minX + point.x * imageRect.width,
                y: imageRect.minY + point.y * imageRect.height
            )
        }
        return CGPoint(
            x: imageRect.minX + point.x * imageRect.width,
            y: imageRect.minY + (1 - point.y) * imageRect.height
        )
    }

    private static func drawArrowHead(_ geometry: AnnotationArrowGeometry, context: CGContext) {
        context.beginPath()
        context.move(to: geometry.firstWing)
        context.addLine(to: geometry.tip)
        context.addLine(to: geometry.secondWing)
        context.strokePath()
    }

    private static func drawMeasure(
        _ item: AnnotationItem,
        imageRect: CGRect,
        context: CGContext,
        lineWidth: CGFloat,
        flipped: Bool
    ) {
        guard let normalizedStart = item.points.first,
              let normalizedEnd = item.points.last else { return }

        let start = renderedPoint(normalizedStart, in: imageRect, flipped: flipped)
        let end = renderedPoint(normalizedEnd, in: imageRect, flipped: flipped)
        let horizontal = AnnotationMeasureMetrics.isHorizontal(
            start: normalizedStart,
            end: normalizedEnd,
            imageSize: imageRect.size
        )
        let fontSize = AnnotationMeasureMetrics.exportFontSize(for: imageRect.size)
        let capLength = fontSize * 0.8

        context.beginPath()
        context.move(to: start)
        context.addLine(to: end)
        if horizontal {
            context.move(to: CGPoint(x: start.x, y: start.y - capLength / 2))
            context.addLine(to: CGPoint(x: start.x, y: start.y + capLength / 2))
            context.move(to: CGPoint(x: end.x, y: end.y - capLength / 2))
            context.addLine(to: CGPoint(x: end.x, y: end.y + capLength / 2))
        } else {
            context.move(to: CGPoint(x: start.x - capLength / 2, y: start.y))
            context.addLine(to: CGPoint(x: start.x + capLength / 2, y: start.y))
            context.move(to: CGPoint(x: end.x - capLength / 2, y: end.y))
            context.addLine(to: CGPoint(x: end.x + capLength / 2, y: end.y))
        }
        context.strokePath()

        let label = AnnotationMeasureMetrics.label(
            start: normalizedStart,
            end: normalizedEnd,
            imageSize: imageRect.size
        )
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.monospacedDigitSystemFont(ofSize: fontSize, weight: .semibold),
            .foregroundColor: item.swatch.numberedCircleTextNSColor
        ]
        let attributedLabel = NSAttributedString(string: label, attributes: attributes)
        let textSize = attributedLabel.size()
        let padding = fontSize * 0.4
        let labelSize = CGSize(width: textSize.width + padding * 2, height: textSize.height + padding * 0.6)
        let center = AnnotationMeasureMetrics.labelCenter(
            start: start,
            end: end,
            horizontal: horizontal,
            labelSize: labelSize,
            capLength: capLength,
            bounds: imageRect
        )

        let labelRect = CGRect(
            x: center.x - labelSize.width / 2,
            y: center.y - labelSize.height / 2,
            width: labelSize.width,
            height: labelSize.height
        )

        context.saveGState()
        context.setFillColor(item.swatch.nsColor.cgColor)
        context.addPath(CGPath(
            roundedRect: labelRect,
            cornerWidth: fontSize * 0.3,
            cornerHeight: fontSize * 0.3,
            transform: nil
        ))
        context.fillPath()

        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(cgContext: context, flipped: flipped)
        attributedLabel.draw(at: CGPoint(
            x: labelRect.minX + padding,
            y: labelRect.minY + (labelRect.height - textSize.height) / 2
        ))
        NSGraphicsContext.restoreGraphicsState()
        context.restoreGState()
    }

    private static func drawNumberedCircle(_ item: AnnotationItem, in rect: CGRect, context: CGContext, flipped: Bool = false) {
        let diameter = min(rect.width, rect.height)
        guard diameter > 1 else { return }

        let outlineWidth = AnnotationNumberedCircleMetrics.outlineWidth(for: diameter)
        // Pointer angles are stored y-down; unflipped contexts are y-up.
        let badgePath = item.badgeStyle.path(
            center: CGPoint(x: rect.midX, y: rect.midY),
            radius: diameter / 2,
            angle: flipped ? item.pointerAngle : -item.pointerAngle
        )
        context.saveGState()
        context.setFillColor(item.swatch.nsColor.cgColor)
        context.addPath(badgePath)
        context.fillPath()
        // Stroke twice as wide and clip to the shape, so the outline sits inside it.
        context.addPath(badgePath)
        context.clip()
        context.addPath(badgePath)
        context.setStrokeColor(item.swatch.numberedCircleOutlineNSColor.cgColor)
        context.setLineWidth(outlineWidth * 2)
        context.setLineJoin(.round)
        context.strokePath()
        context.restoreGState()

        let fontSize = AnnotationNumberedCircleMetrics.fontSize(for: diameter, text: item.text)
        let font = NSFont.monospacedDigitSystemFont(ofSize: fontSize, weight: .bold)
        let paragraphStyle = NSMutableParagraphStyle()
        paragraphStyle.alignment = .center
        paragraphStyle.lineBreakMode = .byClipping

        let attributes: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: item.swatch.numberedCircleTextNSColor,
            .paragraphStyle: paragraphStyle
        ]
        let attributedText = NSAttributedString(string: item.text, attributes: attributes)
        let measuredRect = attributedText.boundingRect(
            with: CGSize(width: rect.width, height: rect.height),
            options: [.usesLineFragmentOrigin, .usesFontLeading]
        )
        let textRect = CGRect(
            x: rect.minX,
            y: rect.midY - measuredRect.height / 2 - fontSize * 0.04,
            width: rect.width,
            height: measuredRect.height + 2
        )

        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(cgContext: context, flipped: flipped)
        attributedText.draw(with: textRect, options: [.usesLineFragmentOrigin, .usesFontLeading])
        NSGraphicsContext.restoreGraphicsState()
    }

    private static func drawFreehand(points: [CGPoint], imageRect: CGRect, context: CGContext, flipped: Bool = false) {
        let renderedPoints = points.map { renderedPoint($0, in: imageRect, flipped: flipped) }
        guard let first = renderedPoints.first else { return }

        context.beginPath()
        context.move(to: first)
        guard renderedPoints.count > 1 else { return }

        if renderedPoints.count == 2 {
            context.addLine(to: renderedPoints[1])
            context.strokePath()
            return
        }

        for index in 1..<renderedPoints.count {
            let previous = renderedPoints[index - 1]
            let current = renderedPoints[index]
            context.addQuadCurve(to: midpoint(previous, current), control: previous)
        }

        context.addLine(to: renderedPoints[renderedPoints.count - 1])
        context.strokePath()
    }

    private static func midpoint(_ lhs: CGPoint, _ rhs: CGPoint) -> CGPoint {
        CGPoint(x: (lhs.x + rhs.x) / 2, y: (lhs.y + rhs.y) / 2)
    }

    private static func drawText(_ item: AnnotationItem, in rect: CGRect, imageHeight: CGFloat, context: CGContext, flipped: Bool = false) {
        let text = item.text.trimmingCharacters(in: .newlines)
        guard !text.isEmpty, rect.width > 1, rect.height > 1 else { return }

        let fontSize = AnnotationTextMetrics.renderedFontSize(lineHeight: item.textLineHeight, imagePixelHeight: imageHeight)
        let font = item.resolvedFont(size: fontSize)
        let paragraphStyle = NSMutableParagraphStyle()
        paragraphStyle.alignment = item.textAlignment
        paragraphStyle.lineBreakMode = .byClipping

        var attributes: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: item.swatch.nsColor,
            .paragraphStyle: paragraphStyle,
            .shadow: AnnotationTextMetrics.textShadow
        ]
        if item.isUnderline {
            attributes[.underlineStyle] = NSUnderlineStyle.single.rawValue
        }
        let attributedText = NSAttributedString(string: text, attributes: attributes)

        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(cgContext: context, flipped: flipped)
        attributedText.draw(with: rect, options: [.usesLineFragmentOrigin, .usesFontLeading])
        NSGraphicsContext.restoreGraphicsState()
    }

    private static func applyPixelation(
        in rect: CGRect,
        canvasSnapshot: CGImage,
        context: CGContext,
        canvasSize: CGSize,
        colorSpace: CGColorSpace,
        density: CGFloat,
        flipped: Bool = false
    ) {
        let targetRect = rect.integral.intersection(CGRect(origin: .zero, size: canvasSize))
        guard targetRect.width >= 1,
              targetRect.height >= 1,
              let croppedImage = canvasSnapshot.cropping(to: imageCropRect(for: targetRect, imageHeight: CGFloat(canvasSnapshot.height), flipped: flipped)) else {
            return
        }

        let pixelSize = RedactionImageProcessor.pixelBlockSize(for: density)
        let lowWidth = max(1, Int(targetRect.width / pixelSize))
        let lowHeight = max(1, Int(targetRect.height / pixelSize))

        guard let lowContext = CGContext(
            data: nil, width: lowWidth, height: lowHeight,
            bitsPerComponent: 8, bytesPerRow: 0, space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return }

        lowContext.interpolationQuality = .medium
        lowContext.draw(croppedImage, in: CGRect(x: 0, y: 0, width: lowWidth, height: lowHeight))
        guard let pixelatedImage = lowContext.makeImage() else { return }

        context.saveGState()
        context.clip(to: targetRect)
        context.interpolationQuality = .none
        if flipped {
            context.translateBy(x: targetRect.minX, y: targetRect.maxY)
            context.scaleBy(x: 1, y: -1)
            context.draw(pixelatedImage, in: CGRect(x: 0, y: 0, width: targetRect.width, height: targetRect.height))
        } else {
            context.draw(pixelatedImage, in: targetRect)
        }
        context.restoreGState()
    }

    private static func applyBlur(
        in rect: CGRect,
        canvasSnapshot: CGImage,
        context: CGContext,
        canvasSize: CGSize,
        density: CGFloat,
        flipped: Bool = false
    ) {
        let targetRect = rect.integral.intersection(CGRect(origin: .zero, size: canvasSize))
        guard targetRect.width >= 1,
              targetRect.height >= 1,
              let croppedImage = canvasSnapshot.cropping(to: imageCropRect(for: targetRect, imageHeight: CGFloat(canvasSnapshot.height), flipped: flipped)) else {
            return
        }

        let radius = RedactionImageProcessor.blurRadius(for: density)
        let fullImageRect = CGRect(x: 0, y: 0, width: canvasSnapshot.width, height: canvasSnapshot.height)
        let cropRectInImage = imageCropRect(for: targetRect, imageHeight: CGFloat(canvasSnapshot.height), flipped: flipped)
        let paddedCropRect = cropRectInImage
            .insetBy(dx: -ceil(radius * 2), dy: -ceil(radius * 2))
            .intersection(fullImageRect)
            .integral

        let paddedImage: CGImage
        if let padded = canvasSnapshot.cropping(to: paddedCropRect) {
            paddedImage = padded
        } else {
            paddedImage = croppedImage
        }

        let inputImage = CIImage(cgImage: paddedImage)
        let filter = CIFilter.gaussianBlur()
        filter.inputImage = inputImage.clampedToExtent()
        filter.radius = Float(radius)

        let outputRect = CGRect(
            x: cropRectInImage.minX - paddedCropRect.minX,
            y: cropRectInImage.minY - paddedCropRect.minY,
            width: cropRectInImage.width,
            height: cropRectInImage.height
        )

        guard let outputImage = filter.outputImage,
              let blurredImage = ciContext.createCGImage(outputImage, from: outputRect) else {
            return
        }

        context.saveGState()
        context.clip(to: targetRect)
        if flipped {
            context.translateBy(x: targetRect.minX, y: targetRect.maxY)
            context.scaleBy(x: 1, y: -1)
            context.draw(blurredImage, in: CGRect(x: 0, y: 0, width: targetRect.width, height: targetRect.height))
        } else {
            context.draw(blurredImage, in: targetRect)
        }
        context.restoreGState()
        ciContext.clearCaches()
    }

    /// Draws the source circle, a connector, and the lens showing the source
    /// enlarged around its centre.
    private static func drawMagnifier(
        _ item: AnnotationItem,
        imageRect: CGRect,
        canvasSnapshot: CGImage,
        context: CGContext,
        lineWidth: CGFloat,
        flipped: Bool
    ) {
        guard let lensRect = item.magnifierLensRect else { return }
        let source = renderedRect(item.bounds, in: imageRect, flipped: flipped)
        let lens = renderedRect(lensRect, in: imageRect, flipped: flipped)
        guard source.width >= 1, lens.width >= 1 else { return }

        context.saveGState()
        context.setStrokeColor(item.swatch.nsColor.cgColor)
        context.setLineWidth(lineWidth)
        context.strokeEllipse(in: source)
        if let (from, to) = AnnotationMagnifierMetrics.connector(source: source, lens: lens) {
            context.move(to: from)
            context.addLine(to: to)
            context.strokePath()
        }
        context.restoreGState()

        let snapshotRect = CGRect(x: 0, y: 0, width: canvasSnapshot.width, height: canvasSnapshot.height)
        let zoomedRect = AnnotationMagnifierMetrics.zoomedImageRect(
            snapshotRect, source: source, lens: lens, magnification: item.magnification
        )
        context.saveGState()
        context.addEllipse(in: lens)
        context.clip()
        context.interpolationQuality = item.magnification >= 3 ? .none : .high
        if flipped {
            context.translateBy(x: 0, y: zoomedRect.minY + zoomedRect.maxY)
            context.scaleBy(x: 1, y: -1)
        }
        context.draw(canvasSnapshot, in: zoomedRect)
        context.restoreGState()

        context.saveGState()
        context.setStrokeColor(item.swatch.nsColor.cgColor)
        context.setLineWidth(lineWidth)
        context.strokeEllipse(in: lens.insetBy(dx: lineWidth / 2, dy: lineWidth / 2))
        context.restoreGState()
    }

    private static func renderedLineWidth(for item: AnnotationItem, imageSize: CGSize) -> CGFloat {
        max(1.5, item.strokeWidth * max(imageSize.width, imageSize.height) / 900)
    }

    private static func imageCropRect(for contextRect: CGRect, imageHeight: CGFloat, flipped: Bool = false) -> CGRect {
        if flipped {
            return CGRect(
                x: contextRect.minX,
                y: contextRect.minY,
                width: contextRect.width,
                height: contextRect.height
            ).integral
        }
        return CGRect(
            x: contextRect.minX,
            y: imageHeight - contextRect.maxY,
            width: contextRect.width,
            height: contextRect.height
        ).integral
    }
}
