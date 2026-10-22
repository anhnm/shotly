import SwiftUI

struct EditorWindowView: View {
    @Bindable var urlHolder: CurrentURL
    var initialCollage: CollageState? = nil
    @State private var model = EditorModel()
    @State private var inspectorPanel: EditorInspectorPanel?
    @State private var showingWatermarkPopover = false
    @State private var isConfirmingDelete = false
    @Environment(\.dismiss) private var dismiss

    /// Tool order mirrors Shottr: selection and text first, shapes, then effects.
    /// Filled rectangles have no button of their own: they are a style of the
    /// rectangle tool, picked in the options bar (or with the F key).
    private static let toolOrder: [AnnotationTool] = [
        .select, .text, .measure, .rectangle, .freehand,
        .arrow, .blur, .spotlight, .magnifier, .numberedCircle, .ellipse, .line,
    ]

    private var isBackdropOpen: Bool {
        inspectorPanel.map(EditorInspectorPanel.backdropPanels.contains) ?? false
    }

    var body: some View {
        GeometryReader { proxy in
            VStack(spacing: 0) {
                EditorTitleBar(height: max(proxy.safeAreaInsets.top, 40)) {
                    titleBarItems
                }
                // Keep hover tooltips, which hang below the bar, above the canvas.
                .zIndex(1)
                Divider()
                editorContent
            }
            .ignoresSafeArea(.container, edges: .top)
        }
        .onDrop(of: [.fileURL, .image], isTargeted: nil) { providers in
            guard let provider = providers.first else { return false }
            
            if provider.canLoadObject(ofClass: URL.self) {
                _ = provider.loadObject(ofClass: URL.self) { url, _ in
                    if let url = url, let nsImage = NSImage(contentsOf: url) {
                        DispatchQueue.main.async {
                            handleImportedImage(nsImage)
                        }
                    }
                }
                return true
            }
            
            if provider.canLoadObject(ofClass: NSImage.self) {
                _ = provider.loadObject(ofClass: NSImage.self) { image, _ in
                    if let nsImage = image as? NSImage {
                        DispatchQueue.main.async {
                            handleImportedImage(nsImage)
                        }
                    }
                }
                return true
            }
            
            return false
        }
        .overlay(alignment: .bottom) {
            if let message = model.toastMessage {
                Text(message)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                    .background(.black.opacity(0.75), in: Capsule())
                    .padding(.bottom, 24)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                    .onAppear {
                        Task {
                            try? await Task.sleep(for: .seconds(1.5))
                            withAnimation { model.toastMessage = nil }
                        }
                    }
            }
        }
        .background {
            ZStack {
                AnnotationKeyCommandHandler(
                    onDelete: { model.deleteSelectedAnnotation() },
                    onUndo: { model.undo() },
                    onRedo: { model.redo() },
                    onSelectAll: { model.selectAllAnnotations() },
                    onSelectTool: { tool in model.selectTool(tool) },
                    onEditorAction: { action in performEditorAction(action) },
                    onViewportCommand: { command in model.handleViewportCommand(command) },
                    onSpacePanChanged: { isDown in model.isSpacePanning = isDown }
                )
                
                Button("") {
                    handlePaste()
                }
                .keyboardShortcut("v", modifiers: .command)
                .opacity(0)
                .disabled(model.sourceImage != nil || model.collageState != nil)

                Button("") {
                    handleEscape()
                }
                .keyboardShortcut(.escape, modifiers: [])
                .opacity(0)

                editorShortcutButtons
            }
        }
        .alert("Delete this screenshot?", isPresented: $isConfirmingDelete) {
            Button("Delete", role: .destructive) { deleteCapture() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("The file is removed from disk and from your capture history. This can't be undone.")
        }
        .onAppear {
            if let collage = initialCollage {
                model.loadCollage(collage)
                inspectorPanel = .collage
            } else if let url = urlHolder.url {
                model.loadImage(from: url)
            }
        }
        .onChange(of: urlHolder.url) { _, newURL in
            if let newURL {
                model.loadImage(from: newURL)
            }
        }
    }

    @ViewBuilder
    private var titleBarItems: some View {
            Text("shotly")
                .font(.system(size: 19, weight: .medium, design: .rounded))
                .foregroundStyle(EditorTitleBar<EmptyView>.brandColor)
                .padding(.leading, 6)
                .padding(.trailing, 22)
                .accessibilityLabel("Shotly")

            EditorToolbarButton(title: "Copy", shortcut: AppPreferences.editorCopyShortcut.displayString, systemImage: "doc.on.doc", isSelected: false) {
                Task { await copyToClipboard() }
            }
            EditorToolbarButton(title: "Save", shortcut: AppPreferences.editorSaveShortcut.displayString, systemImage: "square.and.arrow.down", isSelected: false) {
                Task { await exportImage() }
            }
            EditorToolbarButton(title: "Pin to Screen", shortcut: EditorAction.pin.shortcutHint, systemImage: "pin", isSelected: false) {
                performEditorAction(.pin)
            }
            .disabled(model.collageState != nil)

            ToolbarSeparator()

            EditorToolbarButton(title: "Crop", shortcut: EditorAction.crop.shortcutHint, systemImage: "crop", isSelected: model.isCropping) {
                performEditorAction(.crop)
            }
            .disabled(model.collageState != nil || model.sourceImage == nil)

            ToolbarSeparator()

            ForEach(Self.toolOrder) { tool in
                EditorToolbarButton(
                    title: tool.title,
                    shortcut: tool.shortcutHint,
                    systemImage: tool.systemImage,
                    isSelected: model.selectedTool == tool
                        || (tool == .blur && model.selectedTool == .pixelate)
                        || (tool == .rectangle && model.selectedTool == .filledRectangle)
                ) {
                    model.selectTool(tool)
                }
                .disabled(model.collageState != nil)
            }

            ToolbarSeparator()

            EditorToolbarButton(title: "Backdrop", shortcut: EditorAction.backdrop.shortcutHint, systemImage: "rectangle.inset.filled.and.person.filled", isSelected: isBackdropOpen) {
                performEditorAction(.backdrop)
            }
            .disabled(model.collageState != nil)

            EditorToolbarButton(
                title: model.activeWatermarkPreset.map { "Watermark: \($0.name)" } ?? "Watermark",
                shortcut: EditorAction.watermark.shortcutHint,
                systemImage: model.activeWatermarkPreset != nil ? "seal.fill" : "seal",
                isSelected: model.activeWatermarkPreset != nil
            ) {
                performEditorAction(.watermark)
            }
            .disabled(model.collageState != nil)
            .popover(isPresented: $showingWatermarkPopover, arrowEdge: .bottom) {
                watermarkPopoverContent
            }

            EditorToolbarButton(title: "Metadata", shortcut: EditorAction.metadata.shortcutHint, systemImage: "info.circle", isSelected: inspectorPanel == .metadata) {
                performEditorAction(.metadata)
            }
            .disabled(model.captureMetadata == nil || model.collageState != nil)

        Spacer(minLength: 16)

        EditorInfoCluster(model: model)
            .padding(.trailing, 14)
    }

    private var editorContent: some View {
        HStack(spacing: 0) {
            ZStack(alignment: .topTrailing) {
                EditorCanvasView(model: model)
                    .frame(minWidth: 500, minHeight: 400)
                    .contextMenu { canvasContextMenu }

                // Pinned to the top-right corner of the canvas, like Shottr's tool options.
                EditorFloatingOptionsBar(model: model)
                    .padding(.top, 12)
                    .padding(.trailing, 12)
            }

            if let activeInspectorPanel = inspectorPanel {
                Divider()

                EditorSidePanel(
                    model: model,
                    panel: Binding(
                        get: { activeInspectorPanel },
                        set: { inspectorPanel = $0 }
                    ),
                    onCollageDone: {
                        inspectorPanel = nil
                        withAnimation { model.toastMessage = "Collage ready — editing tools enabled" }
                    }
                )
                .frame(width: 280)
            }
        }
    }

    @ViewBuilder
    private var canvasContextMenu: some View {
        if model.sourceImage != nil || model.collageState != nil {
            Button("Copy") { Task { await copyToClipboard() } }
            Button("Save…") { Task { await exportImage() } }
            Button("Pin to Screen") { pinToScreen() }
                .disabled(model.collageState != nil)
            Divider()
            Button("Zoom to Fit") { model.zoomToFit() }
                .disabled(!model.isViewportZoomable)
            Button("Actual Size") { model.zoomToActualSize() }
                .disabled(!model.isViewportZoomable)
            Divider()
            Button("Delete Screenshot…", role: .destructive) {
                isConfirmingDelete = true
            }
            .disabled(urlHolder.url == nil)
        }
    }

    /// Shared by toolbar buttons and their single-key shortcuts.
    private func performEditorAction(_ action: EditorAction) {
        let isEditableImage = model.collageState == nil && model.sourceImage != nil
        switch action {
        case .pin:
            pinToScreen()
        case .crop:
            guard isEditableImage else { return }
            model.isCropping.toggle()
        case .backdrop:
            guard model.collageState == nil else { return }
            inspectorPanel = isBackdropOpen ? nil : .background
        case .watermark:
            guard model.collageState == nil else { return }
            showingWatermarkPopover.toggle()
        case .metadata:
            guard model.captureMetadata != nil, model.collageState == nil else { return }
            if inspectorPanel == .metadata {
                inspectorPanel = nil
            } else {
                // Opening the Metadata inspector means the user wants the
                // metadata overlay enabled, not just its settings visible.
                model.showMetadata = true
                inspectorPanel = .metadata
            }
        }
    }

    private func handleEscape() {
        if model.isCropping {
            model.isCropping = false
        } else {
            NSApp.keyWindow?.close()
        }
    }

    private func pinToScreen() {
        guard model.collageState == nil, let rendered = model.renderFinal() else { return }
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("shotly_pinned_\(UUID().uuidString.prefix(8)).png")
        guard let destination = CGImageDestinationCreateWithURL(url as CFURL, "public.png" as CFString, 1, nil) else { return }
        CGImageDestinationAddImage(destination, rendered, nil)
        guard CGImageDestinationFinalize(destination) else { return }
        PinnedScreenshotController.shared.pin(url: url, on: NSApp.keyWindow?.screen)
        AnalyticsService.track(.previewPinned)
        withAnimation { model.toastMessage = "Pinned to screen" }
    }

    @ViewBuilder
    private var editorShortcutButtons: some View {
        let copyShortcut = AppPreferences.editorCopyShortcut
        let saveShortcut = AppPreferences.editorSaveShortcut

        Button("") {
            Task { await copyToClipboard() }
        }
        .keyboardShortcut(copyShortcut.keyEquivalent, modifiers: copyShortcut.eventModifiers)
        .opacity(0)

        Button("") {
            Task { await exportImage() }
        }
        .keyboardShortcut(saveShortcut.keyEquivalent, modifiers: saveShortcut.eventModifiers)
        .opacity(0)
    }

    private func exportImage() async {
        guard let rendered = model.renderFinal() else { return }

        let stamp = Int(Date().timeIntervalSince1970 * 1000)
        guard let url = ImageSavePanel.export(rendered, suggestedName: "shotly_\(stamp)") else { return }
        AnalyticsService.track(.editorExported, properties: [
            "format": url.pathExtension.lowercased(),
        ])

        if let sourceURL = model.sourceURL {
            let baseURL = CaptureOrchestrator.baseImageURL(for: url)
            try? FileManager.default.copyItem(at: sourceURL, to: baseURL)

            if let record = HistoryStore.shared.records.first(where: {
                HistoryStore.shared.urlForRecord($0) == sourceURL
                    || HistoryStore.shared.displayURLForRecord($0) == sourceURL
            }) {
                HistoryStore.shared.deleteRecord(record)
            }

        }

        // Collages do not have a single source URL, but their exported result
        // should still appear in screenshot history like a normal capture.
        _ = HistoryStore.shared.importCapture(from: url, deleteSource: false, kind: .screenshot)

        if AppPreferences.copyAfterSave {
            let pb = NSPasteboard.general
            pb.clearContents()
            if let nsImage = NSImage(contentsOf: url) {
                pb.writeObjects([nsImage])
            }
        }

        withAnimation { model.toastMessage = "Saved" }
        try? await Task.sleep(for: .seconds(1.0))
        NSApp.keyWindow?.close()
    }

    private func deleteCapture() {
        guard let url = urlHolder.url else {
            NSApp.keyWindow?.close()
            return
        }
        if let record = HistoryStore.shared.records.first(where: {
            HistoryStore.shared.urlForRecord($0) == url
                || HistoryStore.shared.displayURLForRecord($0) == url
        }) {
            HistoryStore.shared.deleteRecord(record)
        }
        try? FileManager.default.removeItem(at: url)
        NSApp.keyWindow?.close()
    }

    private func copyToClipboard() async {
        guard let rendered = model.renderFinal() else { return }

        let nsImage = NSImage(cgImage: rendered, size: NSSize(width: rendered.width, height: rendered.height))
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.writeObjects([nsImage])

        let screen = NSApp.keyWindow?.screen
        if let previewURL = urlHolder.url {
            NSApp.keyWindow?.close()
            PreviewOverlay.shared.show(url: previewURL, on: screen)
        } else {
            NSApp.keyWindow?.close()
        }
    }

    private func importImage(from url: URL) {
        urlHolder.url = url
        model.loadImage(from: url)
    }

    private func importNSImage(_ nsImage: NSImage) {
        var rect = CGRect(origin: .zero, size: nsImage.size)
        guard let cgImage = nsImage.cgImage(forProposedRect: &rect, context: nil, hints: nil) else { return }
        
        let dir = NSTemporaryDirectory()
        let stamp = Int(Date().timeIntervalSince1970 * 1000)
        let path = "\(dir)shotly_imported_\(stamp)_\(UUID().uuidString.prefix(6)).png"
        let fileURL = URL(fileURLWithPath: path)
        
        guard let destination = CGImageDestinationCreateWithURL(fileURL as CFURL, "public.png" as CFString, 1, nil) else {
            return
        }
        CGImageDestinationAddImage(destination, cgImage, nil)
        guard CGImageDestinationFinalize(destination) else { return }
        
        importImage(from: fileURL)
    }

    private func handleImportedImage(_ nsImage: NSImage) {
        if model.collageState != nil {
            guard model.canAddCollageImages else {
                withAnimation { model.toastMessage = "Collage supports up to 4 images" }
                return
            }
            model.addCollageImages([nsImage])
            inspectorPanel = .collage
            withAnimation { model.toastMessage = "Image added to collage" }
        } else if let currentImage = model.sourceImage {
            let existingImage = NSImage(
                cgImage: currentImage,
                size: NSSize(width: model.imageSize.width, height: model.imageSize.height)
            )
            model.loadCollage(CollageState(
                layoutType: .horizontal,
                slots: [
                    CollageSlot(image: existingImage),
                    CollageSlot(image: nsImage)
                ]
            ))
            inspectorPanel = .collage
            withAnimation { model.toastMessage = "Collage created — choose a layout" }
        } else {
            importNSImage(nsImage)
        }
    }

    private func handlePaste() {
        let pb = NSPasteboard.general
        if let fileURLs = pb.readObjects(forClasses: [NSURL.self], options: nil) as? [URL],
           let firstURL = fileURLs.first,
           let image = NSImage(contentsOf: firstURL) {
            importNSImage(image)
            return
        }
        if let images = pb.readObjects(forClasses: [NSImage.self], options: nil) as? [NSImage],
           let firstImage = images.first {
            importNSImage(firstImage)
        }
    }

    @ViewBuilder
    private var watermarkPopoverContent: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Watermark Presets")
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(.tertiary)
                .padding(.horizontal, 8)
                .padding(.top, 4)
            
            Divider()
            
            Button("None") {
                model.activeWatermarkPreset = nil
                showingWatermarkPopover = false
            }
            .buttonStyle(.plain)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            
            ForEach(WatermarkStore.shared.presets) { preset in
                Button {
                    model.activeWatermarkPreset = preset
                    showingWatermarkPopover = false
                } label: {
                    HStack {
                        Text(preset.name)
                        Spacer()
                        if model.activeWatermarkPreset?.id == preset.id {
                            Image(systemName: "checkmark")
                        }
                    }
                }
                .buttonStyle(.plain)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
            }

            Divider()

            Button {
                showingWatermarkPopover = false
                SettingsWindowController.shared.open(section: .watermark)
            } label: {
                HStack {
                    Image(systemName: "plus.circle")
                    Text("Add More...")
                }
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
        }
        .padding(4)
        .frame(width: 180)
    }
}

