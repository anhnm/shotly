import SwiftUI

/// Shottr-style readout at the right of the toolbar: color under the cursor,
/// image size (click to resize) and zoom level (click for zoom options).
struct EditorInfoCluster: View {
    @Bindable var model: EditorModel
    @State private var isResizePresented = false

    var body: some View {
        HStack(spacing: 12) {
            colorItem

            ToolbarInfoDivider()

            Button {
                isResizePresented = true
            } label: {
                infoItem(value: sizeText, caption: "Image size")
            }
            .buttonStyle(.plain)
            .disabled(!model.isViewportZoomable)
            .help("Resize image")
            .popover(isPresented: $isResizePresented, arrowEdge: .bottom) {
                ImageResizePopover(model: model, isPresented: $isResizePresented)
            }

            ToolbarInfoDivider()

            zoomMenu
        }
        .monospacedDigit()
        .fixedSize()
    }

    private var sizeText: String {
        guard model.imageSize.width > 0 else { return "—" }
        return "\(Int(model.imageSize.width))×\(Int(model.imageSize.height)) px"
    }

    private var colorItem: some View {
        HStack(spacing: 8) {
            Circle()
                .fill(model.hoveredPixel?.color ?? Color.primary.opacity(0.15))
                .frame(width: 18, height: 18)
                .overlay(Circle().stroke(Color.primary.opacity(0.25), lineWidth: 0.5))
            infoItem(value: model.hoveredPixel?.hex ?? "—", caption: "Tab to copy")
        }
        .help("Color under the cursor. Tab copies it, ⇧Tab copies the nearby text color.")
    }

    private func infoItem(value: String, caption: String) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(value)
                .font(.system(size: 12, weight: .semibold))
            Text(caption)
                .font(.system(size: 10))
                .foregroundStyle(.secondary)
        }
        .contentShape(Rectangle())
    }

    private var zoomMenu: some View {
        Menu {
            Button("Zoom In") { model.zoomIn() }
                .keyboardShortcut("=", modifiers: .command)
            Button("Zoom Out") { model.zoomOut() }
                .keyboardShortcut("-", modifiers: .command)
            Divider()
            Button("Fit to Window") { model.zoomToFit() }
                .keyboardShortcut("1", modifiers: .command)
            Button("Actual Size") { model.zoomToActualSize() }
                .keyboardShortcut("0", modifiers: .command)
            Divider()
            ForEach([50, 200, 400, 800], id: \.self) { percent in
                Button("\(percent)%") { model.setPixelScale(CGFloat(percent) / 100) }
            }
        } label: {
            infoItem(value: model.isViewportZoomable ? "\(model.zoomPercent)%" : "—", caption: "Zoom")
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .disabled(!model.isViewportZoomable)
        .fixedSize()
        .help("Zoom: ⌘+ ⌘− ⌘1 ⌘0, Z at cursor, pinch or ⌘-scroll. Hold Space and drag to pan.")
    }
}

private struct ToolbarInfoDivider: View {
    var body: some View {
        Rectangle()
            .fill(Color.primary.opacity(0.15))
            .frame(width: 1, height: 26)
            .accessibilityHidden(true)
    }
}

// MARK: - Resize Popover

private struct ImageResizePopover: View {
    @Bindable var model: EditorModel
    @Binding var isPresented: Bool

    @State private var width: Int
    @State private var height: Int
    @State private var keepsAspectRatio = true
    private let aspectRatio: Double

    init(model: EditorModel, isPresented: Binding<Bool>) {
        self.model = model
        self._isPresented = isPresented
        let size = model.imageSize
        _width = State(initialValue: Int(size.width))
        _height = State(initialValue: Int(size.height))
        aspectRatio = size.height > 0 ? Double(size.width / size.height) : 1
    }

    private var maxDimension: Int { EditorModel.maximumImageDimension }

    private var validationMessage: String? {
        guard (1...maxDimension).contains(width), (1...maxDimension).contains(height) else {
            return "Width and height must be between 1 and \(maxDimension) px."
        }
        return nil
    }

    private var isUnchanged: Bool {
        width == Int(model.imageSize.width) && height == Int(model.imageSize.height)
    }

    private var widthBinding: Binding<Int> {
        Binding(
            get: { width },
            set: { newValue in
                width = newValue
                if keepsAspectRatio {
                    height = max(1, Int((Double(newValue) / aspectRatio).rounded()))
                }
            }
        )
    }

    private var heightBinding: Binding<Int> {
        Binding(
            get: { height },
            set: { newValue in
                height = newValue
                if keepsAspectRatio {
                    width = max(1, Int((Double(newValue) * aspectRatio).rounded()))
                }
            }
        )
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Resize Image")
                .font(.system(size: 13, weight: .semibold))

            HStack(spacing: 6) {
                dimensionField("Width", value: widthBinding)
                Text("×")
                    .foregroundStyle(.secondary)
                dimensionField("Height", value: heightBinding)
                Text("px")
                    .foregroundStyle(.secondary)
            }

            Toggle("Keep aspect ratio", isOn: $keepsAspectRatio)
                .toggleStyle(.checkbox)

            HStack(spacing: 6) {
                ForEach([25, 50, 200], id: \.self) { percent in
                    Button("\(percent)%") { applyPercent(percent) }
                        .controlSize(.small)
                }
            }

            if let validationMessage {
                Text(validationMessage)
                    .font(.system(size: 11))
                    .foregroundStyle(.red)
                    .fixedSize(horizontal: false, vertical: true)
            }

            HStack {
                if model.canRevertImageSize {
                    Button("Revert to Original") {
                        model.revertImageSize()
                        isPresented = false
                    }
                }
                Spacer()
                Button("Cancel") { isPresented = false }
                    .keyboardShortcut(.cancelAction)
                Button("Resize") {
                    model.resizeImage(to: CGSize(width: width, height: height))
                    isPresented = false
                }
                .keyboardShortcut(.defaultAction)
                .disabled(validationMessage != nil || isUnchanged)
            }
        }
        .monospacedDigit()
        .padding(14)
        .frame(width: 300)
    }

    private func dimensionField(_ title: String, value: Binding<Int>) -> some View {
        TextField(title, value: value, format: .number.grouping(.never))
            .textFieldStyle(.roundedBorder)
            .multilineTextAlignment(.trailing)
            .frame(width: 80)
            .accessibilityLabel(title)
    }

    /// Percentages are relative to the current size; keeps the aspect ratio regardless of the toggle.
    private func applyPercent(_ percent: Int) {
        let factor = Double(percent) / 100
        width = max(1, Int((model.imageSize.width * factor).rounded()))
        height = max(1, Int((model.imageSize.height * factor).rounded()))
    }
}
