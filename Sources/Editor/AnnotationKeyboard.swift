import AppKit
import SwiftUI

struct AnnotationKeyCommandHandler: NSViewRepresentable {
    let onDelete: () -> Void
    let onUndo: () -> Void
    let onRedo: () -> Void
    let onSelectAll: () -> Void
    let onSelectTool: (AnnotationTool) -> Void
    let onEditorAction: (EditorAction) -> Void
    let onViewportCommand: (EditorViewportCommand) -> Bool
    let onSpacePanChanged: (Bool) -> Void

    func makeNSView(context: Context) -> AnnotationKeyCommandHandlerView {
        let view = AnnotationKeyCommandHandlerView()
        view.onDelete = onDelete
        view.onUndo = onUndo
        view.onRedo = onRedo
        view.onSelectAll = onSelectAll
        view.onSelectTool = onSelectTool
        view.onEditorAction = onEditorAction
        view.onViewportCommand = onViewportCommand
        view.onSpacePanChanged = onSpacePanChanged
        return view
    }

    func updateNSView(_ nsView: AnnotationKeyCommandHandlerView, context: Context) {
        nsView.onDelete = onDelete
        nsView.onUndo = onUndo
        nsView.onRedo = onRedo
        nsView.onSelectAll = onSelectAll
        nsView.onSelectTool = onSelectTool
        nsView.onEditorAction = onEditorAction
        nsView.onViewportCommand = onViewportCommand
        nsView.onSpacePanChanged = onSpacePanChanged
    }
}

/// Toolbar actions that have a single-key shortcut.
enum EditorAction: CaseIterable {
    case pin
    case crop
    case backdrop
    case watermark
    case metadata

    /// The key that triggers the action; also shown in toolbar tooltips.
    var shortcutHint: String {
        switch self {
        case .pin: "P"
        case .crop: "C"
        case .backdrop: "E"
        case .watermark: "W"
        case .metadata: "I"
        }
    }

    init?(key: String) {
        guard let match = Self.allCases.first(where: { $0.shortcutHint.lowercased() == key }) else { return nil }
        self = match
    }
}

/// Zoom and pixel-inspection commands handled by the editor canvas.
enum EditorViewportCommand {
    case zoomIn
    case zoomOut
    case zoomToFit
    case zoomToActualSize
    case zoomInAtCursor
    case zoomOutAtCursor
    case copyColor
    case copyTextColor
}

final class AnnotationKeyCommandHandlerView: NSView {
    var onDelete: (() -> Void)?
    var onUndo: (() -> Void)?
    var onRedo: (() -> Void)?
    var onSelectAll: (() -> Void)?
    var onSelectTool: ((AnnotationTool) -> Void)?
    var onEditorAction: ((EditorAction) -> Void)?
    var onViewportCommand: ((EditorViewportCommand) -> Bool)?
    var onSpacePanChanged: ((Bool) -> Void)?