private struct AnnotationRedactionModeControl: View {
    @Bindable var model: EditorModel
    @State private var isModePresented = false

    var body: some View {
        Button {
            isModePresented.toggle()
        } label: {
            HStack(spacing: 6) {
                Image(systemName: model.activeRedactionTool == .pixelate ? "square.grid.3x3.fill" : "drop.fill")
                    .font(.system(size: 12, weight: .semibold))
                Text(model.activeRedactionTool == .pixelate ? "Mosaic" : "Blur")
                    .font(.system(size: 13, weight: .medium))
                Image(systemName: "chevron.up.chevron.down")
                    .font(.system(size: 7, weight: .semibold))
                    .foregroundStyle(.tertiary)
            }
            .padding(.horizontal, 10)
            .frame(height: 32)
            .background(ToolbarStyleControlBackground())
            .contentShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
        }
        .buttonStyle(.plain)
        .popover(isPresented: $isModePresented, arrowEdge: .bottom) {
            VStack(spacing: 6) {
                redactionModeButton(.blur, title: "Blur", systemImage: "drop.fill")
                redactionModeButton(.pixelate, title: "Mosaic", systemImage: "square.grid.3x3.fill")
            }
            .padding(8)
            .frame(width: 132)
        }
        .fixedSize()
    }

