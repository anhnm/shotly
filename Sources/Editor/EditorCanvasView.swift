import SwiftUI

struct EditorCanvasView: View {
    @Bindable var model: EditorModel

    @State private var hasActiveInteraction = false
    @State private var hoveredLocation: CGPoint?
    @State private var currentCursor: AnnotationCanvasCursor = .arrow
    @State private var panDragOrigin: CGSize?
    @Environment(\.displayScale) private var displayScale

    var body: some View {
        GeometryReader { proxy in
            if model.sourceImage != nil || model.collageState != nil {
                let sourceImage = model.sourceImage
                let imgW = model.collageState != nil ? model.imageSize.width : CGFloat(sourceImage!.width)
                let imgH = model.collageState != nil ? model.imageSize.height : CGFloat(sourceImage!.height)
                let shortEdge = min(imgW, imgH)
                let pad = shortEdge * model.config.padding

                var canvasW = imgW + pad * 2
                var canvasH = imgH + pad * 2
                let _ = {
                    if let ratio = model.config.aspectRatio.numericValue {
                        let current = canvasW / canvasH
                        if current < ratio { canvasW = canvasH * ratio }
                        else { canvasH = canvasW / ratio }
                    }
                }()

                let showMeta = model.showMetadata && model.captureMetadata != nil
                let metaFontSize = model.config.metadataFontSize * (shortEdge / 800.0)
                let metaHeight = showMeta ? metaFontSize * 2.2 : 0.0
                let displayCanvasH = canvasH + metaHeight

                let canvasSize = CGSize(width: canvasW, height: displayCanvasH)
                let fitFrame = aspectFitRect(imageSize: canvasSize, in: proxy.size)
                let zoom = model.isViewportZoomable ? model.zoomScale : 1
                let pan = model.isViewportZoomable ? model.panOffset : .zero
                let canvasFrame = CGRect(
                    x: proxy.size.width / 2 + pan.width - fitFrame.width * zoom / 2,
                    y: proxy.size.height / 2 + pan.height - fitFrame.height * zoom / 2,
                    width: fitFrame.width * zoom,
                    height: fitFrame.height * zoom
                )
                let viewportMetrics = EditorViewportMetrics(
                    viewportSize: proxy.size,
                    fitCanvasSize: fitFrame.size,
                    fitScale: canvasW > 0 ? fitFrame.width / canvasW : 1,
                    displayScale: displayScale
                )

                let totalHPad = canvasW - imgW
                let totalVPad = canvasH - imgH
                let imgXNorm = model.config.alignment.xFactor * totalHPad / canvasW
                let imgYNorm = model.config.alignment.yFactor * totalVPad / displayCanvasH
                let imgWNorm = imgW / canvasW
                let imgHNorm = imgH / displayCanvasH

                let sourceImageFrame = CGRect(
                    x: canvasFrame.minX + imgXNorm * canvasFrame.width,
                    y: canvasFrame.minY + imgYNorm * canvasFrame.height,
                    width: imgWNorm * canvasFrame.width,
                    height: imgHNorm * canvasFrame.height
                )

                let baseRadius = model.config.cornerRadius * shortEdge
                let m = model.config.alignment.cornerMultipliers
                let cornerScale = min(canvasFrame.width / canvasW, canvasFrame.height / displayCanvasH)
                let viewRadii = (
                    tl: baseRadius * m.tl * cornerScale,
                    tr: baseRadius * m.tr * cornerScale,
                    br: baseRadius * m.br * cornerScale,
                    bl: baseRadius * m.bl * cornerScale
                )

                ZStack(alignment: .topLeading) {
                    // Background layer
                    if model.collageState == nil {
                        CanvasBackgroundView(style: model.config.style)
                            .frame(width: canvasFrame.width, height: canvasFrame.height)
                            .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
                            .position(x: canvasFrame.midX, y: canvasFrame.midY)
                    }

                    // Shadow + Screenshot layer
                    if let displayedCollage = model.collageState {
                        CanvasCollageView(
                            collage: Binding(
                                // SwiftUI may update this binding once more during
                                // the frame where Done finalizes and clears the
                                // collage. Keep the last valid value for that frame
                                // instead of force-unwrapping a now-nil state.
                                get: { model.collageState ?? displayedCollage },
                                set: { updatedCollage in
                                    guard model.collageState != nil else { return }
                                    model.collageState = updatedCollage
                                }
                            ),
                            selectedSlotID: Binding(
                                get: { model.selectedCollageSlotID },
                                set: { model.selectedCollageSlotID = $0 }
                            ),
                            frame: sourceImageFrame,
                            cornerRadii: viewRadii,
                            shadowStrength: model.config.shadowStrength,
                            shortEdge: shortEdge * cornerScale,
                            renderScale: cornerScale
                        )
                    } else if let image = sourceImage {
                        CanvasScreenshotView(
                            image: image,
                            frame: sourceImageFrame,
                            cornerRadii: viewRadii,
                            shadowStrength: model.config.shadowStrength,
                            shortEdge: shortEdge * cornerScale,
                            showsPixels: model.pixelScale >= 3
                        )
                    }

                    if showMeta, let metadata = model.captureMetadata {
                        let scale = canvasFrame.width / canvasW
                        let viewMetaFontSize = metaFontSize * scale
                        let viewMetaHeight = metaHeight * scale
                        Text(metadata.displayString)
                            .font(.system(size: viewMetaFontSize, weight: .regular, design: .monospaced))
                            .foregroundStyle(model.config.metadataColor.color)
                            .frame(width: canvasFrame.width, height: viewMetaHeight)
                            .position(x: canvasFrame.midX, y: canvasFrame.maxY - viewMetaHeight / 2)
                    }

                    // Annotations
                    ForEach(model.items) { item in
                        AnnotationItemView(
                            item: displayItem(item, zoom: zoom),
                            image: model.collageState != nil ? (model.renderCleanCollage().map { NSImage(cgImage: $0, size: model.imageSize) } ?? NSImage()) : (model.previewImage ?? NSImage()),
                            sourceImage: model.collageState != nil ? model.renderCleanCollage() : model.sourceImage,
                            originalImageSize: model.imageSize,
                            imageFrame: sourceImageFrame,
                            canvasFrame: canvasFrame,
                            isSelected: model.selectedItemIDs.contains(item.id),
                            showsResizeHandles: model.selectionCount == 1,
                            isEditingText: item.id == model.editingTextItemID,
                            allowsRedactionPreviewCaching: !(model.isTransformingExistingAnnotation && model.selectedItemIDs.contains(item.id)),
                            text: Binding(
                                get: { item.text },
                                set: { model.setText($0, for: item.id) }
                            ),
                            onCommitText: model.commitTextEditing,
                            onTextSizeChange: { size in
                                model.setTextViewContentSize(size, for: item.id, imageFrame: sourceImageFrame, allowedBounds: model.annotationBounds(for: sourceImageFrame, boundaryFrame: canvasFrame))
                            }
                        )
                    }
                    .allowsHitTesting(!model.isCropping)

                    if let wm = model.activeWatermarkPreset {
                        WatermarkPreviewView(preset: wm, imageFrame: sourceImageFrame)
                    }

                    if model.isCropping {
                        ImageCropOverlay(cropRect: $model.cropRect, imageSize: CGSize(width: sourceImageFrame.width, height: sourceImageFrame.height))
                            .position(x: sourceImageFrame.midX, y: sourceImageFrame.midY)
                    } else if model.hasCrop {
                        ImageCropPreview(cropRect: model.cropRect, imageSize: CGSize(width: sourceImageFrame.width, height: sourceImageFrame.height))
                            .position(x: sourceImageFrame.midX, y: sourceImageFrame.midY)
                    }

                    if let draftItem = model.draftItem {
                        AnnotationItemView(
                            item: displayItem(draftItem, zoom: zoom),
                            image: model.collageState != nil ? (model.renderCleanCollage().map { NSImage(cgImage: $0, size: model.imageSize) } ?? NSImage()) : (model.previewImage ?? NSImage()),
                            sourceImage: model.collageState != nil ? model.renderCleanCollage() : model.sourceImage,
                            originalImageSize: model.imageSize,
                            imageFrame: sourceImageFrame,
                            canvasFrame: canvasFrame,
                            isSelected: false,
                            showsResizeHandles: false,
                            isEditingText: false,
                            allowsRedactionPreviewCaching: false,
                            text: .constant(draftItem.text),
                            onCommitText: {},
                            onTextSizeChange: { _ in }
                        )
                    }

                    // Smart ruler: live spans under the cursor; click to keep them.
                    ForEach(Array(model.smartRulerItems.enumerated()), id: \.offset) { _, item in
                        AnnotationItemView(
                            item: displayItem(item, zoom: zoom),
                            image: NSImage(),
                            sourceImage: nil,
                            originalImageSize: model.imageSize,
                            imageFrame: sourceImageFrame,
                            canvasFrame: canvasFrame,
                            isSelected: false,
                            showsResizeHandles: false,
                            isEditingText: false,
                            allowsRedactionPreviewCaching: false,
                            text: .constant(""),
                            onCommitText: {},
                            onTextSizeChange: { _ in }
                        )
                        .opacity(0.85)
                    }

                    if let selectionRect = model.selectionRect {
                        let viewSel = viewRect(selectionRect, in: sourceImageFrame)
                        AnnotationMarqueeSelectionView()
                            .frame(
                                width: max(viewSel.width, 1),
                                height: max(viewSel.height, 1)
                            )
                            .position(x: viewSel.midX, y: viewSel.midY)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .contentShape(Rectangle())
                .gesture(
                    interactionGesture(imageFrame: sourceImageFrame, boundaryFrame: canvasFrame),
                    isEnabled: model.collageState == nil
                )
                .onContinuousHover { phase in
                    switch phase {
                    case .active(let location):
                        hoveredLocation = location
                        model.updateHover(at: location, imageFrame: sourceImageFrame)
                        updateCursor(at: location, imageFrame: sourceImageFrame)
                    case .ended:
                        hoveredLocation = nil
                        model.clearHover()
                        setCursor(.arrow)
                    }
                }
                .background {
                    CanvasViewportEventView(
                        onScroll: { event, anchor in handleScroll(event, anchor: anchor) },
                        onMagnify: { magnification, anchor in
                            guard model.isViewportZoomable else { return false }
                            model.zoom(by: 1 + magnification, anchor: anchor)
                            return true
                        }
                    )
                }
                .onChange(of: viewportMetrics, initial: true) { _, metrics in
                    model.updateViewportMetrics(metrics)
                }
                .onChange(of: model.selectedTool) { _, _ in refreshCursor(imageFrame: sourceImageFrame) }
                .onChange(of: model.isSpacePanning) { _, _ in refreshCursor(imageFrame: sourceImageFrame) }
                .onChange(of: model.itemIDs) { _, _ in refreshCursor(imageFrame: sourceImageFrame) }
                .onChange(of: model.selectedItemIDs) { _, _ in refreshCursor(imageFrame: sourceImageFrame) }
                .onDisappear { setCursor(.arrow) }
            } else {
                EmptyEditorStateView(
                    onCaptureAction: { action in
                        let screen = NSApp.keyWindow?.screen
                        NSApp.keyWindow?.close()
                        Task {
                            try? await Task.sleep(nanoseconds: 200_000_000)
                            await CaptureOrchestrator.shared.performCapture(action, on: screen)
                        }
                    },
                    onRecordAction: {
                        let screen = NSApp.keyWindow?.screen
                        NSApp.keyWindow?.close()
                        Task {
                            try? await Task.sleep(nanoseconds: 200_000_000)
                            let started = try? await ScreenRecordingManager.shared.startAreaRecording()
                            if started == true {
                                RecordingStatusBarController.shared.show(on: screen)
                            }
                        }
                    }
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color(nsColor: .windowBackgroundColor))
            }
        }
        .clipped()
        .background(TransparencyGrid(style: .dark))
    }

    /// Stroke widths are in view points at fit size; scale them with the zoom so
    /// annotations keep their proportions to the image, matching the export.
    private func displayItem(_ item: AnnotationItem, zoom: CGFloat) -> AnnotationItem {
        guard zoom != 1 else { return item }
        var scaled = item
        scaled.strokeWidth = item.strokeWidth * zoom
        return scaled
    }

    private func handleScroll(_ event: NSEvent, anchor: CGPoint) -> Bool {
        guard model.isViewportZoomable else { return false }
        let lineMultiplier: CGFloat = event.hasPreciseScrollingDeltas ? 1 : 10

        if event.modifierFlags.contains(.command) {
            let delta = event.scrollingDeltaY * lineMultiplier
            model.zoom(by: exp(delta * 0.01), anchor: anchor)
            return true
        }

        guard model.canPan else { return false }
        model.pan(by: CGSize(
            width: event.scrollingDeltaX * lineMultiplier,
            height: event.scrollingDeltaY * lineMultiplier
        ))
        return true
    }

    private func interactionGesture(imageFrame: CGRect, boundaryFrame: CGRect) -> some Gesture {
        DragGesture(minimumDistance: 0, coordinateSpace: .local)
            .onChanged { value in
                if let origin = panDragOrigin {
                    model.setPanOffset(CGSize(
                        width: origin.width + value.translation.width,
                        height: origin.height + value.translation.height
                    ))
                    return
                }
                if !hasActiveInteraction, model.isSpacePanning, model.isViewportZoomable {
                    panDragOrigin = model.panOffset
                    setCursor(.closedHand)
                    return
                }
                if !hasActiveInteraction {
                    hasActiveInteraction = true
                    model.beginInteraction(at: value.startLocation, imageFrame: imageFrame, boundaryFrame: boundaryFrame)
                }
                model.updateInteraction(to: value.location, imageFrame: imageFrame, boundaryFrame: boundaryFrame)
                updateCursor(at: value.location, imageFrame: imageFrame)
            }
            .onEnded { value in
                if panDragOrigin != nil {
                    panDragOrigin = nil
                    updateCursor(at: value.location, imageFrame: imageFrame)
                    return
                }
                model.endInteraction(at: value.location, imageFrame: imageFrame, boundaryFrame: boundaryFrame)
                hasActiveInteraction = false
                updateCursor(at: value.location, imageFrame: imageFrame)
            }
    }

    private func aspectFitRect(imageSize: CGSize, in containerSize: CGSize) -> CGRect {
        guard imageSize.width > 0, imageSize.height > 0,
              containerSize.width > 0, containerSize.height > 0 else { return .zero }
        let padding: CGFloat = 24
        let availableSize = CGSize(width: containerSize.width - padding * 2, height: containerSize.height - padding * 2)
        let scale = min(availableSize.width / imageSize.width, availableSize.height / imageSize.height)
        let size = CGSize(width: imageSize.width * scale, height: imageSize.height * scale)
        return CGRect(
            x: (containerSize.width - size.width) / 2,
            y: (containerSize.height - size.height) / 2,
            width: size.width,
            height: size.height
        )
    }

    private func viewRect(_ rect: CGRect, in imageFrame: CGRect) -> CGRect {
        CGRect(
            x: imageFrame.minX + rect.minX * imageFrame.width,
            y: imageFrame.minY + rect.minY * imageFrame.height,
            width: rect.width * imageFrame.width,
            height: rect.height * imageFrame.height
        )
    }

    private func refreshCursor(imageFrame: CGRect) {
        guard let hoveredLocation else { return }
        updateCursor(at: hoveredLocation, imageFrame: imageFrame)
    }

    private func updateCursor(at location: CGPoint, imageFrame: CGRect) {
        if panDragOrigin != nil {
            setCursor(.closedHand)
            return
        }
        if model.isSpacePanning && model.isViewportZoomable {
            setCursor(.openHand)
            return
        }
        guard model.containsInteractionPoint(location, imageFrame: imageFrame, boundaryFrame: imageFrame) else {
            setCursor(.arrow)
            return
        }

        if hasActiveInteraction {
            setCursor(model.isTransformingExistingAnnotation ? .closedHand : .placement)
        } else if model.hoveredAnnotation(at: location, imageFrame: imageFrame, boundaryFrame: imageFrame) != nil {
            setCursor(.openHand)
        } else if model.selectedTool == .select {
            setCursor(.arrow)
        } else {
            setCursor(.placement)
        }
    }

    private func setCursor(_ cursor: AnnotationCanvasCursor) {
        guard currentCursor != cursor else { return }
        currentCursor = cursor
        cursor.nsCursor.set()
    }
}

// MARK: - SwiftUI Background Layer

private struct CanvasBackgroundView: View {
    let style: BackgroundStyle

    var body: some View {
        switch style {
        case .none:
            TransparencyGrid()

        case .solid(let color):
            Rectangle().fill(color.color)

        case .gradient(let preset):
            Rectangle().fill(preset.swiftUIGradient)

        case .wallpaper(let source):
            if let nsImage = NSImage(contentsOfFile: source.path) {
                Image(nsImage: nsImage)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
            } else {
                Rectangle().fill(.quaternary)
            }

        }
    }
}

// MARK: - Screenshot Layer with Shadow and Rounded Corners

private struct CanvasScreenshotView: View {
    let image: CGImage
    let frame: CGRect
    let cornerRadii: (tl: CGFloat, tr: CGFloat, br: CGFloat, bl: CGFloat)
    let shadowStrength: CGFloat
    let shortEdge: CGFloat
    /// Use nearest-neighbor sampling when zoomed in far enough to inspect pixels.
    let showsPixels: Bool

    private var clipShape: UnevenRoundedRectangle {
        UnevenRoundedRectangle(
            topLeadingRadius: cornerRadii.tl,
            bottomLeadingRadius: cornerRadii.bl,
            bottomTrailingRadius: cornerRadii.br,
            topTrailingRadius: cornerRadii.tr,
            style: .continuous
        )
    }

    private var shadowRadius: CGFloat {
        max(2, shortEdge * (0.035 + shadowStrength * 0.035))
    }

    private var shadowOffset: CGFloat {
        shortEdge * (0.012 + shadowStrength * 0.018)
    }

    private var shadowOpacity: Double {
        Double(shadowStrength * 0.36)
    }

    var body: some View {
        let nsImage = NSImage(cgImage: image, size: NSSize(width: image.width, height: image.height))

        Image(nsImage: nsImage)
            .resizable()
            .interpolation(showsPixels ? .none : .high)
            .clipShape(clipShape)
            .shadow(
                color: shadowStrength > 0 ? .black.opacity(shadowOpacity) : .clear,
                radius: shadowStrength > 0 ? shadowRadius : 0,
                x: 0,
                y: shadowStrength > 0 ? shadowOffset : 0
            )
            .frame(width: frame.width, height: frame.height)
            .position(x: frame.midX, y: frame.midY)
    }
}

// MARK: - Supporting Types

private enum AnnotationCanvasCursor: Equatable {
    case arrow
    case placement
    case openHand
    case closedHand

    var nsCursor: NSCursor {
        switch self {
        case .arrow: .arrow
        case .placement: .annotationPlus
        case .openHand: .openHand
        case .closedHand: .closedHand
        }
    }
}

private struct AnnotationMarqueeSelectionView: View {
    var body: some View {
        Rectangle()
            .fill(Color.accentColor.opacity(0.08))
            .overlay {
                Rectangle()
                    .stroke(
                        Color.accentColor.opacity(0.65),
                        style: StrokeStyle(lineWidth: 1.5, dash: [5, 4])
                    )
            }
    }
}

// MARK: - Image Crop Overlay

private struct ImageCropOverlay: View {
    @Binding var cropRect: CGRect
    let imageSize: CGSize

    private let handleSize: CGFloat = 10
    private let minCropFraction: CGFloat = 0.1
    @State private var startRect: CGRect = .zero

    var body: some View {
        Canvas { context, size in
            let crop = pixelRect(in: size)

            var dimPath = Path()
            dimPath.addRect(CGRect(origin: .zero, size: size))
            dimPath.addRect(crop)
            context.fill(dimPath, with: .color(.black.opacity(0.5)), style: FillStyle(eoFill: true))

            let border = crop.insetBy(dx: -1, dy: -1)
            context.stroke(Path(border), with: .color(.white), lineWidth: 1.5)

            let dashes: [CGFloat] = [4, 4]
            let thirdW = crop.width / 3
            let thirdH = crop.height / 3
            for i in 1...2 {
                var vLine = Path()
                vLine.move(to: CGPoint(x: crop.minX + thirdW * CGFloat(i), y: crop.minY))
                vLine.addLine(to: CGPoint(x: crop.minX + thirdW * CGFloat(i), y: crop.maxY))
                context.stroke(vLine, with: .color(.white.opacity(0.3)), style: StrokeStyle(lineWidth: 0.5, dash: dashes))

                var hLine = Path()
                hLine.move(to: CGPoint(x: crop.minX, y: crop.minY + thirdH * CGFloat(i)))
                hLine.addLine(to: CGPoint(x: crop.maxX, y: crop.minY + thirdH * CGFloat(i)))
                context.stroke(hLine, with: .color(.white.opacity(0.3)), style: StrokeStyle(lineWidth: 0.5, dash: dashes))
            }
        }
        .allowsHitTesting(false)
        .frame(width: imageSize.width, height: imageSize.height)
        .overlay {
            GeometryReader { geo in
                let size = geo.size
                let crop = pixelRect(in: size)

                Rectangle()
                    .fill(Color.clear)
                    .contentShape(Rectangle())
                    .frame(width: crop.width, height: crop.height)
                    .position(x: crop.midX, y: crop.midY)
                    .gesture(dragGesture(size: size))

                cornerHandle(at: CGPoint(x: crop.minX, y: crop.minY), corner: .topLeft, size: size)
                cornerHandle(at: CGPoint(x: crop.maxX, y: crop.minY), corner: .topRight, size: size)
                cornerHandle(at: CGPoint(x: crop.minX, y: crop.maxY), corner: .bottomLeft, size: size)
                cornerHandle(at: CGPoint(x: crop.maxX, y: crop.maxY), corner: .bottomRight, size: size)

                edgeHandle(at: CGPoint(x: crop.midX, y: crop.minY), edge: .top, size: size)
                edgeHandle(at: CGPoint(x: crop.midX, y: crop.maxY), edge: .bottom, size: size)
                edgeHandle(at: CGPoint(x: crop.minX, y: crop.midY), edge: .left, size: size)
                edgeHandle(at: CGPoint(x: crop.maxX, y: crop.midY), edge: .right, size: size)
            }
            .frame(width: imageSize.width, height: imageSize.height)
        }
    }

    private func pixelRect(in size: CGSize) -> CGRect {
        CGRect(
            x: cropRect.origin.x * size.width,
            y: cropRect.origin.y * size.height,
            width: cropRect.width * size.width,
            height: cropRect.height * size.height
        )
    }

    private func cornerHandle(at point: CGPoint, corner: CropCorner, size: CGSize) -> some View {
        Circle()
            .fill(.white)
            .frame(width: handleSize, height: handleSize)
            .shadow(color: .black.opacity(0.3), radius: 2)
            .position(point)
            .gesture(
                DragGesture()
                    .onChanged { value in
                        let nx = value.location.x / size.width
                        let ny = value.location.y / size.height
                        var r = cropRect
                        switch corner {
                        case .topLeft:
                            let newX = min(nx, r.maxX - minCropFraction)
                            let newY = min(ny, r.maxY - minCropFraction)
                            r.size.width += r.origin.x - max(0, newX)
                            r.size.height += r.origin.y - max(0, newY)
                            r.origin.x = max(0, newX)
                            r.origin.y = max(0, newY)
                        case .topRight:
                            r.size.width = max(minCropFraction, min(1 - r.origin.x, nx - r.origin.x))
                            let newY = min(ny, r.maxY - minCropFraction)
                            r.size.height += r.origin.y - max(0, newY)
                            r.origin.y = max(0, newY)
                        case .bottomLeft:
                            let newX = min(nx, r.maxX - minCropFraction)
                            r.size.width += r.origin.x - max(0, newX)
                            r.origin.x = max(0, newX)
                            r.size.height = max(minCropFraction, min(1 - r.origin.y, ny - r.origin.y))
                        case .bottomRight:
                            r.size.width = max(minCropFraction, min(1 - r.origin.x, nx - r.origin.x))
                            r.size.height = max(minCropFraction, min(1 - r.origin.y, ny - r.origin.y))
                        }
                        cropRect = r
                    }
            )
    }

    private func edgeHandle(at point: CGPoint, edge: CropEdge, size: CGSize) -> some View {
        Capsule()
            .fill(.white)
            .frame(
                width: edge == .top || edge == .bottom ? 24 : 6,
                height: edge == .left || edge == .right ? 24 : 6
            )
            .shadow(color: .black.opacity(0.3), radius: 2)
            .position(point)
            .gesture(
                DragGesture()
                    .onChanged { value in
                        let nx = value.location.x / size.width
                        let ny = value.location.y / size.height
                        var r = cropRect
                        switch edge {
                        case .top:
                            let newY = min(ny, r.maxY - minCropFraction)
                            r.size.height += r.origin.y - max(0, newY)
                            r.origin.y = max(0, newY)
                        case .bottom:
                            r.size.height = max(minCropFraction, min(1 - r.origin.y, ny - r.origin.y))
                        case .left:
                            let newX = min(nx, r.maxX - minCropFraction)
                            r.size.width += r.origin.x - max(0, newX)
                            r.origin.x = max(0, newX)
                        case .right:
                            r.size.width = max(minCropFraction, min(1 - r.origin.x, nx - r.origin.x))
                        }
                        cropRect = r
                    }
            )
    }

    private func dragGesture(size: CGSize) -> some Gesture {
        DragGesture()
            .onChanged { value in
                if startRect == .zero { startRect = cropRect }
                let dx = value.translation.width / size.width
                let dy = value.translation.height / size.height
                var r = startRect
                r.origin.x = max(0, min(1 - r.width, startRect.origin.x + dx))
                r.origin.y = max(0, min(1 - r.height, startRect.origin.y + dy))
                cropRect = r
            }
            .onEnded { _ in startRect = .zero }
    }

    private enum CropCorner { case topLeft, topRight, bottomLeft, bottomRight }
    private enum CropEdge { case top, bottom, left, right }
}

// MARK: - Crop Preview (non-interactive, shows active crop)

private struct ImageCropPreview: View {
    let cropRect: CGRect
    let imageSize: CGSize

    var body: some View {
        Canvas { context, size in
            let crop = CGRect(
                x: cropRect.origin.x * size.width,
                y: cropRect.origin.y * size.height,
                width: cropRect.width * size.width,
                height: cropRect.height * size.height
            )

            var dimPath = Path()
            dimPath.addRect(CGRect(origin: .zero, size: size))
            dimPath.addRect(crop)
            context.fill(dimPath, with: .color(.black.opacity(0.5)), style: FillStyle(eoFill: true))

            let border = crop.insetBy(dx: -1, dy: -1)
            context.stroke(Path(border), with: .color(.white.opacity(0.5)), lineWidth: 1)
        }
        .allowsHitTesting(false)
        .frame(width: imageSize.width, height: imageSize.height)
    }
}

struct TransparencyGrid: View {
    enum Style {
        /// Marks transparent image areas.
        case light
        /// Shottr-style workspace around the canvas.
        case dark
    }

    var style: Style = .light

    var body: some View {
        // Tile a 2×2 checker cell instead of drawing every square, so the grid stays
        // cheap when the canvas is zoomed far beyond the window size.
        Rectangle().fill(ImagePaint(image: style == .dark ? Self.darkTile : Self.lightTile, scale: 1))
    }

    private static let lightTile = makeTile(base: NSColor.white, alternate: NSColor(white: 0.88, alpha: 1))
    private static let darkTile = makeTile(base: NSColor(white: 0.17, alpha: 1), alternate: NSColor(white: 0.21, alpha: 1))

    private static func makeTile(base: NSColor, alternate: NSColor) -> Image {
        let cellSize: CGFloat = 10
        let image = NSImage(size: NSSize(width: cellSize * 2, height: cellSize * 2), flipped: false) { rect in
            base.setFill()
            rect.fill()
            alternate.setFill()
            NSRect(x: 0, y: 0, width: cellSize, height: cellSize).fill()
            NSRect(x: cellSize, y: cellSize, width: cellSize, height: cellSize).fill()
            return true
        }
        return Image(nsImage: image)
    }
}

// MARK: - Empty State View

struct EmptyEditorStateView: View {
    let onCaptureAction: (ShortcutService.Action) -> Void
    let onRecordAction: () -> Void
    
    var body: some View {
        VStack(spacing: 24) {
            // Icon
            ZStack(alignment: .bottomTrailing) {
                Image(systemName: "photo")
                    .font(.system(size: 64, weight: .light))
                    .foregroundStyle(.secondary)
                Image(systemName: "cursorarrow")
                    .font(.system(size: 20))
                    .offset(x: 8, y: 8)
                    .foregroundStyle(.secondary)
            }
            .padding(.top, 16)
            
            // Text labels
            VStack(spacing: 6) {
                Text("Drag and drop or paste screenshot")
                    .font(.system(size: 18, weight: .bold))
                    .foregroundStyle(.primary)
                
                Text("Or use keyboard shortcuts to capture")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
            }
            
            // Action buttons row
            HStack(spacing: 8) {
                EmptyStateButton(title: "Full Screen", icon: "desktopcomputer") {
                    onCaptureAction(.fullscreen)
                }
                EmptyStateButton(title: "Window", icon: "macwindow") {
                    onCaptureAction(.window)
                }
                EmptyStateButton(title: "Region", icon: "rectangle.dashed") {
                    onCaptureAction(.region)
                }
                EmptyStateButton(title: "Record GIF", icon: "record.circle") {
                    onRecordAction()
                }
            }
        }
        .padding(32)
        .frame(width: 440)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color(nsColor: .windowBackgroundColor))
                .shadow(color: .black.opacity(0.12), radius: 10, x: 0, y: 4)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(Color.primary.opacity(0.06), lineWidth: 1)
        )
    }
}