    nonisolated(unsafe) private var localKeyMonitor: Any?
    nonisolated(unsafe) private var resignKeyObserver: NSObjectProtocol?
    private var isSpaceDown = false

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        updateLocalKeyMonitor()
        observeResignKey()
    }

    deinit {
        if let localKeyMonitor {
            NSEvent.removeMonitor(localKeyMonitor)
        }
        if let resignKeyObserver {
            NotificationCenter.default.removeObserver(resignKeyObserver)
        }
    }

    /// The key-up for a held Space can be lost when the window loses focus, which
    /// would leave the canvas stuck in pan mode.
    private func observeResignKey() {
        if let resignKeyObserver {
            NotificationCenter.default.removeObserver(resignKeyObserver)
            self.resignKeyObserver = nil
        }
        guard let window else { return }
        resignKeyObserver = NotificationCenter.default.addObserver(
            forName: NSWindow.didResignKeyNotification,
            object: window,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.setSpaceDown(false)
            }
        }
    }

    private func setSpaceDown(_ isDown: Bool) {
        guard isSpaceDown != isDown else { return }
        isSpaceDown = isDown
        onSpacePanChanged?(isDown)
    }

    private func updateLocalKeyMonitor() {
        guard localKeyMonitor == nil else { return }

        localKeyMonitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .keyUp]) { [weak self] event in
            guard let self, self.window?.isKeyWindow == true else {
                return event
            }

            if event.type == .keyUp {
                if event.keyCode == Self.spaceKeyCode, self.isSpaceDown {
                    self.setSpaceDown(false)
                    return nil
                }
                return event
            }

            if Self.isEditingText(in: self.window) {
                return event
            }

            if Self.isPlainKey(event, keyCode: Self.spaceKeyCode) {
                self.setSpaceDown(true)
                return nil
            }

            if let command = Self.viewportCommand(for: event),
               self.onViewportCommand?(command) == true {
                return nil
            }

            if Self.isPlainDelete(event) {
                self.onDelete?()
                return nil
            }

            if Self.isUndo(event) {
                self.onUndo?()
                return nil
            }

            if Self.isRedo(event) {
                self.onRedo?()
                return nil
            }

            if Self.isSelectAll(event) {
                self.onSelectAll?()
                return nil
            }

            if let tool = Self.toolShortcut(for: event) {
                self.onSelectTool?(tool)
                return nil
            }

            if let action = Self.editorActionShortcut(for: event) {
                self.onEditorAction?(action)
                return nil
            }

            return event
        }
    }

    private static let spaceKeyCode: UInt16 = 49
    private static let tabKeyCode: UInt16 = 48

    private static func isPlainKey(_ event: NSEvent, keyCode: UInt16) -> Bool {
        event.keyCode == keyCode
            && event.modifierFlags.intersection([.command, .option, .control, .shift]).isEmpty
    }

    private static func viewportCommand(for event: NSEvent) -> EditorViewportCommand? {
        let flags = event.modifierFlags.intersection([.command, .option, .control, .shift])
        let character = event.charactersIgnoringModifiers?.lowercased()

        if event.keyCode == tabKeyCode {
            if flags.isEmpty { return .copyColor }
            if flags == .shift { return .copyTextColor }
            return nil
        }

        if flags == .command || flags == [.command, .shift] {
            switch character {
            case "=", "+": return .zoomIn
            case "-", "_": return .zoomOut
            case "1" where flags == .command: return .zoomToFit
            case "0" where flags == .command: return .zoomToActualSize
            default: return nil
            }
        }

        if character == "z" {
            if flags.isEmpty { return .zoomInAtCursor }
            if flags == .shift { return .zoomOutAtCursor }
        }

        return nil
    }

    private static func isPlainDelete(_ event: NSEvent) -> Bool {
        event.modifierFlags.intersection([.command, .option, .control, .shift]).isEmpty
            && (event.keyCode == 51 || event.keyCode == 117)
    }

    private static func isEditingText(in window: NSWindow?) -> Bool {
        window?.firstResponder is NSTextView
    }

    private static func isUndo(_ event: NSEvent) -> Bool {
        event.modifierFlags.contains(.command)
            && !event.modifierFlags.contains(.shift)
            && event.charactersIgnoringModifiers?.lowercased() == "z"
    }

    private static func isRedo(_ event: NSEvent) -> Bool {
        event.modifierFlags.contains(.command)
            && event.modifierFlags.contains(.shift)
            && event.charactersIgnoringModifiers?.lowercased() == "z"
    }

    private static func isSelectAll(_ event: NSEvent) -> Bool {
        event.modifierFlags.contains(.command)
            && !event.modifierFlags.contains(.shift)
            && event.charactersIgnoringModifiers?.lowercased() == "a"
    }

    private static func editorActionShortcut(for event: NSEvent) -> EditorAction? {
        guard event.modifierFlags.intersection([.command, .option, .control, .shift]).isEmpty,
              let character = event.charactersIgnoringModifiers?.lowercased(),
              character.count == 1 else {
            return nil
        }
        return EditorAction(key: character)
    }

    private static func toolShortcut(for event: NSEvent) -> AnnotationTool? {
        guard event.modifierFlags.intersection([.command, .option, .control]).isEmpty,
              let character = event.charactersIgnoringModifiers?.lowercased(),
              character.count == 1 else {
            return nil
        }

        switch character {
        case "v": return .select
        case "r": return .rectangle
        case "f": return .filledRectangle
        case "o": return .ellipse
        case "l": return .line
        case "m": return .measure
        case "a": return .arrow
        case "d": return .freehand
        case "n": return .numberedCircle
        case "b": return .blur
        case "g": return .spotlight
        case "t": return .text
        case "h": return .select
        default: return nil
        }
    }
}

extension AnnotationTool {
    /// Single-key shortcut shown in toolbar tooltips; matches `toolShortcut(for:)`.
    var shortcutHint: String {
        switch self {
        case .select: "V"
        case .rectangle: "R"
        case .filledRectangle: "F"
        case .ellipse: "O"
        case .line: "L"
        case .measure: "M"
        case .arrow: "A"
        case .freehand: "D"
        case .numberedCircle: "N"
        case .pixelate, .blur: "B"
        case .spotlight: "G"
        case .text: "T"
        }
    }
}