    private func redactionModeButton(_ tool: AnnotationTool, title: String, systemImage: String) -> some View {
        Button {
            model.setRedactionTool(tool)
            isModePresented = false
        } label: {
            HStack(spacing: 8) {
                Image(systemName: systemImage)
                    .frame(width: 18)
                Text(title)
                Spacer()
                if model.activeRedactionTool == tool {
                    Image(systemName: "checkmark")
                        .foregroundStyle(Color.accentColor)
                }
            }
            .font(.system(size: 12, weight: .medium))
            .padding(.horizontal, 8)
            .frame(height: 30)
            .background(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(model.activeRedactionTool == tool ? Color.accentColor.opacity(0.12) : .clear)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

private struct AnnotationDensityControl: View {
    @Bindable var model: EditorModel
    @State private var isPresented = false

    var body: some View {
        Button {
            isPresented.toggle()
        } label: {
            HStack(spacing: 5) {
                Image(systemName: "slider.horizontal.3")
                    .font(.system(size: 12, weight: .semibold))
                Text("\(Int(model.redactionDensity * 100))%")
                    .font(.system(size: 13, weight: .medium))
                    .monospacedDigit()
            }
            .padding(.horizontal, 10)
            .frame(height: 32)
            .background(ToolbarStyleControlBackground())
            .contentShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
        }
        .buttonStyle(.plain)
        .help("\(densityTitle) density")
        .popover(isPresented: $isPresented, arrowEdge: .bottom) {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Text("\(densityTitle) Density")
                        .font(.system(size: 12, weight: .semibold))
                    Spacer()
                    Text("\(Int(model.redactionDensity * 100))%")
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundStyle(.secondary)
                }
                Slider(
                    value: Binding(
                        get: { model.redactionDensity },
                        set: { model.setRedactionDensity($0) }
                    ),
                    in: 0.15...1
                )
            }
            .padding(12)
            .frame(width: 210)
        }
        .fixedSize()
    }

    private var densityTitle: String {
        if model.showsSpotlightDensityControl { return "Spotlight" }
        return model.activeRedactionTool == .pixelate ? "Mosaic" : "Blur"
    }
}

private struct AnnotationTextToolbarControl: View {
    @Bindable var model: EditorModel
    @State private var isPresented = false

    var body: some View {
        Button {
            isPresented.toggle()
        } label: {
            HStack(spacing: 5) {
                Image(systemName: "textformat")
                    .font(.system(size: 12, weight: .semibold))
                Text("\(Int(model.textFontSize)) pt")
                    .font(.system(size: 13, weight: .medium))
                    .monospacedDigit()
            }
            .padding(.horizontal, 10)
            .frame(height: 32)
            .background(ToolbarStyleControlBackground())
        }
        .buttonStyle(.plain)
        .help("Text style")
        .popover(isPresented: $isPresented, arrowEdge: .bottom) {
            AnnotationTextStyleControls(model: model)
                .padding(12)
                .frame(width: 290)
        }
        .fixedSize()
    }
}

private struct ToolbarStyleControlBackground: View {
    var body: some View {
        RoundedRectangle(cornerRadius: 6, style: .continuous)
            .fill(Color(nsColor: .controlBackgroundColor).opacity(0.5))
            .overlay(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .stroke(Color(nsColor: .separatorColor).opacity(0.5), lineWidth: 0.5)
            )
    }
}

private struct EditorToolbarButton: View {
    let title: String
    var shortcut: String? = nil
    let systemImage: String
    let isSelected: Bool
    let action: () -> Void

    @Environment(\.isEnabled) private var isEnabled
    @State private var isHovered = false
    @State private var showsTooltip = false

    var body: some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: 15, weight: .regular))
                .foregroundStyle(Color.primary.opacity(isEnabled ? (isSelected ? 1 : 0.85) : 0.3))
                .frame(width: 32, height: 30)
                .background(
                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                        .fill(Color.primary.opacity(isSelected ? 0.16 : (isHovered && isEnabled ? 0.08 : 0)))
                )
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
        .task(id: isHovered) {
            guard isHovered else {
                showsTooltip = false
                return
            }
            // Short delay so sweeping across the toolbar does not flash every tooltip.
            try? await Task.sleep(for: .milliseconds(350))
            if !Task.isCancelled { showsTooltip = true }
        }
        .overlay(alignment: .top) {
            if showsTooltip {
                ShortcutTooltip(title: title, shortcut: shortcut)
                    .fixedSize()
                    .offset(y: 38)
                    .allowsHitTesting(false)
            }
        }
        .accessibilityLabel(title)
        .accessibilityHint(shortcut.map { "Shortcut \($0)" } ?? "")
    }
}

