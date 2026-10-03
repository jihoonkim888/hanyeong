import Foundation

/// A key identified by its HID usage page and usage.
public struct HIDKey: Hashable, Codable, Sendable {
    public var page: UInt32
    public var usage: UInt32

    public init(page: UInt32, usage: UInt32) {
        self.page = page
        self.usage = usage
    }

    public init(code: UInt64) {
        self.page = UInt32(code >> 32)
        self.usage = UInt32(code & 0xFFFF_FFFF)
    }

    /// The 64-bit form used by the HID `UserKeyMapping` property: `(page << 32) | usage`.
    public var code: UInt64 { (UInt64(page) << 32) | UInt64(usage) }

    public static func keyboard(_ usage: UInt32) -> HIDKey { HIDKey(page: 0x07, usage: usage) }

    public static let capsLock = keyboard(0x39)
    /// F19. A keyboard's 한영 key is remapped to send this, and the event tap listens for it.
    public static let hanyeong = keyboard(0x6E)
    /// The fn / globe key on the Apple vendor top-case page.
    public static let fn = HIDKey(page: 0xFF, usage: 0x03)
}

public enum KeyGroup: String, CaseIterable, Identifiable, Sendable {
    case modifier, function, editing, letter, symbol, keypad, international

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .modifier: "보조 키"
        case .function: "기능 키"
        case .editing: "편집·이동 키"
        case .letter: "문자·숫자"
        case .symbol: "기호"
        case .keypad: "숫자 키패드"
        case .international: "국제 키"
        }
    }
}

public struct KeyInfo: Identifiable, Hashable, Sendable {
    public let key: HIDKey
    public let name: String
    /// The `key_code` name Karabiner-Elements uses for this key.
    public let karabinerName: String
    public let group: KeyGroup

    public var id: HIDKey { key }
}

public enum KeyCatalog {
    public static let all: [KeyInfo] = build()

    private static let byKey = Dictionary(all.map { ($0.key, $0) }, uniquingKeysWith: { first, _ in first })

    private static let byKarabinerName: [String: HIDKey] = {
        var names = Dictionary(all.map { ($0.karabinerName, $0.key) }, uniquingKeysWith: { first, _ in first })
        for (alias, canonical) in aliases { names[alias] = names[canonical] }
        return names
    }()

    private static let aliases = [
        "fn": "keyboard_fn",
        "left_alt": "left_option", "right_alt": "right_option",
        "left_gui": "left_command", "right_gui": "right_command",
        "japanese_kana": "lang1", "japanese_eisuu": "lang2",
    ]

    public static func info(for key: HIDKey) -> KeyInfo? { byKey[key] }

    public static func name(for key: HIDKey) -> String {
        byKey[key]?.name ?? String(format: "키 0x%02X/0x%02X", key.page, key.usage)
    }

    public static func key(karabinerName: String) -> HIDKey? { byKarabinerName[karabinerName] }

    public static func keys(in group: KeyGroup) -> [KeyInfo] { all.filter { $0.group == group } }

