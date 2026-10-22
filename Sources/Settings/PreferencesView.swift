import SwiftUI
import Carbon
import ServiceManagement

enum SettingsSection: String, CaseIterable, Identifiable {
    case general = "General"
    case hotkeys = "Hotkeys"
    case capture = "Capture"
    case backdrop = "Backdrop"
    case recording = "Recording"
    case watermark = "Watermark"
    case history = "History"
    case about = "About"

    var id: String { rawValue }

    var icon: String {
        switch self {
        case .general: return "gearshape"
        case .hotkeys: return "keyboard"
        case .capture: return "camera.viewfinder"
        case .backdrop: return "photo.artframe"
        case .recording: return "record.circle"
        case .watermark: return "seal"
        case .history: return "clock.arrow.circlepath"
        case .about: return "info.circle"
        }
    }
}

struct PreferencesView: View {
    @AppStorage("bs_appAppearance") private var appAppearanceRaw: String = AppAppearance.system.rawValue
    @State private var selectedSection: SettingsSection = .general

    init(initialSection: SettingsSection = .general) {
        _selectedSection = State(initialValue: initialSection)
    }

    var preferredColorScheme: ColorScheme? {
        switch AppAppearance(rawValue: appAppearanceRaw) ?? .system {
        case .system: return nil
        case .light: return .light
        case .dark: return .dark
        }
    }

    var body: some View {
        // Shottr-style preferences: icon tabs under the title, then a two-column form.
        // The window has a transparent title bar, so the tab row starts below it.
        GeometryReader { proxy in
            VStack(spacing: 0) {
                SettingsTabBar(selection: $selectedSection)
                    .padding(.top, proxy.safeAreaInsets.top)
                    .background(WindowDragBackground())

                Divider()

                selectedTab
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .ignoresSafeArea(.container, edges: .top)
        }
        .frame(minWidth: 640, minHeight: 520)
        .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("switchToSettingsTab"))) { notification in
            if let section = notification.object as? SettingsSection {
                selectedSection = section
            }
        }
        .preferredColorScheme(preferredColorScheme)
    }

    @ViewBuilder
    private var selectedTab: some View {
        switch selectedSection {
        case .general: GeneralSettingsTab()
        case .hotkeys: HotkeysSettingsTab()
        case .capture: CaptureSettingsTab()
        case .backdrop: BackdropSettingsTab()
        case .recording: RecordingSettingsTab()
        case .watermark: WatermarkSettingsTab()
        case .history: HistorySettingsTab()
        case .about: AboutTab()
        }
    }
}

// MARK: - Layout Building Blocks

private struct SettingsTabBar: View {
    @Binding var selection: SettingsSection

    var body: some View {
        HStack(spacing: 2) {
            ForEach(SettingsSection.allCases) { section in
                let isSelected = selection == section
                Button {
                    selection = section
                } label: {
                    VStack(spacing: 3) {
                        Image(systemName: section.icon)
                            .font(.system(size: 18, weight: .regular))
                            .frame(height: 22)
                        Text(section.rawValue)
                            .font(.system(size: 11))
                    }
                    .foregroundStyle(isSelected ? Color.accentColor : Color.primary.opacity(0.75))
                    .frame(width: 70, height: 50)
                    .background(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .fill(isSelected ? Color.primary.opacity(0.1) : .clear)
                    )
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(section.rawValue)
                .accessibilityAddTraits(isSelected ? .isSelected : [])
            }
        }
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity)
    }
}

/// Lets the window be dragged from the empty tab-bar area, since the title bar is transparent.
private struct WindowDragBackground: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView { DragView() }
    func updateNSView(_ nsView: NSView, context: Context) {}

    private final class DragView: NSView {
        override func mouseDown(with event: NSEvent) {
            window?.performDrag(with: event)
        }
    }
}

/// Scrolling page with a two-column grid: right-aligned labels, left-aligned controls.
private struct SettingsPage<Content: View>: View {
    @ViewBuilder let content: Content

    var body: some View {
        ScrollView {
            Grid(alignment: .leadingFirstTextBaseline, horizontalSpacing: 14, verticalSpacing: 12) {
                content
            }
            .padding(.horizontal, 32)
            .padding(.vertical, 24)
            .frame(maxWidth: .infinity)
        }
    }
}

private struct SettingsRow<Content: View>: View {
    let label: String
    @ViewBuilder let content: Content

    init(_ label: String, @ViewBuilder content: () -> Content) {
        self.label = label
        self.content = content()
    }

    var body: some View {
        GridRow {
            Text(label)
                .frame(minWidth: 170, alignment: .trailing)
                .gridColumnAlignment(.trailing)
            VStack(alignment: .leading, spacing: 8) {
                content
            }
            .frame(maxWidth: 380, alignment: .leading)
            .gridColumnAlignment(.leading)
        }
    }
}

private struct SettingsSeparator: View {
    var body: some View {
        GridRow {
            Divider()
                .gridCellColumns(2)
                .padding(.vertical, 6)
        }
    }
}

/// Secondary explanation shown under a control.
private struct SettingsNote: View {
    let text: String

    init(_ text: String) { self.text = text }

    var body: some View {
        Text(text)
            .font(.caption)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
    }
}

/// A reset button that asks before discarding the user's settings.
private struct SettingsResetButton: View {
    let title: String
    let message: String
    let action: () -> Void
    @State private var isConfirming = false

    var body: some View {
        Button(title) { isConfirming = true }
            .controlSize(.small)
            .alert(title, isPresented: $isConfirming) {
                Button("Reset", role: .destructive, action: action)
                Button("Cancel", role: .cancel) {}
            } message: {
                Text(message)
            }
    }
}

// MARK: - General

struct GeneralSettingsTab: View {
    @AppStorage("bs_appAppearance") private var appAppearanceRaw: String = AppAppearance.system.rawValue
    @AppStorage("bs_saveDirectory") private var saveDir = NSHomeDirectory() + "/Desktop"
    @AppStorage("bs_copyAfterSave") private var copyAfterSave = true
    @AppStorage("bs_autoSaveCaptures") private var autoSaveCaptures = true
    @AppStorage("bs_playSound") private var playSound = true
    @AppStorage("bs_smartBlurEnabled") private var smartBlurEnabled = false
    @AppStorage("bs_exportFormat") private var exportFormatRaw: String = ExportFormat.png.rawValue
    @AppStorage("bs_exportQuality") private var exportQuality: Double = 0.9
    @AppStorage("bs_analyticsEnabled") private var analyticsEnabled = true

    @State private var launchesAtLogin = SMAppService.mainApp.status == .enabled
    @State private var launchAtLoginError: String?

    private var appAppearance: Binding<AppAppearance> {
        Binding(
            get: { AppAppearance(rawValue: appAppearanceRaw) ?? .system },
            set: { newValue in
                appAppearanceRaw = newValue.rawValue
                AppPreferences.applyAppearance(newValue)
            }
        )
    }

    private var exportFormat: Binding<ExportFormat> {
        Binding(
            get: { ExportFormat(rawValue: exportFormatRaw) ?? .png },
            set: { exportFormatRaw = $0.rawValue }
        )
    }