private struct ToolbarSeparator: View {
    var body: some View {
        Rectangle()
            .fill(Color.primary.opacity(0.15))
            .frame(width: 1, height: 18)
            .padding(.horizontal, 8)
            .accessibilityHidden(true)
    }
}

// MARK: - Floating Options Bar

/// Style controls for the active tool (or crop controls), floating over the top of the canvas.
private struct EditorFloatingOptionsBar: View {
    @Bindable var model: EditorModel

    private var showsStyleControls: Bool {
        model.hasContextualStyleControls && model.collageState == nil && !model.isCropping
    }

    var body: some View {
        if model.isCropping {
            bar { cropControls }
        } else if showsStyleControls {
            bar { styleControls }
        }
    }

    private func bar<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        HStack(spacing: 8) {
            content()
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color(nsColor: .windowBackgroundColor))
                .shadow(color: .black.opacity(0.25), radius: 6, y: 2)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(Color.primary.opacity(0.1), lineWidth: 0.5)
        )
        .fixedSize()
    }

    @ViewBuilder
    private var styleControls: some View {
        if model.showsColorControl {
            AnnotationColorMenu(selectedSwatch: model.selectedSwatch) { swatch in
                model.setSwatch(swatch)
            }
        }

        if model.showsStrokeControl && !model.isInspectedRectangleFilled {
            StrokeWidthSlider(
                value: model.inspectedStrokeWidth,
                onBegin: { model.beginStrokeWidthChange() },
                onChange: { model.setStrokeWidth($0, registersUndo: false) }
            )
            .padding(.horizontal, 4)
        }

        if model.showsShapeStyleControl {
            RectangleStylePicker(
                style: model.inspectedShapeStyle,
                isFilled: model.isInspectedRectangleFilled,
                onSelectStyle: { model.setShapeStyle($0) },
                onSelectFilled: { model.setRectangleFilled() }
            )
        }

        if model.showsMagnificationControl {
            MagnificationPicker(value: model.inspectedMagnification) { model.setMagnification($0) }
        }

        if model.showsBadgeStyleControl {
            BadgeStylePicker(style: model.inspectedBadgeStyle) { model.setBadgeStyle($0) }
        }

        if model.isRedactionControlsVisible {
            AnnotationRedactionModeControl(model: model)
            AnnotationDensityControl(model: model)
        } else if model.showsSpotlightDensityControl {
            AnnotationDensityControl(model: model)
        }

        if model.showsTextControl {
            AnnotationTextToolbarControl(model: model)
        }
    }

    @ViewBuilder
    private var cropControls: some View {
        let width = Int(CGFloat(model.sourceImage?.width ?? 0) * model.cropRect.width)
        let height = Int(CGFloat(model.sourceImage?.height ?? 0) * model.cropRect.height)

        Image(systemName: "crop")
            .font(.system(size: 12, weight: .medium))
            .foregroundStyle(.secondary)
            .padding(.leading, 4)
        Text("\(width) × \(height) px")
            .font(.system(size: 12, weight: .medium))
            .monospacedDigit()
            .padding(.trailing, 4)

        Button("Reset") { model.resetCrop() }
            .controlSize(.small)
            .disabled(!model.hasCrop)
        Button("Done") { model.isCropping = false }
            .controlSize(.small)
            .keyboardShortcut(.defaultAction)
    }
}

