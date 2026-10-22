import Foundation
import AppKit
import SwiftUI
import Carbon

enum AppPreferences {
    // MARK: - Keys
    private static let appearanceKey = "bs_appAppearance"
    private static let saveDirKey = "bs_saveDirectory"
    private static let copyAfterSaveKey = "bs_copyAfterSave"
    private static let autoSaveCapturesKey = "bs_autoSaveCaptures"
    private static let editorCopyShortcutKey = "bs_editorCopyShortcut"
    private static let editorSaveShortcutKey = "bs_editorSaveShortcut"
    private static let playSoundKey = "bs_playSound"
    private static let overlayPositionKey = "bs_overlayPosition"
    private static let overlayAutoDismissKey = "bs_overlayAutoDismiss"
    private static let overlayDismissDelayKey = "bs_overlayDismissDelay"
    private static let exportFormatKey = "bs_exportFormat"
    private static let exportQualityKey = "bs_exportQuality"
    private static let selfTimerKey = "bs_selfTimerDelay"
    private static let recordingFPSKey = "bs_recordingFPS"
    private static let recordingShowCursorKey = "bs_recordingShowCursor"
    private static let recordingCaptureAudioKey = "bs_recordingCaptureAudio"
    private static let recordingOpenEditorKey = "bs_recordingOpenEditor"
    private static let showMetadataKey = "bs_showMetadata"
    private static let lastWatermarkPresetIDKey = "bs_lastWatermarkPresetID"
    private static let smartBlurEnabledKey = "bs_smartBlurEnabled"
    private static let ocrTranslationEnabledKey = "bs_ocrTranslationEnabled"
    private static let ocrTranslationTargetLanguageKey = "bs_ocrTranslationTargetLanguage"
    private static let hasCompletedOnboardingKey = "bs_hasCompletedOnboarding"
    private static let analyticsEnabledKey = "bs_analyticsEnabled"

    // MARK: - Appearance
    static var hasCompletedOnboarding: Bool {
        get { UserDefaults.standard.bool(forKey: hasCompletedOnboardingKey) }
        set { UserDefaults.standard.set(newValue, forKey: hasCompletedOnboardingKey) }
    }

    static var appearance: AppAppearance {
        get {
            guard let raw = UserDefaults.standard.string(forKey: appearanceKey),
                  let appearance = AppAppearance(rawValue: raw) else { return .system }
            return appearance
        }
        set { UserDefaults.standard.set(newValue.rawValue, forKey: appearanceKey) }
    }

    @MainActor
    static func applyAppearance(_ selectedAppearance: AppAppearance? = nil) {
        // AppStorage/UserDefaults propagation is not guaranteed to be visible
        // synchronously. When the picker changes, apply that exact value so
        // choosing System immediately clears any previous Light/Dark override.
        NSApp.appearance = (selectedAppearance ?? appearance).nsAppearance
    }

    // MARK: - General
    static var saveDirectory: String {
        get { UserDefaults.standard.string(forKey: saveDirKey) ?? NSHomeDirectory() + "/Desktop" }
        set { UserDefaults.standard.set(newValue, forKey: saveDirKey) }
    }

    static var copyAfterSave: Bool {
        get { UserDefaults.standard.object(forKey: copyAfterSaveKey) as? Bool ?? true }
        set { UserDefaults.standard.set(newValue, forKey: copyAfterSaveKey) }
    }

    static var autoSaveCaptures: Bool {
        get { UserDefaults.standard.object(forKey: autoSaveCapturesKey) as? Bool ?? true }
        set { UserDefaults.standard.set(newValue, forKey: autoSaveCapturesKey) }
    }

    static var editorCopyShortcut: EditorShortcut {
        get { loadEditorShortcut(forKey: editorCopyShortcutKey) ?? .defaultCopy }
        set { saveEditorShortcut(newValue, forKey: editorCopyShortcutKey) }
    }

    static var editorSaveShortcut: EditorShortcut {
        get { loadEditorShortcut(forKey: editorSaveShortcutKey) ?? .defaultSave }
        set { saveEditorShortcut(newValue, forKey: editorSaveShortcutKey) }
    }