struct EmptyStateButton: View {
    let title: String
    let icon: String
    let action: () -> Void
    
    @State private var isHovered = false
    
    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Image(systemName: icon)
                    .font(.system(size: 11))
                Text(title)
                    .font(.system(size: 11, weight: .medium))
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(isHovered ? Color.primary.opacity(0.12) : Color.primary.opacity(0.06))
            )
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
    }
}

struct WatermarkPreviewView: View {
    let preset: WatermarkPreset
    let imageFrame: CGRect
    
    var body: some View {
        let targetShortEdge = min(imageFrame.width, imageFrame.height)
        guard targetShortEdge > 0 else { return AnyView(EmptyView()) }
        
        let margin = targetShortEdge * 0.04
        let scaledFontSize = preset.fontSize * (targetShortEdge / 800.0)
        
        return AnyView(
            Group {
                if preset.type == .image, let relativePath = preset.imagePath {
                    let url = WatermarkStore.shared.resolveImagePath(for: relativePath)
                    if let nsImage = NSImage(contentsOf: url) {
                        Image(nsImage: nsImage)
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                            .frame(width: targetShortEdge * preset.scale)
                    }
                } else if preset.type == .text, let text = preset.textContent, !text.isEmpty {
                    Text(text)
                        .font(.custom(preset.fontName, size: scaledFontSize))
                        .foregroundStyle(preset.fontColor.color)
                }
            }
            .opacity(preset.opacity)
            .rotationEffect(.degrees(preset.rotationDegrees))
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: swiftUIPosition)
            .padding(margin)
            .frame(width: imageFrame.width, height: imageFrame.height)
            .position(x: imageFrame.midX, y: imageFrame.midY)
            .allowsHitTesting(false)
        )
    }
    
    private var swiftUIPosition: Alignment {
        switch preset.position {
        case .topLeft: return .topLeading
        case .topRight: return .topTrailing
        case .bottomLeft: return .bottomLeading
        case .bottomRight: return .bottomTrailing
        case .center: return .center
        }
    }
}