// MARK: - Side Panel

/// Right-hand panel. Backdrop panels share one panel with a tab picker, like Shottr's Backdrop tool.
private struct EditorSidePanel: View {
    @Bindable var model: EditorModel
    @Binding var panel: EditorInspectorPanel
    let onCollageDone: () -> Void

    private var isBackdrop: Bool {
        EditorInspectorPanel.backdropPanels.contains(panel)
    }

    var body: some View {
        VStack(spacing: 0) {
            if isBackdrop {
                VStack(alignment: .leading, spacing: 10) {
                    Text("Backdrop")
                        .font(.system(size: 13, weight: .semibold))
                    Picker("Backdrop section", selection: $panel) {
                        ForEach(EditorInspectorPanel.backdropPanels) { item in
                            Text(item.title).tag(item)
                        }
                    }
                    .labelsHidden()
                    .pickerStyle(.segmented)
                }
                .padding(.horizontal, 14)
                .padding(.top, 14)
                .padding(.bottom, 4)
            }

            EditorInspectorView(model: model, panel: panel, onCollageDone: onCollageDone)
        }
        .background(Color(nsColor: .controlBackgroundColor))
    }
}

// MARK: - Title Bar

/// Flat, Shottr-style title bar drawn in the window's full-size content area.
/// The system toolbar is not used because macOS wraps its items in glass capsules.
private struct EditorTitleBar<Content: View>: View {
    /// Midpoint of the app icon's green-to-teal gradient (#6BDD75 → #19C9B7).
    static var brandColor: Color { Color(red: 0x42 / 255, green: 0xD3 / 255, blue: 0x96 / 255) }

    let height: CGFloat
    @ViewBuilder let content: Content

    /// Room for the close/minimize/zoom buttons, which the window still draws.
    private let trafficLightInset: CGFloat = 82

    var body: some View {
        HStack(spacing: 6) {
            content
        }
        .padding(.leading, trafficLightInset)
        .frame(maxWidth: .infinity, alignment: .leading)
        .frame(height: height)
        .background(WindowDragArea())
        .background(Color(nsColor: .windowBackgroundColor))
    }
}

/// Lets the user drag the window, or double-click to zoom/minimize, from empty title bar space.
private struct WindowDragArea: NSViewRepresentable {
    func makeNSView(context: Context) -> WindowDragNSView { WindowDragNSView() }
    func updateNSView(_ nsView: WindowDragNSView, context: Context) {}
}

private final class WindowDragNSView: NSView {
    override func mouseDown(with event: NSEvent) {
        guard let window else { return }
        if event.clickCount == 2 {
            switch UserDefaults.standard.string(forKey: "AppleActionOnDoubleClick") {
            case "Minimize": window.performMiniaturize(nil)
            case "None": break
            default: window.performZoom(nil)
            }
        } else {
            window.performDrag(with: event)
        }
    }
}