    private static func loadEditorShortcut(forKey key: String) -> EditorShortcut? {
        guard let data = UserDefaults.standard.data(forKey: key) else { return nil }
        return try? JSONDecoder().decode(EditorShortcut.self, from: data)
    }

    private static func saveEditorShortcut(_ shortcut: EditorShortcut, forKey key: String) {
        guard let data = try? JSONEncoder().encode(shortcut) else { return }
        UserDefaults.standard.set(data, forKey: key)
    }

    static var playSound: Bool {
        get { UserDefaults.standard.object(forKey: playSoundKey) as? Bool ?? true }
        set { UserDefaults.standard.set(newValue, forKey: playSoundKey) }
    }

    // MARK: - Overlay
    static var overlayPosition: OverlayPosition {
        get {
            guard let raw = UserDefaults.standard.string(forKey: overlayPositionKey),
                  let pos = OverlayPosition(rawValue: raw) else { return .cursor }
            return pos
        }
        set { UserDefaults.standard.set(newValue.rawValue, forKey: overlayPositionKey) }
    }

    static var overlayDismissDelay: Double {
        get {
            let val = UserDefaults.standard.double(forKey: overlayDismissDelayKey)
            return val > 0 ? val : 5.0
        }
        set { UserDefaults.standard.set(newValue, forKey: overlayDismissDelayKey) }
    }

    static var overlayAutoDismiss: Bool {
        get { UserDefaults.standard.object(forKey: overlayAutoDismissKey) as? Bool ?? true }
        set { UserDefaults.standard.set(newValue, forKey: overlayAutoDismissKey) }
    }

    // MARK: - Export
    static var exportFormat: ExportFormat {
        get {
            guard let raw = UserDefaults.standard.string(forKey: exportFormatKey),
                  let fmt = ExportFormat(rawValue: raw) else { return .png }
            return fmt
        }
        set { UserDefaults.standard.set(newValue.rawValue, forKey: exportFormatKey) }
    }

    static var exportQuality: Double {
        get {
            let val = UserDefaults.standard.double(forKey: exportQualityKey)
            return val > 0 ? val : 0.9
        }
        set { UserDefaults.standard.set(newValue, forKey: exportQualityKey) }
    }

    // MARK: - Self Timer
    static var selfTimerDelay: SelfTimerDelay {
        get {
            let val = UserDefaults.standard.integer(forKey: selfTimerKey)
            return SelfTimerDelay(rawValue: val) ?? .off
        }
        set { UserDefaults.standard.set(newValue.rawValue, forKey: selfTimerKey) }
    }

    // MARK: - Recording
    static var recordingFPS: Int {
        get {
            let val = UserDefaults.standard.integer(forKey: recordingFPSKey)
            return val > 0 ? val : 30
        }
        set { UserDefaults.standard.set(newValue, forKey: recordingFPSKey) }
    }

    static var recordingShowCursor: Bool {
        get { UserDefaults.standard.object(forKey: recordingShowCursorKey) as? Bool ?? true }
        set { UserDefaults.standard.set(newValue, forKey: recordingShowCursorKey) }
    }

    static var recordingCaptureAudio: Bool {
        get { UserDefaults.standard.object(forKey: recordingCaptureAudioKey) as? Bool ?? false }
        set { UserDefaults.standard.set(newValue, forKey: recordingCaptureAudioKey) }
    }

    static var recordingOpenEditor: Bool {
        get { UserDefaults.standard.object(forKey: recordingOpenEditorKey) as? Bool ?? true }
        set { UserDefaults.standard.set(newValue, forKey: recordingOpenEditorKey) }
    }

    static var showMetadata: Bool {
        get { UserDefaults.standard.object(forKey: showMetadataKey) as? Bool ?? false }
        set { UserDefaults.standard.set(newValue, forKey: showMetadataKey) }
    }

    static var lastWatermarkPresetID: String? {
        get { UserDefaults.standard.string(forKey: lastWatermarkPresetIDKey) }
        set { UserDefaults.standard.set(newValue, forKey: lastWatermarkPresetIDKey) }
    }

