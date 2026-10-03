import Carbon
import Foundation

struct InputSourceInfo: Equatable {
    var id: String
    /// Short text for the menu bar, such as "한" or "A".
    var label: String
    var isKorean: Bool
}

/// Text Input Source helpers. These must only be called on the main thread:
/// the underlying API asserts on it and crashes the process otherwise.
enum InputSources {
    static let changedNotification = Notification.Name(kTISNotifySelectedKeyboardInputSourceChanged as String)

    /// The source that was selected before the current one, used to toggle when
    /// more than two sources are enabled.
    private static var previousID: String?
    private static var lastSeenID: String?

    static func currentID() -> String {
        id(of: TISCopyCurrentKeyboardInputSource().takeRetainedValue())
    }

    static func current() -> InputSourceInfo {
        let source = TISCopyCurrentKeyboardInputSource().takeRetainedValue()
        let language = languages(of: source).first ?? ""
        let label: String
        switch language {
        case "ko": label = "한"
        case "ja": label = "あ"
        case _ where language.hasPrefix("zh"): label = "中"
        default: label = "A"
        }
        return InputSourceInfo(id: id(of: source), label: label, isKorean: language == "ko")
    }

    /// Records a change so the previously used source is known. Call on every change notification.
    static func noteCurrent(_ id: String) {
        if let lastSeenID, lastSeenID != id { previousID = lastSeenID }
        lastSeenID = id
    }

    /// Selects the other input source directly, without going through the system shortcut.
    @discardableResult
    static func selectOther(than baseline: String) -> Bool {
        let sources = selectable()
        let target = sources.first { id(of: $0) == previousID && id(of: $0) != baseline }
            ?? sources.first { id(of: $0) != baseline }
        guard let target else { return false }
        return TISSelectInputSource(target) == noErr
    }

    private static func selectable() -> [TISInputSource] {
        let filter: [String: Any] = [
            kTISPropertyInputSourceCategory as String: kTISCategoryKeyboardInputSource as String,
            kTISPropertyInputSourceIsSelectCapable as String: true,
        ]
        return TISCreateInputSourceList(filter as CFDictionary, false)?.takeRetainedValue() as? [TISInputSource] ?? []
    }

    private static func id(of source: TISInputSource) -> String {
        guard let pointer = TISGetInputSourceProperty(source, kTISPropertyInputSourceID) else { return "" }
        return Unmanaged<CFString>.fromOpaque(pointer).takeUnretainedValue() as String
    }

    private static func languages(of source: TISInputSource) -> [String] {
        guard let pointer = TISGetInputSourceProperty(source, kTISPropertyInputSourceLanguages) else { return [] }
        return Unmanaged<CFArray>.fromOpaque(pointer).takeUnretainedValue() as? [String] ?? []
    }
}
