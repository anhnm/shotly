import SwiftUI

/// Dark tooltip label with an action name and its keyboard shortcut.
/// Used by the editor toolbar and the capture preview.
struct ShortcutTooltip: View {
    let title: String
    let shortcut: String?

    var body: some View {
        HStack(spacing: 6) {
            Text(title)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.white)
            if let shortcut {
                Text(shortcut)
                    .font(.system(size: 11, weight: .semibold))
                    .monospacedDigit()
                    .foregroundStyle(.white.opacity(0.75))
                    .padding(.horizontal, 5)
                    .padding(.vertical, 1)
                    .background(
                        RoundedRectangle(cornerRadius: 4, style: .continuous)
                            .fill(.white.opacity(0.15))
                    )
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .background(
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(Color.black.opacity(0.85))
                .shadow(color: .black.opacity(0.2), radius: 4, y: 2)
        )
        .fixedSize()
        .allowsHitTesting(false)
    }
}