    static var smartBlurEnabled: Bool {
        get { UserDefaults.standard.object(forKey: smartBlurEnabledKey) as? Bool ?? false }
        set { UserDefaults.standard.set(newValue, forKey: smartBlurEnabledKey) }
    }

    static var ocrTranslationEnabled: Bool {
        get { UserDefaults.standard.object(forKey: ocrTranslationEnabledKey) as? Bool ?? true }
        set { UserDefaults.standard.set(newValue, forKey: ocrTranslationEnabledKey) }
    }

    static var ocrTranslationTargetLanguage: OCRTranslationLanguage {
        get {
            guard let raw = UserDefaults.standard.string(forKey: ocrTranslationTargetLanguageKey),
                  let language = OCRTranslationLanguage(rawValue: raw) else { return .vietnamese }
            return language
        }
        set { UserDefaults.standard.set(newValue.rawValue, forKey: ocrTranslationTargetLanguageKey) }
    }

    static var analyticsEnabled: Bool {
        get { UserDefaults.standard.object(forKey: analyticsEnabledKey) as? Bool ?? true }
        set { UserDefaults.standard.set(newValue, forKey: analyticsEnabledKey) }
    }

    // MARK: - Default Beautifier Config
    static var defaultBeautifierConfig: BeautifierConfig {
        get {
            guard let data = UserDefaults.standard.data(forKey: "bs_defaultBeautifierConfig"),
                  let config = try? JSONDecoder().decode(BeautifierConfig.self, from: data)
            else { return .default }
            return config
        }
        set {
            if let data = try? JSONEncoder().encode(newValue) {
                UserDefaults.standard.set(data, forKey: "bs_defaultBeautifierConfig")
            }
        }
    }
}

struct EditorShortcut: Codable, Equatable, Hashable {
    var keyCode: UInt32
    var modifiers: UInt32

    static let defaultCopy = EditorShortcut(
        keyCode: UInt32(kVK_ANSI_C),
        modifiers: UInt32(cmdKey | shiftKey)
    )
    static let defaultSave = EditorShortcut(
        keyCode: UInt32(kVK_ANSI_S),
        modifiers: UInt32(cmdKey)
    )

    var displayString: String {
        var parts: [String] = []
        // macOS order: Control, Option, Shift, Command.
        if modifiers & UInt32(controlKey) != 0 { parts.append("⌃") }
        if modifiers & UInt32(optionKey) != 0 { parts.append("⌥") }
        if modifiers & UInt32(shiftKey) != 0 { parts.append("⇧") }
        if modifiers & UInt32(cmdKey) != 0 { parts.append("⌘") }
        parts.append(Self.keyName(for: keyCode))
        return parts.joined()
    }

    var keyEquivalent: KeyEquivalent {
        KeyEquivalent(Self.keyCharacter(for: keyCode) ?? "?")
    }

    var eventModifiers: SwiftUI.EventModifiers {
        var result: SwiftUI.EventModifiers = []
        if modifiers & UInt32(cmdKey) != 0 { result.insert(.command) }
        if modifiers & UInt32(shiftKey) != 0 { result.insert(.shift) }
        if modifiers & UInt32(optionKey) != 0 { result.insert(.option) }
        if modifiers & UInt32(controlKey) != 0 { result.insert(.control) }
        return result
    }

    static func supports(keyCode: UInt32) -> Bool {
        keyCharacter(for: keyCode) != nil
    }