    /// Without auto-save, captures are always copied, so the Copy box is locked on.
    private var copyAfterCapture: Binding<Bool> {
        Binding(
            get: { autoSaveCaptures ? copyAfterSave : true },
            set: { copyAfterSave = $0 }
        )
    }

    private var launchAtLogin: Binding<Bool> {
        Binding(
            get: { launchesAtLogin },
            set: { enabled in
                do {
                    if enabled {
                        try SMAppService.mainApp.register()
                    } else {
                        try SMAppService.mainApp.unregister()
                    }
                    launchAtLoginError = nil
                } catch {
                    launchAtLoginError = "Couldn't change the login item: \(error.localizedDescription)"
                }
                launchesAtLogin = SMAppService.mainApp.status == .enabled
            }
        )
    }

    var body: some View {
        SettingsPage {
            SettingsRow("Appearance") {
                Picker("Appearance", selection: appAppearance) {
                    ForEach(AppAppearance.allCases) { appearance in
                        Text(appearance.label).tag(appearance)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .fixedSize()
            }

            SettingsSeparator()

            SettingsRow("Screenshots folder") {
                Button {
                    chooseSaveDirectory()
                } label: {
                    Text(abbreviatedPath(saveDir))
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 4)
                        .frame(maxWidth: 300, alignment: .leading)
                        .background(
                            RoundedRectangle(cornerRadius: 6, style: .continuous)
                                .fill(Color.primary.opacity(0.08))
                        )
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help("Choose the folder where screenshots are saved")
            }

            SettingsRow("After screenshot") {
                HStack(spacing: 16) {
                    Toggle("Save", isOn: $autoSaveCaptures)
                    Toggle("Copy", isOn: copyAfterCapture)
                        .disabled(!autoSaveCaptures)
                }
                .toggleStyle(.checkbox)
                if !autoSaveCaptures {
                    SettingsNote("Captures are only copied to the clipboard. Use Save in the preview or editor to keep one.")
                }
            }

            SettingsRow("Save format") {
                Picker("Save format", selection: exportFormat) {
                    ForEach(ExportFormat.allCases, id: \.self) { format in
                        Text(format.rawValue.uppercased()).tag(format)
                    }
                }
                .pickerStyle(.radioGroup)
                .horizontalRadioGroupLayout()
                .labelsHidden()
            }

            if exportFormat.wrappedValue == .jpeg {
                SettingsRow("JPEG quality") {
                    HStack(spacing: 10) {
                        Slider(value: $exportQuality, in: 0.1...1.0, step: 0.05)
                            .frame(width: 200)
                        Text("\(Int(exportQuality * 100))%")
                            .monospacedDigit()
                            .foregroundStyle(.secondary)
                    }
                }
            }

            SettingsSeparator()

            SettingsRow("Autostart") {
                Toggle("Launch at startup", isOn: launchAtLogin)
                    .toggleStyle(.checkbox)
                if let launchAtLoginError {
                    Text(launchAtLoginError)
                        .font(.caption)
                        .foregroundStyle(.red)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            SettingsRow("Sound") {
                Toggle("Play shutter sound", isOn: $playSound)
                    .toggleStyle(.checkbox)
            }

            SettingsRow("Smart Blur") {
                Toggle("Redact sensitive info automatically", isOn: $smartBlurEnabled)
                    .toggleStyle(.checkbox)
            }

            SettingsSeparator()

            SettingsRow("Privacy") {
                Toggle("Share anonymous usage analytics", isOn: $analyticsEnabled)
                    .toggleStyle(.checkbox)
                    .onChange(of: analyticsEnabled) { _, enabled in
                        AnalyticsService.updateConsent(enabled)
                    }
                SettingsNote("Counts feature usage to help improve Shotly. Screenshots, OCR text, file names, clipboard contents and personal data are never sent.")
            }

            SettingsSeparator()

            SettingsRow("") {
                SettingsResetButton(
                    title: "Reset General Settings",
                    message: "Appearance, folder, save options, sound and privacy go back to their defaults."
                ) {
                    appAppearanceRaw = AppAppearance.system.rawValue
                    AppPreferences.applyAppearance(.system)
                    saveDir = NSHomeDirectory() + "/Desktop"
                    autoSaveCaptures = true
                    copyAfterSave = true
                    playSound = true
                    smartBlurEnabled = false
                    exportFormatRaw = ExportFormat.png.rawValue
                    exportQuality = 0.9
                    analyticsEnabled = true
                    AnalyticsService.updateConsent(true)
                }
            }
        }
    }

    private func chooseSaveDirectory() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.canCreateDirectories = true
        panel.allowsMultipleSelection = false
        panel.directoryURL = URL(fileURLWithPath: saveDir)
        if panel.runModal() == .OK, let url = panel.url {
            saveDir = url.path
        }
    }

    private func abbreviatedPath(_ path: String) -> String {
        (path as NSString).abbreviatingWithTildeInPath
    }
}

// MARK: - Backdrop

struct BackdropSettingsTab: View {
    @State private var defaultConfig = AppPreferences.defaultBeautifierConfig

    var body: some View {
        SettingsPage {
            SettingsRow("Preview") {
                DefaultConfigPreview(config: defaultConfig)
                    .frame(width: 300, height: 160)
                SettingsNote("Applied to every new capture and recording, and used when the editor opens.")
            }

            SettingsSeparator()

            SettingsRow("Padding") {
                valueSlider(value: $defaultConfig.padding, range: 0.0...0.45) { "\(Int($0 * 100))%" }
            }
            SettingsRow("Corner radius") {
                valueSlider(value: $defaultConfig.cornerRadius, range: 0.0...0.12) { "\(Int($0 * 1000))" }
            }
            SettingsRow("Shadow") {
                valueSlider(value: $defaultConfig.shadowStrength, range: 0.0...1.0) { "\(Int($0 * 100))%" }
            }

            SettingsSeparator()

            SettingsRow("Background") {
                Text(backgroundLabel(for: defaultConfig.style))
                    .foregroundStyle(.secondary)
                DefaultBackgroundPicker(selectedStyle: $defaultConfig.style)
            }

            SettingsSeparator()

            SettingsRow("") {
                SettingsResetButton(
                    title: "Reset Backdrop",
                    message: "Padding, corner radius, shadow and background go back to their defaults."
                ) {
                    defaultConfig = .default
                }
            }
        }
        .onChange(of: defaultConfig) { _, newValue in
            AppPreferences.defaultBeautifierConfig = newValue
        }
    }

    private func valueSlider(
        value: Binding<CGFloat>,
        range: ClosedRange<CGFloat>,
        format: @escaping (CGFloat) -> String
    ) -> some View {
        HStack(spacing: 10) {
            Slider(value: value, in: range)
                .frame(width: 220)
            Text(format(value.wrappedValue))
                .monospacedDigit()
                .foregroundStyle(.secondary)
                .frame(minWidth: 36, alignment: .leading)
        }
    }

    private func backgroundLabel(for style: BackgroundStyle) -> String {
        switch style {
        case .none: return "Transparent"
        case .solid(let c): return c.name
        case .gradient(let g): return g.name
        case .wallpaper: return "Custom Image"
        }
    }
}

// MARK: - Default Background Picker (compact for settings)

private struct DefaultBackgroundPicker: View {
    @Binding var selectedStyle: BackgroundStyle

    private let swatchColumns = Array(repeating: GridItem(.fixed(24), spacing: 5), count: 9)

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            LazyVGrid(columns: swatchColumns, spacing: 5) {
                noneButton
                ForEach(SolidColor.presets) { color in
                    solidButton(color)
                }
            }

            LazyVGrid(columns: swatchColumns, spacing: 5) {
                ForEach(GradientPreset.presets) { preset in
                    gradientButton(preset)
                }
            }

            customImageRow
        }
    }

    private var noneButton: some View {
        Button {
            selectedStyle = .none
        } label: {
            ZStack {
                RoundedRectangle(cornerRadius: 4, style: .continuous)
                    .fill(Color.white)
                    .frame(width: 24, height: 24)
                Path { path in
                    path.move(to: CGPoint(x: 22, y: 2))
                    path.addLine(to: CGPoint(x: 2, y: 22))
                }
                .stroke(Color.red.opacity(0.6), lineWidth: 1.5)
            }
            .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 4, style: .continuous)
                    .strokeBorder(selectedStyle == .none ? Color.accentColor : Color.primary.opacity(0.12), lineWidth: selectedStyle == .none ? 2 : 0.5)
            )
        }
        .buttonStyle(.plain)
        .help("No background")
    }

    private func solidButton(_ color: SolidColor) -> some View {
        let isSelected: Bool = {
            if case .solid(let c) = selectedStyle { return c.id == color.id }
            return false
        }()

        return Button {
            selectedStyle = .solid(color)
        } label: {
            RoundedRectangle(cornerRadius: 4, style: .continuous)
                .fill(color.color)
                .frame(width: 24, height: 24)
                .overlay(
                    RoundedRectangle(cornerRadius: 4, style: .continuous)
                        .strokeBorder(isSelected ? Color.accentColor : Color.primary.opacity(0.12), lineWidth: isSelected ? 2 : 0.5)
                )
        }
        .buttonStyle(.plain)
        .help(color.name)
    }

    private func gradientButton(_ preset: GradientPreset) -> some View {
        let isSelected: Bool = {
            if case .gradient(let g) = selectedStyle { return g.id == preset.id }
            return false
        }()

        return Button {
            selectedStyle = .gradient(preset)
        } label: {
            RoundedRectangle(cornerRadius: 4, style: .continuous)
                .fill(preset.swiftUIGradient)
                .frame(width: 24, height: 24)
                .overlay(
                    RoundedRectangle(cornerRadius: 4, style: .continuous)
                        .strokeBorder(isSelected ? Color.accentColor : Color.primary.opacity(0.12), lineWidth: isSelected ? 2 : 0.5)
                )
        }
        .buttonStyle(.plain)
        .help(preset.name)
    }

    @ViewBuilder
    private var customImageRow: some View {
        if case .wallpaper(let source) = selectedStyle {
            HStack(spacing: 8) {
                if let img = NSImage(contentsOfFile: source.path) {
                    Image(nsImage: img)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .frame(width: 24, height: 24)
                        .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: 4, style: .continuous)
                                .strokeBorder(Color.accentColor, lineWidth: 2)
                        )
                }
                Text(URL(fileURLWithPath: source.path).lastPathComponent)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Spacer()
                Button("Change") { pickCustomImage() }
                    .controlSize(.mini)
            }
        } else {
            Button { pickCustomImage() } label: {
                HStack(spacing: 4) {
                    Image(systemName: "plus").font(.caption2)
                    Text("Custom Image...").font(.caption2)
                }
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
        }
    }

    private func pickCustomImage() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.image, .png, .jpeg]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.title = "Choose Background Image"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        selectedStyle = .wallpaper(WallpaperSource(path: url.path))
    }
}