struct CanvasCollageView: View {
    @Binding var collage: CollageState
    @Binding var selectedSlotID: CollageSlot.ID?
    let frame: CGRect
    let cornerRadii: (tl: CGFloat, tr: CGFloat, br: CGFloat, bl: CGFloat)
    let shadowStrength: CGFloat
    let shortEdge: CGFloat
    let renderScale: CGFloat

    private var gap: CGFloat {
        max(0, collage.spacing * renderScale)
    }

    private var clipShape: UnevenRoundedRectangle {
        UnevenRoundedRectangle(
            topLeadingRadius: cornerRadii.tl,
            bottomLeadingRadius: cornerRadii.bl,
            bottomTrailingRadius: cornerRadii.br,
            topTrailingRadius: cornerRadii.tr,
            style: .continuous
        )
    }

    private var shadowRadius: CGFloat {
        max(2, shortEdge * (0.035 + shadowStrength * 0.035))
    }

    private var shadowOffset: CGFloat {
        shortEdge * (0.012 + shadowStrength * 0.018)
    }

    private var shadowOpacity: Double {
        Double(shadowStrength * 0.36)
    }

    var body: some View {
        Group {
            switch collage.layoutType {
            case .vertical:
                VStack(spacing: gap) {
                    ForEach(0..<collage.slots.count, id: \.self) { index in
                        collageSlot(at: index)
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                    }
                }
            case .horizontal:
                HStack(spacing: gap) {
                    ForEach(0..<collage.slots.count, id: \.self) { index in
                        collageSlot(at: index)
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                    }
                }
            case .grid2x2:
                LazyVGrid(columns: [GridItem(.flexible(), spacing: gap), GridItem(.flexible(), spacing: gap)], spacing: gap) {
                    ForEach(0..<4) { index in
                        if index < collage.slots.count {
                            collageSlot(at: index)
                                .frame(height: (frame.height - gap) / 2)
                        } else {
                            Color.black.opacity(0.15)
                                .overlay {
                                    Image(systemName: "photo.badge.plus")
                                        .font(.system(size: 18, weight: .medium))
                                        .foregroundStyle(.white.opacity(0.35))
                                }
                                .frame(height: (frame.height - gap) / 2)
                        }
                    }
                }
            }
        }
        .frame(width: frame.width, height: frame.height)
        .clipShape(clipShape)
        .shadow(
            color: shadowStrength > 0 ? .black.opacity(shadowOpacity) : .clear,
            radius: shadowStrength > 0 ? shadowRadius : 0,
            x: 0,
            y: shadowStrength > 0 ? shadowOffset : 0
        )
    }