    private static func build() -> [KeyInfo] {
        var keys: [KeyInfo] = []
        func add(_ group: KeyGroup, _ usage: UInt32, _ karabinerName: String, _ name: String) {
            keys.append(KeyInfo(key: .keyboard(usage), name: name, karabinerName: karabinerName, group: group))
        }

        add(.modifier, 0x39, "caps_lock", "Caps Lock ⇪")
        add(.modifier, 0xE0, "left_control", "왼쪽 Control ⌃")
        add(.modifier, 0xE2, "left_option", "왼쪽 Option ⌥")
        add(.modifier, 0xE3, "left_command", "왼쪽 Command ⌘")
        add(.modifier, 0xE1, "left_shift", "왼쪽 Shift ⇧")
        add(.modifier, 0xE4, "right_control", "오른쪽 Control ⌃")
        add(.modifier, 0xE6, "right_option", "오른쪽 Option ⌥")
        add(.modifier, 0xE7, "right_command", "오른쪽 Command ⌘")
        add(.modifier, 0xE5, "right_shift", "오른쪽 Shift ⇧")
        keys.append(KeyInfo(key: .fn, name: "fn (지구본)", karabinerName: "keyboard_fn", group: .modifier))

        for n in 1...12 { add(.function, 0x3A + UInt32(n - 1), "f\(n)", "F\(n)") }
        for n in 13...24 where n != 19 { add(.function, 0x68 + UInt32(n - 13), "f\(n)", "F\(n)") }
        // F19 is reserved as the internal 한영 signal, so it is shown under that name.
        add(.function, 0x6E, "f19", "한영 전환")

        add(.editing, 0x29, "escape", "Esc")
        add(.editing, 0x2B, "tab", "Tab ⇥")
        add(.editing, 0x28, "return_or_enter", "Return ↩")
        add(.editing, 0x2C, "spacebar", "Space")
        add(.editing, 0x2A, "delete_or_backspace", "Delete ⌫")
        add(.editing, 0x4C, "delete_forward", "Forward Delete ⌦")
        add(.editing, 0x49, "insert", "Insert")
        add(.editing, 0x4A, "home", "Home")
        add(.editing, 0x4D, "end", "End")
        add(.editing, 0x4B, "page_up", "Page Up")
        add(.editing, 0x4E, "page_down", "Page Down")
        add(.editing, 0x52, "up_arrow", "↑")
        add(.editing, 0x51, "down_arrow", "↓")
        add(.editing, 0x50, "left_arrow", "←")
        add(.editing, 0x4F, "right_arrow", "→")
        add(.editing, 0x46, "print_screen", "Print Screen")
        add(.editing, 0x47, "scroll_lock", "Scroll Lock")
        add(.editing, 0x48, "pause", "Pause")
        add(.editing, 0x65, "application", "메뉴 키")

        for (offset, letter) in "abcdefghijklmnopqrstuvwxyz".enumerated() {
            add(.letter, 0x04 + UInt32(offset), String(letter), String(letter).uppercased())
        }
        for n in 1...9 { add(.letter, 0x1E + UInt32(n - 1), "\(n)", "\(n)") }
        add(.letter, 0x27, "0", "0")

        add(.symbol, 0x35, "grave_accent_and_tilde", "`  ~")
        add(.symbol, 0x2D, "hyphen", "-  _")
        add(.symbol, 0x2E, "equal_sign", "=  +")
        add(.symbol, 0x2F, "open_bracket", "[  {")
        add(.symbol, 0x30, "close_bracket", "]  }")
        add(.symbol, 0x31, "backslash", "\\  |")
        add(.symbol, 0x33, "semicolon", ";  :")
        add(.symbol, 0x34, "quote", "'  \"")
        add(.symbol, 0x36, "comma", ",  <")
        add(.symbol, 0x37, "period", ".  >")
        add(.symbol, 0x38, "slash", "/  ?")

        add(.keypad, 0x53, "keypad_num_lock", "Num Lock")
        add(.keypad, 0x54, "keypad_slash", "키패드 /")
        add(.keypad, 0x55, "keypad_asterisk", "키패드 *")
        add(.keypad, 0x56, "keypad_hyphen", "키패드 -")
        add(.keypad, 0x57, "keypad_plus", "키패드 +")
        add(.keypad, 0x58, "keypad_enter", "키패드 Enter")
        for n in 1...9 { add(.keypad, 0x59 + UInt32(n - 1), "keypad_\(n)", "키패드 \(n)") }
        add(.keypad, 0x62, "keypad_0", "키패드 0")
        add(.keypad, 0x63, "keypad_period", "키패드 .")
        add(.keypad, 0x67, "keypad_equal_sign", "키패드 =")

        add(.international, 0x90, "lang1", "한/영 (LANG1)")
        add(.international, 0x91, "lang2", "한자 (LANG2)")
        add(.international, 0x32, "non_us_pound", "ISO #  (₩)")
        add(.international, 0x64, "non_us_backslash", "ISO \\  (§)")
        add(.international, 0x87, "international1", "International 1 (ろ)")
        add(.international, 0x89, "international3", "International 3 (¥)")

        return keys
    }
}