// MARK: - Default Config Preview

private struct DefaultConfigPreview: View {
    let config: BeautifierConfig

    var body: some View {
        GeometryReader { proxy in
            let mockImageW: CGFloat = 160
            let mockImageH: CGFloat = 100
            let shortEdge = min(mockImageW, mockImageH)
            let pad = shortEdge * config.padding

            var canvasW = mockImageW + pad * 2
            var canvasH = mockImageH + pad * 2
            let _ = {
                if let ratio = config.aspectRatio.numericValue {
                    let current = canvasW / canvasH
                    if current < ratio { canvasW = canvasH * ratio }
                    else { canvasH = canvasW / ratio }
                }
            }()

            let canvasSize = CGSize(width: canvasW, height: canvasH)
            let fitted = aspectFitRect(imageSize: canvasSize, in: proxy.size)

            let totalHPad = canvasW - mockImageW
            let totalVPad = canvasH - mockImageH
            let imgX = fitted.minX + config.alignment.xFactor * totalHPad / canvasW * fitted.width
            let imgY = fitted.minY + config.alignment.yFactor * totalVPad / canvasH * fitted.height
            let imgW = mockImageW / canvasW * fitted.width
            let imgH = mockImageH / canvasH * fitted.height

            let cornerRadius = config.cornerRadius * shortEdge * min(fitted.width / canvasW, fitted.height / canvasH)
            let m = config.alignment.cornerMultipliers

            ZStack {
                previewBackground(config.style)
                    .frame(width: fitted.width, height: fitted.height)
                    .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .strokeBorder(Color.primary.opacity(0.08), lineWidth: 0.5)
                    )
                    .position(x: fitted.midX, y: fitted.midY)

                mockScreenshot
                    .clipShape(UnevenRoundedRectangle(
                        topLeadingRadius: cornerRadius * m.tl,
                        bottomLeadingRadius: cornerRadius * m.bl,
                        bottomTrailingRadius: cornerRadius * m.br,
                        topTrailingRadius: cornerRadius * m.tr,
                        style: .continuous
                    ))
                    .shadow(
                        color: config.shadowStrength > 0 ? .black.opacity(Double(config.shadowStrength * 0.3)) : .clear,
                        radius: config.shadowStrength > 0 ? max(2, shortEdge * 0.02 * (1 + config.shadowStrength)) : 0,
                        x: 0,
                        y: config.shadowStrength > 0 ? shortEdge * 0.01 * (1 + config.shadowStrength) : 0
                    )
                    .frame(width: imgW, height: imgH)
                    .position(x: imgX + imgW / 2, y: imgY + imgH / 2)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private var mockScreenshot: some View {
        ZStack {
            LinearGradient(
                colors: [Color(white: 0.96), Color(white: 0.88)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )

            VStack(spacing: 4) {
                HStack(spacing: 3) {
                    Circle().fill(.red.opacity(0.7)).frame(width: 5, height: 5)
                    Circle().fill(.yellow.opacity(0.7)).frame(width: 5, height: 5)
                    Circle().fill(.green.opacity(0.7)).frame(width: 5, height: 5)
                    Spacer()
                }
                .padding(.horizontal, 6)
                .padding(.top, 4)

                RoundedRectangle(cornerRadius: 2)
                    .fill(Color(white: 0.82))
                    .frame(height: 6)
                    .padding(.horizontal, 8)

                HStack(spacing: 4) {
                    RoundedRectangle(cornerRadius: 2)
                        .fill(Color(white: 0.78))
                        .frame(width: 30, height: 4)
                    RoundedRectangle(cornerRadius: 2)
                        .fill(Color(white: 0.84))
                        .frame(height: 4)
                }
                .padding(.horizontal, 8)

                Spacer()
            }
        }
    }

    @ViewBuilder
    private func previewBackground(_ style: BackgroundStyle) -> some View {
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

    private func aspectFitRect(imageSize: CGSize, in containerSize: CGSize) -> CGRect {
        guard imageSize.width > 0, imageSize.height > 0,
              containerSize.width > 0, containerSize.height > 0 else { return .zero }
        let scale = min(containerSize.width / imageSize.width, containerSize.height / imageSize.height)
        let size = CGSize(width: imageSize.width * scale, height: imageSize.height * scale)
        return CGRect(
            x: (containerSize.width - size.width) / 2,
            y: (containerSize.height - size.height) / 2,
            width: size.width,
            height: size.height
        )
    }
}

// MARK: - Hotkeys

struct HotkeysSettingsTab: View {
    @State private var shortcutResetID = UUID()

    private static let captureShortcuts: [(String, ShortcutService.Action)] = [
        ("Capture area", .region),
        ("Capture fullscreen", .fullscreen),
        ("Capture window", .window),
        ("Record screen", .recording),
        ("Recognize text (OCR)", .ocr),
        ("Pick color", .colorPicker),
    ]

    var body: some View {
        SettingsPage {
            Group {
                ForEach(Self.captureShortcuts, id: \.1) { label, action in
                    SettingsRow(label) {
                        ShortcutRow(action: action)
                    }
                }
            }
            .id(shortcutResetID)

            SettingsSeparator()

            Group {
                SettingsRow("Copy in editor") {
                    EditorShortcutRow(action: .copy)
                }
                SettingsRow("Save in editor") {
                    EditorShortcutRow(action: .save)
                }
            }
            .id(shortcutResetID)

            SettingsSeparator()

            SettingsRow("Editor keys") {
                EditorKeyReference()
                SettingsNote("Single keys work while the editor is open and you are not typing text.")
            }

            SettingsSeparator()

            SettingsRow("") {
                SettingsResetButton(
                    title: "Reset Hotkeys",
                    message: "All capture and editor shortcuts go back to their defaults."
                ) {
                    for action in ShortcutService.Action.allCases {
                        ShortcutService.shared.saveShortcut(ShortcutRow.defaultShortcut(for: action), for: action)
                    }
                    ShortcutService.shared.registerAll()
                    AppPreferences.editorCopyShortcut = .defaultCopy
                    AppPreferences.editorSaveShortcut = .defaultSave
                    shortcutResetID = UUID()
                }
            }
        }
    }
}

/// Read-only list of the editor's single-key shortcuts.
private struct EditorKeyReference: View {
    private static let entries: [(String, String)] = {
        let tools: [AnnotationTool] = [
            .select, .text, .measure, .rectangle, .filledRectangle, .freehand,
            .arrow, .blur, .spotlight, .magnifier, .numberedCircle, .ellipse, .line,
        ]
        var result = tools.map { ($0.shortcutHint, $0.title) }
        result += [
            (EditorAction.crop.shortcutHint, "Crop"),
            (EditorAction.pin.shortcutHint, "Pin to screen"),
            (EditorAction.backdrop.shortcutHint, "Backdrop"),
            (EditorAction.watermark.shortcutHint, "Watermark"),
            (EditorAction.metadata.shortcutHint, "Metadata"),
            ("Z", "Zoom in at cursor"),
            ("⌘0", "Actual size"),
            ("⌘1", "Fit to window"),
            ("Tab", "Copy color under cursor"),
            ("Space", "Hold and drag to pan"),
        ]
        return result
    }()

    var body: some View {
        Grid(alignment: .leading, horizontalSpacing: 8, verticalSpacing: 5) {
            ForEach(Array(stride(from: 0, to: Self.entries.count, by: 2)), id: \.self) { index in
                GridRow {
                    entry(Self.entries[index])
                    if index + 1 < Self.entries.count {
                        entry(Self.entries[index + 1])
                    }
                }
            }
        }
    }

    private func entry(_ item: (String, String)) -> some View {
        HStack(spacing: 8) {
            Text(item.0)
                .font(.system(size: 11, weight: .semibold))
                .monospacedDigit()
                .frame(minWidth: 22)
                .padding(.horizontal, 5)
                .padding(.vertical, 2)
                .background(
                    RoundedRectangle(cornerRadius: 4, style: .continuous)
                        .fill(Color.primary.opacity(0.1))
                )
            Text(item.1)
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
        .frame(width: 180, alignment: .leading)
    }
}

// MARK: - Capture

struct CaptureSettingsTab: View {
    @AppStorage("bs_selfTimerDelay") private var selfTimerRaw: Int = 0
    @AppStorage("bs_overlayPosition") private var overlayPositionRaw: String = OverlayPosition.cursor.rawValue
    @AppStorage("bs_overlayAutoDismiss") private var overlayAutoDismiss: Bool = true
    @AppStorage("bs_overlayDismissDelay") private var overlayDismissDelay: Double = 5.0
    @AppStorage("bs_ocrTranslationEnabled") private var ocrTranslationEnabled: Bool = true
    @AppStorage("bs_ocrTranslationTargetLanguage") private var ocrTranslationTargetLanguageRaw: String = OCRTranslationLanguage.vietnamese.rawValue

    private var selfTimerDelay: Binding<SelfTimerDelay> {
        Binding(
            get: { SelfTimerDelay(rawValue: selfTimerRaw) ?? .off },
            set: { selfTimerRaw = $0.rawValue }
        )
    }

    private var overlayPosition: Binding<OverlayPosition> {
        Binding(
            get: { OverlayPosition(rawValue: overlayPositionRaw) ?? .cursor },
            set: { overlayPositionRaw = $0.rawValue }
        )
    }

    var body: some View {
        SettingsPage {
            SettingsRow("Self timer") {
                Picker("Self timer", selection: selfTimerDelay) {
                    ForEach(SelfTimerDelay.allCases, id: \.self) { delay in
                        Text(delay.label).tag(delay)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .fixedSize()
            }

            SettingsSeparator()

            SettingsRow("Preview thumbnail") {
                Picker("Position", selection: overlayPosition) {
                    Text("At cursor").tag(OverlayPosition.cursor)
                    Text("Bottom right").tag(OverlayPosition.bottomRight)
                    Text("Bottom left").tag(OverlayPosition.bottomLeft)
                }
                .pickerStyle(.radioGroup)
                .horizontalRadioGroupLayout()
                .labelsHidden()
            }

            SettingsRow("Hide thumbnail") {
                HStack(spacing: 10) {
                    Toggle("Automatically after", isOn: $overlayAutoDismiss)
                        .toggleStyle(.checkbox)
                    Stepper(value: $overlayDismissDelay, in: 2...15, step: 1) {
                        Text("\(Int(overlayDismissDelay)) s")
                            .monospacedDigit()
                            .frame(minWidth: 32, alignment: .trailing)
                    }
                    .disabled(!overlayAutoDismiss)
                }
                if overlayAutoDismiss {
                    SettingsNote("It also hides when you click outside it, and stays while the pointer is over it.")
                }
            }

            SettingsSeparator()

            SettingsRow("OCR translation") {
                Toggle("Translate recognized text", isOn: $ocrTranslationEnabled)
                    .toggleStyle(.checkbox)
                if ocrTranslationEnabled {
                    Picker("Translate to", selection: $ocrTranslationTargetLanguageRaw) {
                        ForEach(OCRTranslationLanguage.allCases) { language in
                            Text(language.label).tag(language.rawValue)
                        }
                    }
                    .fixedSize()
                    SettingsNote("The source language is detected automatically. Uses Apple's on-device Translation on macOS 15 or later.")
                } else {
                    SettingsNote("Recognized text is still copied to the clipboard; the translation window won't open.")
                }
            }

            SettingsSeparator()

            SettingsRow("") {
                SettingsResetButton(
                    title: "Reset Capture Settings",
                    message: "Self timer, preview thumbnail and OCR translation go back to their defaults."
                ) {
                    selfTimerRaw = 0
                    overlayPositionRaw = OverlayPosition.cursor.rawValue
                    overlayAutoDismiss = true
                    overlayDismissDelay = 5.0
                    ocrTranslationEnabled = true
                    ocrTranslationTargetLanguageRaw = OCRTranslationLanguage.vietnamese.rawValue
                }
            }
        }
    }
}

// MARK: - Recording Settings

struct RecordingSettingsTab: View {
    @AppStorage("bs_recordingFPS") private var recordingFPS: Int = 30
    @AppStorage("bs_recordingShowCursor") private var showCursor: Bool = true
    @AppStorage("bs_recordingCaptureAudio") private var captureAudio: Bool = false
    @AppStorage("bs_recordingOpenEditor") private var openEditor: Bool = true

    var body: some View {
        SettingsPage {
            SettingsRow("Frame rate") {
                Picker("Frame rate", selection: $recordingFPS) {
                    Text("24 fps").tag(24)
                    Text("30 fps").tag(30)
                    Text("60 fps").tag(60)
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .fixedSize()
                SettingsNote("Higher frame rates are smoother but make larger files.")
            }

            SettingsSeparator()

            SettingsRow("Record") {
                Toggle("Show cursor", isOn: $showCursor)
                    .toggleStyle(.checkbox)
                Toggle("Capture system audio", isOn: $captureAudio)
                    .toggleStyle(.checkbox)
            }

            SettingsRow("After recording") {
                Toggle("Open the video editor", isOn: $openEditor)
                    .toggleStyle(.checkbox)
                SettingsNote("When off, recordings are saved directly without opening the trim editor.")
            }

            SettingsSeparator()

            SettingsRow("") {
                SettingsResetButton(
                    title: "Reset Recording Settings",
                    message: "Frame rate, cursor, audio and after-recording options go back to their defaults."
                ) {
                    recordingFPS = 30
                    showCursor = true
                    captureAudio = false
                    openEditor = true
                }
            }
        }
    }
}

private enum EditorShortcutAction {
    case copy
    case save

    var current: EditorShortcut {
        get {
            switch self {
            case .copy: return AppPreferences.editorCopyShortcut
            case .save: return AppPreferences.editorSaveShortcut
            }
        }
    }

    func save(_ shortcut: EditorShortcut) {
        switch self {
        case .copy: AppPreferences.editorCopyShortcut = shortcut
        case .save: AppPreferences.editorSaveShortcut = shortcut
        }
    }
}

/// Field-style button showing a shortcut; click to record a new one.
private struct ShortcutField: View {
    let display: String
    let isRecording: Bool
    let onStart: () -> Void
    let onRecord: (UInt32, UInt32) -> Void
    let onCancel: () -> Void

    var body: some View {
        if isRecording {
            ShortcutRecorderView(onRecord: onRecord, onCancel: onCancel)
                .frame(width: 130, height: 24)
        } else {
            Button(action: onStart) {
                Text(display)
                    .font(.system(size: 12, weight: .medium))
                    .monospacedDigit()
                    .frame(width: 118, height: 22)
                    .background(
                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .fill(Color.primary.opacity(0.08))
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .stroke(Color.primary.opacity(0.12), lineWidth: 0.5)
                    )
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help("Click, then press the new shortcut. Esc cancels.")
        }
    }
}

private struct EditorShortcutRow: View {
    let action: EditorShortcutAction

    @State private var shortcut: EditorShortcut
    @State private var isRecording = false
    @State private var errorMessage: String?

    init(action: EditorShortcutAction) {
        self.action = action
        _shortcut = State(initialValue: action.current)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            ShortcutField(
                display: shortcut.displayString,
                isRecording: isRecording,
                onStart: {
                    errorMessage = nil
                    isRecording = true
                },
                onRecord: { keyCode, modifiers in
                    guard EditorShortcut.supports(keyCode: keyCode) else {
                        errorMessage = "That key isn't supported. Use a letter, number or punctuation key."
                        isRecording = false
                        return
                    }
                    let newShortcut = EditorShortcut(keyCode: keyCode, modifiers: modifiers)
                    shortcut = newShortcut
                    action.save(newShortcut)
                    errorMessage = nil
                    isRecording = false
                },
                onCancel: { isRecording = false }
            )

            if let errorMessage {
                Text(errorMessage)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .onAppear {
            shortcut = action.current
        }
    }
}

struct ShortcutRow: View {
    let action: ShortcutService.Action

    @State private var shortcut: ShortcutService.Shortcut?
    @State private var isRecording = false

    var body: some View {
        HStack(spacing: 12) {
            ShortcutField(
                display: shortcut?.displayString ?? "—",
                isRecording: isRecording,
                onStart: { isRecording = true },
                onRecord: { keyCode, modifiers in
                    shortcut = ShortcutService.Shortcut(
                        keyCode: keyCode,
                        modifiers: modifiers,
                        enabled: shortcut?.enabled ?? true
                    )
                    persist()
                    isRecording = false
                },
                onCancel: { isRecording = false }
            )

            Toggle("Enabled", isOn: Binding(
                get: { shortcut?.enabled ?? false },
                set: { enabled in
                    shortcut?.enabled = enabled
                    persist()
                }
            ))
            .toggleStyle(.checkbox)
        }
        .onAppear {
            shortcut = ShortcutService.shared.loadShortcut(for: action) ?? Self.defaultShortcut(for: action)
        }
    }

    private func persist() {
        guard let shortcut else { return }
        ShortcutService.shared.saveShortcut(shortcut, for: action)
        ShortcutService.shared.registerAll()
    }

    static func defaultShortcut(for action: ShortcutService.Action) -> ShortcutService.Shortcut {
        switch action {
        case .region: return .defaultRegion
        case .fullscreen: return .defaultFullscreen
        case .window: return .defaultWindow
        case .ocr: return .defaultOCR
        case .colorPicker: return .defaultColorPicker
        case .recording: return .defaultRecording
        }
    }
}

// MARK: - Shortcut Recorder

struct ShortcutRecorderView: NSViewRepresentable {
    let onRecord: (UInt32, UInt32) -> Void
    let onCancel: () -> Void

    func makeNSView(context: Context) -> ShortcutRecorderNSView {
        let view = ShortcutRecorderNSView()
        view.onRecord = onRecord
        view.onCancel = onCancel
        ShortcutService.shared.unregisterAll()
        DispatchQueue.main.async {
            view.window?.makeFirstResponder(view)
        }
        return view
    }

    func updateNSView(_ nsView: ShortcutRecorderNSView, context: Context) {}

    static func dismantleNSView(_ nsView: ShortcutRecorderNSView, coordinator: ()) {
        nsView.removeMonitor()
        ShortcutService.shared.registerAll()
    }
}

final class ShortcutRecorderNSView: NSView {
    var onRecord: ((UInt32, UInt32) -> Void)?
    var onCancel: (() -> Void)?
    private var eventMonitor: Any?

    override var acceptsFirstResponder: Bool { true }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if window != nil {
            installMonitor()
        }
    }

    private func installMonitor() {
        guard eventMonitor == nil else { return }
        eventMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self else { return event }

            let keyCode = UInt32(event.keyCode)

            if keyCode == 53 {
                self.onCancel?()
                return nil
            }

            let flags = event.modifierFlags
            var carbonMods: UInt32 = 0
            if flags.contains(.command) { carbonMods |= UInt32(cmdKey) }
            if flags.contains(.shift) { carbonMods |= UInt32(shiftKey) }
            if flags.contains(.option) { carbonMods |= UInt32(optionKey) }
            if flags.contains(.control) { carbonMods |= UInt32(controlKey) }

            guard carbonMods != 0 else { return event }

            self.onRecord?(keyCode, carbonMods)
            return nil
        }
    }

    func removeMonitor() {
        if let monitor = eventMonitor {
            NSEvent.removeMonitor(monitor)
            eventMonitor = nil
        }
    }

    override func draw(_ dirtyRect: NSRect) {
        let path = NSBezierPath(roundedRect: bounds.insetBy(dx: 0.5, dy: 0.5), xRadius: 4, yRadius: 4)
        NSColor.controlAccentColor.withAlphaComponent(0.15).setFill()
        path.fill()
        NSColor.controlAccentColor.setStroke()
        path.lineWidth = 1.5
        path.stroke()

        let text = "Press shortcut..." as NSString
        let attrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 11, weight: .medium),
            .foregroundColor: NSColor.controlAccentColor,
        ]
        let size = text.size(withAttributes: attrs)
        let point = NSPoint(
            x: (bounds.width - size.width) / 2,
            y: (bounds.height - size.height) / 2
        )
        text.draw(at: point, withAttributes: attrs)
    }

    override func keyDown(with event: NSEvent) {}
    override func flagsChanged(with event: NSEvent) {}
}

// MARK: - History

struct HistorySettingsTab: View {
    private enum Kind: String, CaseIterable, Identifiable {
        case screenshots = "Screenshots"
        case recordings = "Recordings"
        var id: String { rawValue }
    }

    @State private var kind: Kind = .screenshots

    var body: some View {
        VStack(spacing: 0) {
            Picker("History", selection: $kind) {
                ForEach(Kind.allCases) { Text($0.rawValue).tag($0) }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .fixedSize()
            .padding(.vertical, 12)

            switch kind {
            case .screenshots: HistoryTab()
            case .recordings: VideosTab()
            }
        }
    }
}

// MARK: - History (Screenshots only)

struct HistoryTab: View {
    @State private var thumbnails: [String: NSImage] = [:]
    @State private var isConfirmingClear = false

    private var screenshots: [CaptureRecord] {
        HistoryStore.shared.records.filter { $0.kind == .screenshot }
    }

    var body: some View {
        if screenshots.isEmpty {
            ContentUnavailableView("No screenshots yet", systemImage: "photo.on.rectangle.angled")
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            VStack(spacing: 0) {
                HStack {
                    Spacer()
                    Button(role: .destructive) {
                        isConfirmingClear = true
                    } label: {
                        Label("Clear All", systemImage: "trash")
                            .font(.caption)
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.red)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .alert("Clear all screenshots?", isPresented: $isConfirmingClear) {
                        Button("Clear All", role: .destructive) {
                            thumbnails.removeAll()
                            screenshots.forEach { HistoryStore.shared.deleteRecord($0) }
                        }
                        Button("Cancel", role: .cancel) {}
                    } message: {
                        Text("Every screenshot in the history and its file is deleted. This can't be undone.")
                    }
                }

                List {
                    ForEach(screenshots) { record in
                        HStack(spacing: 12) {
                            if let thumb = thumbnails[record.id.uuidString] {
                                Image(nsImage: thumb)
                                    .resizable()
                                    .aspectRatio(contentMode: .fill)
                                    .frame(width: 64, height: 48)
                                    .clipShape(RoundedRectangle(cornerRadius: 4))
                            } else {
                                RoundedRectangle(cornerRadius: 4)
                                    .fill(.quaternary)
                                    .frame(width: 64, height: 48)
                                    .onAppear {
                                        loadThumbnail(for: record)
                                    }
                            }

                            VStack(alignment: .leading, spacing: 2) {
                                Text(record.filename)
                                    .font(.caption.weight(.medium))
                                    .lineLimit(1)
                                Text("\(record.pixelWidth) x \(record.pixelHeight)")
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                                Text(record.createdAt, style: .relative)
                                    .font(.caption2)
                                    .foregroundStyle(.tertiary)
                            }

                            Spacer()

                            Button {
                                let url = HistoryStore.shared.displayURLForRecord(record)
                                PreviewOverlay.shared.show(url: url)
                            } label: {
                                Image(systemName: "eye")
                                    .font(.caption)
                            }
                            .buttonStyle(.plain)
                            .foregroundStyle(.secondary)
                            .help("Preview")

                            Button {
                                thumbnails.removeValue(forKey: record.id.uuidString)
                                HistoryStore.shared.deleteRecord(record)
                            } label: {
                                Image(systemName: "trash")
                                    .font(.caption)
                            }
                            .buttonStyle(.plain)
                            .foregroundStyle(.secondary)
                        }
                        .padding(.vertical, 2)
                    }
                }
            }
        }
    }

    private func loadThumbnail(for record: CaptureRecord) {
        Task.detached {
            let thumb = await HistoryStore.shared.thumbnail(for: record, maxSize: 80)
            await MainActor.run {
                if let thumb {
                    thumbnails[record.id.uuidString] = thumb
                }
            }
        }
    }
}

// MARK: - Videos (Recordings only)

struct VideosTab: View {
    @State private var thumbnails: [String: NSImage] = [:]
    @State private var isConfirmingClear = false

    private var recordings: [CaptureRecord] {
        HistoryStore.shared.records.filter { $0.kind == .recording }
    }

    var body: some View {
        if recordings.isEmpty {
            ContentUnavailableView("No recordings yet", systemImage: "video.circle")
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            VStack(spacing: 0) {
                HStack {
                    Spacer()
                    Button(role: .destructive) {
                        isConfirmingClear = true
                    } label: {
                        Label("Clear All", systemImage: "trash")
                            .font(.caption)
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.red)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .alert("Clear all recordings?", isPresented: $isConfirmingClear) {
                        Button("Clear All", role: .destructive) {
                            thumbnails.removeAll()
                            recordings.forEach { HistoryStore.shared.deleteRecord($0) }
                        }
                        Button("Cancel", role: .cancel) {}
                    } message: {
                        Text("Every recording in the history and its file is deleted. This can't be undone.")
                    }
                }

                List {
                    ForEach(recordings) { record in
                        HStack(spacing: 12) {
                            if let thumb = thumbnails[record.id.uuidString] {
                                Image(nsImage: thumb)
                                    .resizable()
                                    .aspectRatio(contentMode: .fill)
                                    .frame(width: 64, height: 48)
                                    .clipShape(RoundedRectangle(cornerRadius: 4))
                            } else {
                                RoundedRectangle(cornerRadius: 4)
                                    .fill(.quaternary)
                                    .frame(width: 64, height: 48)
                                    .onAppear {
                                        loadThumbnail(for: record)
                                    }
                            }

                            VStack(alignment: .leading, spacing: 2) {
                                HStack(spacing: 4) {
                                    Text(record.filename)
                                        .font(.caption.weight(.medium))
                                        .lineLimit(1)
                                    Image(systemName: "video.fill")
                                        .font(.system(size: 8))
                                        .foregroundStyle(.secondary)
                                }
                                Text("\(record.pixelWidth) x \(record.pixelHeight)")
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                                Text(record.createdAt, style: .relative)
                                    .font(.caption2)
                                    .foregroundStyle(.tertiary)
                            }

                            Spacer()

                            Button {
                                let url = HistoryStore.shared.urlForRecord(record)
                                VideoEditorWindowController.shared.open(url: url)
                            } label: {
                                Image(systemName: "slider.horizontal.3")
                                    .font(.caption)
                            }
                            .buttonStyle(.plain)
                            .foregroundStyle(.secondary)
                            .help("Open in editor")

                            Button {
                                thumbnails.removeValue(forKey: record.id.uuidString)
                                HistoryStore.shared.deleteRecord(record)
                            } label: {
                                Image(systemName: "trash")
                                    .font(.caption)
                            }
                            .buttonStyle(.plain)
                            .foregroundStyle(.secondary)
                        }
                        .padding(.vertical, 2)
                    }
                }
            }
        }
    }

    private func loadThumbnail(for record: CaptureRecord) {
        Task.detached {
            let thumb = await HistoryStore.shared.thumbnail(for: record, maxSize: 80)
            await MainActor.run {
                if let thumb {
                    thumbnails[record.id.uuidString] = thumb
                }
            }
        }
    }
}

// MARK: - About

struct WatermarkSettingsTab: View {
    @State private var store = WatermarkStore.shared
    @State private var selectedPresetID: UUID?
    
    // Form state (bound to the currently selected preset editing copy)
    @State private var name: String = ""
    @State private var type: WatermarkType = .text
    @State private var textContent: String = ""
    @State private var fontName: String = "Helvetica"
    @State private var fontSize: Double = 36.0
    @State private var fontColor: AnnotationSwatch = .white
    @State private var imagePath: String? = nil
    @State private var opacity: Double = 0.8
    @State private var position: WatermarkPosition = .bottomRight
    @State private var rotationDegrees: Double = 0.0
    @State private var scale: Double = 0.2

    var body: some View {
        HStack(spacing: 0) {
            // Left list
            VStack(spacing: 0) {
                List(store.presets, id: \.id, selection: $selectedPresetID) { preset in
                    Text(preset.name)
                        .font(.system(size: 13, weight: .medium))
                        .tag(preset.id)
                }
                .listStyle(.inset)
                
                Divider()
                
                // Bottom control
                HStack(spacing: 12) {
                    Button(action: createNewPreset) {
                        Image(systemName: "plus")
                        Text("Add")
                    }
                    .buttonStyle(.borderless)
                    
                    Spacer()
                    
                    if let selectedPreset = selectedPreset {
                        Button(role: .destructive) {
                            deletePreset(selectedPreset)
                        } label: {
                            Image(systemName: "trash")
                            Text("Delete")
                        }
                        .buttonStyle(.borderless)
                    }
                }
                .padding(10)
            }
            .frame(width: 200)
            .background(Color(NSColor.controlBackgroundColor))
            
            Divider()
            
            // Right detail form
            if let selectedPresetID = selectedPresetID {
                ScrollView {
                    Form {
                        Section("Preset Name") {
                            TextField("Name", text: $name)
                                .textFieldStyle(.roundedBorder)
                        }
                        
                        Section("Type") {
                            Picker("Type", selection: $type) {
                                ForEach(WatermarkType.allCases, id: \.self) { t in
                                    Text(t.rawValue).tag(t)
                                }
                            }
                            .pickerStyle(.segmented)
                        }
                        
                        if type == .text {
                            Section("Text Content") {
                                TextField("Text", text: $textContent)
                                    .textFieldStyle(.roundedBorder)
                                
                                Picker("Font", selection: $fontName) {
                                    Text("Helvetica").tag("Helvetica")
                                    Text("Arial").tag("Arial")
                                    Text("Courier").tag("Courier")
                                    Text("SF Pro").tag("SF Pro")
                                    Text("System Monospaced").tag("System Monospaced")
                                }
                                
                                Slider(value: $fontSize, in: 8.0...72.0, step: 1.0) {
                                    Text("Font Size (\(Int(fontSize)) pt)")
                                }
                                
                                Text("Color")
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                                    .padding(.top, 4)
                                
                                HStack(spacing: 8) {
                                    ForEach(AnnotationSwatch.allCases) { swatch in
                                        Button {
                                            fontColor = swatch
                                        } label: {
                                            Circle()
                                                .fill(swatch.color)
                                                .frame(width: 16, height: 16)
                                                .overlay(Circle().stroke(Color.primary.opacity(0.15), lineWidth: 0.5))
                                                .overlay {
                                                    if fontColor == swatch {
                                                        Circle()
                                                            .stroke(Color.accentColor, lineWidth: 1.5)
                                                            .frame(width: 22, height: 22)
                                                    }
                                                }
                                        }
                                        .buttonStyle(.plain)
                                        .frame(width: 22, height: 22)
                                    }
                                }
                            }
                        } else {
                            Section("Watermark Image") {
                                if let imagePath = imagePath {
                                    let url = store.resolveImagePath(for: imagePath)
                                    if let nsImage = NSImage(contentsOf: url) {
                                        Image(nsImage: nsImage)
                                            .resizable()
                                            .aspectRatio(contentMode: .fit)
                                            .frame(maxHeight: 80)
                                            .clipShape(RoundedRectangle(cornerRadius: 8))
                                            .shadow(radius: 2)
                                    }
                                } else {
                                    VStack(spacing: 8) {
                                        Image(systemName: "photo")
                                            .font(.system(size: 24))
                                            .foregroundStyle(.tertiary)
                                        Text("No Image Selected")
                                            .font(.subheadline)
                                            .foregroundStyle(.secondary)
                                    }
                                    .frame(maxWidth: .infinity)
                                    .frame(height: 80)
                                }
                                
                                Button("Choose Image File...") {
                                    chooseImageFile()
                                }
                            }
                        }
                        
                        Section("Position & Size") {
                            Picker("Position", selection: $position) {
                                ForEach(WatermarkPosition.allCases, id: \.self) { pos in
                                    Text(pos.rawValue).tag(pos)
                                }
                            }
                            
                            Slider(value: $scale, in: 0.05...0.6, step: 0.01) {
                                Text("Scale (\(Int(scale * 100))%)")
                            }
                            
                            Slider(value: $opacity, in: 0.1...1.0, step: 0.05) {
                                Text("Opacity (\(Int(opacity * 100))%)")
                            }
                            
                            Slider(value: $rotationDegrees, in: -180.0...180.0, step: 5.0) {
                                Text("Rotation (\(Int(rotationDegrees))°)")
                            }
                        }
                    }
                    .padding(20)
                    .onChange(of: name) { saveCurrentChanges() }
                    .onChange(of: type) { saveCurrentChanges() }
                    .onChange(of: textContent) { saveCurrentChanges() }
                    .onChange(of: fontName) { saveCurrentChanges() }
                    .onChange(of: fontSize) { saveCurrentChanges() }
                    .onChange(of: fontColor) { saveCurrentChanges() }
                    .onChange(of: imagePath) { saveCurrentChanges() }
                    .onChange(of: opacity) { saveCurrentChanges() }
                    .onChange(of: position) { saveCurrentChanges() }
                    .onChange(of: rotationDegrees) { saveCurrentChanges() }
                    .onChange(of: scale) { saveCurrentChanges() }
                }
            } else {
                VStack(spacing: 8) {
                    Image(systemName: "stamp")
                        .font(.system(size: 32))
                        .foregroundStyle(.tertiary)
                    Text("No Preset Selected")
                        .font(.headline)
                    Text("Select an existing watermark preset or add a new one to customize.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 20)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onAppear {
            if selectedPresetID == nil && !store.presets.isEmpty {
                selectedPresetID = store.presets.first?.id
            }
            loadPresetState()
        }
        .onChange(of: selectedPresetID) { _, _ in
            loadPresetState()
        }
    }
    
    private var selectedPreset: WatermarkPreset? {
        store.presets.first { $0.id == selectedPresetID }
    }
    
    private func loadPresetState() {
        guard let preset = selectedPreset else { return }
        name = preset.name
        type = preset.type
        textContent = preset.textContent ?? ""
        fontName = preset.fontName
        fontSize = preset.fontSize
        fontColor = preset.fontColor
        imagePath = preset.imagePath
        opacity = preset.opacity
        position = preset.position
        rotationDegrees = preset.rotationDegrees
        scale = preset.scale
    }
    
    private func saveCurrentChanges() {
        guard let preset = selectedPreset else { return }
        var updated = preset
        updated.name = name
        updated.type = type
        updated.textContent = textContent.isEmpty ? nil : textContent
        updated.fontName = fontName
        updated.fontSize = fontSize
        updated.fontColor = fontColor
        updated.imagePath = imagePath
        updated.opacity = opacity
        updated.position = position
        updated.rotationDegrees = rotationDegrees
        updated.scale = scale
        
        store.updatePreset(updated)
    }
    
    private func createNewPreset() {
        let newPreset = WatermarkPreset(name: "New Preset", type: .text, textContent: "My Watermark")
        store.addPreset(newPreset)
        selectedPresetID = newPreset.id
    }
    
    private func deletePreset(_ preset: WatermarkPreset) {
        store.deletePreset(preset)
        selectedPresetID = store.presets.first?.id
    }
    
    private func chooseImageFile() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.allowedContentTypes = [.png, .jpeg]
        
        if panel.runModal() == .OK, let url = panel.url {
            if let relativeFilename = store.importWatermarkImage(from: url) {
                imagePath = relativeFilename
                saveCurrentChanges()
            }
        }
    }
}

struct AboutTab: View {
    @State private var showingCoffeeSheet = false
    
    private var version: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "?"
    }

    private var appIcon: NSImage? {
        if let icon = NSImage(named: "AppIcon") {
            return icon
        }
        return NSApp.applicationIconImage
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                // Header: icon + name
                HStack(spacing: 14) {
                    if let icon = appIcon {
                        Image(nsImage: icon)
                            .resizable()
                            .interpolation(.high)
                            .frame(width: 64, height: 64)
                            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                    }

                    VStack(alignment: .leading, spacing: 3) {
                        Text("Shotly")
                            .font(.system(size: 20, weight: .bold))

                        Text("Version \(version)")
                            .font(.system(size: 12))
                            .foregroundStyle(.secondary)

                        Text("Capture, edit, and share screenshots — fast.")
                            .font(.system(size: 12))
                            .foregroundStyle(.tertiary)
                    }
                }
                .padding(.bottom, 20)

                aboutSection("Updates") {
                    UpdateSettingsSection()
                }

                aboutSection("About") {
                    Text("Shotly is a screenshot and screen recording tool for macOS, built for quick capture, clean annotation, and effortless sharing.")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                        .lineSpacing(2)
                }

                aboutSection("Welcome Guide") {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Need a quick guide on how to capture, edit, or record your screen?")
                            .font(.system(size: 12))
                            .foregroundStyle(.secondary)
                            .lineSpacing(2)

                        Button("Show Welcome Guide") {
                            OnboardingWindowController.shared.open()
                        }
                        .controlSize(.small)
                    }
                }

                aboutSection("Upgraded by") {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack(spacing: 4) {
                            Text("Anh Nguyễn -")
                                .font(.system(size: 12))
                                .foregroundStyle(.secondary)
                            Link("Facebook", destination: URL(string: "https://www.facebook.com/anh2610/")!)
                                .font(.system(size: 12))
                        }
                        
                        Button("☕ Buy Me a Coffee") {
                            showingCoffeeSheet = true
                        }
                        .controlSize(.small)
                    }
                }

                aboutSection("Credits") {
                    Text("Based on Better Shot, an open-source project by Kartik Labhshetwar.")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                        .lineSpacing(2)
                }
            }
            .padding(24)
        }
        .sheet(isPresented: $showingCoffeeSheet) {
            BuyMeACoffeeSheet()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private func aboutSection<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(title)
                .font(.system(size: 13, weight: .bold))
                .padding(.bottom, 10)

            content()
                .padding(.leading, 2)
                .padding(.bottom, 20)
        }
    }

}

// MARK: - Updates

private struct UpdateSettingsSection: View {
    @State private var updater = AppUpdater.shared
    @AppStorage(AppUpdater.automaticChecksKey) private var checksAutomatically = true

    private var isBusy: Bool {
        switch updater.state {
        case .checking, .downloading, .installing: return true
        default: return false
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 10) {
                Button("Check for Updates") {
                    Task { await updater.checkForUpdates(userInitiated: true) }
                }
                .controlSize(.small)
                .disabled(isBusy)

                status
            }

            Toggle("Check for updates automatically", isOn: $checksAutomatically)
                .toggleStyle(.checkbox)
                .font(.system(size: 12))
        }
    }

    @ViewBuilder
    private var status: some View {
        switch updater.state {
        case .checking:
            HStack(spacing: 6) {
                ProgressView().controlSize(.small)
                Text("Checking…")
            }
            .font(.system(size: 12))
            .foregroundStyle(.secondary)
        case .upToDate:
            Text("Shotly \(updater.currentVersion) is the latest version.")
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
        case .available(let manifest), .installing(let manifest), .downloading(let manifest, _):
            Button("Version \(manifest.version) available…") {
                UpdateWindowController.shared.show()
            }
            .buttonStyle(.link)
            .font(.system(size: 12))
        case .failed(let message):
            Text(message)
                .font(.system(size: 12))
                .foregroundStyle(.red)
                .fixedSize(horizontal: false, vertical: true)
        case .idle:
            EmptyView()
        }
    }
}