    private func binding(for index: Int) -> Binding<CollageSlot> {
        Binding(
            get: { collage.slots[index] },
            set: { collage.slots[index] = $0 }
        )
    }

    private func collageSlot(at index: Int) -> some View {
        let id = collage.slots[index].id
        return CollageSlotView(
            slot: binding(for: index),
            isLocked: collage.isLocked,
            isSelected: selectedSlotID == id,
            onSelect: { selectedSlotID = id }
        )
    }
}

struct CollageSlotView: View {
    @Binding var slot: CollageSlot
    let isLocked: Bool
    let isSelected: Bool
    let onSelect: () -> Void
    @State private var dragStartOffset: CGPoint = .zero

    var body: some View {
        GeometryReader { slotProxy in
            let w = slotProxy.size.width
            let h = slotProxy.size.height
            
            let imgSize = slot.image.size
            let wRatio = w / max(imgSize.width, 1.0)
            let hRatio = h / max(imgSize.height, 1.0)
            let baseScale = max(wRatio, hRatio)
            
            let finalWidth = imgSize.width * baseScale * slot.zoomScale
            let finalHeight = imgSize.height * baseScale * slot.zoomScale
            
            Image(nsImage: slot.image)
                .resizable()
                .interpolation(.high)
                .aspectRatio(contentMode: .fill)
                .frame(width: finalWidth, height: finalHeight)
                .offset(x: slot.panOffset.x, y: slot.panOffset.y)
                .contentShape(Rectangle())
                .gesture(
                    DragGesture()
                        .onChanged { value in
                            slot.panOffset = CGPoint(
                                x: dragStartOffset.x + value.translation.width,
                                y: dragStartOffset.y + value.translation.height
                            )
                        }
                        .onEnded { _ in
                            dragStartOffset = slot.panOffset
                        }
                )
                .gesture(
                    MagnificationGesture()
                        .onChanged { value in
                            slot.zoomScale = max(0.5, min(5.0, value))
                        }
                )
                .onScrollWheel { delta in
                    guard !isLocked else { return }
                    slot.zoomScale = max(0.5, min(5.0, slot.zoomScale + delta * 0.05))
                }
                .allowsHitTesting(!isLocked)
        }
        .clipped()
        .contentShape(Rectangle())
        .overlay {
            Rectangle()
                .strokeBorder(
                    isSelected ? Color.accentColor : Color.white.opacity(0.48),
                    lineWidth: isSelected ? 2 : 1
                )
                .allowsHitTesting(false)
        }
        .simultaneousGesture(
            TapGesture().onEnded { onSelect() }
        )
    }
}

private struct ScrollWheelModifier: ViewModifier {
    let handler: (CGFloat) -> Void

    func body(content: Content) -> some View {
        content.background(
            ScrollWheelView(handler: handler)
        )
    }
}

private struct ScrollWheelView: NSViewRepresentable {
    let handler: (CGFloat) -> Void

    func makeNSView(context: Context) -> _CanvasScrollWheelNSView {
        let v = _CanvasScrollWheelNSView()
        v.handler = handler
        return v
    }

    func updateNSView(_ nsView: _CanvasScrollWheelNSView, context: Context) {
        nsView.handler = handler
    }
}

final class _CanvasScrollWheelNSView: NSView {
    var handler: ((CGFloat) -> Void)?

    override var acceptsFirstResponder: Bool { true }

    override func scrollWheel(with event: NSEvent) {
        let delta = event.deltaY
        handler?(delta)
    }
}

private extension View {
    func onScrollWheel(_ handler: @escaping (CGFloat) -> Void) -> some View {
        modifier(ScrollWheelModifier(handler: handler))
    }
}
