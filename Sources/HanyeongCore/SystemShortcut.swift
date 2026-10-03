import Foundation

/// The system keyboard shortcut that switches input sources, as stored in
/// `com.apple.symbolichotkeys`. 한영 presses this shortcut on the user's behalf because,
/// unlike selecting an input source from a background process, it switches Korean reliably.
public struct SystemShortcut: Equatable, Sendable {
    public enum Kind: Sendable {
        case previousSource
        case nextSource
    }

    public var kind: Kind
    public var keyCode: Int
    /// Modifier bits in the `CGEventFlags` layout.
    public var modifiers: UInt64

    public init(kind: Kind, keyCode: Int, modifiers: UInt64) {
        self.kind = kind
        self.keyCode = keyCode
        self.modifiers = modifiers
    }

    private static let shift: UInt64 = 0x20000
    private static let control: UInt64 = 0x40000
    private static let option: UInt64 = 0x80000
    private static let command: UInt64 = 0x100000

    public static let f19KeyCode = 80

    /// When the shortcut is a bare F19, the remapped 한영 key keeps working through the
    /// system alone, even while the app is not running or cannot see key events.
    public var isBareF19: Bool {
        keyCode == Self.f19KeyCode && modifiers & (Self.shift | Self.control | Self.option | Self.command) == 0
    }

    public var displayName: String {
        var name = ""
        if modifiers & Self.control != 0 { name += "⌃" }
        if modifiers & Self.option != 0 { name += "⌥" }
        if modifiers & Self.shift != 0 { name += "⇧" }
        if modifiers & Self.command != 0 { name += "⌘" }
        return name + (Self.keyNames[keyCode] ?? "키 코드 \(keyCode)")
    }

    public var kindName: String {
        switch kind {
        case .previousSource: "이전 입력 소스 선택"
        case .nextSource: "입력 메뉴에서 다음 소스 선택"
        }
    }

    /// Picks the shortcut to press from the `AppleSymbolicHotKeys` dictionary.
    /// "Previous input source" (60) is preferred because it toggles between the two most
    /// recent sources; "next source" (61) is used when 60 is turned off.
    public static func resolve(symbolicHotKeys: [String: Any]?) -> SystemShortcut? {
        let candidates: [(id: String, kind: Kind, defaultModifiers: UInt64)] = [
            ("60", .previousSource, control),
            ("61", .nextSource, control | option),
        ]
        for candidate in candidates {
            guard let entry = symbolicHotKeys?[candidate.id] as? [String: Any] else {
                // No entry means the user never changed it, so the default (Space) applies.
                return SystemShortcut(kind: candidate.kind, keyCode: 49, modifiers: candidate.defaultModifiers)
            }
            guard (entry["enabled"] as? NSNumber)?.boolValue == true,
                  let value = entry["value"] as? [String: Any],
                  let parameters = value["parameters"] as? [NSNumber], parameters.count >= 3
            else { continue }
            let keyCode = parameters[1].intValue
            guard keyCode != 0xFFFF else { continue }
            return SystemShortcut(kind: candidate.kind, keyCode: keyCode, modifiers: parameters[2].uint64Value)
        }
        return nil
    }

    private static let keyNames: [Int: String] = {
        var names: [Int: String] = [49: "Space", 36: "Return", 48: "Tab", 53: "Esc"]
        let functionKeys = [122, 120, 99, 118, 96, 97, 98, 100, 101, 109, 103, 111, 105, 107, 113, 106, 64, 79, 80, 90]
        for (index, keyCode) in functionKeys.enumerated() { names[keyCode] = "F\(index + 1)" }
        return names
    }()
}