    private static func keyCharacter(for code: UInt32) -> Character? {
        let characters: [UInt32: Character] = [
            UInt32(kVK_ANSI_A): "a", UInt32(kVK_ANSI_S): "s", UInt32(kVK_ANSI_D): "d",
            UInt32(kVK_ANSI_F): "f", UInt32(kVK_ANSI_H): "h", UInt32(kVK_ANSI_G): "g",
            UInt32(kVK_ANSI_Z): "z", UInt32(kVK_ANSI_X): "x", UInt32(kVK_ANSI_C): "c",
            UInt32(kVK_ANSI_V): "v", UInt32(kVK_ANSI_B): "b", UInt32(kVK_ANSI_Q): "q",
            UInt32(kVK_ANSI_W): "w", UInt32(kVK_ANSI_E): "e", UInt32(kVK_ANSI_R): "r",
            UInt32(kVK_ANSI_Y): "y", UInt32(kVK_ANSI_T): "t", UInt32(kVK_ANSI_1): "1",
            UInt32(kVK_ANSI_2): "2", UInt32(kVK_ANSI_3): "3", UInt32(kVK_ANSI_4): "4",
            UInt32(kVK_ANSI_5): "5", UInt32(kVK_ANSI_6): "6", UInt32(kVK_ANSI_7): "7",
            UInt32(kVK_ANSI_8): "8", UInt32(kVK_ANSI_9): "9", UInt32(kVK_ANSI_0): "0",
            UInt32(kVK_ANSI_O): "o", UInt32(kVK_ANSI_U): "u", UInt32(kVK_ANSI_I): "i",
            UInt32(kVK_ANSI_P): "p", UInt32(kVK_ANSI_L): "l", UInt32(kVK_ANSI_J): "j",
            UInt32(kVK_ANSI_K): "k", UInt32(kVK_ANSI_N): "n", UInt32(kVK_ANSI_M): "m",
            UInt32(kVK_ANSI_LeftBracket): "[", UInt32(kVK_ANSI_RightBracket): "]",
            UInt32(kVK_ANSI_Slash): "/", UInt32(kVK_ANSI_Minus): "-",
            UInt32(kVK_ANSI_Equal): "=", UInt32(kVK_ANSI_Comma): ",",
            UInt32(kVK_ANSI_Period): ".", UInt32(kVK_ANSI_Semicolon): ";",
            UInt32(kVK_ANSI_Quote): "'", UInt32(kVK_ANSI_Grave): "`"
        ]
        return characters[code]
    }

    private static func keyName(for code: UInt32) -> String {
        guard let character = keyCharacter(for: code) else { return "?" }
        return String(character).uppercased()
    }
}

// MARK: - Enums

enum AppAppearance: String, CaseIterable, Identifiable {
    case system
    case light
    case dark

    var id: String { rawValue }

    var label: String {
        switch self {
        case .system: return "System"
        case .light: return "Light"
        case .dark: return "Dark"
        }
    }

    var nsAppearance: NSAppearance? {
        switch self {
        case .system: return nil
        case .light: return NSAppearance(named: .aqua)
        case .dark: return NSAppearance(named: .darkAqua)
        }
    }
}

enum OverlayPosition: String, CaseIterable, Codable {
    /// Next to the mouse pointer, where the capture ended (Shottr-style).
    case cursor = "cursor"
    case bottomRight = "bottomRight"
    case bottomLeft = "bottomLeft"
}

enum ExportFormat: String, CaseIterable {
    case png, jpeg

    var utType: String {
        switch self {
        case .png: return "public.png"
        case .jpeg: return "public.jpeg"
        }
    }

    var fileExtension: String {
        switch self {
        case .png: return "png"
        case .jpeg: return "jpg"
        }
    }
}

enum OCRTranslationLanguage: String, CaseIterable, Identifiable {
    case vietnamese = "vi"
    case english = "en"
    case japanese = "ja"
    case korean = "ko"
    case simplifiedChinese = "zh-Hans"
    case traditionalChinese = "zh-Hant"
    case french = "fr"
    case german = "de"
    case spanish = "es"

    var id: String { rawValue }

    var label: String {
        switch self {
        case .vietnamese: return "Vietnamese"
        case .english: return "English"
        case .japanese: return "Japanese"
        case .korean: return "Korean"
        case .simplifiedChinese: return "Chinese (Simplified)"
        case .traditionalChinese: return "Chinese (Traditional)"
        case .french: return "French"
        case .german: return "German"
        case .spanish: return "Spanish"
        }
    }

    var localeLanguage: Locale.Language {
        Locale.Language(identifier: rawValue)
    }
}

enum SelfTimerDelay: Int, CaseIterable {
    case off = 0
    case three = 3
    case five = 5
    case ten = 10

    var label: String {
        switch self {
        case .off: return "Off"
        default: return "\(rawValue)s"
        }
    }
}
