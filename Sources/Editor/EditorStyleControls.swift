import SwiftUI

// MARK: - Stroke Width Slider

/// Shottr-style stroke width slider: a wedge track that widens to the right,
/// with a pill thumb. Reports drag start separately so one drag is one undo step.
struct StrokeWidthSlider: View {
    let value: CGFloat
    var range: ClosedRange<CGFloat> = 1...20
    let onBegin: () -> Void
    let onChange: (CGFloat) -> Void

    @State private var isDragging = false

    private let trackWidth: CGFloat = 110
    private let thumbSize = CGSize(width: 26, height: 17)

    private var fraction: CGFloat {
        (min(max(value, range.lowerBound), range.upperBound) - range.lowerBound)
            / (range.upperBound - range.lowerBound)
    }

    var body: some View {
        let usable = trackWidth - thumbSize.width
        let thumbX = thumbSize.width / 2 + fraction * usable

        ZStack(alignment: .leading) {
            WedgeTrack()
                .fill(Color.primary.opacity(0.12))
                .overlay(WedgeTrack().stroke(Color.primary.opacity(0.35), lineWidth: 1))
                .frame(height: 11)

            Capsule()
                .fill(Color.white)
                .shadow(color: .black.opacity(0.35), radius: 2, y: 1)
                .frame(width: thumbSize.width, height: thumbSize.height)
                .offset(x: thumbX - thumbSize.width / 2)
        }
        .frame(width: trackWidth, height: 32)
        .contentShape(Rectangle())
        .gesture(
            DragGesture(minimumDistance: 0)
                .onChanged { drag in
                    if !isDragging {
                        isDragging = true
                        onBegin()
                    }
                    let clampedX = min(max(drag.location.x - thumbSize.width / 2, 0), usable)
                    let newValue = range.lowerBound + clampedX / usable * (range.upperBound - range.lowerBound)
                    let rounded = newValue.rounded()
                    if rounded != value { onChange(rounded) }
                }
                .onEnded { _ in isDragging = false }
        )
        .help("Stroke width: \(Int(value)) px")
        .accessibilityElement()
        .accessibilityLabel("Stroke width")
        .accessibilityValue("\(Int(value)) pixels")
        .accessibilityAdjustableAction { direction in
            let step: CGFloat = direction == .increment ? 1 : -1
            let next = min(max(value + step, range.lowerBound), range.upperBound)
            guard next != value else { return }
            onBegin()
            onChange(next)
        }
    }
}

private struct WedgeTrack: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.minX, y: rect.midY - 0.5))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.minX, y: rect.midY + 0.5))
        path.closeSubpath()
        return path
    }
}

// MARK: - Rectangle Style Picker

/// Outline styles (rounded, square, dashed) plus a filled option, as a segmented group.
struct RectangleStylePicker: View {
    let style: AnnotationShapeStyle
    let isFilled: Bool
    let onSelectStyle: (AnnotationShapeStyle) -> Void
    let onSelectFilled: () -> Void

    var body: some View {
        HStack(spacing: 2) {
            ForEach(AnnotationShapeStyle.allCases) { option in
                let isSelected = !isFilled && style == option
                segment(isSelected: isSelected, title: option.title) {
                    onSelectStyle(option)
                } icon: {
                    outlineIcon(for: option, color: iconColor(isSelected))
                }
            }

            Rectangle()
                .fill(Color.primary.opacity(0.2))
                .frame(width: 1, height: 18)
                .padding(.horizontal, 3)
                .accessibilityHidden(true)

            segment(isSelected: isFilled, title: "Filled") {
                onSelectFilled()
            } icon: {
                RoundedRectangle(cornerRadius: 4, style: .continuous)
                    .fill(iconColor(isFilled))
            }
        }
        .padding(3)
        .background(
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .fill(Color.primary.opacity(0.08))
        )
    }

    private func iconColor(_ isSelected: Bool) -> Color {
        isSelected ? .white : .primary
    }

    @ViewBuilder
    private func outlineIcon(for option: AnnotationShapeStyle, color: Color) -> some View {
        switch option {
        case .rounded:
            RoundedRectangle(cornerRadius: 5, style: .continuous)
                .stroke(color, lineWidth: 1.8)
        case .sharp:
            Rectangle()
                .stroke(color, style: StrokeStyle(lineWidth: 1.8, lineJoin: .miter))
        case .dashed:
            RoundedRectangle(cornerRadius: 3, style: .continuous)
                .stroke(color, style: StrokeStyle(lineWidth: 1.8, dash: [3, 2.5]))
        }
    }

    private func segment<Icon: View>(
        isSelected: Bool,
        title: String,
        action: @escaping () -> Void,
        @ViewBuilder icon: () -> Icon
    ) -> some View {
        Button(action: action) {
            icon()
                .frame(width: 17, height: 13)
                .frame(width: 34, height: 28)
                .background(
                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                        .fill(isSelected ? Color.accentColor : .clear)
                )
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(title)
        .accessibilityLabel(title)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}
